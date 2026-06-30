import AppKit

extension BlockInputView {
    func canCopyActiveSelection() -> Bool {
        guard let copiedText = selectedPlainText() else {
            return false
        }
        return !copiedText.isEmpty
    }

    func copyActiveSelection() -> Bool {
        guard let copiedText = selectedPlainText(), !copiedText.isEmpty else {
            return false
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copiedText, forType: .string)
        return true
    }

    func cutActiveSelection() -> Bool {
        guard isEditable else {
            return false
        }
        if let copiedText = markdownAwareCopiedTextForTextCut() {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(copiedText, forType: .string)
            return performTextViewEditAction(#selector(NSText.delete(_:)))
        }
        if case .text = selection {
            return performTextViewEditAction(#selector(NSText.cut(_:)))
        }
        guard selection?.wholeSelectedBlockIDs.isEmpty == false || isMixedSelection,
              copyActiveSelection() else {
            return false
        }
        return deleteSelectedBlocksForBackspaceOrDelete() != nil
    }

    func pasteIntoActiveSelection() -> Bool {
        guard isEditable else {
            return false
        }
        if pasteTextAtImageCaretIfNeeded() {
            return true
        }
        switch selection {
        case .cursor, .text:
            return performTextViewEditAction(#selector(NSText.paste(_:)))
        case .blocks, .mixed, nil:
            return false
        }
    }

    /// Deletes the selected whole blocks.
    @discardableResult
    public func deleteSelectedBlocksForBackspaceOrDelete() -> BlockInputSelection? {
        guard isEditable else {
            return nil
        }
        refreshDocumentFromStore()
        if case let .mixed(selection) = selection {
            return deleteMixedSelection(selection)
        }
        guard case let .blocks(blockIDs) = selection,
              !blockIDs.isEmpty else {
            return nil
        }
        if blockIDs.count == 1,
           let blockID = blockIDs.first,
           block(withID: blockID)?.kind == .table {
            return deleteTable(blockID: blockID) ? selection : nil
        }
        return performStructuralEdit(
            named: blockIDs.count == 1 ? "Delete Block" : "Delete Blocks",
            storeSyncAction: { beforeDocument, afterDocument, _ in
                if beforeDocument.blocks.count == 1,
                   let replacementBlock = afterDocument.blocks.first {
                    return .replaceBlock(replacementBlock)
                }
                if beforeDocument.blocks.count == blockIDs.count,
                   afterDocument.blocks.count == 1 {
                    return .replaceDocument
                }
                return .deleteBlocks(blockIDs)
            },
            edit: { document in
                document.deleteBlocks(blockIDs: blockIDs)
            }
        )
    }

    @discardableResult
    func replaceActiveSelection(with insertedText: String) -> Bool {
        guard isEditable,
              !insertedText.isEmpty else {
            return false
        }
        switch selection {
        case let .text(textRange):
            return finishTypedSelectionReplacement(replaceTextSelection(textRange, with: insertedText))
        case let .mixed(selection):
            return finishTypedSelectionReplacement(replaceMixedSelection(selection, with: insertedText))
        case let .blocks(blockIDs):
            return finishTypedSelectionReplacement(replaceBlockSelection(blockIDs, with: insertedText))
        case .cursor, nil:
            return false
        }
    }

    private func finishTypedSelectionReplacement(_ selection: BlockInputSelection?) -> Bool {
        guard selection != nil else {
            return false
        }
        collectionView.layoutSubtreeIfNeeded()
        if case let .cursor(cursor) = selection {
            focus(blockID: cursor.blockID, utf16Offset: cursor.utf16Offset)
        } else {
            restoreVisibleSelection()
        }
        return true
    }

    private func performTextViewEditAction(_ action: Selector) -> Bool {
        switch selection {
        case let .cursor(cursor):
            guard let item = visibleItem(for: cursor.blockID) else {
                return false
            }
            item.focusText(atUTF16Offset: cursor.utf16Offset)
        case let .text(textRange):
            guard let item = visibleItem(for: textRange.blockID) else {
                return false
            }
            item.focusText(inUTF16Range: textRange.range)
        case .blocks, .mixed, nil:
            return false
        }
        guard let textView = window?.firstResponder as? BlockInputTextView else {
            return false
        }
        if action == #selector(NSText.cut(_:)) {
            textView.performCutFromEditorCommand()
            return true
        }
        if action == #selector(NSText.paste(_:)) {
            textView.performPasteFromEditorCommand()
            return true
        }
        return NSApp.sendAction(action, to: textView, from: self)
    }

    private func replaceTextSelection(
        _ textRange: BlockInputTextRange,
        with insertedText: String
    ) -> BlockInputSelection? {
        performStructuralEdit(
            named: "Insert Text",
            storeSyncAction: { _, afterDocument, _ in
                guard let block = afterDocument.block(withID: textRange.blockID) else {
                    return .replaceDocument
                }
                return .replaceBlock(block)
            },
            edit: { document in
                document.replaceText(in: textRange.blockID, range: textRange.range, replacement: insertedText)
            }
        )
    }

    private func replaceMixedSelection(
        _ selection: BlockInputMixedSelection,
        with insertedText: String
    ) -> BlockInputSelection? {
        performStructuralEdit(
            named: "Insert Text",
            storeSyncAction: { _, _, _ in .replaceDocument },
            edit: { document in
                guard let cursor = document.deleteMixedSelection(selection) else {
                    return nil
                }
                return document.replaceText(
                    in: cursor.blockID,
                    range: NSRange(location: cursor.utf16Offset, length: 0),
                    replacement: insertedText
                )
            }
        )
    }

    private func replaceBlockSelection(
        _ blockIDs: [BlockInputBlockID],
        with insertedText: String
    ) -> BlockInputSelection? {
        guard !blockIDs.isEmpty else {
            return nil
        }
        let selectedIDs = Set(blockIDs)
        return performStructuralEdit(
            named: "Insert Text",
            storeSyncAction: { _, afterDocument, _ in
                guard blockIDs.count == 1,
                      let blockID = blockIDs.first,
                      let replacementBlock = afterDocument.block(withID: blockID) else {
                    return .replaceDocument
                }
                return .replaceBlock(replacementBlock)
            },
            edit: { document in
                guard let firstSelectedBlock = document.blocks.first(where: { selectedIDs.contains($0.id) }) else {
                    return nil
                }
                let replacementBlock = BlockInputBlock(
                    id: firstSelectedBlock.id,
                    kind: .paragraph,
                    text: insertedText
                )
                var didInsertReplacement = false
                document.blocks = document.blocks.compactMap { block in
                    guard selectedIDs.contains(block.id) else {
                        return block
                    }
                    guard !didInsertReplacement else {
                        return nil
                    }
                    didInsertReplacement = true
                    return replacementBlock
                }
                return .cursor(BlockInputCursor(
                    blockID: replacementBlock.id,
                    utf16Offset: replacementBlock.utf16Length
                ))
            }
        )
    }

    private func selectedPlainText() -> String? {
        switch selection {
        case let .text(textRange):
            guard let block = block(withID: textRange.blockID) else {
                return nil
            }
            if let cellText = block.markdownAwareCopiedTableCellText(in: textRange.range, fileBaseURL: fileBaseURL) {
                return cellText
            }
            return block.markdownAwareCopiedText(in: textRange.range, fileBaseURL: fileBaseURL)
        case let .blocks(blockIDs):
            let copiedBlocks = blocksForMarkdownCopy(blockIDs: blockIDs)
            guard !copiedBlocks.isEmpty else {
                return nil
            }
            return BlockInputDocument(blocks: copiedBlocks.clipboardMarkdownBlocks).markdown
        case let .mixed(mixedSelection):
            let copiedBlocks = blocksForMixedMarkdownCopy(mixedSelection)
            guard !copiedBlocks.isEmpty else {
                return nil
            }
            return BlockInputDocument(blocks: copiedBlocks.clipboardMarkdownBlocks).markdown
        case .cursor, nil:
            return nil
        }
    }

    private func markdownAwareCopiedTextForTextCut() -> String? {
        // Full-body frontmatter cuts copy the Markdown block, while partial body
        // cuts intentionally stay on AppKit's raw text path.
        guard case let .text(textRange) = selection,
              let block = block(withID: textRange.blockID),
              visibleItem(for: textRange.blockID) != nil,
              block.kind == .frontMatter else {
            return nil
        }
        return block.markdownAwareCopiedTextForFullTextRange(textRange.range)
    }

    private var isMixedSelection: Bool {
        if case .mixed = selection {
            return true
        }
        return false
    }

    private func deleteMixedSelection(_ selection: BlockInputMixedSelection) -> BlockInputSelection? {
        performStructuralEdit(
            named: "Delete Selection",
            storeSyncAction: { _, _, _ in .replaceDocument },
            edit: { document in
                let cursor = document.deleteMixedSelection(selection)
                return cursor.map(BlockInputSelection.cursor)
            }
        )
    }

    private func blocksForMarkdownCopy(blockIDs: [BlockInputBlockID]) -> [BlockInputBlock] {
        let indexedBlocks = blockIDs.compactMap { blockID -> (index: Int, block: BlockInputBlock)? in
            guard let index = index(of: blockID),
                  let block = block(at: index) else {
                return nil
            }
            return (index, block)
        }
        return indexedBlocks
            .sorted { $0.index < $1.index }
            .map(\.block)
    }

    private func blocksForMixedMarkdownCopy(_ selection: BlockInputMixedSelection) -> [BlockInputBlock] {
        let edgeBlockIDs = [
            selection.leadingTextRange?.blockID,
            selection.trailingTextRange?.blockID
        ].compactMap { $0 }
        let blockIDs = selection.blockIDs + edgeBlockIDs
        return blockIDs.compactMap { blockID -> (index: Int, block: BlockInputBlock)? in
            guard let index = index(of: blockID), var block = block(at: index) else {
                return nil
            }
            if let textRange = selection.leadingTextRange, textRange.blockID == blockID {
                block.applyPartialMarkdownCopyRange(textRange.range)
            }
            if let textRange = selection.trailingTextRange, textRange.blockID == blockID {
                block.applyPartialMarkdownCopyRange(textRange.range)
            }
            return (index, block)
        }
        .sorted { $0.index < $1.index }
        .map(\.block)
    }
}

extension BlockInputBlock {
    func markdownAwareCopiedTableCellText(in sourceRange: NSRange, fileBaseURL: URL? = nil) -> String? {
        guard kind == .table,
              let table = BlockInputTable(markdown: text),
              let position = table.cellPosition(containingSourceRange: sourceRange),
              let localRange = table.localRange(forSourceRange: sourceRange, in: position),
              let cell = table.cell(at: position) else {
            return nil
        }
        return BlockInputBlock(text: cell.text).markdownAwareCopiedText(in: localRange, fileBaseURL: fileBaseURL)
    }

