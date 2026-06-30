import AppKit

extension BlockInputView {
    /// Handles Shift+Left/Right while preserving the illusion of one continuous Markdown document.
    ///
    /// `NSTextView` can adjust selections inside one block, but once the active edge crosses block chrome, this view
    /// owns the anchor/focus bookkeeping and rebuilds the canonical editor selection on each key press.
    func handleHorizontalSelectionAdjustmentKeyEvent(_ event: NSEvent) -> Bool {
        guard let direction = event.horizontalSelectionAdjustmentDirection else {
            return false
        }
        if tableKeyboardRowSelection != nil {
            return handleTableKeyboardRowSelection(direction)
        }
        if let textView = window?.firstResponder as? BlockInputTextView,
           textView.requestHorizontalSelectionAdjustmentFromOwningBlock(direction) {
            return true
        }
        return adjustSelectionHorizontally(direction)
    }

    func handleHorizontalSelectionAdjustmentCommand(_ selector: Selector) -> Bool {
        if tableKeyboardRowSelection != nil {
            switch selector {
            case #selector(moveLeftAndModifySelection(_:)),
                 #selector(moveBackwardAndModifySelection(_:)):
                return handleTableKeyboardRowSelection(.leftward)
            case #selector(moveRightAndModifySelection(_:)),
                 #selector(moveForwardAndModifySelection(_:)):
                return handleTableKeyboardRowSelection(.rightward)
            default:
                break
            }
        }
        switch selector {
        case #selector(moveLeftAndModifySelection(_:)),
             #selector(moveBackwardAndModifySelection(_:)):
            return adjustSelectionHorizontally(.leftward)
        case #selector(moveRightAndModifySelection(_:)),
             #selector(moveForwardAndModifySelection(_:)):
            return adjustSelectionHorizontally(.rightward)
        default:
            return false
        }
    }

    func adjustSelectionHorizontally(
        from blockID: BlockInputBlockID,
        selectedRange: NSRange,
        direction: BlockInputHorizontalMovementDirection
    ) -> Bool {
        if case .blocks = selection {
            return adjustSelectionHorizontally(direction)
        }
        if case .mixed = selection {
            return adjustSelectionHorizontally(direction)
        }
        guard let block = block(withID: blockID),
              block.kind != .horizontalRule else {
            return false
        }
        let clampedRange = selectedRange.clamped(to: block.utf16Length)
        if clampedRange.length == 0,
           startAdjacentTableRowSelectionHorizontally(
            from: blockID,
            block: block,
            offset: clampedRange.location,
            direction: direction
           ) {
            return true
        }
        if clampedRange.length == 0 {
            let anchorOffset: Int
            if let navigation = inlineLinkNavigation(for: block),
               navigation.characterBoundaryNeedsCustomMovement(from: clampedRange.location, direction: direction) {
                anchorOffset = navigation.selectionAnchorOffset(from: clampedRange.location, direction: direction)
            } else {
                anchorOffset = clampedRange.location
            }
            let anchor = BlockInputDocumentTextBoundary(blockID: blockID, utf16Offset: anchorOffset)
            return adjustSelectionHorizontally(from: anchor, direction: direction)
        }
        let start = BlockInputDocumentTextBoundary(blockID: blockID, utf16Offset: clampedRange.location)
        let end = BlockInputDocumentTextBoundary(blockID: blockID, utf16Offset: NSMaxRange(clampedRange))
        guard let seededSelection = selection(from: start, to: end) else {
            return false
        }
        applySelection(seededSelection, notify: false)
        return adjustSelectionHorizontally(direction)
    }

    func adjustSelectionHorizontally(_ direction: BlockInputHorizontalMovementDirection) -> Bool {
        // Editor-owned cursor selections bypass the text-view request path, so table edges must intercept before
        // generic document-boundary expansion can select the table's Markdown source.
        if case let .cursor(cursor) = selection,
           startAdjacentTableRowSelectionHorizontally(
            from: cursor.blockID,
            offset: cursor.utf16Offset,
            direction: direction
           ) {
            return true
        }
        guard let span = horizontalSelectionSpan(preferredDirection: direction),
              let nextActiveBoundary = horizontalBoundary(from: span.active, moving: direction),
              nextActiveBoundary != span.active,
              let adjustedSelection = selection(from: span.anchor, to: nextActiveBoundary) else {
            return false
        }
        if startAdjacentTableRowSelectionHorizontally(from: span, direction: direction) {
            return true
        }
        applyHorizontalSelection(adjustedSelection, anchor: span.anchor, active: nextActiveBoundary)
        scrollHorizontalSelectionBoundaryToVisible(nextActiveBoundary)
        return true
    }

