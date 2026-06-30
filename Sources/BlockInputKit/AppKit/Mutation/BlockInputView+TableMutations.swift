import AppKit

extension BlockInputView {
    func blockItemDidRequestSelectTable(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) {
        refreshDocumentFromStore()
        guard block(withID: blockID)?.kind == .table else {
            return
        }
        applySelection(.blocks([blockID]), notify: true)
        if window != nil {
            window?.makeFirstResponder(self)
            selectOnlyVisibleBlockItem(item)
            publishFocusChange(true)
        }
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestTableFocus position: BlockInputTable.CellPosition
    ) -> Bool {
        guard let block = block(withID: blockID),
              let table = BlockInputTable(markdown: block.text),
              let afterSelection = tableSelection(blockID: blockID, table: table, position: position) else {
            return false
        }
        applySelection(afterSelection, notify: true)
        item.tableView.focusCell(at: position)
        return true
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestTableBodyRowAppendFrom position: BlockInputTable.CellPosition?
    ) -> Bool {
        appendTableBodyRow(blockID: blockID)
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestTableColumnAppendFrom position: BlockInputTable.CellPosition?
    ) -> Bool {
        appendTableColumn(blockID: blockID)
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestTableBodyRowInsertionAt position: BlockInputTable.CellPosition
    ) -> Bool {
        insertTableBodyRow(blockID: blockID, position: position)
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestTableBodyRowDeletionAt position: BlockInputTable.CellPosition
    ) -> Bool {
        deleteTableBodyRow(blockID: blockID, position: position, keepsLastBodyRow: true)
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestTableColumnDeletionAt position: BlockInputTable.CellPosition
    ) -> Bool {
        deleteTableColumn(blockID: blockID, position: position)
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestParagraphAdjacentToTable placement: BlockInputTableBoundaryPlacement
    ) -> Bool {
        insertParagraphAdjacentToTable(blockID: blockID, placement: placement)
    }

    @discardableResult
    func insertTable(after blockID: BlockInputBlockID) -> Bool {
        guard isEditable else {
            return false
        }
        guard let index = index(of: blockID) else {
            return false
        }
        let table = BlockInputTable.normalized(
            header: ["", ""],
            bodyRows: [["", ""]],
            alignments: [.left, .left]
        )
        if let existingBlock = block(at: index),
           existingBlock.kind.allowsTableContextInsertion,
           existingBlock.isEmpty {
            let beforeSelection = selection
            let replacement = BlockInputBlock(id: existingBlock.id, kind: .table, text: table.markdown)
            guard let replacementSelection = tableSelection(
                blockID: replacement.id,
                table: table,
                position: BlockInputTable.CellPosition(row: .header, column: 0)
            ) else {
                return false
            }
            _ = applyGranularBlockReplacement(replacement, at: index, selection: replacementSelection)
            undoController?.registerBlockReplacementStructuralEdit(
                actionName: "Insert Table",
                beforeBlock: existingBlock,
                afterBlock: replacement,
                selectionBefore: beforeSelection,
                selectionAfter: replacementSelection
            )
            return true
        }
        let insertedBlock = BlockInputBlock(kind: .table, text: table.markdown)
        guard let afterSelection = tableSelection(
            blockID: insertedBlock.id,
            table: table,
            position: BlockInputTable.CellPosition(row: .header, column: 0)
        ) else {
            return false
        }
        return insertBlock(insertedBlock, at: index + 1, actionName: "Insert Table", selectionAfter: afterSelection)
    }

    @discardableResult
    func deleteTable(blockID: BlockInputBlockID) -> Bool {
        guard isEditable else {
            return false
        }
        refreshDocumentFromStore()
        guard block(withID: blockID)?.kind == .table else {
            return false
        }
        return performStructuralEdit(
            named: "Delete Table",
            storeSyncAction: { beforeDocument, afterDocument, _ in
                if beforeDocument.blocks.count == 1,
                   let replacementBlock = afterDocument.blocks.first {
                    return .replaceBlock(replacementBlock)
                }
                return .deleteBlocks([blockID])
            },
            edit: { document in
                document.deleteBlock(blockID: blockID)
            }
        ) != nil
    }

