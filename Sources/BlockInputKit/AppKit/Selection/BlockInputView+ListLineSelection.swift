import AppKit

extension BlockInputView {
    func applyExpandedTextSelection(
        _ textRange: BlockInputTextRange,
        block: BlockInputBlock,
        direction: BlockInputVerticalMovementDirection
    ) -> Bool {
        applySelection(.text(textRange), notify: true)
        restoreVisibleTextSelection(textRange)
        if block.usesIncrementalListLineSelection {
            // Multi-line list blocks behave like row-backed surfaces: remember the active edge so reversing Shift+Arrow
            // removes internal list lines instead of treating a top-anchored range as a request for the previous block.
            blockSelectionExpansion = BlockInputBlockSelectionExpansion(anchorBlockID: textRange.blockID, direction: direction)
        }
        BlockInputSelectionDebug.emit("expanded text range=\(textRange.range)")
        return true
    }

    func promoteTextSelectionToBlockIfNeeded(
        from blockID: BlockInputBlockID,
        selectedRange: NSRange,
        currentBlock: BlockInputBlock,
        direction: BlockInputVerticalMovementDirection,
        preferredTextContainerX: CGFloat?
    ) -> Bool? {
        guard selectedRange.shouldPromoteToBlockSelection(in: currentBlock.text, direction: direction) else {
            return nil
        }
        if promoteCompletedIncrementalListTextSelectionIfNeeded(
            from: blockID,
            selectedRange: selectedRange,
            currentBlock: currentBlock,
            direction: direction
        ) {
            return true
        }
        return expandBlockSelection(from: blockID, direction: direction, preferredTextContainerX: preferredTextContainerX)
    }

    func contractIncrementalListTextSelectionIfNeeded(
        from blockID: BlockInputBlockID,
        selectedRange: NSRange,
        currentBlock: BlockInputBlock,
        direction: BlockInputVerticalMovementDirection
    ) -> Bool {
        guard currentBlock.usesIncrementalListLineSelection,
              let expansion = blockSelectionExpansion,
              expansion.anchorBlockID == blockID,
              expansion.direction != direction,
              selectedRange.length > 0 else {
            return false
        }
        if let contractedRange = currentBlock.incrementalListSelectionRangeAfterContracting(
            selectedRange,
            expansionDirection: expansion.direction
        ), contractedRange.length > 0 {
            applyIncrementalListTextSelection(
                BlockInputTextRange(blockID: blockID, range: contractedRange),
                expansionDirection: expansion.direction
            )
            return true
        }
        let cursor = BlockInputCursor(
            blockID: blockID,
            utf16Offset: currentBlock.incrementalListAnchorOffset(for: selectedRange, expansionDirection: expansion.direction)
        )
        applySelection(.cursor(cursor), notify: true)
        focusVisibleItem(for: cursor)
        return true
    }

    func promoteCompletedIncrementalListTextSelectionIfNeeded(
        from blockID: BlockInputBlockID,
        selectedRange: NSRange,
        currentBlock: BlockInputBlock,
        direction: BlockInputVerticalMovementDirection
    ) -> Bool {
        guard currentBlock.usesIncrementalListLineSelection,
              currentBlock.incrementalListSelectionCoversWholeBlock(selectedRange) else {
            return false
        }
        applyIncrementalListWholeBlockSelection(blockID: blockID, direction: direction)
        return true
    }

    func promoteExpandedIncrementalListTextSelectionIfNeeded(
        from blockID: BlockInputBlockID,
        expandedRange: NSRange,
        currentBlock: BlockInputBlock,
        direction: BlockInputVerticalMovementDirection
    ) -> Bool {
        guard currentBlock.usesIncrementalListLineSelection,
              currentBlock.incrementalListSelectionCoversWholeBlock(expandedRange) else {
            return false
        }
        // A multi-line list block becomes a whole block only after every internal list line has been selected.
        applyIncrementalListWholeBlockSelection(blockID: blockID, direction: direction)
        return true
    }

    func expandActiveIncrementalListEndpointIfNeeded(
        _ mixedSelection: BlockInputMixedSelection,
        direction: BlockInputVerticalMovementDirection
    ) -> Bool {
        let endpoint = direction == .upward ? mixedSelection.leadingTextRange : mixedSelection.trailingTextRange
        guard let endpoint,
              let block = block(withID: endpoint.blockID),
              block.usesIncrementalListLineSelection,
              !block.incrementalListSelectionCoversWholeBlock(endpoint.range),
              let expandedRange = block.incrementalListSelectionRangeAfterExpanding(endpoint.range, direction: direction),
              expandedRange != endpoint.range else {
            return false
        }
        let nextSelection = expandedIncrementalListEndpointSelection(
            mixedSelection,
            endpoint: endpoint,
            block: block,
            expandedRange: expandedRange,
            direction: direction
        )
        let preferredTextContainerX = preferredNavigationX
        applySelection(nextSelection, notify: true)
        preferredNavigationX = preferredTextContainerX
        let anchorID = blockSelectionExpansion?.anchorBlockID ?? endpoint.blockID
        blockSelectionExpansion = BlockInputBlockSelectionExpansion(anchorBlockID: anchorID, direction: direction)
        window?.makeFirstResponder(self)
        publishFocusChange(true)
        return true
    }

