import AppKit

extension BlockInputView {
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didDragSelectBlocksWith event: NSEvent,
        selectedRange: NSRange?
    ) -> Bool {
        updateBlockSelectionDrag(from: blockID, item: item, with: event, selectedRange: selectedRange)
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestExpandSelection direction: BlockInputVerticalMovementDirection,
        selectedRange: NSRange,
        preferredTextContainerX: CGFloat?
    ) -> Bool {
        let expansionRange: NSRange
        if case let .text(textRange) = selection, textRange.blockID == blockID {
            expansionRange = textRange.range
        } else {
            expansionRange = selectedRange
        }
        BlockInputSelectionDebug.emit(
            "delegate expand block=\(blockID.rawValue) direction=\(direction.debugName) " +
                "selectedRange=\(expansionRange) selection=\(String(describing: selection))"
        )
        if case .blocks = selection {
            return expandBlockSelection(direction: direction)
        }
        if case .mixed = selection {
            return expandBlockSelection(direction: direction)
        }
        return expandSelection(
            from: blockID,
            selectedRange: expansionRange,
            direction: direction,
            preferredTextContainerX: preferredTextContainerX
        )
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestExpandActiveBlockSelection direction: BlockInputVerticalMovementDirection
    ) -> Bool {
        if case .blocks = selection {
            return expandBlockSelection(direction: direction)
        }
        guard case let .text(textRange) = selection,
              textRange.blockID == blockID,
              blockSelectionExpansion?.anchorBlockID == blockID,
              blockSelectionExpansion?.direction == direction else {
            return false
        }
        return expandSelection(from: blockID, selectedRange: textRange.range, direction: direction, preferredTextContainerX: nil)
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestHorizontalSelectionAdjustment direction: BlockInputHorizontalMovementDirection,
        selectedRange: NSRange
    ) -> Bool {
        adjustSelectionHorizontally(from: blockID, selectedRange: selectedRange, direction: direction)
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestLineBoundarySelection direction: BlockInputLineBoundarySelectionDirection,
        selectedRange: NSRange
    ) -> Bool {
        adjustSelectionToLineBoundary(from: blockID, selectedRange: selectedRange, direction: direction)
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestWordMovement direction: BlockInputWordMovementDirection,
        selectedRange: NSRange
    ) -> Bool {
        moveWord(from: blockID, selectedRange: selectedRange, direction: direction)
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestWordSelectionAdjustment direction: BlockInputWordMovementDirection,
        previousSelectedRange: NSRange,
        selectedRange: NSRange
    ) -> Bool {
        adjustWordSelection(
            from: blockID,
            previousSelectedRange: previousSelectedRange,
            selectedRange: selectedRange,
            direction: direction
        )
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestCollapseSelection direction: BlockInputVerticalMovementDirection
    ) -> Bool {
        collapseMultiBlockSelection(direction: direction)
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestDocumentBoundary direction: BlockInputVerticalMovementDirection
    ) -> Bool {
        moveCaretToDocumentBoundary(direction)
    }

    func blockItemDidRequestCancelSelection(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) -> Bool {
        cancelMultiBlockSelection()
    }

    func blockItemDidRequestMouseDownCancelSelection(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) -> Bool {
        cancelMultiBlockSelectionForMouseDown()
    }
}