    @discardableResult
    func appendTableBodyRow(blockID: BlockInputBlockID) -> Bool {
        guard isEditable else {
            return false
        }
        guard let beforeBlock = block(withID: blockID),
              let table = BlockInputTable(markdown: beforeBlock.text) else {
            return false
        }
        let updatedTable = table.appendingBodyRow()
        let focus = BlockInputTable.CellPosition(row: .body(table.bodyRows.count), column: 0)
        return replaceTableBlock(blockID: blockID, with: updatedTable, focus: focus, actionName: "Append Row")
    }

    @discardableResult
    func appendTableColumn(blockID: BlockInputBlockID) -> Bool {
        guard isEditable else {
            return false
        }
        guard let beforeBlock = block(withID: blockID),
              let table = BlockInputTable(markdown: beforeBlock.text) else {
            return false
        }
        let updatedTable = table.appendingColumn()
        let focus = BlockInputTable.CellPosition(row: .header, column: table.columnCount)
        return replaceTableBlock(blockID: blockID, with: updatedTable, focus: focus, actionName: "Append Column")
    }

    @discardableResult
    func insertTableBodyRow(blockID: BlockInputBlockID, position: BlockInputTable.CellPosition) -> Bool {
        guard isEditable else {
            return false
        }
        guard let beforeBlock = block(withID: blockID),
              let table = BlockInputTable(markdown: beforeBlock.text) else {
            return false
        }
        let insertionIndex: Int
        switch position.row {
        case .header:
            insertionIndex = 0
        case .body(let rowIndex):
            insertionIndex = rowIndex + 1
        }
        guard let updatedTable = table.insertingBodyRow(at: insertionIndex) else {
            return false
        }
        let focus = BlockInputTable.CellPosition(row: .body(insertionIndex), column: 0)
        return replaceTableBlock(blockID: blockID, with: updatedTable, focus: focus, actionName: "Insert Row")
    }

    @discardableResult
    func insertTableColumn(blockID: BlockInputBlockID, position: BlockInputTable.CellPosition) -> Bool {
        guard isEditable else {
            return false
        }
        guard let beforeBlock = block(withID: blockID),
              let table = BlockInputTable(markdown: beforeBlock.text) else {
            return false
        }
        let insertionColumn = position.column + 1
        guard let updatedTable = table.insertingColumn(at: insertionColumn) else {
            return false
        }
        let focus = BlockInputTable.CellPosition(row: position.row, column: insertionColumn)
        return replaceTableBlock(blockID: blockID, with: updatedTable, focus: focus, actionName: "Insert Column")
    }

    @discardableResult
    func deleteTableBodyRow(
        blockID: BlockInputBlockID,
        position: BlockInputTable.CellPosition,
        keepsLastBodyRow: Bool
    ) -> Bool {
        guard isEditable else {
            return false
        }
        guard case .body(let rowIndex) = position.row,
              let beforeBlock = block(withID: blockID),
              let table = BlockInputTable(markdown: beforeBlock.text),
              let updatedTable = table.deletingBodyRow(rowIndex, keepsLastBodyRow: keepsLastBodyRow) else {
            return false
        }
        let targetRowIndex = min(rowIndex, max(updatedTable.bodyRows.count - 1, 0))
        let focus = BlockInputTable.CellPosition(
            row: .body(targetRowIndex),
            column: min(position.column, max(updatedTable.columnCount - 1, 0))
        )
        return replaceTableBlock(blockID: blockID, with: updatedTable, focus: focus, actionName: "Delete Row")
    }