    func markdownAwareCopiedText(in range: NSRange, fileBaseURL: URL? = nil) -> String? {
        guard kind != .horizontalRule else {
            return nil
        }
        let clampedRange = text.clampedRange(range)
        guard clampedRange.length > 0 else {
            return nil
        }
        if kind == .quote,
           clampedRange.location == 0,
           NSMaxRange(clampedRange) == utf16Length {
            return BlockInputDocument(blocks: [self]).markdown
        }
        if case .code = kind,
           clampedRange.location == 0,
           NSMaxRange(clampedRange) == utf16Length {
            return BlockInputDocument(blocks: [self]).markdown
        }
        if kind == .frontMatter,
           clampedRange.location == 0,
           NSMaxRange(clampedRange) == utf16Length {
            return BlockInputDocument(blocks: [self]).markdown
        }
        if let copiedLinkLabelText = copiedVisibleInlineLinkText(in: clampedRange, fileBaseURL: fileBaseURL) {
            return copiedLinkLabelText
        }
        return (text as NSString).substring(with: clampedRange)
    }

    func markdownAwareCopiedTextForFullTextRange(_ range: NSRange) -> String? {
        let clampedRange = text.clampedRange(range)
        guard clampedRange.length > 0,
              clampedRange.location == 0,
              NSMaxRange(clampedRange) == utf16Length else {
            return nil
        }
        return markdownAwareCopiedText(in: clampedRange)
    }

