import AppKit

extension BlockInputView {
    struct ReturnSelection {
        var offset: Int
        var length: Int
    }

    /// Inserts a new block with a specific kind and text below the active block (vim register paste).
    ///
    /// Unlike `insertBlockBelowCurrentBlock()`, this preserves the block kind (heading level, list type, etc.)
    /// from a yanked or deleted block. Caret lands at the start of the new block.
    @discardableResult
    func insertBlockBelowCurrentBlock(kind: BlockInputBlockKind, text: String) -> BlockInputSelection? {
        guard isEditable, let blockID = activeBlockID else { return nil }
        let newBlock = BlockInputBlock(kind: kind, text: text)
        let afterSelection = BlockInputSelection.cursor(BlockInputCursor(blockID: newBlock.id, utf16Offset: 0))
        return performStructuralEdit(named: "Paste Block") { document in
            guard let index = document.index(of: blockID) else { return nil }
            document.insertBlock(newBlock, at: index + 1)
            return afterSelection
        }
    }

    /// Inserts a new empty paragraph block above the active block and moves the caret into it (vim `O`).
    @discardableResult
    public func insertBlockAboveCurrentBlock() -> BlockInputSelection? {
        guard isEditable, let blockID = activeBlockID else { return nil }
        let insertedBlock = BlockInputBlock()
        let afterSelection = BlockInputSelection.cursor(BlockInputCursor(blockID: insertedBlock.id, utf16Offset: 0))
        return performStructuralEdit(named: "Insert Block") { document in
            guard let index = document.index(of: blockID) else { return nil }
            document.insertBlock(insertedBlock, at: index)
            return afterSelection
        }
    }

    /// Deletes the active block and moves the caret to the adjacent block (vim `dd`).
    ///
    /// If the document has only one block, the block's content is cleared instead.
    @discardableResult
    public func deleteCurrentBlock() -> BlockInputSelection? {
        guard isEditable, let blockID = activeBlockID else { return nil }
        refreshDocumentFromStore()
        return performStructuralEdit(named: "Delete Block") { document in
            document.deleteBlock(blockID: blockID)
        }
    }

    /// Selects the active block as a whole-block selection (vim `V`).
    @discardableResult
    public func selectCurrentBlock() -> BlockInputSelection? {
        guard let blockID = activeBlockID else { return nil }
        let blockSelection = BlockInputSelection.blocks([blockID])
        applySelection(blockSelection, notify: true)
        return blockSelection
    }

    /// Moves the caret to the start of the block immediately after the active block.
    @discardableResult
    public func moveAfterCurrentBlock() -> BlockInputSelection? {
        refreshDocumentFromStore()
        guard let blockID = activeBlockID,
              let index = document.index(of: blockID),
              document.blocks.indices.contains(index + 1) else {
            return nil
        }
        let target = document.blocks[index + 1]
        let cursor = BlockInputCursor(blockID: target.id, utf16Offset: 0)
        applySelection(.cursor(cursor), notify: true)
        // Scroll the block into view and seat the text-view selection synchronously so that
        // the next movement command (e.g. another vim `j`) can dispatch doCommand on a mounted,
        // properly-focused text view. Without this, mountedBlockItem returns nil for an off-screen
        // block and the cursor stalls at the bottom of the visible viewport.
        focusVisibleItem(for: cursor)
        return .cursor(cursor)
    }

    /// Moves the caret to the start of the block immediately before the active block.
    @discardableResult
    public func moveBeforeCurrentBlock() -> BlockInputSelection? {
        refreshDocumentFromStore()
        guard let blockID = activeBlockID,
              let index = document.index(of: blockID),
              index > 0 else {
            return nil
        }
        let target = document.blocks[index - 1]
        let cursor = BlockInputCursor(blockID: target.id, utf16Offset: 0)
        applySelection(.cursor(cursor), notify: true)
        focusVisibleItem(for: cursor)
        return .cursor(cursor)
    }

    /// Applies Return key semantics to the active block.
    @discardableResult
    public func insertBlockBelowCurrentBlock() -> BlockInputSelection? {
        guard isEditable,
              let blockID = activeBlockID else {
            return nil
        }
        let returnSelection = currentReturnSelection(for: blockID)
        if let granularSelection = performGranularReturnIfPossible(
            blockID: blockID,
            returnSelection: returnSelection
        ) {
            return granularSelection
        }

        refreshDocumentFromStore()
        let focusedBlock = block(withID: blockID)
        let actionName = returnActionName(for: focusedBlock, selection: returnSelection)
        return performStructuralEdit(
            named: actionName,
            storeSyncAction: { beforeDocument, afterDocument, afterSelection in
                self.returnStoreSyncAction(
                    for: blockID,
                    beforeDocument: beforeDocument,
                    afterDocument: afterDocument,
                    afterSelection: afterSelection
                )
            },
            edit: { document in
                document.handleReturn(
                    in: blockID,
                    utf16Offset: returnSelection?.offset,
                    selectedUTF16Length: returnSelection?.length ?? 0
                )
            }
        )
    }

