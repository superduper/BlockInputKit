import AppKit

extension BlockInputView {
    @discardableResult
    func insertFileURLsInline(
        _ fileURLs: [URL],
        into blockID: BlockInputBlockID,
        atUTF16Offset utf16Offset: Int,
        item: BlockInputBlockItem
    ) -> BlockInputSelection? {
        guard item.representedBlockID == blockID else {
            return nil
        }
        return insertFileURLsInline(fileURLs, into: blockID, atUTF16Offset: utf16Offset)
    }

    @discardableResult
    func insertFileURLsInline(
        _ fileURLs: [URL],
        into blockID: BlockInputBlockID,
        atUTF16Offset utf16Offset: Int
    ) -> BlockInputSelection? {
        guard isEditable else {
            return nil
        }
        let baseInsertionText = inlineFileInsertionText(for: fileURLs)
        guard !baseInsertionText.isEmpty,
              let index = index(of: blockID),
              var block = block(at: index),
              block.id == blockID,
              BlockInputBlockItem.supportsInlineMarkdownStyling(block.kind) else {
            return nil
        }
        let beforeBlock = block
        let beforeSelection = selection
        let insertionOffset = min(max(utf16Offset, 0), block.utf16Length)
        let insertionText = Self.adjustedInlineInsertionText(baseInsertionText, in: block.text, at: insertionOffset)
        let mutableText = NSMutableString(string: block.text)
        mutableText.insert(insertionText, at: insertionOffset)
        block.text = mutableText as String
        let afterOffset = insertionOffset + (insertionText as NSString).length
        let afterSelection = BlockInputSelection.cursor(BlockInputCursor(
            blockID: blockID,
            utf16Offset: afterOffset
        ))
        _ = applyGranularBlockReplacement(block, at: index, selection: afterSelection)
        undoController?.registerBlockReplacementStructuralEdit(
            actionName: inlineFileInsertionActionName(for: fileURLs),
            beforeBlock: beforeBlock,
            afterBlock: block,
            selectionBefore: beforeSelection,
            selectionAfter: afterSelection
        )
        return afterSelection
    }

    func insertLocalFileURLsInlineIfPossible(
        _ fileURLs: [URL],
        into blockID: BlockInputBlockID
    ) -> BlockInputSelection? {
        guard imagePresentation == .textLinksWithPreviewStrip,
              fileURLs.allSatisfy({ Self.imageTextBlock(for: $0) != nil }),
              let block = block(withID: blockID),
              BlockInputBlockItem.supportsInlineMarkdownStyling(block.kind) else {
            return nil
        }
        return insertFileURLsInline(
            fileURLs,
            into: blockID,
            atUTF16Offset: localFileInlineInsertionOffset(in: block)
        )
    }

    @discardableResult
    func insertFileReferencesInline(
        _ references: [BlockInputFileDropReference],
        into blockID: BlockInputBlockID,
        atUTF16Offset utf16Offset: Int
    ) -> BlockInputSelection? {
        guard isEditable else {
            return nil
        }
        let baseInsertionText = inlineFileInsertionText(for: references)
        guard !baseInsertionText.isEmpty,
              let index = index(of: blockID),
              var block = block(at: index),
              block.id == blockID,
              BlockInputBlockItem.supportsInlineMarkdownStyling(block.kind) else {
            return nil
        }
        let beforeBlock = block
        let beforeSelection = selection
        let insertionOffset = min(max(utf16Offset, 0), block.utf16Length)
        let insertionText = Self.adjustedInlineInsertionText(baseInsertionText, in: block.text, at: insertionOffset)
        let mutableText = NSMutableString(string: block.text)
        mutableText.insert(insertionText, at: insertionOffset)
        block.text = mutableText as String
        let afterOffset = insertionOffset + (insertionText as NSString).length
        let afterSelection = BlockInputSelection.cursor(BlockInputCursor(
            blockID: blockID,
            utf16Offset: afterOffset
        ))
        _ = applyGranularBlockReplacement(block, at: index, selection: afterSelection)
        undoController?.registerBlockReplacementStructuralEdit(
            actionName: inlineFileInsertionActionName(for: references),
            beforeBlock: beforeBlock,
            afterBlock: block,
            selectionBefore: beforeSelection,
            selectionAfter: afterSelection
        )
        return afterSelection
    }

