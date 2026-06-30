import AppKit

extension BlockInputTableView {
    var activeCellSelectedSourceRange: NSRange? {
        guard let activeCell = activeCellView else {
            return nil
        }
        return sourceRange(for: activeCell.textView, localRange: activeCell.textView.selectedRange())
    }

    func isTableCellTextView(_ textView: NSTextView) -> Bool {
        cellView(containing: textView) != nil
    }

    func sourceRange(for textView: NSTextView, localRange: NSRange) -> NSRange? {
        guard let table,
              let cellView = cellView(containing: textView) else {
            return nil
        }
        return table.sourceRange(forLocalRange: localRange, in: cellView.position)
    }

    func sourceSelection(for textView: NSTextView, localRange: NSRange) -> BlockInputSelection? {
        guard let configuredBlockID,
              let sourceRange = sourceRange(for: textView, localRange: localRange) else {
            return nil
        }
        if sourceRange.length == 0 {
            return .cursor(BlockInputCursor(blockID: configuredBlockID, utf16Offset: sourceRange.location))
        }
        return .text(BlockInputTextRange(blockID: configuredBlockID, range: sourceRange))
    }

    func sourceInlineMarkdownRange(
        for textView: NSTextView,
        localRange: BlockInputInlineMarkdownRange
    ) -> BlockInputInlineMarkdownRange? {
        guard let sourceFullRange = sourceRange(for: textView, localRange: localRange.fullRange),
              let sourceContentRange = sourceRange(for: textView, localRange: localRange.contentRange) else {
            return nil
        }
        let delimiterRanges = localRange.delimiterRanges.compactMap { sourceRange(for: textView, localRange: $0) }
        guard delimiterRanges.count == localRange.delimiterRanges.count else {
            return nil
        }
        return BlockInputInlineMarkdownRange(
            style: localRange.style,
            fullRange: sourceFullRange,
            contentRange: sourceContentRange,
            delimiterRanges: delimiterRanges,
            linkDestination: localRange.linkDestination
        )
    }

    func sourceOffset(atWindowLocation windowLocation: NSPoint) -> Int? {
        guard let cellView = cellView(atWindowLocation: windowLocation) else {
            return nil
        }
        let localRange = cellView.textView.localInsertionRange(atWindowLocation: windowLocation)
        guard let sourceRange = sourceRange(for: cellView.textView, localRange: localRange) else {
            return nil
        }
        return sourceRange.location
    }

    func anchorWindowRect(forSourceRange range: NSRange) -> NSRect? {
        guard let table,
              let position = table.cellPosition(containingSourceRange: range),
              let localRange = table.localRange(forSourceRange: range, in: position),
              let cellView = cellView(at: position) else {
            return nil
        }
        return cellView.textView.anchorWindowRect(forLocalRange: localRange)
    }

    @discardableResult
    func focusSourceRange(_ range: NSRange) -> Bool {
        guard let table,
              let position = table.cellPosition(containingSourceRange: range),
              let localRange = table.localRange(forSourceRange: range, in: position),
              let cellView = cellView(at: position) else {
            return false
        }
        clearRowSelection()
        clearCellSelection()
        window?.makeFirstResponder(cellView.textView)
        cellView.textView.setSelectedRange(localRange)
        cellView.textView.scrollRangeToVisible(localRange)
        return true
    }

    var activeCellPosition: BlockInputTable.CellPosition? {
        activeCellView?.position
    }

    var activeCellText: String? {
        activeCellView?.textView.string
    }

    @discardableResult
    func focusCell(at position: BlockInputTable.CellPosition, localRange: NSRange = NSRange(location: 0, length: 0)) -> Bool {
        guard let cellView = cellView(at: position) else {
            return false
        }
        let clampedRange = cellView.textView.string.blockInputTableViewClampedRange(localRange)
        selectedRow = nil
        selectedCellRange = nil
        updateSelectionChrome()
        window?.makeFirstResponder(cellView.textView)
        cellView.textView.setSelectedRange(clampedRange)
        cellView.textView.scrollRangeToVisible(clampedRange)
        return true
    }