    private func performGranularReturnIfPossible(
        blockID: BlockInputBlockID,
        returnSelection: ReturnSelection?
    ) -> BlockInputSelection? {
        guard let index = activeStandaloneBlockIndex(for: blockID),
              let block = block(at: index),
              cachedBlockMatches(block, at: index) else {
            return nil
        }
        if let leadingReturnMove = leadingReturnMove(from: block, selection: returnSelection) {
            return performGranularLeadingReturnMove(
                actionName: "Insert Block",
                beforeBlock: block,
                leadingReturnMove: leadingReturnMove,
                replacementIndex: index
            )
        }
        if let replacement = block.codeFenceBlockForReturn(
            utf16Offset: returnSelection?.offset,
            selectedUTF16Length: returnSelection?.length ?? 0
        ) {
            return performGranularReturnBlockReplacement(
                actionName: "Format Block",
                beforeBlock: block,
                afterBlock: replacement,
                index: index
            )
        }
        if let replacement = replacementBlockForGranularReturn(from: block, at: index, selection: returnSelection) {
            return performGranularReturnBlockReplacement(
                actionName: returnActionName(for: block, selection: returnSelection),
                beforeBlock: block,
                afterBlock: replacement,
                index: index
            )
        }
        if let inlineExit = inlineExitForGranularReturn(from: block, selection: returnSelection) {
            return performGranularReturnInlineExit(
                actionName: returnActionName(for: block, selection: returnSelection),
                beforeBlock: block,
                inlineExit: inlineExit,
                replacementIndex: index
            )
        }
        guard let insertedBlock = insertedBlockForGranularReturn(from: block, selection: returnSelection) else {
            return nil
        }
        return performGranularReturnBlockInsertion(
            actionName: "Insert Block",
            sourceBlock: block,
            sourceIndex: index,
            insertedBlock: insertedBlock,
            insertionIndex: index + 1
        )
    }

    private func cachedBlockMatches(_ block: BlockInputBlock, at index: Int) -> Bool {
        guard isDocumentCacheSynchronized else {
            return documentStore != nil
        }
        return document.blocks.indices.contains(index) && document.blocks[index] == block
    }

    private func replacementBlockForGranularReturn(
        from block: BlockInputBlock,
        at index: Int,
        selection: ReturnSelection?
    ) -> BlockInputBlock? {
        if block.isEmpty,
           returnOutdentsListItem(block: block, selection: selection) {
            var replacement = block
            let lineIndentation = replacement.indentationLevel(forLine: 0)
            if replacement.lineIndentationLevels.isEmpty {
                replacement.indentationLevel = max(0, lineIndentation - 1)
            } else {
                replacement.setIndentationLevel(lineIndentation - 1, forLine: 0)
            }
            normalizeNumberedListStartIfNeeded(for: &replacement, at: index)
            return replacement
        }
        guard block.isEmpty,
              block.kind.exitsToParagraphOnEmptyReturn,
              !returnOutdentsListItem(block: block, selection: selection) else {
            return nil
        }
        return BlockInputBlock(id: block.id, kind: .paragraph)
    }

    private func insertedBlockForGranularReturn(
        from block: BlockInputBlock,
        selection: ReturnSelection?
    ) -> BlockInputBlock? {
        if block.kind.insertsSiblingListItemOnReturn {
            guard block.lineIndentationLevels.isEmpty,
                  block.text.rangeOfCharacter(from: .newlines) == nil,
                  (selection?.length ?? 0) == 0,
                  (selection?.offset ?? block.utf16Length) == block.utf16Length else {
                return nil
            }
            return BlockInputBlock(
                kind: nextListKind(after: block.kind),
                indentationLevel: block.indentationLevel
            )
        }
        guard !block.kind.acceptsInlineReturn,
              !(block.isEmpty && block.kind.exitsToParagraphOnEmptyReturn) else {
            return nil
        }
        // Only the end-of-block, no-selection case appends a plain empty block; a mid-block caret (or a
        // selection) must split text, which the structural handleReturn path handles, so fall through.
        guard (selection?.length ?? 0) == 0,
              (selection?.offset ?? block.utf16Length) == block.utf16Length else {
            return nil
        }
        return BlockInputBlock()
    }

