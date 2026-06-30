import AppKit

extension BlockInputView {
    func expandSelection(
        from blockID: BlockInputBlockID,
        selectedRange: NSRange,
        direction: BlockInputVerticalMovementDirection,
        preferredTextContainerX: CGFloat?
    ) -> Bool {
        BlockInputSelectionDebug.emit(
            "expand text block=\(blockID.rawValue) range=\(selectedRange) direction=\(direction.debugName) selection=\(String(describing: selection))"
        )
        guard let block = block(withID: blockID),
              block.kind != .horizontalRule else {
            return expandBlockSelection(from: blockID, direction: direction, preferredTextContainerX: preferredTextContainerX)
        }
        if selectedRange.length == 0,
           promoteCaretSelectionAcrossBlockBoundary(
            from: blockID,
            selectedRange: selectedRange,
            currentBlock: block,
            direction: direction,
            preferredTextContainerX: preferredTextContainerX
           ) {
            return true
        }
        if contractIncrementalListTextSelectionIfNeeded(
            from: blockID,
            selectedRange: selectedRange,
            currentBlock: block,
            direction: direction
        ) {
            return true
        }
        if let promoted = promoteTextSelectionToBlockIfNeeded(
            from: blockID,
            selectedRange: selectedRange,
            currentBlock: block,
            direction: direction,
            preferredTextContainerX: preferredTextContainerX
        ) {
            return promoted
        }
        let expandedRange = block.text.expandingLineSelection(selectedRange, direction: direction)
        guard expandedRange != selectedRange else { return false }
        if promoteExpandedIncrementalListTextSelectionIfNeeded(
            from: blockID,
            expandedRange: expandedRange,
            currentBlock: block,
            direction: direction
        ) {
            return true
        }
        return applyExpandedTextSelection(
            BlockInputTextRange(blockID: blockID, range: expandedRange),
            block: block,
            direction: direction
        )
    }

    func promoteNativeSelectionExpansionIfNeeded(
        from blockID: BlockInputBlockID,
        selectedRange: NSRange,
        direction: BlockInputVerticalMovementDirection
    ) -> Bool {
        guard let block = block(withID: blockID),
              block.kind != .horizontalRule,
              selectedRange.shouldPromoteToBlockSelection(in: block.text, direction: direction) else {
            return false
        }
        if promoteCompletedIncrementalListTextSelectionIfNeeded(
            from: blockID,
            selectedRange: selectedRange,
            currentBlock: block,
            direction: direction
        ) {
            return true
        }
        let boundaryOffset = direction == .upward ? selectedRange.location : NSMaxRange(selectedRange)
        let preferredTextContainerX = visibleItem(for: blockID)?
            .textContainerX(forUTF16Offset: boundaryOffset)
        return expandBlockSelection(
            from: blockID,
            direction: direction,
            preferredTextContainerX: preferredTextContainerX
        )
    }

    func expandBlockSelection(direction: BlockInputVerticalMovementDirection) -> Bool {
        BlockInputSelectionDebug.emit(
            "expand blocks direction=\(direction.debugName) selection=\(String(describing: selection))"
        )
        guard let selectedBounds = selectedBlockIndexBounds() else {
            BlockInputSelectionDebug.emit("expand blocks rejected")
            return false
        }
        let firstIndex = selectedBounds.lowerBound
        let lastIndex = selectedBounds.upperBound
        if contractSelectionIfNeeded(direction: direction, firstIndex: firstIndex, lastIndex: lastIndex) {
            return true
        }
        if case let .mixed(mixedSelection) = selection,
           blockSelectionExpansion?.direction == direction,
           expandActiveIncrementalListEndpointIfNeeded(mixedSelection, direction: direction) {
            return true
        }
        guard let expandedBounds = expandedBlockSelectionBounds(from: selectedBounds, direction: direction) else {
            return false
        }
        if case .blocks = selection,
           expandBlockSelectionIntoIncrementalListEndpoint(
            selectedBounds: selectedBounds,
            expandedBounds: expandedBounds,
            direction: direction
           ) {
            return true
        }
        if case let .mixed(mixedSelection) = selection,
           blockSelectionExpansion?.direction == direction {
            return expandMixedSelectionContinuing(mixedSelection, expandedBounds: expandedBounds, direction: direction)
        }
        return applyExpandedBlockSelection(
            selectedBounds: selectedBounds,
            expandedBounds: expandedBounds,
            direction: direction
        )
    }

