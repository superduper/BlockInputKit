import AppKit

struct BlockInputTableKeyboardRowSelection {
    var tableBlockID: BlockInputBlockID
    var originCursor: BlockInputCursor
    var originSelection: BlockInputSelection?
    var outsideTableSelection: BlockInputMixedSelection?
    var anchorDisplayRow: Int
    var focusDisplayRow: Int
    var direction: BlockInputVerticalMovementDirection
    var isPromotedToWholeTable: Bool
}

extension BlockInputView {
    func startAdjacentTableRowSelectionHorizontally(
        from blockID: BlockInputBlockID,
        block: BlockInputBlock,
        offset: Int,
        direction: BlockInputHorizontalMovementDirection,
        originCursor: BlockInputCursor? = nil,
        originSelection: BlockInputSelection? = nil,
        outsideTableSelection: BlockInputMixedSelection? = nil
    ) -> Bool {
        switch direction {
        case .leftward:
            guard offset == 0,
                  let index = index(of: blockID),
                  index > 0,
                  let previousBlock = self.block(at: index - 1),
                  previousBlock.kind == .table else {
                return false
            }
            return startTableKeyboardRowSelection(
                tableBlockID: previousBlock.id,
                originCursor: originCursor ?? BlockInputCursor(blockID: blockID, utf16Offset: offset),
                direction: .upward,
                originSelection: originSelection,
                outsideTableSelection: outsideTableSelection
            )
        case .rightward:
            guard offset == block.utf16Length,
                  let index = index(of: blockID),
                  index + 1 < blockCount,
                  let nextBlock = self.block(at: index + 1),
                  nextBlock.kind == .table else {
                return false
            }
            return startTableKeyboardRowSelection(
                tableBlockID: nextBlock.id,
                originCursor: originCursor ?? BlockInputCursor(blockID: blockID, utf16Offset: offset),
                direction: .downward,
                originSelection: originSelection,
                outsideTableSelection: outsideTableSelection
            )
        }
    }

    func startAdjacentTableRowSelectionHorizontally(
        from blockID: BlockInputBlockID,
        offset: Int,
        direction: BlockInputHorizontalMovementDirection
    ) -> Bool {
        guard let block = block(withID: blockID) else {
            return false
        }
        return startAdjacentTableRowSelectionHorizontally(
            from: blockID,
            block: block,
            offset: offset,
            direction: direction
        )
    }

    func startTableKeyboardRowSelection(
        tableBlockID: BlockInputBlockID,
        originCursor: BlockInputCursor,
        direction: BlockInputVerticalMovementDirection,
        originSelection: BlockInputSelection? = nil,
        outsideTableSelection: BlockInputMixedSelection? = nil
    ) -> Bool {
        guard let tableView = visibleItem(for: tableBlockID)?.tableView,
              let displayRowRange = tableView.keyboardDisplayRowRange else {
            return false
        }
        let displayRow = direction == .upward ? displayRowRange.upperBound : displayRowRange.lowerBound
        return applyTableKeyboardRowSelection(
            BlockInputTableKeyboardRowSelection(
                tableBlockID: tableBlockID,
                originCursor: originCursor,
                originSelection: originSelection,
                outsideTableSelection: outsideTableSelection,
                anchorDisplayRow: displayRow,
                focusDisplayRow: displayRow,
                direction: direction,
                isPromotedToWholeTable: false
            )
        )
    }

    func startAdjacentTableRowSelectionVerticallyFromTextRange(
        blockID: BlockInputBlockID,
        index: Int,
        direction: BlockInputVerticalMovementDirection
    ) -> Bool {
        guard case let .text(textRange) = selection,
              textRange.blockID == blockID,
              let currentBlock = block(withID: blockID),
              textRange.range.length > 0 else {
            return false
        }
        switch direction {
        case .upward:
            guard textRange.range.location <= 0,
                  index > 0,
                  let previousBlock = block(at: index - 1),
                  previousBlock.kind == .table else {
                return false
            }
            return startTableKeyboardRowSelection(
                tableBlockID: previousBlock.id,
                originCursor: BlockInputCursor(blockID: blockID, utf16Offset: NSMaxRange(textRange.range)),
                direction: .upward,
                originSelection: selection,
                outsideTableSelection: BlockInputMixedSelection(blockIDs: [], trailingTextRange: textRange)
            )
        case .downward:
            guard NSMaxRange(textRange.range) >= currentBlock.utf16Length,
                  index + 1 < blockCount,
                  let nextBlock = block(at: index + 1),
                  nextBlock.kind == .table else {
                return false
            }
            return startTableKeyboardRowSelection(
                tableBlockID: nextBlock.id,
                originCursor: BlockInputCursor(blockID: blockID, utf16Offset: textRange.range.location),
                direction: .downward,
                originSelection: selection,
                outsideTableSelection: BlockInputMixedSelection(blockIDs: [], leadingTextRange: textRange)
            )
        }
    }

