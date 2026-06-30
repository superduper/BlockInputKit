import AppKit

extension BlockInputView {
    func contractSelectionIfNeeded(
        direction: BlockInputVerticalMovementDirection,
        firstIndex: Int,
        lastIndex: Int
    ) -> Bool {
        guard let expansion = blockSelectionExpansion,
              expansion.direction != direction,
              let anchorIndex = index(of: expansion.anchorBlockID) else {
            return false
        }
        if firstIndex...lastIndex ~= anchorIndex {
            switch selection {
            case .blocks:
                return shrinkBlockSelection(
                    anchorIndex: anchorIndex,
                    direction: expansion.direction,
                    firstIndex: firstIndex,
                    lastIndex: lastIndex
                )
            case let .mixed(mixedSelection):
                return shrinkMixedSelection(mixedSelection, direction: expansion.direction, anchorIndex: anchorIndex)
            case .cursor, .text, nil:
                return false
            }
        }
        // Boundary-origin selections can leave the original caret block outside the selected bounds. Lists still need
        // their internal line-by-line contraction before that outside caret is restored.
        if case let .mixed(mixedSelection) = selection,
           shrinkActiveIncrementalListEndpoint(
            mixedSelection,
            expansionDirection: expansion.direction,
            preservesPartialOnlyMixedSelection: true
           ) {
            return true
        }
        if demoteExcludedAnchorIncrementalListSelectionIfNeeded(
            expansionDirection: expansion.direction,
            firstIndex: firstIndex,
            lastIndex: lastIndex
        ) {
            return true
        }
        return restoreExcludedAnchorSelectionIfNeeded(
            anchorIndex: anchorIndex,
            direction: expansion.direction,
            firstIndex: firstIndex,
            lastIndex: lastIndex
        )
    }

    private func shrinkBlockSelection(
        anchorIndex: Int,
        direction: BlockInputVerticalMovementDirection,
        firstIndex: Int,
        lastIndex: Int
    ) -> Bool {
        let shrunkenBounds: ClosedRange<Int>
        switch direction {
        case .upward:
            guard firstIndex < anchorIndex else {
                if demoteIncrementalListWholeBlockSelectionIfNeeded(at: anchorIndex, expansionDirection: direction) {
                    return true
                }
                return restoreAnchorTextSelection(at: anchorIndex, direction: direction)
            }
            if demoteActiveIncrementalListWholeBlockSelectionIfNeeded(
                at: firstIndex,
                expansionDirection: direction,
                preservesPartialOnlyMixedSelection: false
            ) {
                return true
            }
            shrunkenBounds = (firstIndex + 1)...lastIndex
        case .downward:
            guard anchorIndex < lastIndex else {
                if demoteIncrementalListWholeBlockSelectionIfNeeded(at: anchorIndex, expansionDirection: direction) {
                    return true
                }
                return restoreAnchorTextSelection(at: anchorIndex, direction: direction)
            }
            if demoteActiveIncrementalListWholeBlockSelectionIfNeeded(
                at: lastIndex,
                expansionDirection: direction,
                preservesPartialOnlyMixedSelection: false
            ) {
                return true
            }
            shrunkenBounds = firstIndex...(lastIndex - 1)
        }
        guard shrunkenBounds.lowerBound != shrunkenBounds.upperBound else {
            return restoreAnchorTextSelection(at: anchorIndex, direction: direction)
        }
        let selectedIDs = shrunkenBounds.compactMap { block(at: $0)?.id }
        guard !selectedIDs.isEmpty else {
            return false
        }
        applySelection(.blocks(selectedIDs), notify: true)
        scrollBlockSelectionBoundaryToVisible(direction == .upward ? shrunkenBounds.lowerBound : shrunkenBounds.upperBound)
        window?.makeFirstResponder(self)
        publishFocusChange(true)
        return true
    }

