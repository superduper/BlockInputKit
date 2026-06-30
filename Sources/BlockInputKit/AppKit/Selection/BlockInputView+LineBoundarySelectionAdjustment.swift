import AppKit

extension BlockInputView {
    func handleLineBoundarySelectionKeyEvent(_ event: NSEvent) -> Bool {
        guard let direction = event.lineBoundarySelectionDirection else {
            return false
        }
        if let textView = window?.firstResponder as? BlockInputTextView,
           textView.requestLineBoundarySelectionFromOwningBlock(direction) {
            return true
        }
        return adjustSelectionToLineBoundary(direction)
    }

    func handleLineBoundarySelectionCommand(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(moveToBeginningOfLineAndModifySelection(_:)),
             #selector(moveToLeftEndOfLineAndModifySelection(_:)):
            return adjustSelectionToLineBoundary(.beginning)
        case #selector(moveToEndOfLineAndModifySelection(_:)),
             #selector(moveToRightEndOfLineAndModifySelection(_:)):
            return adjustSelectionToLineBoundary(.end)
        default:
            return false
        }
    }

    func adjustSelectionToLineBoundary(
        from blockID: BlockInputBlockID,
        selectedRange: NSRange,
        direction: BlockInputLineBoundarySelectionDirection
    ) -> Bool {
        if case .blocks = selection {
            return adjustSelectionToLineBoundary(direction)
        }
        if case .mixed = selection {
            return adjustSelectionToLineBoundary(direction)
        }
        return false
    }

    func adjustSelectionToLineBoundary(_ direction: BlockInputLineBoundarySelectionDirection) -> Bool {
        guard let span = lineBoundarySelectionSpan(),
              let activeIndex = index(of: span.active.blockID),
              let activeBlock = block(at: activeIndex),
              activeBlock.kind != .horizontalRule,
              !activeBlock.kind.isImage else {
            return false
        }
        syncActiveMountedTextIfNeeded(for: span.active)
        guard let targetBoundary = lineBoundary(from: span.active, direction: direction),
              let adjustedSelection = selection(from: span.anchor, to: targetBoundary) else {
            return false
        }
        if targetBoundary == span.active {
            return true
        }
        applyHorizontalSelection(adjustedSelection, anchor: span.anchor, active: targetBoundary)
        scrollHorizontalSelectionBoundaryToVisible(targetBoundary)
        return true
    }

    private func lineBoundarySelectionSpan() -> (anchor: BlockInputDocumentTextBoundary, active: BlockInputDocumentTextBoundary)? {
        guard let selectedBounds = selectionBounds() else {
            return nil
        }
        if let span = horizontalLineBoundarySelectionSpan(selectedBounds: selectedBounds) {
            return span
        }
        if let span = blockLineBoundarySelectionSpan(selectedBounds: selectedBounds) {
            return span
        }
        guard canResolveLineBoundaryFromFocus else {
            return nil
        }
        return lastFocusedLineBoundarySelectionSpan(selectedBounds: selectedBounds)
    }

    private func horizontalLineBoundarySelectionSpan(
        selectedBounds: (start: BlockInputDocumentTextBoundary, end: BlockInputDocumentTextBoundary)
    ) -> (anchor: BlockInputDocumentTextBoundary, active: BlockInputDocumentTextBoundary)? {
        if let expansion = horizontalSelectionExpansion {
            if let active = expansion.active {
                return (anchor: expansion.anchor, active: active)
            }
            if let span = anchoredHorizontalSelectionSpan(anchor: expansion.anchor, selectedBounds: selectedBounds) {
                return span
            }
        }
        return nil
    }

    private func blockLineBoundarySelectionSpan(
        selectedBounds: (start: BlockInputDocumentTextBoundary, end: BlockInputDocumentTextBoundary)
    ) -> (anchor: BlockInputDocumentTextBoundary, active: BlockInputDocumentTextBoundary)? {
        guard let expansion = blockSelectionExpansion else {
            return nil
        }
        switch expansion.direction {
        case .upward:
            return (anchor: selectedBounds.end, active: selectedBounds.start)
        case .downward:
            return (anchor: selectedBounds.start, active: selectedBounds.end)
        }
    }

    private var canResolveLineBoundaryFromFocus: Bool {
        switch selection {
        case .blocks, .mixed:
            return true
        case .cursor, .text, nil:
            return false
        }
    }

    private func lastFocusedLineBoundarySelectionSpan(
        selectedBounds: (start: BlockInputDocumentTextBoundary, end: BlockInputDocumentTextBoundary)
    ) -> (anchor: BlockInputDocumentTextBoundary, active: BlockInputDocumentTextBoundary)? {
        guard let lastFocusedBlockID else {
            return nil
        }
        if selectedBounds.end.blockID == lastFocusedBlockID {
            return (anchor: selectedBounds.start, active: selectedBounds.end)
        }
        if selectedBounds.start.blockID == lastFocusedBlockID {
            return (anchor: selectedBounds.end, active: selectedBounds.start)
        }
        return nil
    }

    private func lineBoundary(
        from boundary: BlockInputDocumentTextBoundary,
        direction: BlockInputLineBoundarySelectionDirection
    ) -> BlockInputDocumentTextBoundary? {
        guard let block = block(withID: boundary.blockID),
              block.kind != .horizontalRule,
              !block.kind.isImage else {
            return nil
        }
        let offset = min(max(boundary.utf16Offset, 0), block.utf16Length)
        let targetOffset = visibleItem(for: boundary.blockID, refreshConfiguration: false)?
            .lineBoundaryUTF16Offset(containingUTF16Offset: offset, direction: direction)
            ?? block.text.sourceLineBoundaryOffset(containingUTF16Offset: offset, direction: direction)
        return BlockInputDocumentTextBoundary(
            blockID: boundary.blockID,
            utf16Offset: min(max(targetOffset, 0), block.utf16Length)
        )
    }

    private func syncActiveMountedTextIfNeeded(for boundary: BlockInputDocumentTextBoundary) {
        guard let textView = window?.firstResponder as? BlockInputTextView,
              let item = textView.blockItem,
              item.representedBlockID == boundary.blockID,
              let index = index(of: boundary.blockID),
              var block = block(at: index),
              block.kind != .horizontalRule else {
            return
        }
        let currentText = item.currentText
        guard currentText != block.text else {
            return
        }
        block.text = currentText
        _ = replaceCachedBlock(block, at: index)
        syncDocumentStore(.replaceBlock(block))
    }
}

private extension String {
    func sourceLineBoundaryOffset(
        containingUTF16Offset offset: Int,
        direction: BlockInputLineBoundarySelectionDirection
    ) -> Int {
        let text = self as NSString
        guard text.length > 0 else {
            return 0
        }
        let clampedOffset = min(max(offset, 0), text.length)
        var lineStart = 0
        var lineEnd = 0
        var contentsEnd = 0
        text.getLineStart(
            &lineStart,
            end: &lineEnd,
            contentsEnd: &contentsEnd,
            for: NSRange(location: clampedOffset, length: 0)
        )
        switch direction {
        case .beginning:
            return lineStart
        case .end:
            return contentsEnd
        }
    }
}
