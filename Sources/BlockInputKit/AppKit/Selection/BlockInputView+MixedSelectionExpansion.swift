import AppKit

extension BlockInputView {
    func promoteCaretSelectionAcrossBlockBoundary(
        from blockID: BlockInputBlockID,
        selectedRange: NSRange,
        currentBlock: BlockInputBlock,
        direction: BlockInputVerticalMovementDirection,
        preferredTextContainerX: CGFloat?
    ) -> Bool {
        guard let index = index(of: blockID) else {
            return false
        }
        let textLength = currentBlock.utf16Length
        let offset = min(max(selectedRange.location, 0), textLength)
        let isSingleLine = !currentBlock.text.contains(where: { $0 == "\n" || $0 == "\r" })
        let isDocumentBoundaryDirection = (direction == .upward && offset == 0) || (direction == .downward && offset == textLength)
        guard isSingleLine || isDocumentBoundaryDirection else {
            return false
        }
        switch direction {
        case .upward:
            return promoteCaretSelectionUpward(
                from: blockID,
                index: index,
                offset: offset,
                preferredTextContainerX: preferredTextContainerX
            )
        case .downward:
            return promoteCaretSelectionDownward(
                from: blockID,
                index: index,
                offset: offset,
                textLength: textLength,
                preferredTextContainerX: preferredTextContainerX
            )
        }
    }

    private func promoteCaretSelectionUpward(
        from blockID: BlockInputBlockID,
        index: Int,
        offset: Int,
        preferredTextContainerX: CGFloat?
    ) -> Bool {
        guard index > 0, let previousBlock = block(at: index - 1) else {
            return false
        }
        let previousID = previousBlock.id
        if previousBlock.kind == .table {
            let outsideSelection = offset > 0
                ? BlockInputMixedSelection(
                    blockIDs: [],
                    trailingTextRange: BlockInputTextRange(blockID: blockID, range: NSRange(location: 0, length: offset))
                )
                : nil
            return startTableKeyboardRowSelection(
                tableBlockID: previousID,
                originCursor: BlockInputCursor(blockID: blockID, utf16Offset: offset),
                direction: .upward,
                outsideTableSelection: outsideSelection
            )
        }
        if offset <= 0 {
            if promoteIncrementalListBoundary(
                targetBlock: previousBlock,
                targetID: previousID,
                anchorBlockID: blockID,
                direction: .upward,
                scrollIndex: index - 1,
                preferredTextContainerX: preferredTextContainerX
            ) {
                return true
            }
            return applyPromotedSelection(.blocks([previousID]), anchorBlockID: blockID, direction: .upward, scrollIndex: index - 1)
        }
        let range = BlockInputTextRange(blockID: blockID, range: NSRange(location: 0, length: offset))
        let targetRange = partialTargetRange(
            for: previousID,
            at: index - 1,
            direction: .upward,
            preferredTextContainerX: preferredTextContainerX
        )
        return applyPromotedSelection(
            .mixed(BlockInputMixedSelection(
                blockIDs: targetRange == nil ? [previousID] : [],
                leadingTextRange: targetRange,
                trailingTextRange: range
            )),
            anchorBlockID: blockID,
            direction: .upward,
            scrollIndex: index - 1,
            preferredTextContainerX: preferredTextContainerX
        )
    }

    private func promoteCaretSelectionDownward(
        from blockID: BlockInputBlockID,
        index: Int,
        offset: Int,
        textLength: Int,
        preferredTextContainerX: CGFloat?
    ) -> Bool {
        guard index + 1 < blockCount, let nextBlock = block(at: index + 1) else {
            return false
        }
        let nextID = nextBlock.id
        if nextBlock.kind == .table {
            let outsideSelection = offset < textLength
                ? BlockInputMixedSelection(
                    blockIDs: [],
                    leadingTextRange: BlockInputTextRange(blockID: blockID, range: NSRange(location: offset, length: textLength - offset))
                )
                : nil
            return startTableKeyboardRowSelection(
                tableBlockID: nextID,
                originCursor: BlockInputCursor(blockID: blockID, utf16Offset: offset),
                direction: .downward,
                outsideTableSelection: outsideSelection
            )
        }
        if offset >= textLength {
            if promoteIncrementalListBoundary(
                targetBlock: nextBlock,
                targetID: nextID,
                anchorBlockID: blockID,
                direction: .downward,
                scrollIndex: index + 1,
                preferredTextContainerX: preferredTextContainerX
            ) {
                return true
            }
            return applyPromotedSelection(.blocks([nextID]), anchorBlockID: blockID, direction: .downward, scrollIndex: index + 1)
        }
        let range = BlockInputTextRange(blockID: blockID, range: NSRange(location: offset, length: textLength - offset))
        let targetRange = partialTargetRange(
            for: nextID,
            at: index + 1,
            direction: .downward,
            preferredTextContainerX: preferredTextContainerX
        )
        return applyPromotedSelection(
            .mixed(BlockInputMixedSelection(
                blockIDs: targetRange == nil ? [nextID] : [],
                leadingTextRange: range,
                trailingTextRange: targetRange
            )),
            anchorBlockID: blockID,
            direction: .downward,
            scrollIndex: index + 1,
            preferredTextContainerX: preferredTextContainerX
        )
    }