    private func applyExpandedBlockSelection(
        selectedBounds: ClosedRange<Int>,
        expandedBounds: ClosedRange<Int>,
        direction: BlockInputVerticalMovementDirection
    ) -> Bool {
        let expandedIDs: [BlockInputBlockID]
        if case let .mixed(mixedSelection) = selection {
            expandedIDs = expandedMixedBlockIDs(mixedSelection, expandedBounds: expandedBounds, direction: direction)
        } else {
            expandedIDs = expandedBounds.compactMap { block(at: $0)?.id }
        }
        guard !expandedIDs.isEmpty else {
            return false
        }
        if case let .mixed(mixedSelection) = selection {
            applySelection(.mixed(BlockInputMixedSelection(
                blockIDs: expandedIDs,
                leadingTextRange: mixedSelection.leadingTextRange,
                trailingTextRange: mixedSelection.trailingTextRange
            )), notify: true)
        } else {
            applySelection(.blocks(expandedIDs), notify: true)
        }
        if blockSelectionExpansion == nil {
            let anchorID = direction == .upward
                ? block(at: selectedBounds.upperBound)?.id
                : block(at: selectedBounds.lowerBound)?.id
            blockSelectionExpansion = anchorID.map {
                BlockInputBlockSelectionExpansion(anchorBlockID: $0, direction: direction)
            }
        }
        BlockInputSelectionDebug.emit("expanded blocks count=\(expandedIDs.count)")
        scrollBlockSelectionBoundaryToVisible(direction == .upward ? expandedBounds.lowerBound : expandedBounds.upperBound)
        window?.makeFirstResponder(self)
        publishFocusChange(true)
        return true
    }

    private func selectedBlockIndexBounds() -> ClosedRange<Int>? {
        switch selection {
        case let .blocks(blockIDs):
            return selectedBlockIndexBounds(for: blockIDs)
        case let .mixed(mixedSelection):
            var blockIDs = mixedSelection.blockIDs
            if let blockID = mixedSelection.leadingTextRange?.blockID {
                blockIDs.append(blockID)
            }
            if let blockID = mixedSelection.trailingTextRange?.blockID {
                blockIDs.append(blockID)
            }
            return selectedBlockIndexBounds(for: blockIDs)
        case .cursor, .text, nil:
            return nil
        }
    }

    private func selectedBlockIndexBounds(for blockIDs: [BlockInputBlockID]) -> ClosedRange<Int>? {
        let indexes = blockIDs.compactMap { index(of: $0) }
        guard let firstIndex = indexes.min(),
              let lastIndex = indexes.max() else {
            return nil
        }
        return firstIndex...lastIndex
    }

    private func expandedBlockSelectionBounds(
        from bounds: ClosedRange<Int>,
        direction: BlockInputVerticalMovementDirection
    ) -> ClosedRange<Int>? {
        switch direction {
        case .upward:
            guard bounds.lowerBound > 0 else {
                return nil
            }
            return (bounds.lowerBound - 1)...bounds.upperBound
        case .downward:
            guard bounds.upperBound + 1 < blockCount else {
                return nil
            }
            return bounds.lowerBound...(bounds.upperBound + 1)
        }
    }

    private func expandedMixedBlockIDs(
        _ mixedSelection: BlockInputMixedSelection,
        expandedBounds: ClosedRange<Int>,
        direction: BlockInputVerticalMovementDirection
    ) -> [BlockInputBlockID] {
        var blockIDs = mixedSelection.blockIDs
        switch direction {
        case .upward:
            if let blockID = block(at: expandedBounds.lowerBound)?.id,
               !blockIDs.contains(blockID),
               mixedSelection.leadingTextRange?.blockID != blockID,
               mixedSelection.trailingTextRange?.blockID != blockID {
                blockIDs.append(blockID)
            }
        case .downward:
            if let blockID = block(at: expandedBounds.upperBound)?.id,
               !blockIDs.contains(blockID),
               mixedSelection.leadingTextRange?.blockID != blockID,
               mixedSelection.trailingTextRange?.blockID != blockID {
                blockIDs.append(blockID)
            }
        }
        return blockIDs.sorted { lhs, rhs in
            (index(of: lhs) ?? Int.max) < (index(of: rhs) ?? Int.max)
        }
    }