    private func shrinkMixedSelection(
        _ selection: BlockInputMixedSelection,
        direction: BlockInputVerticalMovementDirection,
        anchorIndex: Int
    ) -> Bool {
        if shrinkActiveIncrementalListEndpoint(selection, expansionDirection: direction) {
            return true
        }
        let sortedBlockIDs = selection.blockIDs.sorted { lhs, rhs in
            (index(of: lhs) ?? Int.max) < (index(of: rhs) ?? Int.max)
        }
        guard !sortedBlockIDs.isEmpty else {
            return restoreMixedAnchorTextSelection(selection, direction: direction, anchorIndex: anchorIndex)
        }

        let blockIDToRemove = direction == .upward ? sortedBlockIDs.first : sortedBlockIDs.last
        guard let blockIDToRemove,
              let removedIndex = index(of: blockIDToRemove) else {
            return false
        }
        let remainingBlockIDs = sortedBlockIDs.filter { $0 != blockIDToRemove }
        let nextSelection = mixedSelectionAfterDemotingActiveEdge(
            selection,
            direction: direction,
            removedBlockID: blockIDToRemove,
            removedIndex: removedIndex,
            remainingBlockIDs: remainingBlockIDs
        )
        guard !remainingBlockIDs.isEmpty else {
            if nextSelection.hasPartialTextRange {
                return applyContractedMixedSelection(nextSelection, scrollIndex: removedIndex)
            }
            return restoreMixedAnchorTextSelection(selection, direction: direction, anchorIndex: anchorIndex)
        }

        return applyContractedMixedSelection(nextSelection, scrollIndex: removedIndex)
    }

    private func demoteIncrementalListWholeBlockSelectionIfNeeded(
        at index: Int,
        expansionDirection: BlockInputVerticalMovementDirection
    ) -> Bool {
        guard let block = block(at: index),
              let demotedRange = block.incrementalListSelectionRangeAfterDemotingWholeBlock(
                expansionDirection: expansionDirection
              ) else {
            return false
        }
        let textRange = BlockInputTextRange(blockID: block.id, range: demotedRange)
        applySelection(.text(textRange), notify: true)
        restoreVisibleTextSelection(textRange)
        // Whole list blocks demote back into their internal list lines before contraction leaves the block.
        blockSelectionExpansion = BlockInputBlockSelectionExpansion(anchorBlockID: block.id, direction: expansionDirection)
        publishFocusChange(true)
        return true
    }

    private func shrinkActiveIncrementalListEndpoint(
        _ selection: BlockInputMixedSelection,
        expansionDirection: BlockInputVerticalMovementDirection,
        preservesPartialOnlyMixedSelection: Bool = false
    ) -> Bool {
        let endpoint = expansionDirection == .upward ? selection.leadingTextRange : selection.trailingTextRange
        guard let endpoint,
              let block = block(withID: endpoint.blockID),
              block.usesIncrementalListLineSelection else {
            return false
        }
        let blockIDs = selection.blockIDs
        var leadingTextRange = selection.leadingTextRange
        var trailingTextRange = selection.trailingTextRange
        if let contractedRange = block.incrementalListSelectionRangeAfterContracting(
            endpoint.range,
            expansionDirection: expansionDirection
        ), contractedRange.length > 0 {
            let contractedTextRange = BlockInputTextRange(blockID: endpoint.blockID, range: contractedRange)
            if expansionDirection == .upward {
                leadingTextRange = contractedTextRange
            } else {
                trailingTextRange = contractedTextRange
            }
        } else if expansionDirection == .upward {
            leadingTextRange = nil
        } else {
            trailingTextRange = nil
        }

        let nextSelection = contractedSelectionFromMixedParts(
            blockIDs: blockIDs,
            leadingTextRange: leadingTextRange,
            trailingTextRange: trailingTextRange,
            preservesPartialOnlyMixedSelection: preservesPartialOnlyMixedSelection
        )
        guard let nextSelection else {
            return false
        }

        let preferredTextContainerX = preferredNavigationX
        applySelection(nextSelection, notify: true)
        preferredNavigationX = preferredTextContainerX
        if case let .text(textRange) = nextSelection {
            restoreVisibleTextSelection(textRange)
        } else {
            window?.makeFirstResponder(self)
        }
        blockSelectionExpansion = BlockInputBlockSelectionExpansion(
            anchorBlockID: blockSelectionExpansion?.anchorBlockID ?? endpoint.blockID,
            direction: expansionDirection
        )
        publishFocusChange(true)
        return true
    }