    func nextCellPosition(after position: BlockInputTable.CellPosition) -> BlockInputTable.CellPosition? {
        guard let table else {
            return nil
        }
        if position.column + 1 < table.columnCount {
            return BlockInputTable.CellPosition(row: position.row, column: position.column + 1)
        }
        switch position.row {
        case .header:
            return table.bodyRows.isEmpty ? nil : BlockInputTable.CellPosition(row: .body(0), column: 0)
        case .body(let rowIndex):
            let nextRowIndex = rowIndex + 1
            return table.bodyRows.indices.contains(nextRowIndex)
                ? BlockInputTable.CellPosition(row: .body(nextRowIndex), column: 0)
                : nil
        }
    }

    func previousCellPosition(before position: BlockInputTable.CellPosition) -> BlockInputTable.CellPosition? {
        guard let table else {
            return nil
        }
        if position.column > 0 {
            return BlockInputTable.CellPosition(row: position.row, column: position.column - 1)
        }
        switch position.row {
        case .header:
            return nil
        case .body(let rowIndex):
            let previousRow: BlockInputTable.Row = rowIndex == 0 ? .header : .body(rowIndex - 1)
            return BlockInputTable.CellPosition(row: previousRow, column: max(table.columnCount - 1, 0))
        }
    }

    func verticalCellPosition(
        from position: BlockInputTable.CellPosition,
        placement: BlockInputTableBoundaryPlacement
    ) -> BlockInputTable.CellPosition? {
        guard let table else {
            return nil
        }
        switch (position.row, placement) {
        case (.header, .below):
            return table.bodyRows.isEmpty ? nil : BlockInputTable.CellPosition(row: .body(0), column: position.column)
        case (.header, .above):
            return nil
        case (.body(let rowIndex), .below):
            let nextRowIndex = rowIndex + 1
            return table.bodyRows.indices.contains(nextRowIndex)
                ? BlockInputTable.CellPosition(row: .body(nextRowIndex), column: position.column)
                : nil
        case (.body(let rowIndex), .above):
            let previousRow: BlockInputTable.Row = rowIndex == 0 ? .header : .body(rowIndex - 1)
            return BlockInputTable.CellPosition(row: previousRow, column: position.column)
        }
    }

    func selectRow(_ row: BlockInputTable.Row) {
        selectedRow = row
        selectedCellRange = nil
        updateSelectionChrome()
    }

    func isRowSelected(_ row: BlockInputTable.Row) -> Bool {
        selectedRow == row
    }

    func selectAllInActiveCellIfNeeded() -> Bool {
        guard let activeCell = activeCellView else {
            return false
        }
        let fullRange = NSRange(location: 0, length: (activeCell.textView.string as NSString).length)
        guard activeCell.textView.selectedRange() != fullRange else {
            return false
        }
        selectedRow = nil
        selectedCellRange = nil
        updateSelectionChrome()
        activeCell.textView.setSelectedRange(fullRange)
        if let sourceSelection = sourceSelection(for: activeCell.textView, localRange: fullRange),
           case let .text(textRange) = sourceSelection {
            delegate?.tableView(self, didChangeSelectionIn: activeCell.position, sourceRange: textRange.range)
        }
        return true
    }

    func clearRowSelection() {
        guard selectedRow != nil else {
            return
        }
        selectedRow = nil
        updateSelectionChrome()
    }

    func clearCellSelection() {
        guard selectedCellRange != nil else {
            return
        }
        selectedCellRange = nil
        updateSelectionChrome()
    }

    func clearCellSelectionUnlessDragging() {
        guard !isDraggingCellSelection else {
            return
        }
        clearCellSelection()
    }

    func beginCellSelectionDrag(from textView: NSTextView) {
        cellSelectionDragAnchor = cellView(containing: textView)?.position
        isDraggingCellSelection = false
    }

    func updateCellSelectionDrag(from textView: NSTextView, windowLocation: NSPoint) -> Bool {
        guard let anchor = cellSelectionDragAnchor,
              let target = cellViewForSelection(atWindowLocation: windowLocation)?.position else {
            return false
        }
        guard target != anchor || isDraggingCellSelection else {
            return false
        }
        isDraggingCellSelection = true
        selectedRow = nil
        selectedCellRange = BlockInputTableCellSelection(anchor: anchor, focus: target)
        updateSelectionChrome()
        promoteWholeCellSelectionToTableSelectionIfNeeded()
        return true
    }

