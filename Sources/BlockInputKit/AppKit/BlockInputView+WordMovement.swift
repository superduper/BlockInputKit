import AppKit

extension BlockInputView {
    func handleWordSelectionAdjustmentShortcut(_ event: NSEvent) -> Bool {
        guard let direction = event.blockInputWordSelectionDirection else {
            return false
        }
        if let textView = window?.firstResponder as? BlockInputTextView {
            return textView.handleWordSelectionAdjustmentShortcut(event)
        }
        return adjustWordSelection(direction)
    }

    func handleWordSelectionAdjustmentCommand(_ selector: Selector) -> Bool {
        guard !(window?.firstResponder is BlockInputTextView) else {
            return false
        }
        switch selector {
        case #selector(NSResponder.moveWordLeftAndModifySelection(_:)),
             #selector(NSResponder.moveWordBackwardAndModifySelection(_:)):
            return adjustWordSelection(.leftward)
        case #selector(NSResponder.moveWordRightAndModifySelection(_:)),
             #selector(NSResponder.moveWordForwardAndModifySelection(_:)):
            return adjustWordSelection(.rightward)
        default:
            return false
        }
    }

    func handleWordMovementShortcut(_ event: NSEvent) -> Bool {
        guard let direction = event.blockInputWordMovementDirection else {
            return false
        }
        if window?.firstResponder is BlockInputTextView {
            return false
        }
        return moveWordFromCurrentSelection(direction)
    }

    func handleWordMovementCommand(_ selector: Selector) -> Bool {
        guard !(window?.firstResponder is BlockInputTextView) else {
            return false
        }
        switch selector {
        case #selector(NSResponder.moveWordLeft(_:)),
             #selector(NSResponder.moveWordBackward(_:)):
            return moveWordFromCurrentSelection(.leftward)
        case #selector(NSResponder.moveWordRight(_:)),
             #selector(NSResponder.moveWordForward(_:)):
            return moveWordFromCurrentSelection(.rightward)
        default:
            return false
        }
    }

    func moveWord(
        from blockID: BlockInputBlockID,
        selectedRange: NSRange,
        direction: BlockInputWordMovementDirection
    ) -> Bool {
        refreshDocumentFromStore()
        guard let index = index(of: blockID),
              let block = block(at: index),
              selectedRange.length == 0 else {
            return false
        }
        let offset = min(max(selectedRange.location, 0), block.utf16Length)
        switch direction {
        case .leftward:
            guard offset <= 0 else {
                return false
            }
        case .rightward:
            guard offset >= block.utf16Length else {
                return false
            }
        }
        return moveWordToAdjacentBlock(from: index, direction: direction)
    }

    func adjustWordSelection(
        from blockID: BlockInputBlockID,
        previousSelectedRange: NSRange,
        selectedRange: NSRange,
        direction: BlockInputWordMovementDirection
    ) -> Bool {
        refreshDocumentFromStore()
        guard let block = block(withID: blockID),
              block.kind != .horizontalRule else {
            return adjustWordSelection(direction)
        }
        let previousRange = previousSelectedRange.clampedWordSelectionRange(to: block.utf16Length)
        let currentRange = selectedRange.clampedWordSelectionRange(to: block.utf16Length)
        let nativeChangedSelection = !NSEqualRanges(previousRange, currentRange)
        syncNativeWordSelection(
            blockID: blockID,
            previousRange: previousRange,
            currentRange: currentRange,
            direction: direction,
            notify: nativeChangedSelection
        )
        guard !nativeChangedSelection else {
            return true
        }
        return adjustWordSelection(direction)
    }

    func adjustWordSelection(_ direction: BlockInputWordMovementDirection) -> Bool {
        let horizontalDirection = direction.horizontalMovementDirection
        guard let span = horizontalSelectionSpan(preferredDirection: horizontalDirection),
              let nextActiveBoundary = wordSelectionBoundary(from: span.active, moving: direction),
              nextActiveBoundary != span.active else {
            return false
        }
        let adjustedSelection = selection(from: span.anchor, to: nextActiveBoundary)
            ?? emptyCrossBlockWordSelection(anchor: span.anchor, active: nextActiveBoundary)
        guard let adjustedSelection else {
            return false
        }
        applyHorizontalSelection(adjustedSelection, anchor: span.anchor, active: nextActiveBoundary)
        scrollHorizontalSelectionBoundaryToVisible(nextActiveBoundary)
        return true
    }