    private func performGranularReturnBlockReplacement(
        actionName: String,
        beforeBlock: BlockInputBlock,
        afterBlock: BlockInputBlock,
        index: Int
    ) -> BlockInputSelection {
        let beforeSelection = selection
        let afterSelection = BlockInputSelection.cursor(BlockInputCursor(
            blockID: afterBlock.id,
            utf16Offset: 0
        ))
        syncDocumentStore(.replaceBlock(afterBlock))
        _ = replaceCachedBlock(afterBlock, at: index)
        applySelection(afterSelection, notify: true)
        undoController?.registerBlockReplacementStructuralEdit(
            actionName: actionName,
            beforeBlock: beforeBlock,
            afterBlock: afterBlock,
            selectionBefore: beforeSelection,
            selectionAfter: afterSelection
        )
        reloadVisibleBlock(at: index)
        publishDocumentChange()
        return afterSelection
    }

    private func performGranularReturnBlockInsertion(
        actionName: String,
        sourceBlock: BlockInputBlock,
        sourceIndex: Int,
        insertedBlock: BlockInputBlock,
        insertionIndex: Int
    ) -> BlockInputSelection? {
        let beforeSelection = selection
        let insertedBlocks = [insertedBlock]
        let resolvedInsertionIndex = frontMatterPreservingInsertionIndex(insertionIndex)
        guard let numberingChanges = prepareReturnInsertionNumberingChanges(
            sourceBlock: sourceBlock,
            sourceIndex: sourceIndex,
            insertedBlock: insertedBlock,
            insertedBlocks: insertedBlocks,
            insertionIndex: resolvedInsertionIndex
        ) else {
            return nil
        }
        let afterSelection = BlockInputSelection.cursor(BlockInputCursor(
            blockID: insertedBlock.id,
            utf16Offset: 0
        ))
        syncDocumentStore(.insertBlocks(insertedBlocks, insertionIndex: resolvedInsertionIndex))
        if let markerTransaction = numberingChanges.afterMarkerTransaction {
            syncDocumentStore(.numberedListMarkerTransaction(markerTransaction))
        } else {
            numberingChanges.afterChangedBlocks.forEach { syncDocumentStore(.replaceBlock($0)) }
        }
        applySelection(afterSelection, notify: true)
        undoController?.registerBlockInsertionStructuralEdit(
            actionName: actionName,
            insertedBlocks: insertedBlocks,
            insertionIndex: resolvedInsertionIndex,
            beforeChangedBlocks: numberingChanges.beforeChangedBlocks,
            afterChangedBlocks: numberingChanges.afterChangedBlocks,
            beforeMarkerTransaction: numberingChanges.beforeMarkerTransaction,
            afterMarkerTransaction: numberingChanges.afterMarkerTransaction,
            selectionBefore: beforeSelection,
            selectionAfter: afterSelection
        )
        insertVisibleBlock(at: resolvedInsertionIndex)
        publishDocumentChange()
        return afterSelection
    }

    func reloadVisibleBlock(at index: Int) {
        let indexPath = IndexPath(item: index, section: 0)
        if shouldDeferGranularCountLayout,
           let block = block(at: index),
           reconfigureVisibleReplacement(block, at: index) {
            // Same-row replacements, such as empty quote -> paragraph, should
            // stay mounted in large documents instead of reloading the row.
            return
        }
        collectionView.reloadItems(at: [indexPath])
        collectionView.layoutSubtreeIfNeeded()
        restoreVisibleSelection()
        invalidatePreferredHeight()
    }

    func insertVisibleBlock(at index: Int) {
        let indexPath = IndexPath(item: index, section: 0)
        if shouldDeferGranularCountLayout {
            reconfigureMountedBlocksAfterGranularCountChange(startingAt: index)
            scrollActiveTextSelectionToVisibleIfNeeded()
            return
        }
        collectionView.insertItems(at: [indexPath])
        collectionView.layoutSubtreeIfNeeded()
        restoreMountedSelection()
        invalidatePreferredHeight()
        scrollActiveTextSelectionToVisibleIfNeeded()
    }

    private func currentReturnSelection(for blockID: BlockInputBlockID) -> ReturnSelection? {
        switch selection {
        case let .cursor(cursor) where cursor.blockID == blockID:
            return ReturnSelection(offset: cursor.utf16Offset, length: 0)
        case let .text(range) where range.blockID == blockID:
            return ReturnSelection(offset: range.range.location, length: range.range.length)
        default:
            return nil
        }
    }