    func handleTableKeyboardRowSelection(_ direction: BlockInputVerticalMovementDirection) -> Bool {
        guard let state = tableKeyboardRowSelection,
              let tableView = visibleItem(for: state.tableBlockID)?.tableView,
              let displayRowRange = tableView.keyboardDisplayRowRange else {
            return false
        }
        if state.isPromotedToWholeTable {
            return handlePromotedTableKeyboardRowSelection(state, displayRowRange: displayRowRange, direction: direction)
        }
        let ladder = BlockInputLinearSelectionLadder(
            anchor: state.anchorDisplayRow,
            focus: state.focusDisplayRow,
            bounds: displayRowRange
        )
        if ladder.isCollapsedAtAnchor,
           direction != state.direction {
            return restoreTableKeyboardRowSelectionOrigin(state)
        }
        guard let nextFocus = ladder.focusAfterMoving(direction) else {
            if direction == state.direction {
                return expandTableKeyboardRowSelectionPastTable(direction: direction)
            }
            return restoreTableKeyboardRowSelectionOrigin(state)
        }
        var nextState = state
        nextState.focusDisplayRow = nextFocus
        return applyTableKeyboardRowSelection(nextState)
    }

    func handleTableKeyboardRowSelection(_ direction: BlockInputHorizontalMovementDirection) -> Bool {
        if let state = tableKeyboardRowSelection,
           state.isPromotedToWholeTable {
            let continuationDirection = horizontalContinuationDirection(for: state.direction)
            if direction == continuationDirection || promotedTableSelectionExtendsOutsideTable(state) {
                // A promoted table is now a whole-block selection, but continued Shift+Left/Right should still behave
                // like one Markdown document: step into or out of adjacent text before demoting table rows.
                return adjustPromotedTableKeyboardRowSelectionHorizontally(direction, preserving: state)
            }
        }
        switch direction {
        case .leftward:
            return handleTableKeyboardRowSelection(.upward)
        case .rightward:
            return handleTableKeyboardRowSelection(.downward)
        }
    }

    func shouldHandleTableKeyboardRowSelectionVertically() -> Bool {
        guard let state = tableKeyboardRowSelection else {
            return false
        }
        // Once a promoted table extends into adjacent text, vertical keys should move that mixed span instead of stealing
        // the active edge before horizontal keys can contract back into table rows.
        return !state.isPromotedToWholeTable || !promotedTableSelectionExtendsOutsideTable(state)
    }

    private func handlePromotedTableKeyboardRowSelection(
        _ state: BlockInputTableKeyboardRowSelection,
        displayRowRange: ClosedRange<Int>,
        direction: BlockInputVerticalMovementDirection
    ) -> Bool {
        guard direction != state.direction else {
            return expandTableKeyboardRowSelectionPastTable(direction: direction)
        }
        guard let demotedFocus = BlockInputLinearSelectionLadder.focusAfterDemotingWholeSelection(
            within: displayRowRange,
            expansionDirection: state.direction
        ) else {
            return restoreTableKeyboardRowSelectionOrigin(state)
        }
        var nextState = state
        nextState.focusDisplayRow = demotedFocus
        nextState.isPromotedToWholeTable = false
        return applyTableKeyboardRowSelection(nextState)
    }

    private func expandTableKeyboardRowSelectionPastTable(direction: BlockInputVerticalMovementDirection) -> Bool {
        guard expandBlockSelection(direction: direction) else {
            return false
        }
        tableKeyboardRowSelection = nil
        return true
    }

    private func adjustPromotedTableKeyboardRowSelectionHorizontally(
        _ direction: BlockInputHorizontalMovementDirection,
        preserving state: BlockInputTableKeyboardRowSelection
    ) -> Bool {
        tableKeyboardRowSelection = nil
        guard adjustSelectionHorizontally(direction) else {
            tableKeyboardRowSelection = state
            return false
        }
        if selectionCanRestorePromotedTableKeyboardRowSelection(state) {
            tableKeyboardRowSelection = state
        }
        return true
    }

    private func promotedTableSelectionExtendsOutsideTable(_ state: BlockInputTableKeyboardRowSelection) -> Bool {
        guard let tableIndex = index(of: state.tableBlockID) else {
            return false
        }
        switch state.direction {
        case .upward:
            return selectedIndexesBeforeTable().contains { $0 < tableIndex }
        case .downward:
            return selectedIndexesAfterTable().contains { $0 > tableIndex }
        }
    }

    private func selectedIndexesBeforeTable() -> [Int] {
        switch selection {
        case let .blocks(blockIDs):
            return blockIDs.compactMap { index(of: $0) }
        case let .mixed(selection):
            return ([selection.leadingTextRange?.blockID] + selection.blockIDs)
                .compactMap { $0 }
                .compactMap { index(of: $0) }
        case .cursor, .text, nil:
            return []
        }
    }

