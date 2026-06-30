import AppKit

extension BlockInputTableView {
    func adjustCellSelection(from textView: NSTextView, vertically direction: BlockInputVerticalMovementDirection) -> Bool {
        let delta = direction == .upward ? -1 : 1
        return adjustRowSelection(from: textView, delta: delta)
    }

    func adjustCellSelection(from textView: NSTextView, horizontally direction: BlockInputHorizontalMovementDirection) -> Bool {
        let delta = direction == .leftward ? -1 : 1
        return adjustColumnSelection(from: textView, delta: delta)
    }

    @discardableResult
    func selectKeyboardRows(anchorDisplayRow: Int, focusDisplayRow: Int) -> Bool {
        guard let selection = rowSelection(anchorDisplayRow: anchorDisplayRow, focusDisplayRow: focusDisplayRow) else {
            return false
        }
        selectedRow = nil
        selectedCellRange = selection
        updateSelectionChrome()
        return true
    }

    func clearKeyboardCellSelection() {
        selectedCellRange = nil
        updateSelectionChrome()
    }

    var keyboardDisplayRowRange: ClosedRange<Int>? {
        guard let table else {
            return nil
        }
        return 0...table.bodyRows.count
    }

    private func adjustRowSelection(from textView: NSTextView, delta: Int) -> Bool {
        guard let table,
              let activePosition = cellView(containing: textView)?.position else {
            return false
        }
        let lastDisplayRow = table.bodyRows.count
        let selection = selectedCellRange
        let anchorDisplayRow: Int
        let focusDisplayRow: Int
        if let selection, isSelectedWholeRows(selection) {
            anchorDisplayRow = BlockInputTableCellSelection.displayRowIndex(for: selection.anchor.row)
            focusDisplayRow = min(max(BlockInputTableCellSelection.displayRowIndex(for: selection.focus.row) + delta, 0), lastDisplayRow)
        } else {
            let activeDisplayRow = BlockInputTableCellSelection.displayRowIndex(for: activePosition.row)
            anchorDisplayRow = activeDisplayRow
            focusDisplayRow = activeDisplayRow
        }
        guard let nextSelection = rowSelection(anchorDisplayRow: anchorDisplayRow, focusDisplayRow: focusDisplayRow) else {
            return false
        }
        selectedRow = nil
        selectedCellRange = nextSelection
        updateSelectionChrome()
        if promoteWholeCellSelectionToTableSelectionIfNeeded() {
            return true
        }
        publishActiveCellSourceSelection(from: textView)
        return true
    }

    private func adjustColumnSelection(from textView: NSTextView, delta: Int) -> Bool {
        guard let table,
              let activePosition = cellView(containing: textView)?.position else {
            return false
        }
        let lastColumn = max(table.columnCount - 1, 0)
        let selection = selectedCellRange
        let anchorColumn: Int
        let focusColumn: Int
        if let selection, isSelectedWholeColumns(selection) {
            anchorColumn = selection.anchor.column
            focusColumn = min(max(selection.focus.column + delta, 0), lastColumn)
        } else {
            anchorColumn = activePosition.column
            focusColumn = activePosition.column
        }
        guard let nextSelection = columnSelection(anchorColumn: anchorColumn, focusColumn: focusColumn) else {
            return false
        }
        selectedRow = nil
        selectedCellRange = nextSelection
        updateSelectionChrome()
        if promoteWholeCellSelectionToTableSelectionIfNeeded() {
            return true
        }
        publishActiveCellSourceSelection(from: textView)
        return true
    }

    private func rowSelection(anchorDisplayRow: Int, focusDisplayRow: Int) -> BlockInputTableCellSelection? {
        guard let table,
              table.columnCount > 0 else {
            return nil
        }
        let lastDisplayRow = table.bodyRows.count
        let clampedAnchorRow = min(max(anchorDisplayRow, 0), lastDisplayRow)
        let clampedFocusRow = min(max(focusDisplayRow, 0), lastDisplayRow)
        return BlockInputTableCellSelection(
            anchor: BlockInputTable.CellPosition(
                row: BlockInputTableCellSelection.row(forDisplayRowIndex: clampedAnchorRow),
                column: 0
            ),
            focus: BlockInputTable.CellPosition(
                row: BlockInputTableCellSelection.row(forDisplayRowIndex: clampedFocusRow),
                column: table.columnCount - 1
            )
        )
    }

    private func columnSelection(anchorColumn: Int, focusColumn: Int) -> BlockInputTableCellSelection? {
        guard let table,
              table.columnCount > 0 else {
            return nil
        }
        let lastColumn = table.columnCount - 1
        let clampedAnchorColumn = min(max(anchorColumn, 0), lastColumn)
        let clampedFocusColumn = min(max(focusColumn, 0), lastColumn)
        return BlockInputTableCellSelection(
            anchor: BlockInputTable.CellPosition(row: .header, column: clampedAnchorColumn),
            focus: BlockInputTable.CellPosition(
                row: BlockInputTableCellSelection.row(forDisplayRowIndex: table.bodyRows.count),
                column: clampedFocusColumn
            )
        )
    }

    private func isSelectedWholeRows(_ selectedCellRange: BlockInputTableCellSelection) -> Bool {
        guard let table,
              table.columnCount > 0 else {
            return false
        }
        return selectedCellRange.columnRange == 0...(table.columnCount - 1)
    }

    private func isSelectedWholeColumns(_ selectedCellRange: BlockInputTableCellSelection) -> Bool {
        guard let table,
              table.columnCount > 0 else {
            return false
        }
        return selectedCellRange.rowRange == 0...table.bodyRows.count
    }
}
