import AppKit

extension BlockInputTextView {
    func handleHorizontalSelectionAdjustmentCommand(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(moveLeftAndModifySelection(_:)),
             #selector(moveBackwardAndModifySelection(_:)):
            return requestHorizontalSelectionAdjustmentFromOwningBlock(.leftward)
        case #selector(moveRightAndModifySelection(_:)),
             #selector(moveForwardAndModifySelection(_:)):
            return requestHorizontalSelectionAdjustmentFromOwningBlock(.rightward)
        default:
            return false
        }
    }

    func handleLineBoundarySelectionCommand(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(moveToBeginningOfLineAndModifySelection(_:)),
             #selector(moveToLeftEndOfLineAndModifySelection(_:)):
            return requestLineBoundarySelectionFromOwningBlock(.beginning)
        case #selector(moveToEndOfLineAndModifySelection(_:)),
             #selector(moveToRightEndOfLineAndModifySelection(_:)):
            return requestLineBoundarySelectionFromOwningBlock(.end)
        default:
            return false
        }
    }

    func handleHorizontalSelectionAdjustmentShortcut(_ event: NSEvent) -> Bool {
        guard let direction = event.horizontalSelectionAdjustmentDirection else {
            return false
        }
        return requestHorizontalSelectionAdjustmentFromOwningBlock(direction)
    }

    func handleLineBoundarySelectionShortcut(_ event: NSEvent) -> Bool {
        guard let direction = event.lineBoundarySelectionDirection else {
            return false
        }
        return requestLineBoundarySelectionFromOwningBlock(direction)
    }

    func handleLocalInlineLinkHorizontalSelectionCommand(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(moveLeftAndModifySelection(_:)),
             #selector(moveBackwardAndModifySelection(_:)):
            return modifySelectionAcrossInlineLinkSource(.leftward)
        case #selector(moveRightAndModifySelection(_:)),
             #selector(moveForwardAndModifySelection(_:)):
            return modifySelectionAcrossInlineLinkSource(.rightward)
        default:
            return false
        }
    }

    func handleLocalInlineLinkHorizontalSelectionShortcut(_ event: NSEvent) -> Bool {
        guard let direction = event.horizontalSelectionAdjustmentDirection else {
            return false
        }
        return modifySelectionAcrossInlineLinkSource(direction)
    }

    func requestHorizontalSelectionAdjustmentFromOwningBlock(_ direction: BlockInputHorizontalMovementDirection) -> Bool {
        let result = blockItem?.requestHorizontalSelectionAdjustment(direction) == true
        BlockInputSelectionDebug.emit(
            "text request horizontal direction=\(direction.debugName) range=\(selectedRange()) result=\(result)"
        )
        return result
    }

    func requestLineBoundarySelectionFromOwningBlock(_ direction: BlockInputLineBoundarySelectionDirection) -> Bool {
        let result = blockItem?.requestLineBoundarySelection(direction) == true
        BlockInputSelectionDebug.emit(
            "text request line boundary direction=\(direction.debugName) range=\(selectedRange()) result=\(result)"
        )
        return result
    }

    private func modifySelectionAcrossInlineLinkSource(_ direction: BlockInputHorizontalMovementDirection) -> Bool {
        guard blockItem?.supportsInlineMarkdownLinkRendering(for: self) == true else {
            return false
        }
        let previousRange = selectedRange()
        let activeOffset = previousRange.activeHorizontalSelectionOffset(for: direction)
        let navigation = inlineLinkNavigation()
        guard navigation.characterBoundaryNeedsCustomMovement(from: activeOffset, direction: direction),
              let targetOffset = navigation.characterBoundary(from: activeOffset, direction: direction) else {
            return false
        }
        let anchor = previousRange.horizontalSelectionAnchor(for: direction, navigation: navigation)
        let range = NSRange(location: min(anchor, targetOffset), length: abs(targetOffset - anchor))
        setSelectedRange(range)
        scrollRangeToVisible(range)
        blockItem?.updateSelectionDependentAttributesForCurrentSelection()
        return true
    }
}

private extension NSRange {
    func activeHorizontalSelectionOffset(for direction: BlockInputHorizontalMovementDirection) -> Int {
        switch direction {
        case .leftward:
            return location
        case .rightward:
            return NSMaxRange(self)
        }
    }

    func horizontalSelectionAnchor(
        for direction: BlockInputHorizontalMovementDirection,
        navigation: BlockInputInlineLinkNavigation
    ) -> Int {
        guard length == 0 else {
            switch direction {
            case .leftward:
                return NSMaxRange(self)
            case .rightward:
                return location
            }
        }
        return navigation.selectionAnchorOffset(from: location, direction: direction)
    }
}