    private func contractedSelectionFromMixedParts(
        blockIDs: [BlockInputBlockID],
        leadingTextRange: BlockInputTextRange?,
        trailingTextRange: BlockInputTextRange?,
        preservesPartialOnlyMixedSelection: Bool = false
    ) -> BlockInputSelection? {
        let sortedBlockIDs = blockIDs.sortedByDocumentOrder(in: self)
        switch (sortedBlockIDs.isEmpty, leadingTextRange, trailingTextRange) {
        case (true, nil, nil):
            return nil
        case (false, nil, nil):
            return .blocks(sortedBlockIDs)
        case (true, let leading?, nil):
            if preservesPartialOnlyMixedSelection {
                return .mixed(BlockInputMixedSelection(blockIDs: [], leadingTextRange: leading))
            }
            return .text(leading)
        case (true, nil, let trailing?):
            if preservesPartialOnlyMixedSelection {
                return .mixed(BlockInputMixedSelection(blockIDs: [], trailingTextRange: trailing))
            }
            return .text(trailing)
        default:
            return .mixed(BlockInputMixedSelection(
                blockIDs: sortedBlockIDs,
                leadingTextRange: leadingTextRange,
                trailingTextRange: trailingTextRange
            ))
        }
    }

    private func demoteExcludedAnchorIncrementalListSelectionIfNeeded(
        expansionDirection: BlockInputVerticalMovementDirection,
        firstIndex: Int,
        lastIndex: Int
    ) -> Bool {
        let activeIndex = expansionDirection == .upward ? firstIndex : lastIndex
        // Keep the mixed selection form even when the demoted list is the only selected block. That preserves the
        // external caret anchor, so the next reverse key press can shrink another list line instead of re-anchoring
        // inside the list block.
        return demoteActiveIncrementalListWholeBlockSelectionIfNeeded(
            at: activeIndex,
            expansionDirection: expansionDirection,
            preservesPartialOnlyMixedSelection: true
        )
    }

    private func demoteActiveIncrementalListWholeBlockSelectionIfNeeded(
        at activeIndex: Int,
        expansionDirection: BlockInputVerticalMovementDirection,
        preservesPartialOnlyMixedSelection: Bool
    ) -> Bool {
        guard case let .blocks(blockIDs) = selection,
              let block = block(at: activeIndex),
              blockIDs.contains(block.id),
              block.usesIncrementalListLineSelection,
              let demotedRange = block.incrementalListSelectionRangeAfterDemotingWholeBlock(
                expansionDirection: expansionDirection
              ) else {
            return false
        }
        // The active whole list block is not removed in one jump. It first returns to the last internal line range
        // that existed before whole-block promotion, mirroring table row contraction.
        let remainingBlockIDs = blockIDs
            .filter { $0 != block.id }
            .sortedByDocumentOrder(in: self)
        let textRange = BlockInputTextRange(blockID: block.id, range: demotedRange)
        let nextSelection = expansionDirection == .upward
            ? contractedSelectionFromMixedParts(
                blockIDs: remainingBlockIDs,
                leadingTextRange: textRange,
                trailingTextRange: nil,
                preservesPartialOnlyMixedSelection: preservesPartialOnlyMixedSelection
            )
            : contractedSelectionFromMixedParts(
                blockIDs: remainingBlockIDs,
                leadingTextRange: nil,
                trailingTextRange: textRange,
                preservesPartialOnlyMixedSelection: preservesPartialOnlyMixedSelection
            )
        guard let nextSelection else {
            return false
        }
        let preferredTextContainerX = preferredNavigationX
        applySelection(nextSelection, notify: true)
        preferredNavigationX = preferredTextContainerX
        blockSelectionExpansion = BlockInputBlockSelectionExpansion(
            anchorBlockID: blockSelectionExpansion?.anchorBlockID ?? block.id,
            direction: expansionDirection
        )
        window?.makeFirstResponder(self)
        publishFocusChange(true)
        return true
    }