    func expandBlockSelectionIntoIncrementalListEndpoint(
        selectedBounds: ClosedRange<Int>,
        expandedBounds: ClosedRange<Int>,
        direction: BlockInputVerticalMovementDirection
    ) -> Bool {
        let targetIndex = direction == .upward ? expandedBounds.lowerBound : expandedBounds.upperBound
        guard !selectedBounds.contains(targetIndex),
              let targetBlock = block(at: targetIndex),
              targetBlock.usesIncrementalListLineSelection,
              let targetRange = targetBlock.incrementalListEdgeRange(direction: direction) else {
            return false
        }
        let selectedBlockIDs = selectedBounds.compactMap { block(at: $0)?.id }
        let textRange = BlockInputTextRange(blockID: targetBlock.id, range: targetRange)
        let selection = direction == .upward
            ? mixedSelectionFromParts(blockIDs: selectedBlockIDs, leadingTextRange: textRange, trailingTextRange: nil)
            : mixedSelectionFromParts(blockIDs: selectedBlockIDs, leadingTextRange: nil, trailingTextRange: textRange)
        applySelection(selection, notify: true)
        let anchorID = blockSelectionExpansion?.anchorBlockID
            ?? (direction == .upward ? block(at: selectedBounds.upperBound)?.id : block(at: selectedBounds.lowerBound)?.id)
            ?? targetBlock.id
        blockSelectionExpansion = BlockInputBlockSelectionExpansion(anchorBlockID: anchorID, direction: direction)
        scrollBlockSelectionBoundaryToVisible(targetIndex)
        window?.makeFirstResponder(self)
        publishFocusChange(true)
        return true
    }

    private func applyIncrementalListTextSelection(
        _ textRange: BlockInputTextRange,
        expansionDirection: BlockInputVerticalMovementDirection
    ) {
        applySelection(.text(textRange), notify: true)
        restoreVisibleTextSelection(textRange)
        blockSelectionExpansion = BlockInputBlockSelectionExpansion(anchorBlockID: textRange.blockID, direction: expansionDirection)
    }

    private func applyIncrementalListWholeBlockSelection(
        blockID: BlockInputBlockID,
        direction: BlockInputVerticalMovementDirection
    ) {
        applySelection(.blocks([blockID]), notify: true)
        blockSelectionExpansion = BlockInputBlockSelectionExpansion(anchorBlockID: blockID, direction: direction)
        restoreVisibleBlockSelection([blockID])
        publishFocusChange(true)
    }

    private func expandedIncrementalListEndpointSelection(
        _ mixedSelection: BlockInputMixedSelection,
        endpoint: BlockInputTextRange,
        block: BlockInputBlock,
        expandedRange: NSRange,
        direction: BlockInputVerticalMovementDirection
    ) -> BlockInputSelection {
        var blockIDs = mixedSelection.blockIDs
        var leadingTextRange = mixedSelection.leadingTextRange
        var trailingTextRange = mixedSelection.trailingTextRange
        let expandedTextRange = BlockInputTextRange(blockID: endpoint.blockID, range: expandedRange)
        if block.incrementalListSelectionCoversWholeBlock(expandedRange) {
            if !blockIDs.contains(endpoint.blockID) {
                blockIDs.append(endpoint.blockID)
            }
            if direction == .upward {
                leadingTextRange = nil
            } else {
                trailingTextRange = nil
            }
        } else if direction == .upward {
            leadingTextRange = expandedTextRange
        } else {
            trailingTextRange = expandedTextRange
        }
        return mixedSelectionFromParts(
            blockIDs: blockIDs,
            leadingTextRange: leadingTextRange,
            trailingTextRange: trailingTextRange
        )
    }

    private func mixedSelectionFromParts(
        blockIDs: [BlockInputBlockID],
        leadingTextRange: BlockInputTextRange?,
        trailingTextRange: BlockInputTextRange?
    ) -> BlockInputSelection {
        let sortedBlockIDs = blockIDs.sorted { lhs, rhs in
            (index(of: lhs) ?? Int.max) < (index(of: rhs) ?? Int.max)
        }
        guard leadingTextRange != nil || trailingTextRange != nil else {
            return .blocks(sortedBlockIDs)
        }
        return .mixed(BlockInputMixedSelection(
            blockIDs: sortedBlockIDs,
            leadingTextRange: leadingTextRange,
            trailingTextRange: trailingTextRange
        ))
    }
}