    func finishCellSelectionDrag() -> Bool {
        guard cellSelectionDragAnchor != nil || isDraggingCellSelection else {
            return false
        }
        let consumed = isDraggingCellSelection
        cellSelectionDragAnchor = nil
        isDraggingCellSelection = false
        return consumed
    }

    var selectedWholeColumnDeletionPosition: BlockInputTable.CellPosition? {
        guard let table,
              let selectedCellRange,
              selectedCellRange.rowRange == 0...table.bodyRows.count,
              selectedCellRange.columnRange.lowerBound == selectedCellRange.columnRange.upperBound else {
            return nil
        }
        return BlockInputTable.CellPosition(row: .header, column: selectedCellRange.columnRange.lowerBound)
    }

    var selectedWholeBodyRowDeletionPosition: BlockInputTable.CellPosition? {
        guard let selectedCellRange,
              isSelectedWholeRow(selectedCellRange),
              selectedCellRange.rowRange.lowerBound > 0 else {
            return nil
        }
        return BlockInputTable.CellPosition(row: .body(selectedCellRange.rowRange.lowerBound - 1), column: 0)
    }

    var hasSelectedWholeHeaderRow: Bool {
        guard let selectedCellRange,
              isSelectedWholeRow(selectedCellRange) else {
            return false
        }
        return selectedCellRange.rowRange.lowerBound == 0
    }

    var activeCellView: BlockInputTableCellView? {
        guard let responder = window?.firstResponder as? NSTextView else {
            return nil
        }
        return cellView(containing: responder)
    }

    func cellView(containing textView: NSTextView) -> BlockInputTableCellView? {
        cellRows.flatMap { $0 }.first { $0.textView === textView }
    }

    func cellView(at position: BlockInputTable.CellPosition) -> BlockInputTableCellView? {
        cellRows.flatMap { $0 }.first { $0.position == position }
    }

    func cellView(atWindowLocation windowLocation: NSPoint) -> BlockInputTableCellView? {
        cellRows.flatMap { $0 }.first { cell in
            let localPoint = cell.textView.convert(windowLocation, from: nil)
            return cell.textView.bounds.contains(localPoint)
        }
    }

    func cellViewForSelection(atWindowLocation windowLocation: NSPoint) -> BlockInputTableCellView? {
        cellRows.flatMap { $0 }.first { cell in
            let localPoint = cell.convert(windowLocation, from: nil)
            return cell.bounds.contains(localPoint)
        }
    }

    @discardableResult
    func promoteWholeCellSelectionToTableSelectionIfNeeded() -> Bool {
        guard let selectedCellRange,
              isSelectedWholeTable(selectedCellRange) else {
            return false
        }
        self.selectedCellRange = nil
        updateSelectionChrome()
        delegate?.tableViewDidRequestWholeTableSelection(self)
        return true
    }

    func publishActiveCellSourceSelection(from textView: NSTextView) {
        guard let cell = cellView(containing: textView),
              let sourceRange = sourceRange(for: textView, localRange: textView.selectedRange()) else {
            return
        }
        delegate?.tableView(self, didChangeSelectionIn: cell.position, sourceRange: sourceRange)
    }

    private func isSelectedWholeRow(_ selectedCellRange: BlockInputTableCellSelection) -> Bool {
        guard let table,
              table.columnCount > 0,
              selectedCellRange.rowRange.lowerBound == selectedCellRange.rowRange.upperBound else {
            return false
        }
        return selectedCellRange.columnRange == 0...(table.columnCount - 1)
    }

    private func isSelectedWholeTable(_ selectedCellRange: BlockInputTableCellSelection) -> Bool {
        guard let table,
              table.columnCount > 0 else {
            return false
        }
        return selectedCellRange.rowRange == 0...table.bodyRows.count
            && selectedCellRange.columnRange == 0...(table.columnCount - 1)
    }
}

private extension String {
    func blockInputTableViewClampedRange(_ range: NSRange) -> NSRange {
        let text = self as NSString
        let location = min(max(range.location, 0), text.length)
        let length = min(max(range.length, 0), max(text.length - location, 0))
        return NSRange(location: location, length: length)
    }
}