    func expandHorizontalSelectionVerticallyIfNeeded(_ direction: BlockInputVerticalMovementDirection) -> Bool {
        guard horizontalSelectionExpansion != nil,
              let span = horizontalSelectionSpan(preferredDirection: .rightward),
              let activeIndex = index(of: span.active.blockID),
              let target = verticalBoundary(from: span.active, activeIndex: activeIndex, direction: direction),
              target != span.active,
              let adjustedSelection = selection(from: span.anchor, to: target) else {
            return false
        }
        applyHorizontalSelection(adjustedSelection, anchor: span.anchor, active: target)
        scrollBlockSelectionBoundaryToVisible(index(of: target.blockID) ?? activeIndex)
        return true
    }

    private func adjustSelectionHorizontally(
        from anchor: BlockInputDocumentTextBoundary,
        direction: BlockInputHorizontalMovementDirection
    ) -> Bool {
        if startAdjacentTableRowSelectionHorizontally(
            from: anchor.blockID,
            offset: anchor.utf16Offset,
            direction: direction
        ) {
            return true
        }
        guard let active = horizontalBoundary(from: anchor, moving: direction),
              let adjustedSelection = selection(from: anchor, to: active) else {
            return false
        }
        applyHorizontalSelection(adjustedSelection, anchor: anchor, active: active)
        scrollHorizontalSelectionBoundaryToVisible(active)
        return true
    }

    private func startAdjacentTableRowSelectionHorizontally(
        from span: (anchor: BlockInputDocumentTextBoundary, active: BlockInputDocumentTextBoundary),
        direction: BlockInputHorizontalMovementDirection
    ) -> Bool {
        guard let block = block(withID: span.active.blockID) else {
            return false
        }
        let outsideSelection = outsideTableSelection(anchor: span.anchor, active: span.active, direction: direction)
        return startAdjacentTableRowSelectionHorizontally(
            from: span.active.blockID,
            block: block,
            offset: span.active.utf16Offset,
            direction: direction,
            originCursor: BlockInputCursor(blockID: span.anchor.blockID, utf16Offset: span.anchor.utf16Offset),
            originSelection: outsideSelection == nil ? nil : selection,
            outsideTableSelection: outsideSelection
        )
    }

    private func outsideTableSelection(
        anchor: BlockInputDocumentTextBoundary,
        active: BlockInputDocumentTextBoundary,
        direction: BlockInputHorizontalMovementDirection
    ) -> BlockInputMixedSelection? {
        guard anchor.blockID == active.blockID,
              let block = block(withID: active.blockID) else {
            return nil
        }
        let start = min(anchor.utf16Offset, active.utf16Offset)
        let end = max(anchor.utf16Offset, active.utf16Offset)
        let clampedStart = min(max(start, 0), block.utf16Length)
        let clampedEnd = min(max(end, clampedStart), block.utf16Length)
        guard clampedEnd > clampedStart else {
            return nil
        }
        let textRange = BlockInputTextRange(
            blockID: active.blockID,
            range: NSRange(location: clampedStart, length: clampedEnd - clampedStart)
        )
        switch direction {
        case .leftward:
            return BlockInputMixedSelection(blockIDs: [], trailingTextRange: textRange)
        case .rightward:
            return BlockInputMixedSelection(blockIDs: [], leadingTextRange: textRange)
        }
    }