    @discardableResult
    func deleteTableColumn(blockID: BlockInputBlockID, position: BlockInputTable.CellPosition) -> Bool {
        guard isEditable else {
            return false
        }
        guard let beforeBlock = block(withID: blockID),
              let table = BlockInputTable(markdown: beforeBlock.text),
              let updatedTable = table.deletingColumn(position.column) else {
            return false
        }
        let targetColumn = min(position.column, max(updatedTable.columnCount - 1, 0))
        let focusRow: BlockInputTable.Row
        switch position.row {
        case .header:
            focusRow = .header
        case .body(let rowIndex):
            focusRow = .body(min(rowIndex, max(updatedTable.bodyRows.count - 1, 0)))
        }
        let focus = BlockInputTable.CellPosition(row: focusRow, column: targetColumn)
        return replaceTableBlock(blockID: blockID, with: updatedTable, focus: focus, actionName: "Delete Column")
    }

    private func insertParagraphAdjacentToTable(
        blockID: BlockInputBlockID,
        placement: BlockInputTableBoundaryPlacement
    ) -> Bool {
        guard isEditable else {
            return false
        }
        guard let index = index(of: blockID),
              block(at: index)?.kind == .table else {
            return false
        }
        let insertedBlock = BlockInputBlock()
        let insertionIndex = placement == .above ? index : index + 1
        let afterSelection = BlockInputSelection.cursor(BlockInputCursor(blockID: insertedBlock.id, utf16Offset: 0))
        return insertBlock(insertedBlock, at: insertionIndex, actionName: "Insert Block", selectionAfter: afterSelection)
    }

    private func replaceTableBlock(
        blockID: BlockInputBlockID,
        with table: BlockInputTable,
        focus position: BlockInputTable.CellPosition,
        actionName: String
    ) -> Bool {
        guard isEditable else {
            return false
        }
        guard let index = index(of: blockID),
              var block = block(at: index),
              block.kind == .table,
              let afterSelection = tableSelection(blockID: blockID, table: table, position: position) else {
            return false
        }
        let beforeBlock = block
        let beforeSelection = selection
        block.text = table.markdown
        _ = applyGranularBlockReplacement(block, at: index, selection: afterSelection)
        undoController?.registerBlockReplacementStructuralEdit(
            actionName: actionName,
            beforeBlock: beforeBlock,
            afterBlock: block,
            selectionBefore: beforeSelection,
            selectionAfter: afterSelection
        )
        return true
    }

    private func insertBlock(
        _ block: BlockInputBlock,
        at insertionIndex: Int,
        actionName: String,
        selectionAfter afterSelection: BlockInputSelection
    ) -> Bool {
        guard isEditable else {
            return false
        }
        let beforeSelection = selection
        let insertedBlocks = [block]
        let resolvedInsertionIndex = frontMatterPreservingInsertionIndex(insertionIndex)
        if canSynchronizeCacheForGranularInsertion(insertedBlockCount: insertedBlocks.count) {
            guard document.insertBlocks(insertedBlocks, at: resolvedInsertionIndex) != nil else {
                return false
            }
        } else {
            markDocumentCacheUnsynchronized()
        }
        syncDocumentStore(.insertBlocks(insertedBlocks, insertionIndex: resolvedInsertionIndex))
        applySelection(afterSelection, notify: true)
        undoController?.registerBlockInsertionStructuralEdit(
            actionName: actionName,
            insertedBlocks: insertedBlocks,
            insertionIndex: resolvedInsertionIndex,
            selectionBefore: beforeSelection,
            selectionAfter: afterSelection
        )
        insertVisibleBlock(at: resolvedInsertionIndex)
        publishDocumentChange()
        return true
    }

    private func tableSelection(
        blockID: BlockInputBlockID,
        table: BlockInputTable,
        position: BlockInputTable.CellPosition
    ) -> BlockInputSelection? {
        guard let sourceRange = table.sourceRange(forLocalRange: NSRange(location: 0, length: 0), in: position) else {
            return nil
        }
        return .cursor(BlockInputCursor(blockID: blockID, utf16Offset: sourceRange.location))
    }
}