    private func moveWordFromCurrentSelection(_ direction: BlockInputWordMovementDirection) -> Bool {
        refreshDocumentFromStore()
        guard let boundary = wordMovementBoundary(for: direction),
              let index = index(of: boundary.blockID),
              let block = block(at: index) else {
            return false
        }
        guard block.kind != .horizontalRule else {
            return moveWordToAdjacentBlock(from: index, direction: direction)
        }
        let offset = min(max(boundary.utf16Offset, 0), block.utf16Length)
        if canMoveWordWithinBlock(block, from: offset, direction: direction) {
            focusAndMoveWord(block: block, initialUTF16Offset: offset, direction: direction)
            return true
        }
        return moveWordToAdjacentBlock(from: index, direction: direction)
    }

    private func moveWordToAdjacentBlock(
        from index: Int,
        direction: BlockInputWordMovementDirection
    ) -> Bool {
        let targetIndex = direction == .leftward ? index - 1 : index + 1
        guard let targetBlock = block(at: targetIndex) else {
            return false
        }
        if targetBlock.kind == .horizontalRule {
            selectHorizontalRuleForWordMovement(targetBlock, at: targetIndex)
            return true
        }
        let offset = direction == .leftward ? targetBlock.utf16Length : 0
        focusAndMoveWord(block: targetBlock, initialUTF16Offset: offset, direction: direction)
        return true
    }

    private func canMoveWordWithinBlock(
        _ block: BlockInputBlock,
        from offset: Int,
        direction: BlockInputWordMovementDirection
    ) -> Bool {
        switch direction {
        case .leftward:
            return offset > 0
        case .rightward:
            return offset < block.utf16Length
        }
    }

    private func syncNativeWordSelection(
        blockID: BlockInputBlockID,
        previousRange: NSRange,
        currentRange: NSRange,
        direction: BlockInputWordMovementDirection,
        notify: Bool
    ) {
        let currentSelection: BlockInputSelection = currentRange.length == 0
            ? .cursor(BlockInputCursor(blockID: blockID, utf16Offset: currentRange.location))
            : .text(BlockInputTextRange(blockID: blockID, range: currentRange))
        applySelection(currentSelection, notify: notify && selection != currentSelection)
        guard currentRange.length > 0,
              let anchor = wordSelectionAnchor(
                blockID: blockID,
                previousRange: previousRange,
                currentRange: currentRange,
                direction: direction
              ) else {
            return
        }
        let active = wordSelectionActiveBoundary(
            blockID: blockID,
            anchor: anchor,
            currentRange: currentRange
        )
        horizontalSelectionExpansion = BlockInputHorizontalSelectionExpansion(anchor: anchor, active: active)
        preferredNavigationX = textContainerX(for: active)
        blockSelectionExpansion = nil
    }

    private func wordSelectionAnchor(
        blockID: BlockInputBlockID,
        previousRange: NSRange,
        currentRange: NSRange,
        direction: BlockInputWordMovementDirection
    ) -> BlockInputDocumentTextBoundary? {
        if previousRange.length == 0 {
            return BlockInputDocumentTextBoundary(blockID: blockID, utf16Offset: previousRange.location)
        }
        switch direction {
        case .leftward:
            if NSMaxRange(currentRange) == NSMaxRange(previousRange) {
                return BlockInputDocumentTextBoundary(blockID: blockID, utf16Offset: NSMaxRange(previousRange))
            }
            return BlockInputDocumentTextBoundary(blockID: blockID, utf16Offset: previousRange.location)
        case .rightward:
            if currentRange.location == previousRange.location {
                return BlockInputDocumentTextBoundary(blockID: blockID, utf16Offset: previousRange.location)
            }
            return BlockInputDocumentTextBoundary(blockID: blockID, utf16Offset: NSMaxRange(previousRange))
        }
    }

    private func wordSelectionActiveBoundary(
        blockID: BlockInputBlockID,
        anchor: BlockInputDocumentTextBoundary,
        currentRange: NSRange
    ) -> BlockInputDocumentTextBoundary {
        if anchor.utf16Offset == currentRange.location {
            return BlockInputDocumentTextBoundary(blockID: blockID, utf16Offset: NSMaxRange(currentRange))
        }
        return BlockInputDocumentTextBoundary(blockID: blockID, utf16Offset: currentRange.location)
    }

