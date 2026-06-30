import AppKit

extension BlockInputBlockItem: BlockInputTableViewDelegate {
    func isTableCellTextView(_ textView: NSTextView) -> Bool {
        tableView.isTableCellTextView(textView)
    }

    func sourceSelectedRange(for textView: NSTextView, localRange: NSRange) -> NSRange {
        tableView.sourceRange(for: textView, localRange: localRange) ?? localRange
    }

    func sourceInlineMarkdownRange(
        for textView: NSTextView,
        localRange: BlockInputInlineMarkdownRange
    ) -> BlockInputInlineMarkdownRange? {
        tableView.sourceInlineMarkdownRange(for: textView, localRange: localRange)
    }

    func supportsInlineMarkdownLinkRendering(for textView: NSTextView) -> Bool {
        if tableView.isTableCellTextView(textView) {
            return true
        }
        guard let kind = renderedBlock?.kind else {
            return false
        }
        return Self.supportsInlineMarkdownStyling(kind)
    }

    func handleTableCellCommand(_ selector: Selector, selectedRange: NSRange) -> Bool {
        if handleTableCellSelectionCommand(selector) {
            return true
        }
        switch selector {
        case #selector(insertTab(_:)):
            return moveTableFocus(.forward)
        case #selector(insertBacktab(_:)):
            return moveTableFocus(.backward)
        case #selector(insertNewline(_:)):
            return moveTableFocusVertically(.below)
        case #selector(insertNewlineIgnoringFieldEditor(_:)):
            return moveTableFocusVertically(.above)
        case #selector(deleteBackward(_:)), #selector(deleteForward(_:)):
            return handleTableCellDeleteCommand(selectedRange: selectedRange)
        case #selector(selectAll(_:)):
            requestSelectAll()
            return true
        case #selector(cancelOperation(_:)):
            return requestCancelSelection()
        default:
            return false
        }
    }

    private func handleTableCellDeleteCommand(selectedRange: NSRange) -> Bool {
        guard isEditable else {
            return false
        }
        if deleteActiveTableSelectionIfNeeded() {
            return true
        }
        if deleteSelectedTableCellsIfNeeded() {
            return true
        }
        return handleTableCellDelete(selectedRange: selectedRange)
    }

