import AppKit

struct BlockInputAcceptedFileDrop: Sendable {
    var context: BlockInputFileDropContext
    var inlineValidation: InlineValidation?
    var storeID: ObjectIdentifier?

    struct InlineValidation: Sendable {
        var blockID: BlockInputBlockID
        var kind: BlockInputBlockKind
        var text: String
    }
}

extension BlockInputView {
    func cancelFileDropTasks() {
        for task in fileDropTasks.values {
            task.cancel()
        }
        fileDropTasks.removeAll()
    }

    private func acceptedFileDrop(
        fileURLs: [URL],
        placement: BlockInputFileDropPlacement
    ) -> BlockInputAcceptedFileDrop? {
        let files = fileURLs.enumerated().compactMap(Self.droppedFile)
        guard !files.isEmpty else {
            return nil
        }
        return acceptedDrop(files: files, placement: placement)
    }

    /// Builds a validated accepted-drop snapshot for `placement`, independent of the file URLs that produced it.
    ///
    /// Shared by file drops (which pass classified `files`) and rich paste (which validates placement but resolves
    /// references later through registered paste handlers), so both honor the same edit-target re-validation.
    func acceptedDrop(
        files: [BlockInputDroppedFile] = [],
        placement: BlockInputFileDropPlacement
    ) -> BlockInputAcceptedFileDrop? {
        guard isEditable else {
            return nil
        }
        let inlineValidation: BlockInputAcceptedFileDrop.InlineValidation?
        switch placement {
        case let .inline(blockID, _):
            guard let block = block(withID: blockID),
                  BlockInputBlockItem.supportsInlineMarkdownStyling(block.kind) else {
                return nil
            }
            inlineValidation = .init(blockID: blockID, kind: block.kind, text: block.text)
        case .documentEnd:
            guard !showsProgressiveLoadingRow else {
                return nil
            }
            inlineValidation = nil
        }
        return BlockInputAcceptedFileDrop(
            context: BlockInputFileDropContext(files: files, placement: placement, document: document),
            inlineValidation: inlineValidation,
            storeID: documentStore.map { ObjectIdentifier($0 as AnyObject) }
        )
    }

    func handleDroppedFileURLs(
        _ fileURLs: [URL],
        placement: BlockInputFileDropPlacement
    ) -> Bool {
        guard isEditable else {
            return false
        }
        guard let acceptedDrop = acceptedFileDrop(fileURLs: fileURLs, placement: placement) else {
            return false
        }
        guard let fileDropHandler else {
            return applyDefaultFileDrop(acceptedDrop)
        }
        scheduleFileDrop(acceptedDrop, handler: fileDropHandler)
        return true
    }