    static func joinedInlineFileInsertionText(_ sources: [String]) -> String {
        var result = ""
        for source in sources {
            guard !source.isEmpty else {
                continue
            }
            if !result.isEmpty, result.last?.isWhitespace != true {
                result.append(" ")
            }
            result.append(source)
        }
        return result
    }

    private func localFileInlineInsertionOffset(in block: BlockInputBlock) -> Int {
        switch selection {
        case let .cursor(cursor) where cursor.blockID == block.id:
            return cursor.utf16Offset
        case let .text(range) where range.blockID == block.id:
            return NSMaxRange(range.range)
        default:
            return block.utf16Length
        }
    }

    private func inlineFileInsertionText(for fileURLs: [URL]) -> String {
        let sources = fileURLs.compactMap { url in
            if imagePresentation == .textLinksWithPreviewStrip,
               let imageTextBlock = Self.imageTextBlock(for: url) {
                return imageTextBlock.text
            }
            return Self.inlineFileLinkMarkdownSource(for: url)
        }
        return Self.joinedInlineFileInsertionText(sources)
    }

    private func inlineFileInsertionText(for references: [BlockInputFileDropReference]) -> String {
        let sources = references.compactMap { reference in
            if imagePresentation == .textLinksWithPreviewStrip,
               let imageTextBlock = Self.imageTextBlock(for: reference) {
                return imageTextBlock.text
            }
            return Self.inlineFileLinkMarkdownSource(for: reference)
        }
        return Self.joinedInlineFileInsertionText(sources)
    }

    private func inlineFileInsertionActionName(for fileURLs: [URL]) -> String {
        guard imagePresentation == .textLinksWithPreviewStrip,
              !fileURLs.isEmpty,
              fileURLs.allSatisfy({ Self.imageTextBlock(for: $0) != nil }) else {
            return "Insert Files"
        }
        return fileURLs.count == 1 ? "Insert Image" : "Insert Images"
    }

    private func inlineFileInsertionActionName(for references: [BlockInputFileDropReference]) -> String {
        guard imagePresentation == .textLinksWithPreviewStrip,
              !references.isEmpty,
              references.allSatisfy({ Self.imageTextBlock(for: $0) != nil }) else {
            return "Insert Files"
        }
        return references.count == 1 ? "Insert Image" : "Insert Images"
    }

    static func inlineFileLinkMarkdownSource(for url: URL) -> String? {
        guard url.isFileURL else {
            return nil
        }
        let displayName = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        return BlockInputLinkURL.markdownLink(label: displayName, destination: url.absoluteString)
    }

    static func inlineFileLinkMarkdownSource(for reference: BlockInputFileDropReference) -> String? {
        guard reference.kind == .fileLink,
              let source = normalizedDropSource(reference.source) else {
            return nil
        }
        let label = reference.label.isEmpty ? source : reference.label
        return BlockInputLinkURL.markdownLink(label: label, destination: source)
    }

    static func adjustedInlineInsertionText(_ insertionText: String, in text: String, at utf16Offset: Int) -> String {
        var insertionText = insertionText
        if insertionText.hasSuffix(" "),
           isWhitespace(at: utf16Offset, in: text) {
            insertionText.removeLast()
        }
        return insertionText
    }

    private static func isWhitespace(at utf16Offset: Int, in text: String) -> Bool {
        let nsText = text as NSString
        guard utf16Offset >= 0,
              utf16Offset < nsText.length,
              let scalar = UnicodeScalar(Int(nsText.character(at: utf16Offset))) else {
            return false
        }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
}
