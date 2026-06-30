import AppKit

extension BlockInputTextView {
    override func moveWordLeft(_ sender: Any?) {
        if moveWordAcrossInlineLinkSource(.leftward) {
            return
        }
        if blockItem?.isTableCellTextView(self) != true,
           requestWordMovementFromOwningBlock(.leftward) {
            return
        }
        super.moveWordLeft(sender)
    }

    override func moveWordRight(_ sender: Any?) {
        if moveWordAcrossInlineLinkSource(.rightward) {
            return
        }
        if blockItem?.isTableCellTextView(self) != true,
           requestWordMovementFromOwningBlock(.rightward) {
            return
        }
        super.moveWordRight(sender)
    }

    override func moveWordBackward(_ sender: Any?) {
        if moveWordAcrossInlineLinkSource(.leftward) {
            return
        }
        if blockItem?.isTableCellTextView(self) != true,
           requestWordMovementFromOwningBlock(.leftward) {
            return
        }
        super.moveWordBackward(sender)
    }

    override func moveWordForward(_ sender: Any?) {
        if moveWordAcrossInlineLinkSource(.rightward) {
            return
        }
        if blockItem?.isTableCellTextView(self) != true,
           requestWordMovementFromOwningBlock(.rightward) {
            return
        }
        super.moveWordForward(sender)
    }

    override func moveWordLeftAndModifySelection(_ sender: Any?) {
        let previousRange = selectedRange()
        if modifyWordSelectionAcrossInlineLinkSource(.leftward, previousRange: previousRange) {
            return
        }
        super.moveWordLeftAndModifySelection(sender)
        requestWordSelectionAdjustmentFromOwningBlock(
            .leftward,
            previousSelectedRange: previousRange,
            selectedRange: selectedRange()
        )
    }

    override func moveWordRightAndModifySelection(_ sender: Any?) {
        let previousRange = selectedRange()
        if modifyWordSelectionAcrossInlineLinkSource(.rightward, previousRange: previousRange) {
            return
        }
        super.moveWordRightAndModifySelection(sender)
        requestWordSelectionAdjustmentFromOwningBlock(
            .rightward,
            previousSelectedRange: previousRange,
            selectedRange: selectedRange()
        )
    }

    override func moveWordBackwardAndModifySelection(_ sender: Any?) {
        let previousRange = selectedRange()
        if modifyWordSelectionAcrossInlineLinkSource(.leftward, previousRange: previousRange) {
            return
        }
        super.moveWordBackwardAndModifySelection(sender)
        requestWordSelectionAdjustmentFromOwningBlock(
            .leftward,
            previousSelectedRange: previousRange,
            selectedRange: selectedRange()
        )
    }

    override func moveWordForwardAndModifySelection(_ sender: Any?) {
        let previousRange = selectedRange()
        if modifyWordSelectionAcrossInlineLinkSource(.rightward, previousRange: previousRange) {
            return
        }
        super.moveWordForwardAndModifySelection(sender)
        requestWordSelectionAdjustmentFromOwningBlock(
            .rightward,
            previousSelectedRange: previousRange,
            selectedRange: selectedRange()
        )
    }

    func handleWordSelectionAdjustmentShortcut(_ event: NSEvent) -> Bool {
        guard blockItem?.isTableCellTextView(self) != true,
              let direction = event.blockInputWordSelectionDirection else {
            return false
        }
        switch direction {
        case .leftward:
            moveWordLeftAndModifySelection(nil)
        case .rightward:
            moveWordRightAndModifySelection(nil)
        }
        return true
    }

    func handleWordSelectionAdjustmentCommand(_ selector: Selector) -> Bool {
        guard blockItem?.isTableCellTextView(self) != true else {
            return false
        }
        switch selector {
        case #selector(NSResponder.moveWordLeftAndModifySelection(_:)):
            moveWordLeftAndModifySelection(nil)
            return true
        case #selector(NSResponder.moveWordBackwardAndModifySelection(_:)):
            moveWordBackwardAndModifySelection(nil)
            return true
        case #selector(NSResponder.moveWordRightAndModifySelection(_:)):
            moveWordRightAndModifySelection(nil)
            return true
        case #selector(NSResponder.moveWordForwardAndModifySelection(_:)):
            moveWordForwardAndModifySelection(nil)
            return true
        default:
            return false
        }
    }

    func handleWordMovementShortcut(_ event: NSEvent) -> Bool {
        guard let direction = event.blockInputWordMovementDirection else {
            return false
        }
        switch direction {
        case .leftward:
            moveWordLeft(nil)
        case .rightward:
            moveWordRight(nil)
        }
        return true
    }

    func handleWordMovementCommand(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveWordLeft(_:)):
            moveWordLeft(nil)
            return true
        case #selector(NSResponder.moveWordBackward(_:)):
            moveWordBackward(nil)
            return true
        case #selector(NSResponder.moveWordRight(_:)):
            moveWordRight(nil)
            return true
        case #selector(NSResponder.moveWordForward(_:)):
            moveWordForward(nil)
            return true
        default:
            return false
        }
    }

    func requestWordMovementFromOwningBlock(_ direction: BlockInputWordMovementDirection) -> Bool {
        let range = selectedRange()
        guard range.length == 0 else {
            return false
        }
        let textLength = (string as NSString).length
        switch direction {
        case .leftward:
            guard range.location <= 0 else {
                return false
            }
        case .rightward:
            guard range.location >= textLength else {
                return false
            }
        }
        let result = blockItem?.requestWordMovement(direction, selectedRange: range) == true
        BlockInputSelectionDebug.emit(
            "text request word direction=\(direction.debugName) range=\(range) result=\(result)"
        )
        return result
    }

    @discardableResult
    func requestWordSelectionAdjustmentFromOwningBlock(
        _ direction: BlockInputWordMovementDirection,
        previousSelectedRange: NSRange,
        selectedRange: NSRange
    ) -> Bool {
        guard blockItem?.isTableCellTextView(self) != true else {
            return false
        }
        let result = blockItem?.requestWordSelectionAdjustment(
            direction,
            previousSelectedRange: previousSelectedRange,
            selectedRange: selectedRange
        ) == true
        BlockInputSelectionDebug.emit(
            "text request word selection direction=\(direction.debugName) previous=\(previousSelectedRange) " +
                "range=\(selectedRange) result=\(result)"
        )
        return result
    }
}