    private func scheduleFileDrop(
        _ acceptedDrop: BlockInputAcceptedFileDrop,
        handler: @escaping BlockInputFileDropHandler
    ) {
        let id = UUID()
        fileDropTasks[id] = Task.detached(priority: .userInitiated) { [weak self, acceptedDrop, handler] in
            let result: BlockInputFileDropResult
            do {
                result = try await handler(acceptedDrop.context)
            } catch {
                result = .cancel
            }
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                fileDropTasks[id] = nil
                guard !Task.isCancelled else {
                    return
                }
                _ = applyFileDropResult(result, acceptedDrop: acceptedDrop)
            }
        }
    }

    private func applyFileDropResult(
        _ result: BlockInputFileDropResult,
        acceptedDrop: BlockInputAcceptedFileDrop
    ) -> Bool {
        guard isEditable else {
            return false
        }
        switch result {
        case .useDefault:
            return applyDefaultFileDrop(acceptedDrop)
        case .cancel:
            return false
        case let .insert(references):
            return applyFileDropReferences(references, acceptedDrop: acceptedDrop)
        }
    }

    private func applyDefaultFileDrop(_ acceptedDrop: BlockInputAcceptedFileDrop) -> Bool {
        applyFileDropReferences(acceptedDrop.context.files.map(\.defaultReference), acceptedDrop: acceptedDrop)
    }

    func applyFileDropReferences(
        _ references: [BlockInputFileDropReference],
        acceptedDrop: BlockInputAcceptedFileDrop
    ) -> Bool {
        guard fileDropTargetIsStillValid(acceptedDrop) else {
            return false
        }
        let references = references.filter { Self.normalizedDropSource($0.source) != nil }
        guard !references.isEmpty else {
            return false
        }
        switch acceptedDrop.context.placement {
        case let .inline(blockID, utf16Offset):
            if imagePresentation == .textLinksWithPreviewStrip {
                return insertFileReferencesInline(references, into: blockID, atUTF16Offset: utf16Offset) != nil
            }
            let imageReferences = references.filter { $0.kind == .image }
            let fileReferences = references.filter { $0.kind == .fileLink }
            guard !imageReferences.isEmpty else {
                return insertFileReferencesInline(fileReferences, into: blockID, atUTF16Offset: utf16Offset) != nil
            }
            guard !fileReferences.isEmpty else {
                return insertImageReferences(imageReferences, below: blockID) != nil
            }
            return insertMixedImageAndFileReferences(
                imageReferences: imageReferences,
                fileReferences: fileReferences,
                into: blockID,
                atUTF16Offset: utf16Offset
            ) != nil
        case .documentEnd:
            let blocks = references.compactMap(Self.block(for:))
            guard !blocks.isEmpty else {
                return false
            }
            return insertDroppedFileBlocks(blocks, at: blockCount) != nil
        }
    }

    /// Atomically inserts image blocks below `blockID` and file link chips inline into `blockID`.
    /// Both mutations are grouped under a single undo entry so that undoing one step fully
    /// reverts the drop without leaving orphaned image blocks behind.
    @discardableResult
    func insertMixedImageFileURLsAndFileURLsInline(
        imageURLs: [URL],
        fileURLs: [URL],
        into blockID: BlockInputBlockID,
        atUTF16Offset utf16Offset: Int
    ) -> BlockInputSelection? {
        let imageBlocks = imageURLs.compactMap(Self.imageBlock(for:))
        let baseInsertionText = Self.joinedInlineFileInsertionText(
            fileURLs.compactMap { Self.inlineFileLinkMarkdownSource(for: $0) }
        )
        guard !imageBlocks.isEmpty, !baseInsertionText.isEmpty else {
            return nil
        }
        return performStructuralEdit(named: "Insert Files") { document in
            guard let blockIndex = document.blocks.firstIndex(where: { $0.id == blockID }),
                  BlockInputBlockItem.supportsInlineMarkdownStyling(document.blocks[blockIndex].kind) else {
                return nil
            }
            let insertionOffset = min(max(utf16Offset, 0), document.blocks[blockIndex].utf16Length)
            let insertionText = Self.adjustedInlineInsertionText(
                baseInsertionText,
                in: document.blocks[blockIndex].text,
                at: insertionOffset
            )
            let mutableText = NSMutableString(string: document.blocks[blockIndex].text)
            mutableText.insert(insertionText, at: insertionOffset)
            document.blocks[blockIndex].text = mutableText as String
            guard document.insertBlocks(imageBlocks, at: blockIndex + 1) != nil else {
                return nil
            }
            return .cursor(BlockInputCursor(blockID: blockID, utf16Offset: insertionOffset + (insertionText as NSString).length))
        }
    }

    /// Atomically inserts image blocks below `blockID` and file reference chips inline into `blockID`.
    /// Both mutations are grouped under a single undo entry so that undoing one step fully
    /// reverts the drop without leaving orphaned image blocks behind.
    private func insertMixedImageAndFileReferences(
        imageReferences: [BlockInputFileDropReference],
        fileReferences: [BlockInputFileDropReference],
        into blockID: BlockInputBlockID,
        atUTF16Offset utf16Offset: Int
    ) -> BlockInputSelection? {
        let imageBlocks = imageReferences.compactMap { reference -> BlockInputBlock? in
            guard reference.kind == .image else { return nil }
            return Self.block(for: reference)
        }
        let baseInsertionText = Self.joinedInlineFileInsertionText(
            fileReferences.compactMap { Self.inlineFileLinkMarkdownSource(for: $0) }
        )
        guard !imageBlocks.isEmpty, !baseInsertionText.isEmpty else {
            return nil
        }
        return performStructuralEdit(named: "Insert Files") { document in
            guard let blockIndex = document.blocks.firstIndex(where: { $0.id == blockID }),
                  BlockInputBlockItem.supportsInlineMarkdownStyling(document.blocks[blockIndex].kind) else {
                return nil
            }
            let insertionOffset = min(max(utf16Offset, 0), document.blocks[blockIndex].utf16Length)
            let insertionText = Self.adjustedInlineInsertionText(
                baseInsertionText,
                in: document.blocks[blockIndex].text,
                at: insertionOffset
            )
            let mutableText = NSMutableString(string: document.blocks[blockIndex].text)
            mutableText.insert(insertionText, at: insertionOffset)
            document.blocks[blockIndex].text = mutableText as String
            guard document.insertBlocks(imageBlocks, at: blockIndex + 1) != nil else {
                return nil
            }
            return .cursor(BlockInputCursor(blockID: blockID, utf16Offset: insertionOffset + (insertionText as NSString).length))
        }
    }

    private func fileDropTargetIsStillValid(_ acceptedDrop: BlockInputAcceptedFileDrop) -> Bool {
        guard acceptedDrop.storeID == documentStore.map({ ObjectIdentifier($0 as AnyObject) }) else {
            return false
        }
        switch acceptedDrop.context.placement {
        case .documentEnd:
            return !showsProgressiveLoadingRow
        case .inline:
            guard let inlineValidation = acceptedDrop.inlineValidation,
                  let block = block(withID: inlineValidation.blockID) else {
                return false
            }
            return block.kind == inlineValidation.kind &&
                block.text == inlineValidation.text &&
                BlockInputBlockItem.supportsInlineMarkdownStyling(block.kind)
        }
    }

    private static func droppedFile(index: Int, url: URL) -> BlockInputDroppedFile? {
        guard url.isFileURL else {
            return nil
        }
        let kind: BlockInputDroppedFileKind = imageBlock(for: url) == nil ? .fileLink : .image
        let label = kind == .image
            ? url.deletingPathExtension().lastPathComponent
            : (url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)
        return BlockInputDroppedFile(
            index: index,
            url: url,
            defaultKind: kind,
            defaultSource: url.absoluteString,
            defaultLabel: label
        )
    }
}