    mutating func applyPartialMarkdownCopyRange(_ range: NSRange) {
        let originalTextLength = utf16Length
        let clampedRange = text.clampedRange(range)
        text = (text as NSString).substring(with: clampedRange)
        stripMarkdownChromeIfPartialCopyNeedsPlainText(clampedRange, originalTextLength: originalTextLength)
    }

    mutating func stripMarkdownChromeIfPartialCopyNeedsPlainText(_ range: NSRange, originalTextLength: Int) {
        let coversWholeBlock = range.location <= 0 && NSMaxRange(range) >= originalTextLength
        guard !coversWholeBlock,
              range.location > 0 || hasInvisibleMarkdownFence else {
            return
        }
        kind = .paragraph
        indentationLevel = 0
        lineIndentationLevels = []
    }

    var hasInvisibleMarkdownFence: Bool {
        if case .code = kind {
            return true
        }
        if kind == .frontMatter {
            return true
        }
        return false
    }

}

private extension Array where Element == BlockInputBlock {
    var clipboardMarkdownBlocks: [BlockInputBlock] {
        map(\.clipboardMarkdownBlock)
    }
}

private extension BlockInputBlock {
    var clipboardMarkdownBlock: BlockInputBlock {
        guard case var .image(image) = kind,
              image.width == nil,
              image.height == nil else {
            return self
        }
        image.sourceStyle = .markdown
        var block = self
        block.kind = .image(image)
        return block
    }
}

private extension String {
    func clampedRange(_ range: NSRange) -> NSRange {
        let text = self as NSString
        let location = min(max(range.location, 0), text.length)
        let length = min(max(range.length, 0), max(text.length - location, 0))
        return NSRange(location: location, length: length)
    }
}