    private func verticalBoundary(
        from boundary: BlockInputDocumentTextBoundary,
        activeIndex: Int,
        direction: BlockInputVerticalMovementDirection
    ) -> BlockInputDocumentTextBoundary? {
        switch direction {
        case .upward:
            guard activeIndex > 0, let targetBlock = block(at: activeIndex - 1) else {
                return nil
            }
            let targetRange = partialTargetRange(
                for: targetBlock.id,
                at: activeIndex - 1,
                direction: direction,
                preferredTextContainerX: preferredNavigationX
            )
            let offset = targetRange?.range.location ?? 0
            return BlockInputDocumentTextBoundary(blockID: targetBlock.id, utf16Offset: offset)
        case .downward:
            guard activeIndex + 1 < blockCount, let targetBlock = block(at: activeIndex + 1) else {
                return nil
            }
            let targetRange = partialTargetRange(
                for: targetBlock.id,
                at: activeIndex + 1,
                direction: direction,
                preferredTextContainerX: preferredNavigationX
            )
            let offset = targetRange.map { NSMaxRange($0.range) } ?? targetBlock.utf16Length
            return BlockInputDocumentTextBoundary(blockID: targetBlock.id, utf16Offset: offset)
        }
    }

    func applyHorizontalSelection(
        _ selection: BlockInputSelection,
        anchor: BlockInputDocumentTextBoundary,
        active: BlockInputDocumentTextBoundary
    ) {
        applySelection(selection, notify: true)
        horizontalSelectionExpansion = selection.isCollapsed ? nil : BlockInputHorizontalSelectionExpansion(anchor: anchor, active: active)
        preferredNavigationX = textContainerX(for: active)
        blockSelectionExpansion = nil
        switch selection {
        case let .cursor(cursor):
            focusVisibleItem(for: cursor)
        case let .text(textRange):
            restoreVisibleTextSelection(textRange)
        case .blocks, .mixed:
            window?.makeFirstResponder(self)
            publishFocusChange(true)
        }
    }

    func textContainerX(for boundary: BlockInputDocumentTextBoundary) -> CGFloat? {
        guard let item = visibleItem(for: boundary.blockID, refreshConfiguration: false) else {
            return nil
        }
        return item.textContainerX(forUTF16Offset: boundary.utf16Offset)
    }

    func horizontalSelectionSpan(
        preferredDirection: BlockInputHorizontalMovementDirection
    ) -> (anchor: BlockInputDocumentTextBoundary, active: BlockInputDocumentTextBoundary)? {
        guard let selectedBounds = selectionBounds() else {
            return nil
        }
        // Keep the original fixed edge whenever Shift+Left/Right continues from an editor-owned selection. Without
        // this, opposite-direction movement would flip the anchor and expand instead of first contracting.
        if let expansion = horizontalSelectionExpansion {
            if let active = expansion.active {
                return (anchor: expansion.anchor, active: active)
            }
            if let span = anchoredHorizontalSelectionSpan(anchor: expansion.anchor, selectedBounds: selectedBounds) {
                return span
            }
        }
        if let expansion = blockSelectionExpansion {
            switch expansion.direction {
            case .upward:
                return (anchor: selectedBounds.end, active: selectedBounds.start)
            case .downward:
                return (anchor: selectedBounds.start, active: selectedBounds.end)
            }
        }
        switch preferredDirection {
        case .leftward:
            return (anchor: selectedBounds.end, active: selectedBounds.start)
        case .rightward:
            return (anchor: selectedBounds.start, active: selectedBounds.end)
        }
    }

    func selectionBounds() -> (start: BlockInputDocumentTextBoundary, end: BlockInputDocumentTextBoundary)? {
        switch selection {
        case let .cursor(cursor):
            let boundary = BlockInputDocumentTextBoundary(blockID: cursor.blockID, utf16Offset: cursor.utf16Offset)
            return (start: boundary, end: boundary)
        case let .text(textRange):
            return (
                start: BlockInputDocumentTextBoundary(blockID: textRange.blockID, utf16Offset: textRange.range.location),
                end: BlockInputDocumentTextBoundary(blockID: textRange.blockID, utf16Offset: NSMaxRange(textRange.range))
            )
        case let .blocks(blockIDs):
            return wholeBlockSelectionBounds(blockIDs)
        case let .mixed(selection):
            return mixedSelectionBounds(selection)
        case nil:
            return nil
        }
    }