    private func mixedSelectionAfterDemotingActiveEdge(
        _ selection: BlockInputMixedSelection,
        direction: BlockInputVerticalMovementDirection,
        removedBlockID: BlockInputBlockID,
        removedIndex: Int,
        remainingBlockIDs: [BlockInputBlockID]
    ) -> BlockInputMixedSelection {
        switch direction {
        case .upward:
            let leadingTextRange = selection.leadingTextRange == nil ? nil : partialTargetRange(
                for: removedBlockID,
                at: removedIndex,
                direction: .upward,
                preferredTextContainerX: preferredNavigationX
            )
            return BlockInputMixedSelection(
                blockIDs: remainingBlockIDs,
                leadingTextRange: leadingTextRange,
                trailingTextRange: selection.trailingTextRange
            )
        case .downward:
            let trailingTextRange = selection.trailingTextRange == nil ? nil : partialTargetRange(
                for: removedBlockID,
                at: removedIndex,
                direction: .downward,
                preferredTextContainerX: preferredNavigationX
            )
            return BlockInputMixedSelection(
                blockIDs: remainingBlockIDs,
                leadingTextRange: selection.leadingTextRange,
                trailingTextRange: trailingTextRange
            )
        }
    }

    private func applyContractedMixedSelection(_ selection: BlockInputMixedSelection, scrollIndex: Int) -> Bool {
        let preferredTextContainerX = preferredNavigationX
        applySelection(.mixed(selection), notify: true)
        preferredNavigationX = preferredTextContainerX
        scrollBlockSelectionBoundaryToVisible(scrollIndex)
        window?.makeFirstResponder(self)
        publishFocusChange(true)
        return true
    }

    private func restoreMixedAnchorTextSelection(
        _ selection: BlockInputMixedSelection,
        direction: BlockInputVerticalMovementDirection,
        anchorIndex: Int
    ) -> Bool {
        let textRange = direction == .upward ? selection.trailingTextRange : selection.leadingTextRange
        guard let textRange else {
            return restoreAnchorTextSelection(at: anchorIndex, direction: direction)
        }
        applySelection(.text(textRange), notify: true)
        restoreVisibleTextSelection(textRange)
        blockSelectionExpansion = BlockInputBlockSelectionExpansion(anchorBlockID: textRange.blockID, direction: direction)
        publishFocusChange(true)
        return true
    }

    private func restoreExcludedAnchorSelectionIfNeeded(
        anchorIndex: Int,
        direction: BlockInputVerticalMovementDirection,
        firstIndex: Int,
        lastIndex: Int
    ) -> Bool {
        switch direction {
        case .upward:
            guard lastIndex + 1 == anchorIndex else {
                return false
            }
            return restoreAnchorCursorSelection(at: anchorIndex, direction: direction)
        case .downward:
            guard firstIndex - 1 == anchorIndex else {
                return false
            }
            return restoreAnchorCursorSelection(at: anchorIndex, direction: direction)
        }
    }

    private func restoreAnchorCursorSelection(at anchorIndex: Int, direction: BlockInputVerticalMovementDirection) -> Bool {
        guard let block = block(at: anchorIndex),
              block.kind != .horizontalRule else {
            return false
        }
        let cursor = BlockInputCursor(
            blockID: block.id,
            utf16Offset: direction == .upward ? 0 : block.cursorUTF16Length
        )
        applySelection(.cursor(cursor), notify: true)
        focusVisibleItem(for: cursor)
        blockSelectionExpansion = nil
        publishFocusChange(true)
        return true
    }

    private func restoreAnchorTextSelection(at anchorIndex: Int, direction: BlockInputVerticalMovementDirection) -> Bool {
        guard let block = block(at: anchorIndex),
              block.kind != .horizontalRule else {
            return false
        }
        let textRange = BlockInputTextRange(
            blockID: block.id,
            range: NSRange(location: 0, length: block.utf16Length)
        )
        applySelection(.text(textRange), notify: true)
        restoreVisibleTextSelection(textRange)
        // Visible selection restoration can synchronously re-report `.text`.
        // Re-save the contraction anchor afterward so the next AppKit-routed key
        // can expand from this full text selection again.
        blockSelectionExpansion = BlockInputBlockSelectionExpansion(anchorBlockID: block.id, direction: direction)
        publishFocusChange(true)
        return true
    }
}

private extension BlockInputMixedSelection {
    var hasPartialTextRange: Bool {
        leadingTextRange != nil || trailingTextRange != nil
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
