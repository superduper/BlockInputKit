import AppKit

extension BlockInputView {
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didChangeTableCellText change: BlockInputTableCellTextChange
    ) {
        guard isEditable else {
            if let block = block(withID: blockID) {
                item.updateTableCellEditState(for: block)
            }
            return
        }
        guard let index = index(of: blockID),
              let beforeBlock = block(at: index),
              beforeBlock.kind == .table,
              let beforeTable = BlockInputTable(markdown: beforeBlock.text),
              let afterTable = beforeTable.replacingCellText(
                row: change.position.row,
                column: change.position.column,
                text: change.text
              ) else {
            return
        }
        var afterBlock = beforeBlock
        afterBlock.text = afterTable.markdown
        guard beforeBlock != afterBlock else {
            item.tableView.updateTableAfterCellEdit(afterTable)
            return
        }

        let beforeSelection = change.selectionBefore ?? selection
        let didReplaceCachedBlock = replaceCachedBlock(afterBlock, at: index)
        // Table cell selection normalization reads the store-backed block text, so update the store before refreshing
        // the table view can emit selection changes using the edited table's fresh source ranges.
        syncDocumentStore(.replaceBlock(afterBlock))
        item.tableView.updateTableAfterCellEdit(afterTable)
        let afterSelection = tableCellSelection(blockID: blockID, table: afterTable, change: change)
        applySelection(afterSelection, notify: true)
        undoController?.registerTextEdit(
            blockID: blockID,
            beforeText: beforeBlock.text,
            afterText: afterBlock.text,
            beforeLineIndentationLevels: beforeBlock.lineIndentationLevels,
            afterLineIndentationLevels: afterBlock.lineIndentationLevels,
            selectionBefore: beforeSelection,
            selectionAfter: afterSelection
        )
        item.updateTableCellEditState(for: afterBlock)
        if shouldInvalidateLayoutForTextChange(item: item, beforeBlock: beforeBlock, afterBlock: afterBlock) {
            resizeVisibleItem(item, for: afterBlock)
            invalidateLayoutForBlock(at: index, editedItem: item, block: afterBlock)
        }
        if !didReplaceCachedBlock && isDocumentCacheSynchronized {
            refreshDocumentFromStore()
        }
        publishDocumentChange()
        dismissCompletionPopup()
    }

    private func tableCellSelection(
        blockID: BlockInputBlockID,
        table: BlockInputTable,
        change: BlockInputTableCellTextChange
    ) -> BlockInputSelection {
        guard let sourceRange = table.sourceRange(forLocalRange: change.selectedLocalRange, in: change.position) else {
            let fallbackOffset = table.cell(at: change.position).map { NSMaxRange($0.sourceRange) } ?? table.markdown.utf16.count
            return .cursor(BlockInputCursor(blockID: blockID, utf16Offset: fallbackOffset))
        }
        if sourceRange.length == 0 {
            return .cursor(BlockInputCursor(blockID: blockID, utf16Offset: sourceRange.location))
        }
        return .text(BlockInputTextRange(blockID: blockID, range: sourceRange))
    }
}