    private func selectedIndexesAfterTable() -> [Int] {
        switch selection {
        case let .blocks(blockIDs):
            return blockIDs.compactMap { index(of: $0) }
        case let .mixed(selection):
            return (selection.blockIDs + [selection.trailingTextRange?.blockID].compactMap { $0 })
                .compactMap { index(of: $0) }
        case .cursor, .text, nil:
            return []
        }
    }

    private func selectionCanRestorePromotedTableKeyboardRowSelection(_ state: BlockInputTableKeyboardRowSelection) -> Bool {
        switch selection {
        case let .blocks(blockIDs):
            return blockIDs.contains(state.tableBlockID)
        case let .mixed(selection):
            return selection.blockIDs.contains(state.tableBlockID)
        case .cursor, .text, nil:
            return false
        }
    }

    private func horizontalContinuationDirection(
        for direction: BlockInputVerticalMovementDirection
    ) -> BlockInputHorizontalMovementDirection {
        switch direction {
        case .upward:
            return .leftward
        case .downward:
            return .rightward
        }
    }

    private func applyTableKeyboardRowSelection(_ state: BlockInputTableKeyboardRowSelection) -> Bool {
        guard let tableView = visibleItem(for: state.tableBlockID)?.tableView,
              let displayRowRange = tableView.keyboardDisplayRowRange else {
            return false
        }
        let ladder = BlockInputLinearSelectionLadder(
            anchor: state.anchorDisplayRow,
            focus: state.focusDisplayRow,
            bounds: displayRowRange
        )
        if ladder.coversBounds {
            tableView.clearKeyboardCellSelection()
            applySelection(promotedTableSelection(for: state), notify: true)
            var promotedState = state
            promotedState.isPromotedToWholeTable = true
            promotedState.focusDisplayRow = BlockInputLinearSelectionLadder.promotedFocusIndex(
                in: displayRowRange,
                direction: state.direction
            )
            tableKeyboardRowSelection = promotedState
            window?.makeFirstResponder(self)
            publishFocusChange(true)
            return true
        }
        guard tableView.selectKeyboardRows(
            anchorDisplayRow: state.anchorDisplayRow,
            focusDisplayRow: state.focusDisplayRow
        ) else {
            return false
        }
        applySelection(tableRowSelection(for: state), notify: true)
        tableKeyboardRowSelection = state
        window?.makeFirstResponder(self)
        publishFocusChange(true)
        return true
    }

    private func restoreTableKeyboardRowSelectionOrigin(_ state: BlockInputTableKeyboardRowSelection) -> Bool {
        visibleItem(for: state.tableBlockID)?.tableView.clearKeyboardCellSelection()
        applySelection(state.originSelection ?? .cursor(state.originCursor), notify: true)
        restoreVisibleSelection()
        return true
    }

    private func tableCursorSelection(for state: BlockInputTableKeyboardRowSelection) -> BlockInputSelection? {
        guard let block = block(withID: state.tableBlockID),
              let table = BlockInputTable(markdown: block.text) else {
            return nil
        }
        let position = BlockInputTable.CellPosition(
            row: BlockInputTableCellSelection.row(forDisplayRowIndex: state.focusDisplayRow),
            column: 0
        )
        guard let sourceRange = table.sourceRange(forLocalRange: NSRange(location: 0, length: 0), in: position) else {
            return nil
        }
        return .cursor(BlockInputCursor(blockID: state.tableBlockID, utf16Offset: sourceRange.location))
    }

    private func tableRowSelection(for state: BlockInputTableKeyboardRowSelection) -> BlockInputSelection? {
        guard let outsideTableSelection = state.outsideTableSelection else {
            return tableCursorSelection(for: state)
        }
        return .mixed(outsideTableSelection)
    }

    private func promotedTableSelection(for state: BlockInputTableKeyboardRowSelection) -> BlockInputSelection {
        guard let outsideTableSelection = state.outsideTableSelection else {
            return .blocks([state.tableBlockID])
        }
        var blockIDs = outsideTableSelection.blockIDs
        if !blockIDs.contains(state.tableBlockID) {
            blockIDs.append(state.tableBlockID)
        }
        return .mixed(BlockInputMixedSelection(
            blockIDs: blockIDs.sortedByDocumentOrder(in: self),
            leadingTextRange: outsideTableSelection.leadingTextRange,
            trailingTextRange: outsideTableSelection.trailingTextRange
        ))
    }
}

private extension Array where Element == BlockInputBlockID {
    @MainActor
    func sortedByDocumentOrder(in view: BlockInputView) -> [BlockInputBlockID] {
        sorted { lhs, rhs in
            (view.index(of: lhs) ?? Int.max) < (view.index(of: rhs) ?? Int.max)
        }
    }
}
