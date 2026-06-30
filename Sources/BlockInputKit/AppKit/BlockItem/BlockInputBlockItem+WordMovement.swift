import AppKit

extension BlockInputBlockItem {
    @discardableResult
    func focusAndMoveWord(
        initialUTF16Offset offset: Int,
        direction: BlockInputWordMovementDirection
    ) -> NSRange {
        let textLength = (textView.string as NSString).length
        let clampedOffset = min(max(offset, 0), textLength)
        focusText(atUTF16Offset: clampedOffset)
        guard shouldPerformNativeWordMovement(
            from: clampedOffset,
            textLength: textLength,
            direction: direction
        ) else {
            return textView.selectedRange()
        }
        switch direction {
        case .leftward:
            textView.moveWordLeft(nil)
        case .rightward:
            textView.moveWordRight(nil)
        }
        updateTypingAttributesForCurrentSelection()
        return textView.selectedRange()
    }

    func requestWordMovement(
        _ direction: BlockInputWordMovementDirection,
        selectedRange: NSRange
    ) -> Bool {
        guard let blockID else {
            return false
        }
        return delegate?.blockItem(
            self,
            blockID: blockID,
            didRequestWordMovement: direction,
            selectedRange: selectedRange
        ) ?? false
    }

    func requestWordSelectionAdjustment(
        _ direction: BlockInputWordMovementDirection,
        previousSelectedRange: NSRange,
        selectedRange: NSRange
    ) -> Bool {
        guard let blockID else {
            return false
        }
        return delegate?.blockItem(
            self,
            blockID: blockID,
            didRequestWordSelectionAdjustment: direction,
            previousSelectedRange: previousSelectedRange,
            selectedRange: selectedRange
        ) ?? false
    }

    private func shouldPerformNativeWordMovement(
        from offset: Int,
        textLength: Int,
        direction: BlockInputWordMovementDirection
    ) -> Bool {
        switch direction {
        case .leftward:
            return offset > 0
        case .rightward:
            return offset < textLength
        }
    }
}