    func expandMixedSelectionContinuing(
        _ mixedSelection: BlockInputMixedSelection,
        expandedBounds: ClosedRange<Int>,
        direction: BlockInputVerticalMovementDirection
    ) -> Bool {
        // When selection started inside a block, the active edge crosses block boundaries at a stable X position.
        // The old partial endpoint becomes a whole middle block only after the next Shift+Arrow continues past it.
        var blockIDs = mixedSelection.blockIDs
        var leadingTextRange = mixedSelection.leadingTextRange
        var trailingTextRange = mixedSelection.trailingTextRange
        let preferredTextContainerX = preferredNavigationX
        let targetIndex = direction == .upward ? expandedBounds.lowerBound : expandedBounds.upperBound
        guard let targetID = block(at: targetIndex)?.id else {
            return false
        }

        switch direction {
        case .upward:
            if let leadingBlockID = leadingTextRange?.blockID, !blockIDs.contains(leadingBlockID) {
                blockIDs.append(leadingBlockID)
            }
            leadingTextRange = partialTargetRange(
                for: targetID,
                at: targetIndex,
                direction: direction,
                preferredTextContainerX: preferredTextContainerX
            )
            if leadingTextRange == nil, !blockIDs.contains(targetID) {
                blockIDs.append(targetID)
            }
        case .downward:
            if let trailingBlockID = trailingTextRange?.blockID, !blockIDs.contains(trailingBlockID) {
                blockIDs.append(trailingBlockID)
            }
            trailingTextRange = partialTargetRange(
                for: targetID,
                at: targetIndex,
                direction: direction,
                preferredTextContainerX: preferredTextContainerX
            )
            if trailingTextRange == nil, !blockIDs.contains(targetID) {
                blockIDs.append(targetID)
            }
        }

        applySelection(.mixed(BlockInputMixedSelection(
            blockIDs: blockIDs.sortedByDocumentOrder(in: self),
            leadingTextRange: leadingTextRange,
            trailingTextRange: trailingTextRange
        )), notify: true)
        preferredNavigationX = preferredTextContainerX
        scrollBlockSelectionBoundaryToVisible(targetIndex)
        window?.makeFirstResponder(self)
        publishFocusChange(true)
        return true
    }

    func partialTargetRange(
        for blockID: BlockInputBlockID,
        at index: Int,
        direction: BlockInputVerticalMovementDirection,
        preferredTextContainerX: CGFloat?
    ) -> BlockInputTextRange? {
        // Mirror NSTextView vertical selection: the newly crossed block is selected only up to the caret's X position.
        guard let block = block(at: index),
              block.id == blockID,
              block.kind != .horizontalRule else {
            return nil
        }
        if let range = incrementalListBoundaryRange(for: block, direction: direction) {
            return BlockInputTextRange(blockID: blockID, range: range)
        }
        let targetItem = visibleItem(for: blockID)
        let linePosition: BlockInputBlockItem.TextLinePosition = direction == .upward ? .last : .first
        let offset = targetItem?.utf16Offset(
            closestToTextContainerX: preferredTextContainerX,
            linePosition: linePosition
        ) ?? (direction == .upward ? block.utf16Length : 0)
        let range: NSRange
        switch direction {
        case .upward:
            range = NSRange(location: offset, length: block.utf16Length - offset)
        case .downward:
            range = NSRange(location: 0, length: offset)
        }
        guard range.length > 0 else {
            return nil
        }
        return BlockInputTextRange(blockID: blockID, range: range)
    }

    private func promoteIncrementalListBoundary(
        targetBlock: BlockInputBlock,
        targetID: BlockInputBlockID,
        anchorBlockID: BlockInputBlockID,
        direction: BlockInputVerticalMovementDirection,
        scrollIndex: Int,
        preferredTextContainerX: CGFloat?
    ) -> Bool {
        guard let targetRange = incrementalListBoundaryRange(for: targetBlock, direction: direction) else {
            return false
        }
        let textRange = BlockInputTextRange(blockID: targetID, range: targetRange)
        let selection: BlockInputSelection = direction == .upward
            ? .mixed(BlockInputMixedSelection(blockIDs: [], leadingTextRange: textRange))
            : .mixed(BlockInputMixedSelection(blockIDs: [], trailingTextRange: textRange))
        return applyPromotedSelection(
            selection,
            anchorBlockID: anchorBlockID,
            direction: direction,
            scrollIndex: scrollIndex,
            preferredTextContainerX: preferredTextContainerX
        )
    }

    private func incrementalListBoundaryRange(
        for block: BlockInputBlock,
        direction: BlockInputVerticalMovementDirection
    ) -> NSRange? {
        // Multi-line list blocks have their own row-like selection ladder. Entering one from a neighboring caret
        // must start at the boundary list line; selecting the whole block here would skip all nested sub-items.
        guard block.usesIncrementalListLineSelection else {
            return nil
        }
        return block.incrementalListEdgeRange(direction: direction)
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