    private func wordSelectionBoundary(
        from boundary: BlockInputDocumentTextBoundary,
        moving direction: BlockInputWordMovementDirection
    ) -> BlockInputDocumentTextBoundary? {
        guard let index = index(of: boundary.blockID),
              let block = block(at: index) else {
            return nil
        }
        let offset = min(max(boundary.utf16Offset, 0), block.utf16Length)
        if block.kind != .horizontalRule,
           canMoveWordWithinBlock(block, from: offset, direction: direction) {
            return BlockInputDocumentTextBoundary(
                blockID: block.id,
                utf16Offset: wordSelectionOffset(in: block, from: offset, direction: direction)
            )
        }
        return wordSelectionBoundaryInAdjacentBlock(from: index, direction: direction)
    }

    private func wordSelectionBoundaryInAdjacentBlock(
        from index: Int,
        direction: BlockInputWordMovementDirection
    ) -> BlockInputDocumentTextBoundary? {
        let targetIndex = direction == .leftward ? index - 1 : index + 1
        guard let targetBlock = block(at: targetIndex) else {
            return nil
        }
        guard targetBlock.kind != .horizontalRule else {
            return BlockInputDocumentTextBoundary(blockID: targetBlock.id, utf16Offset: 0)
        }
        let initialOffset = direction == .leftward ? targetBlock.utf16Length : 0
        return BlockInputDocumentTextBoundary(
            blockID: targetBlock.id,
            utf16Offset: wordSelectionOffset(in: targetBlock, from: initialOffset, direction: direction)
        )
    }

    private func wordSelectionOffset(
        in block: BlockInputBlock,
        from offset: Int,
        direction: BlockInputWordMovementDirection
    ) -> Int {
        guard let item = visibleItem(for: block.id, refreshConfiguration: false) else {
            return offset
        }
        let selectedRange = item.focusAndMoveWord(initialUTF16Offset: offset, direction: direction)
        return min(max(selectedRange.location, 0), block.utf16Length)
    }

    private func emptyCrossBlockWordSelection(
        anchor: BlockInputDocumentTextBoundary,
        active: BlockInputDocumentTextBoundary
    ) -> BlockInputSelection? {
        guard wordSelectionBoundariesTouchAcrossAdjacentBlocks(anchor, active) else {
            return nil
        }
        guard let block = block(withID: anchor.blockID), block.kind != .horizontalRule else {
            return .blocks([anchor.blockID])
        }
        return .cursor(BlockInputCursor(
            blockID: anchor.blockID,
            utf16Offset: min(max(anchor.utf16Offset, 0), block.utf16Length)
        ))
    }

    private func wordSelectionBoundariesTouchAcrossAdjacentBlocks(
        _ lhs: BlockInputDocumentTextBoundary,
        _ rhs: BlockInputDocumentTextBoundary
    ) -> Bool {
        guard let lhsIndex = index(of: lhs.blockID),
              let rhsIndex = index(of: rhs.blockID),
              abs(lhsIndex - rhsIndex) == 1 else {
            return false
        }
        if lhsIndex < rhsIndex {
            return lhs.utf16Offset >= (block(at: lhsIndex)?.utf16Length ?? 0) && rhs.utf16Offset <= 0
        }
        return rhs.utf16Offset >= (block(at: rhsIndex)?.utf16Length ?? 0) && lhs.utf16Offset <= 0
    }

    private func focusAndMoveWord(
        block: BlockInputBlock,
        initialUTF16Offset offset: Int,
        direction: BlockInputWordMovementDirection
    ) {
        blockSelectionExpansion = nil
        horizontalSelectionExpansion = nil
        preferredNavigationX = nil
        guard let item = visibleItem(for: block.id) else {
            focus(blockID: block.id, utf16Offset: offset)
            return
        }
        let selectedRange = item.focusAndMoveWord(initialUTF16Offset: offset, direction: direction)
        applySelection(
            .cursor(BlockInputCursor(blockID: block.id, utf16Offset: selectedRange.location)),
            notify: true
        )
    }

    private func selectHorizontalRuleForWordMovement(_ block: BlockInputBlock, at index: Int) {
        selectedHorizontalRuleIndex = index
        blockSelectionExpansion = nil
        horizontalSelectionExpansion = nil
        preferredNavigationX = nil
        applySelection(.blocks([block.id]), notify: true)
        if let item = visibleItem(for: block.id, refreshConfiguration: false) {
            selectOnlyVisibleBlockItem(item)
        }
        window?.makeFirstResponder(self)
        publishFocusChange(true)
    }