    private func wholeBlockSelectionBounds(
        _ blockIDs: [BlockInputBlockID]
    ) -> (start: BlockInputDocumentTextBoundary, end: BlockInputDocumentTextBoundary)? {
        let indexes = blockIDs.compactMap { index(of: $0) }.sorted()
        guard let firstIndex = indexes.first,
              let lastIndex = indexes.last,
              let firstBlock = block(at: firstIndex),
              let lastBlock = block(at: lastIndex) else {
            return nil
        }
        return (
            start: BlockInputDocumentTextBoundary(blockID: firstBlock.id, utf16Offset: 0),
            end: BlockInputDocumentTextBoundary(blockID: lastBlock.id, utf16Offset: lastBlock.utf16Length)
        )
    }

    private func mixedSelectionBounds(
        _ selection: BlockInputMixedSelection
    ) -> (start: BlockInputDocumentTextBoundary, end: BlockInputDocumentTextBoundary)? {
        let sortedWholeIndexes = selection.blockIDs.compactMap { index(of: $0) }.sorted()
        let leadingIndex = selection.leadingTextRange.flatMap { index(of: $0.blockID) }
        let trailingIndex = selection.trailingTextRange.flatMap { index(of: $0.blockID) }
        let firstIndex = [leadingIndex, sortedWholeIndexes.first, trailingIndex].compactMap { $0 }.min()
        let lastIndex = [leadingIndex, sortedWholeIndexes.last, trailingIndex].compactMap { $0 }.max()
        guard let firstIndex, let lastIndex,
              let firstBlock = block(at: firstIndex),
              let lastBlock = block(at: lastIndex) else {
            return nil
        }
        if let singleBlockBounds = singleBlockMixedSelectionBounds(
            selection,
            firstBlock: firstBlock,
            firstIndex: firstIndex,
            lastIndex: lastIndex
        ) {
            return singleBlockBounds
        }
        let startOffset = selection.leadingTextRange?.blockID == firstBlock.id
            ? selection.leadingTextRange?.range.location ?? 0
            : 0
        let endOffset = selection.trailingTextRange?.blockID == lastBlock.id
            ? selection.trailingTextRange.map { NSMaxRange($0.range) } ?? lastBlock.utf16Length
            : lastBlock.utf16Length
        return (
            start: BlockInputDocumentTextBoundary(blockID: firstBlock.id, utf16Offset: startOffset),
            end: BlockInputDocumentTextBoundary(blockID: lastBlock.id, utf16Offset: endOffset)
        )
    }

    private func singleBlockMixedSelectionBounds(
        _ selection: BlockInputMixedSelection,
        firstBlock: BlockInputBlock,
        firstIndex: Int,
        lastIndex: Int
    ) -> (start: BlockInputDocumentTextBoundary, end: BlockInputDocumentTextBoundary)? {
        // A one-block editor-owned partial selection stores its exact range in `BlockInputMixedSelection`; do not widen
        // it to the whole block or the saved horizontal anchor will be lost before Shift+Up/Down can reuse its X.
        guard firstIndex == lastIndex,
              let textRange = [selection.leadingTextRange, selection.trailingTextRange]
            .compactMap({ $0 })
            .first(where: { $0.blockID == firstBlock.id }) else {
            return nil
        }
        return (
            start: BlockInputDocumentTextBoundary(blockID: firstBlock.id, utf16Offset: textRange.range.location),
            end: BlockInputDocumentTextBoundary(blockID: firstBlock.id, utf16Offset: NSMaxRange(textRange.range))
        )
    }

    private func horizontalBoundary(
        from boundary: BlockInputDocumentTextBoundary,
        moving direction: BlockInputHorizontalMovementDirection
    ) -> BlockInputDocumentTextBoundary? {
        switch direction {
        case .leftward:
            return boundaryBefore(boundary)
        case .rightward:
            return boundaryAfter(boundary)
        }
    }