    func handleSelectionExpansionShortcut(_ event: NSEvent) -> Bool {
        handleSelectionExpansionKeyEvent(event) || handleHorizontalSelectionAdjustmentKeyEvent(event)
    }

    func handleSelectionExpansionCommand(_ selector: Selector) -> Bool {
        BlockInputSelectionDebug.emit(
            "view command selector=\(selector) selection=\(String(describing: selection))"
        )
        if shouldHandleTableKeyboardRowSelectionVertically() {
            switch selector {
            case #selector(moveUpAndModifySelection(_:)):
                return handleTableKeyboardRowSelection(.upward)
            case #selector(moveDownAndModifySelection(_:)):
                return handleTableKeyboardRowSelection(.downward)
            default:
                break
            }
        }
        switch selection {
        case .blocks, .mixed:
            break
        case .cursor, .text, nil:
            return false
        }
        switch selector {
        case #selector(moveUpAndModifySelection(_:)):
            _ = expandBlockSelection(direction: .upward)
            return true
        case #selector(moveDownAndModifySelection(_:)):
            _ = expandBlockSelection(direction: .downward)
            return true
        default:
            return false
        }
    }

    func handleDocumentBoundaryCommand(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(moveToBeginningOfDocument(_:)):
            return moveCaretToDocumentBoundary(.upward)
        case #selector(moveToEndOfDocument(_:)):
            return moveCaretToDocumentBoundary(.downward)
        default:
            return false
        }
    }

    func handleSelectionExpansionKeyEvent(_ event: NSEvent) -> Bool {
        if event.isArrowKey {
            BlockInputSelectionDebug.emit(
                "view key key=\(event.debugKeyName) modifiers=\(event.debugModifierNames) selection=\(String(describing: selection))"
            )
        }
        guard let direction = event.blockInputSelectionExpansionDirection else {
            if event.isArrowKey {
                BlockInputSelectionDebug.emit("view key no Shift+Arrow direction")
            }
            return false
        }
        if shouldHandleTableKeyboardRowSelectionVertically() {
            return handleTableKeyboardRowSelection(direction)
        }
        if let textView = window?.firstResponder as? BlockInputTextView,
           shouldRouteSelectionExpansionThroughFocusedTextView(textView) {
            _ = textView.requestSelectionExpansionFromOwningBlock(direction)
            return true
        }
        switch selection {
        case .blocks, .mixed:
            _ = expandHorizontalSelectionVerticallyIfNeeded(direction)
                || expandBlockSelection(direction: direction)
            return true
        case let .text(textRange):
            _ = expandSelection(from: textRange.blockID, selectedRange: textRange.range, direction: direction, preferredTextContainerX: nil)
            return true
        case let .cursor(cursor):
            let range = NSRange(location: cursor.utf16Offset, length: 0)
            _ = expandSelection(from: cursor.blockID, selectedRange: range, direction: direction, preferredTextContainerX: nil)
            return true
        case nil:
            break
        }
        if let textView = window?.firstResponder as? BlockInputTextView {
            _ = textView.requestSelectionExpansionFromOwningBlock(direction)
            return true
        }
        BlockInputSelectionDebug.emit("view key no selection source")
        return false
    }

    private func shouldRouteSelectionExpansionThroughFocusedTextView(_ textView: BlockInputTextView) -> Bool {
        guard let blockID = textView.blockItem?.representedBlockID else {
            return false
        }
        switch selection {
        case let .cursor(cursor):
            return cursor.blockID == blockID
                && textView.selectedRange() == NSRange(location: cursor.utf16Offset, length: 0)
        case let .text(textRange):
            return textRange.blockID == blockID
                && textView.selectedRange() == textRange.range
        case .blocks, .mixed, nil:
            return false
        }
    }

    func expandBlockSelection(
        from blockID: BlockInputBlockID,
        direction: BlockInputVerticalMovementDirection,
        preferredTextContainerX: CGFloat? = nil
    ) -> Bool {
        BlockInputSelectionDebug.emit("promote block=\(blockID.rawValue) direction=\(direction.debugName)")
        guard let index = index(of: blockID) else {
            BlockInputSelectionDebug.emit("promote rejected missing index")
            return false
        }
        if startAdjacentTableRowSelectionVerticallyFromTextRange(
            blockID: blockID,
            index: index,
            direction: direction
        ) {
            return true
        }
        if let promotion = mixedPromotionFromTextRange(
            blockID: blockID,
            index: index,
            direction: direction,
            preferredTextContainerX: preferredTextContainerX
        ) {
            return applyPromotedSelection(
                promotion.selection,
                anchorBlockID: blockID,
                direction: direction,
                scrollIndex: promotion.scrollIndex,
                preferredTextContainerX: preferredTextContainerX
            )
        }
        let bounds: ClosedRange<Int>
        switch direction {
        case .upward:
            guard index > 0 else {
                return false
            }
            bounds = (index - 1)...index
        case .downward:
            guard index + 1 < blockCount else {
                return false
            }
            bounds = index...(index + 1)
        }
        let selectedIDs = bounds.compactMap { block(at: $0)?.id }
        guard !selectedIDs.isEmpty else {
            return false
        }
        let scrollIndex = direction == .upward ? bounds.lowerBound : bounds.upperBound
        return applyPromotedSelection(
            .blocks(selectedIDs),
            anchorBlockID: blockID,
            direction: direction,
            scrollIndex: scrollIndex
        )
    }

    private func mixedPromotionFromTextRange(
        blockID: BlockInputBlockID,
        index: Int,
        direction: BlockInputVerticalMovementDirection,
        preferredTextContainerX: CGFloat?
    ) -> (selection: BlockInputSelection, scrollIndex: Int)? {
        guard let currentBlock = block(withID: blockID),
              currentBlock.kind != .horizontalRule,
              let textRange = textRangeForMixedPromotion(block: currentBlock, direction: direction) else {
            return nil
        }
        switch direction {
        case .upward:
            guard index > 0, let previousID = block(at: index - 1)?.id else {
                return nil
            }
            let targetRange = partialTargetRange(
                for: previousID,
                at: index - 1,
                direction: direction,
                preferredTextContainerX: preferredTextContainerX
            )
            return (
                .mixed(BlockInputMixedSelection(
                    blockIDs: targetRange == nil ? [previousID] : [],
                    leadingTextRange: targetRange,
                    trailingTextRange: textRange
                )),
                index - 1
            )
        case .downward:
            guard index + 1 < blockCount, let nextID = block(at: index + 1)?.id else {
                return nil
            }
            let targetRange = partialTargetRange(
                for: nextID,
                at: index + 1,
                direction: direction,
                preferredTextContainerX: preferredTextContainerX
            )
            return (
                .mixed(BlockInputMixedSelection(
                    blockIDs: targetRange == nil ? [nextID] : [],
                    leadingTextRange: textRange,
                    trailingTextRange: targetRange
                )),
                index + 1
            )
        }
    }

    private func textRangeForMixedPromotion(
        block: BlockInputBlock,
        direction: BlockInputVerticalMovementDirection
    ) -> BlockInputTextRange? {
        guard case let .text(textRange) = selection,
              textRange.blockID == block.id,
              textRange.range.length > 0 else {
            return nil
        }
        let textLength = block.utf16Length
        // Even when the current block is fully selected, keep it as the fixed text endpoint. The newly crossed
        // neighboring block starts partial and only becomes a whole middle block after another Shift+Arrow press.
        switch direction {
        case .upward:
            guard textRange.range.location <= 0 else {
                return nil
            }
            return textRange
        case .downward:
            guard NSMaxRange(textRange.range) >= textLength else {
                return nil
            }
            return textRange
        }
    }

}