    private func wordMovementBoundary(for direction: BlockInputWordMovementDirection) -> BlockInputDocumentTextBoundary? {
        switch selection {
        case let .cursor(cursor):
            return BlockInputDocumentTextBoundary(blockID: cursor.blockID, utf16Offset: cursor.utf16Offset)
        case let .text(textRange):
            let offset = direction == .leftward ? textRange.range.location : NSMaxRange(textRange.range)
            return BlockInputDocumentTextBoundary(blockID: textRange.blockID, utf16Offset: offset)
        case let .blocks(blockIDs):
            return wordMovementBoundary(forWholeBlockIDs: blockIDs, direction: direction)
        case let .mixed(selection):
            return wordMovementBoundary(forMixedSelection: selection, direction: direction)
        case nil:
            return nil
        }
    }

    private func wordMovementBoundary(
        forWholeBlockIDs blockIDs: [BlockInputBlockID],
        direction: BlockInputWordMovementDirection
    ) -> BlockInputDocumentTextBoundary? {
        let indexes = blockIDs.compactMap { index(of: $0) }.sorted()
        guard let boundaryIndex = direction == .leftward ? indexes.first : indexes.last,
              let block = block(at: boundaryIndex) else {
            return nil
        }
        let offset = direction == .leftward ? 0 : block.utf16Length
        return BlockInputDocumentTextBoundary(blockID: block.id, utf16Offset: offset)
    }

    private func wordMovementBoundary(
        forMixedSelection selection: BlockInputMixedSelection,
        direction: BlockInputWordMovementDirection
    ) -> BlockInputDocumentTextBoundary? {
        let candidates = mixedWordMovementBoundaryCandidates(selection)
        guard let boundary = direction == .leftward
            ? candidates.min(by: isEarlierWordMovementCandidate)
            : candidates.max(by: isEarlierWordMovementCandidate) else {
            return nil
        }
        return boundary.boundary
    }

    private func mixedWordMovementBoundaryCandidates(
        _ selection: BlockInputMixedSelection
    ) -> [(index: Int, boundary: BlockInputDocumentTextBoundary)] {
        var candidates: [(index: Int, boundary: BlockInputDocumentTextBoundary)] = []
        for blockID in selection.blockIDs {
            guard let index = index(of: blockID),
                  let block = block(at: index) else {
                continue
            }
            candidates.append((
                index,
                BlockInputDocumentTextBoundary(blockID: blockID, utf16Offset: 0)
            ))
            candidates.append((
                index,
                BlockInputDocumentTextBoundary(blockID: blockID, utf16Offset: block.utf16Length)
            ))
        }
        if let range = selection.leadingTextRange,
           let index = index(of: range.blockID) {
            candidates.append((
                index,
                BlockInputDocumentTextBoundary(blockID: range.blockID, utf16Offset: range.range.location)
            ))
            candidates.append((
                index,
                BlockInputDocumentTextBoundary(blockID: range.blockID, utf16Offset: NSMaxRange(range.range))
            ))
        }
        if let range = selection.trailingTextRange,
           let index = index(of: range.blockID) {
            candidates.append((
                index,
                BlockInputDocumentTextBoundary(blockID: range.blockID, utf16Offset: range.range.location)
            ))
            candidates.append((
                index,
                BlockInputDocumentTextBoundary(blockID: range.blockID, utf16Offset: NSMaxRange(range.range))
            ))
        }
        return candidates
    }

    private func isEarlierWordMovementCandidate(
        _ lhs: (index: Int, boundary: BlockInputDocumentTextBoundary),
        _ rhs: (index: Int, boundary: BlockInputDocumentTextBoundary)
    ) -> Bool {
        lhs.index < rhs.index ||
            (lhs.index == rhs.index && lhs.boundary.utf16Offset < rhs.boundary.utf16Offset)
    }

}

extension BlockInputWordMovementDirection {
    var horizontalMovementDirection: BlockInputHorizontalMovementDirection {
        switch self {
        case .leftward:
            return .leftward
        case .rightward:
            return .rightward
        }
    }

    var debugName: String {
        switch self {
        case .leftward:
            return "left"
        case .rightward:
            return "right"
        }
    }
}

private extension NSRange {
    func clampedWordSelectionRange(to textLength: Int) -> NSRange {
        let location = min(max(location, 0), textLength)
        let length = min(max(length, 0), max(textLength - location, 0))
        return NSRange(location: location, length: length)
    }
}