    private func boundaryBefore(_ boundary: BlockInputDocumentTextBoundary) -> BlockInputDocumentTextBoundary? {
        guard let index = index(of: boundary.blockID),
              let block = block(at: index) else {
            return nil
        }
        let offset = min(max(boundary.utf16Offset, 0), block.utf16Length)
        if block.kind != .horizontalRule, offset > 0 {
            if let navigation = inlineLinkNavigation(for: block),
               navigation.characterBoundaryNeedsCustomMovement(from: offset, direction: .leftward),
               let sourceOffset = navigation.characterBoundary(from: offset, direction: .leftward) {
                return BlockInputDocumentTextBoundary(blockID: block.id, utf16Offset: sourceOffset)
            }
            return BlockInputDocumentTextBoundary(blockID: block.id, utf16Offset: offset - 1)
        }
        // Crossing left from a fully selected block lands on the previous block's final character, matching the
        // flattened-Markdown behavior the editor models.
        guard index > 0, let previousBlock = self.block(at: index - 1) else {
            return nil
        }
        let previousOffset = previousBlock.kind == .horizontalRule ? 0 : max(previousBlock.utf16Length - 1, 0)
        return BlockInputDocumentTextBoundary(blockID: previousBlock.id, utf16Offset: previousOffset)
    }

    private func boundaryAfter(_ boundary: BlockInputDocumentTextBoundary) -> BlockInputDocumentTextBoundary? {
        guard let index = index(of: boundary.blockID),
              let block = block(at: index) else {
            return nil
        }
        let offset = min(max(boundary.utf16Offset, 0), block.utf16Length)
        if block.kind != .horizontalRule, offset < block.utf16Length {
            if let navigation = inlineLinkNavigation(for: block),
               navigation.characterBoundaryNeedsCustomMovement(from: offset, direction: .rightward),
               let sourceOffset = navigation.characterBoundary(from: offset, direction: .rightward) {
                return BlockInputDocumentTextBoundary(blockID: block.id, utf16Offset: sourceOffset)
            }
            return BlockInputDocumentTextBoundary(
                blockID: block.id,
                utf16Offset: rightwardListLineBoundaryOffset(from: offset, in: block) ?? offset + 1
            )
        }
        // Crossing right from a fully selected block lands on the next block's first character.
        guard index + 1 < blockCount, let nextBlock = self.block(at: index + 1) else {
            return nil
        }
        let nextOffset = nextBlock.kind == .horizontalRule ? 0 : min(1, nextBlock.utf16Length)
        return BlockInputDocumentTextBoundary(blockID: nextBlock.id, utf16Offset: nextOffset)
    }

    private func rightwardListLineBoundaryOffset(from offset: Int, in block: BlockInputBlock) -> Int? {
        // Multi-line list blocks render each source line as a visible list item. Plain Shift+Right should not appear
        // stuck on the invisible newline between parent and nested list lines; include the next visible character too.
        guard block.usesIncrementalListLineSelection else {
            return nil
        }
        let text = block.text as NSString
        guard offset < text.length else {
            return nil
        }
        let character = text.character(at: offset)
        if character.isCarriageReturn,
           offset + 1 < text.length,
           text.character(at: offset + 1).isLineFeed {
            let nextLineStart = offset + 2
            return nextLineStart < text.length ? nextLineStart + 1 : nextLineStart
        }
        if character.isLineEnding {
            let nextLineStart = offset + 1
            return nextLineStart < text.length ? nextLineStart + 1 : nextLineStart
        }
        return nil
    }

    func scrollHorizontalSelectionBoundaryToVisible(_ boundary: BlockInputDocumentTextBoundary) {
        guard let index = index(of: boundary.blockID) else {
            return
        }
        collectionView.scrollToItems(at: [IndexPath(item: index, section: 0)], scrollPosition: .nearestVerticalEdge)
        collectionView.layoutSubtreeIfNeeded()
    }

    private func inlineLinkNavigation(for block: BlockInputBlock) -> BlockInputInlineLinkNavigation? {
        guard BlockInputBlockItem.supportsInlineMarkdownStyling(block.kind) else {
            return nil
        }
        return BlockInputInlineLinkNavigation(text: block.text, fileBaseURL: fileBaseURL)
    }
}

private extension BlockInputSelection {
    var isCollapsed: Bool {
        if case .cursor = self {
            return true
        }
        return false
    }
}

private extension NSRange {
    func clamped(to textLength: Int) -> NSRange {
        let location = min(max(location, 0), textLength)
        let length = min(max(length, 0), max(textLength - location, 0))
        return NSRange(location: location, length: length)
    }
}