    private func returnActionName(for block: BlockInputBlock?, selection: ReturnSelection?) -> String {
        guard let block else {
            return "Insert Block"
        }
        if returnOutdentsListItem(block: block, selection: selection) {
            return "Outdent Block"
        }
        if block.isEmpty && block.kind.exitsToParagraphOnEmptyReturn {
            return "Unformat Block"
        }
        if block.codeFenceBlockForReturn(
            utf16Offset: selection?.offset,
            selectedUTF16Length: selection?.length ?? 0
        ) != nil {
            return "Format Block"
        }
        guard !block.isEmpty && block.kind.acceptsInlineReturn else {
            return "Insert Block"
        }
        let requiresStructuralReturn = block.requiresStructuralReturnHandling(
            utf16Offset: selection?.offset ?? block.utf16Length,
            selectedUTF16Length: selection?.length ?? 0
        )
        return requiresStructuralReturn ? "Insert Block" : "Insert Line"
    }

    private func returnOutdentsListItem(block: BlockInputBlock, selection: ReturnSelection?) -> Bool {
        guard block.kind.supportsIndentation,
              (selection?.length ?? 0) == 0 else {
            return false
        }
        if block.isEmpty {
            return block.indentationLevel(forLine: 0) > 0
        }
        guard block.kind.acceptsInlineReturn else {
            return false
        }
        let offset = selection?.offset ?? block.utf16Length
        guard block.emptyInlineLineRemovalRangeForReturn(utf16Offset: offset) != nil else {
            return false
        }
        let lineIndex = block.lineIndex(containingUTF16Offset: offset)
        return block.indentationLevel(forLine: lineIndex) > 0
    }

    private func returnStoreSyncAction(
        for blockID: BlockInputBlockID,
        beforeDocument: BlockInputDocument,
        afterDocument: BlockInputDocument,
        afterSelection: BlockInputSelection
    ) -> StoreSyncAction {
        guard case let .cursor(cursor) = afterSelection,
              let focusedBlock = afterDocument.block(withID: cursor.blockID) else {
            return .replaceDocument
        }
        if beforeDocument.blocks.count == afterDocument.blocks.count {
            return .replaceBlock(focusedBlock)
        }
        if let beforeSourceBlock = beforeDocument.block(withID: blockID),
           let afterSourceBlock = afterDocument.block(withID: blockID),
           beforeSourceBlock != afterSourceBlock {
            return .replaceDocument
        }
        guard let insertedIndex = afterDocument.index(of: cursor.blockID) else {
            return .replaceDocument
        }
        return .insertBlocks([focusedBlock], insertionIndex: insertedIndex)
    }

    private func normalizeNumberedListStartIfNeeded(
        for block: inout BlockInputBlock,
        at index: Int
    ) {
        guard case .numberedListItem = block.kind else {
            return
        }
        let indentationLevel = block.indentationLevel(forLine: 0)
        if let previousStart = previousNumberedListStart(before: index, indentationLevel: indentationLevel) {
            block.kind = .numberedListItem(start: previousStart + 1)
        } else if indentationLevel > 0 {
            block.kind = .numberedListItem(start: 1)
        }
    }

    private func previousNumberedListStart(before index: Int, indentationLevel: Int) -> Int? {
        guard index > 0 else {
            return nil
        }
        var visitedCount = 0
        for previousIndex in stride(from: index - 1, through: 0, by: -1) {
            guard visitedCount < 128 else {
                return nil
            }
            visitedCount += 1
            guard let previousBlock = block(at: previousIndex),
                  previousBlock.kind.isReturnListItem else {
                return nil
            }
            let previousIndentationLevel = previousBlock.indentationLevel(forLine: 0)
            if case let .numberedListItem(start) = previousBlock.kind,
               previousIndentationLevel == indentationLevel {
                return start
            }
            if previousIndentationLevel < indentationLevel {
                return nil
            }
        }
        return nil
    }

    private func nextListKind(after kind: BlockInputBlockKind) -> BlockInputBlockKind {
        switch kind {
        case .bulletedListItem:
            return .bulletedListItem
        case let .numberedListItem(start):
            return .numberedListItem(start: start + 1)
        case .checklistItem:
            return .checklistItem(isChecked: false)
        case .paragraph, .heading, .code, .horizontalRule, .frontMatter, .quote, .table, .image, .rawMarkdown:
            return kind
        }
    }

}

private extension BlockInputBlockKind {
    var isReturnListItem: Bool {
        switch self {
        case .bulletedListItem, .numberedListItem, .checklistItem:
            return true
        case .paragraph, .heading, .code, .horizontalRule, .frontMatter, .quote, .table, .image, .rawMarkdown:
            return false
        }
    }
}
