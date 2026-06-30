import AppKit

extension BlockInputView {
    func blockItem(_ item: BlockInputBlockItem, didChangeSelectionIn blockID: BlockInputBlockID, selectedRange: NSRange?) {
        guard shouldTrackTextSelectionChange(from: item, selectedRange: selectedRange),
              let block = block(withID: blockID),
              block.kind != .horizontalRule else {
            return
        }
        let previousActiveBlockID = currentSelectionOwnerBlockID()
        let range = selectedRange ?? item.currentSelectedRange
        let nativeExpansionDirection = nativeTextSelectionExpansionDirection(
            blockID: blockID,
            selectedRange: range,
            blockText: block.text
        )
        if shouldPromoteNativeTextSelection(
            blockID: blockID,
            range: range,
            direction: nativeExpansionDirection,
            blockText: block.text
        ) {
            return
        }
        applyTextSelectionChange(
            blockID: blockID,
            range: range,
            blockText: block.text,
            nativeExpansionDirection: nativeExpansionDirection
        )
        if let previousActiveBlockID,
           previousActiveBlockID != blockID {
            refreshSelectionDependentAttributesForVisibleItem(blockID: previousActiveBlockID)
        }
        refreshCompletionSession(item: item, blockID: blockID, originatedFromTextChange: false)
    }

    func refreshSelectionDependentAttributesForVisibleItem(blockID: BlockInputBlockID) {
        visibleConfiguredItem(for: blockID)?
            .updateSelectionDependentAttributesForCurrentSelection()
    }

    func currentSelectionOwnerBlockID() -> BlockInputBlockID? {
        switch selection {
        case let .cursor(cursor):
            return cursor.blockID
        case let .text(textRange):
            return textRange.blockID
        case let .blocks(blockIDs):
            return lastFocusedBlockID ?? blockIDs.first
        case let .mixed(mixedSelection):
            return mixedSelection.leadingTextRange?.blockID
                ?? mixedSelection.trailingTextRange?.blockID
                ?? lastFocusedBlockID
                ?? mixedSelection.blockIDs.first
        case nil:
            return lastFocusedBlockID
        }
    }
}

private extension BlockInputView {
    func shouldTrackTextSelectionChange(from item: BlockInputBlockItem, selectedRange: NSRange?) -> Bool {
        guard !item.isDraggingBlockSelection else {
            return false
        }
        if window?.firstResponder === self, selectedRange == nil {
            return false
        }
        if case .blocks = selection,
           selectedRange == nil,
           NSApp.currentEvent?.type != .leftMouseDown,
           NSApp.currentEvent?.type != .leftMouseDragged {
            return false
        }
        return true
    }

    func shouldPromoteNativeTextSelection(
        blockID: BlockInputBlockID,
        range: NSRange,
        direction: BlockInputVerticalMovementDirection?,
        blockText: String
    ) -> Bool {
        guard let direction,
              shouldPromoteRepeatedNativeTextSelection(
                blockID: blockID,
                selectedRange: range,
                direction: direction,
                blockText: blockText
              ) else {
            return false
        }
        return promoteNativeSelectionExpansionIfNeeded(from: blockID, selectedRange: range, direction: direction)
    }

    func applyTextSelectionChange(
        blockID: BlockInputBlockID,
        range: NSRange,
        blockText: String,
        nativeExpansionDirection: BlockInputVerticalMovementDirection?
    ) {
        if range.length == 0 {
            applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: range.location)), notify: true)
            return
        }
        applySelection(.text(BlockInputTextRange(blockID: blockID, range: range)), notify: true)
        updateNativeTextSelectionExpansion(
            blockID: blockID,
            range: range,
            blockText: blockText,
            direction: nativeExpansionDirection
        )
    }

    func updateNativeTextSelectionExpansion(
        blockID: BlockInputBlockID,
        range: NSRange,
        blockText: String,
        direction: BlockInputVerticalMovementDirection?
    ) {
        guard let direction,
              range.isSelectionExpansionBoundary(in: blockText, direction: direction) else {
            lastNativeTextSelectionExpansion = nil
            return
        }
        lastNativeTextSelectionExpansion = BlockInputNativeTextSelectionExpansion(
            blockID: blockID,
            range: range,
            direction: direction
        )
    }

    func visibleConfiguredItem(for blockID: BlockInputBlockID) -> BlockInputBlockItem? {
        collectionView.visibleItems()
            .compactMap { $0 as? BlockInputBlockItem }
            .first { $0.representedBlockID == blockID }
    }
}