    private func handleTableCellSelectionCommand(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(moveUpAndModifySelection(_:)):
            return adjustTableCellSelectionVertically(.upward)
        case #selector(moveDownAndModifySelection(_:)):
            return adjustTableCellSelectionVertically(.downward)
        case #selector(moveLeftAndModifySelection(_:)),
             #selector(moveBackwardAndModifySelection(_:)):
            return adjustTableCellSelectionHorizontally(.leftward)
        case #selector(moveRightAndModifySelection(_:)),
             #selector(moveForwardAndModifySelection(_:)):
            return adjustTableCellSelectionHorizontally(.rightward)
        default:
            return false
        }
    }

    func handleTableCellKeyDown(_ event: NSEvent, selectedRange: NSRange) -> Bool {
        if let direction = event.blockInputSelectionExpansionDirection {
            return adjustTableCellSelectionVertically(direction)
        }
        if let direction = event.horizontalSelectionAdjustmentDirection {
            return adjustTableCellSelectionHorizontally(direction)
        }
        guard event.isBackspaceOrDelete else {
            return false
        }
        let selector = event.keyCode == 117 || event.charactersIgnoringModifiers == "\u{F728}"
            ? #selector(deleteForward(_:))
            : #selector(deleteBackward(_:))
        return handleTableCellCommand(selector, selectedRange: selectedRange)
    }

    func beginTableCellSelectionDrag(from textView: NSTextView) {
        tableView.beginCellSelectionDrag(from: textView)
    }

    func updateTableCellSelectionDrag(from textView: NSTextView, with event: NSEvent) -> Bool {
        tableView.updateCellSelectionDrag(from: textView, windowLocation: event.locationInWindow)
    }

    func finishTableCellSelectionDrag() -> Bool {
        tableView.finishCellSelectionDrag()
    }

    private func adjustTableCellSelectionVertically(_ direction: BlockInputVerticalMovementDirection) -> Bool {
        guard let activeCellView = tableView.activeCellView else {
            return false
        }
        return tableView.adjustCellSelection(from: activeCellView.textView, vertically: direction)
    }

    private func adjustTableCellSelectionHorizontally(_ direction: BlockInputHorizontalMovementDirection) -> Bool {
        guard let activeCellView = tableView.activeCellView else {
            return false
        }
        return tableView.adjustCellSelection(from: activeCellView.textView, horizontally: direction)
    }

    func tableView(_ tableView: BlockInputTableView, didBeginEditing position: BlockInputTable.CellPosition) {
        guard let blockID else {
            return
        }
        updateSelectionDependentAttributesForCurrentSelection()
        delegate?.blockItemDidBeginEditing(self, blockID: blockID)
    }

    func tableView(_ tableView: BlockInputTableView, didEndEditing position: BlockInputTable.CellPosition) {
        guard let blockID else {
            return
        }
        updateSelectionDependentAttributesForCurrentSelection()
        delegate?.blockItemDidEndEditing(self, blockID: blockID)
    }

    func tableView(_ tableView: BlockInputTableView, didChangeSelectionIn position: BlockInputTable.CellPosition, sourceRange: NSRange) {
        guard let blockID else {
            return
        }
        updateSelectionDependentAttributesForCurrentSelection()
        delegate?.blockItem(self, didChangeSelectionIn: blockID, selectedRange: sourceRange)
    }

    func tableViewDidRequestWholeTableSelection(_ tableView: BlockInputTableView) {
        guard let blockID else {
            return
        }
        updateSelectionDependentAttributesForCurrentSelection()
        delegate?.blockItemDidRequestSelectTable(self, blockID: blockID)
    }

    func tableView(
        _ tableView: BlockInputTableView,
        didChangeText text: String,
        in position: BlockInputTable.CellPosition,
        selectedLocalRange: NSRange,
        selectionBefore: BlockInputSelection?
    ) {
        guard isEditable,
              let blockID else {
            return
        }
        delegate?.blockItem(
            self,
            blockID: blockID,
            didChangeTableCellText: BlockInputTableCellTextChange(
                text: text,
                position: position,
                selectedLocalRange: selectedLocalRange,
                selectionBefore: selectionBefore
            )
        )
    }

    func tableView(
        _ tableView: BlockInputTableView,
        shouldChangeTextIn position: BlockInputTable.CellPosition,
        affectedLocalRange: NSRange,
        replacementString: String?
    ) -> Bool {
        isEditable
    }

    func tableViewDidRequestAppendBodyRow(_ tableView: BlockInputTableView, from position: BlockInputTable.CellPosition?) {
        guard isEditable,
              let blockID else {
            return
        }
        _ = delegate?.blockItem(self, blockID: blockID, didRequestTableBodyRowAppendFrom: position)
    }

    func tableViewDidRequestAppendColumn(_ tableView: BlockInputTableView, from position: BlockInputTable.CellPosition?) {
        guard isEditable,
              let blockID else {
            return
        }
        _ = delegate?.blockItem(self, blockID: blockID, didRequestTableColumnAppendFrom: position)
    }

    private func moveTableFocus(_ direction: TableCellLinearMovement) -> Bool {
        guard let blockID,
              let position = tableView.activeCellPosition else {
            return false
        }
        let target = direction == .forward
            ? tableView.nextCellPosition(after: position)
            : tableView.previousCellPosition(before: position)
        guard let target else {
            guard direction == .forward else {
                return false
            }
            // Final-cell Tab inserts below the current row, matching the context-menu Insert Row behavior.
            // Always consume the event so that a rejected or skipped insertion never falls through to
            // super.doCommand(by:), which would insert a literal tab character into the cell text.
            if isEditable {
                _ = delegate?.blockItem(self, blockID: blockID, didRequestTableBodyRowInsertionAt: position)
            }
            return true
        }
        return delegate?.blockItem(self, blockID: blockID, didRequestTableFocus: target) ?? false
    }

    private func moveTableFocusVertically(_ placement: BlockInputTableBoundaryPlacement) -> Bool {
        guard let blockID,
              let position = tableView.activeCellPosition else {
            return false
        }
        if let target = tableView.verticalCellPosition(from: position, placement: placement) {
            return delegate?.blockItem(self, blockID: blockID, didRequestTableFocus: target) ?? false
        }
        guard isEditable else {
            return false
        }
        return delegate?.blockItem(self, blockID: blockID, didRequestParagraphAdjacentToTable: placement) ?? false
    }

    private func handleTableCellDelete(selectedRange: NSRange) -> Bool {
        guard isEditable,
              selectedRange.length == 0,
              let blockID,
              let position = tableView.activeCellPosition,
              tableView.activeCellText?.isEmpty == true else {
            return false
        }
        if tableView.isRowSelected(position.row) {
            guard case .body = position.row else {
                return true
            }
            return delegate?.blockItem(self, blockID: blockID, didRequestTableBodyRowDeletionAt: position) ?? false
        }
        tableView.selectRow(position.row)
        return true
    }

    private func deleteActiveTableSelectionIfNeeded() -> Bool {
        guard isEditable,
              let blockID else {
            return false
        }
        return delegate?.blockItemDidRequestDeleteActiveSelection(self, blockID: blockID) ?? false
    }

    private func deleteSelectedTableCellsIfNeeded() -> Bool {
        guard isEditable,
              let blockID else {
            return false
        }
        if let position = tableView.selectedWholeColumnDeletionPosition {
            _ = delegate?.blockItem(self, blockID: blockID, didRequestTableColumnDeletionAt: position)
            return true
        }
        if let position = tableView.selectedWholeBodyRowDeletionPosition {
            _ = delegate?.blockItem(self, blockID: blockID, didRequestTableBodyRowDeletionAt: position)
            return true
        }
        return tableView.hasSelectedWholeHeaderRow
    }
}

private enum TableCellLinearMovement {
    case forward
    case backward
}
