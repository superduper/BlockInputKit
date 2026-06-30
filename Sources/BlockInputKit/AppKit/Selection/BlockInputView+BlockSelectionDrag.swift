import AppKit

extension BlockInputView {
    func updateBlockSelectionDrag(
        from startBlockID: BlockInputBlockID,
        item: BlockInputBlockItem? = nil,
        with event: NSEvent,
        selectedRange: NSRange? = nil
    ) -> Bool {
        collectionView.autoscroll(with: event)
        collectionView.layoutSubtreeIfNeeded()
        guard let startIndex = index(of: startBlockID),
              let targetIndex = blockSelectionDragTargetIndex(forWindowLocation: event.locationInWindow),
              targetIndex != startIndex else {
            return false
        }
        let preferredTextContainerX = preferredTextContainerX(
            from: item,
            selectedRange: selectedRange,
            targetIsAfterStart: targetIndex > startIndex
        )
        let nextSelection = blockSelectionDragSelection(
            from: startBlockID,
            startIndex: startIndex,
            targetIndex: targetIndex,
            selectedRange: selectedRange,
            targetWindowLocation: event.locationInWindow
        )
        guard nextSelection?.isEmpty == false else {
            return false
        }
        hideDropIndicator()
        applySelection(nextSelection, notify: true)
        blockSelectionExpansion = BlockInputBlockSelectionExpansion(
            anchorBlockID: startBlockID,
            direction: targetIndex > startIndex ? .downward : .upward
        )
        preferredNavigationX = preferredTextContainerX
        if window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }
        collectionView.scrollToItems(at: [IndexPath(item: targetIndex, section: 0)], scrollPosition: .nearestVerticalEdge)
        publishFocusChange(true)
        return true
    }

    private func blockSelectionDragSelection(
        from startBlockID: BlockInputBlockID,
        startIndex: Int,
        targetIndex: Int,
        selectedRange: NSRange?,
        targetWindowLocation: NSPoint
    ) -> BlockInputSelection? {
        guard let selectedRange,
              let startBlock = block(withID: startBlockID),
              startBlock.kind != .horizontalRule,
              let edgeRange = startBlock.partialDragSelectionRange(selectedRange, targetIsAfterStart: targetIndex > startIndex) else {
            let bounds = min(startIndex, targetIndex)...max(startIndex, targetIndex)
            return .blocks(bounds.compactMap { block(at: $0)?.id })
        }

        if targetIndex > startIndex {
            let targetID = block(at: targetIndex)?.id
            let targetRange = targetID.flatMap {
                partialDragTargetRange(
                    for: $0,
                    at: targetIndex,
                    direction: .downward,
                    targetWindowLocation: targetWindowLocation
                )
            }
            let blockIDs: [BlockInputBlockID] = if targetRange == nil {
                (startIndex + 1...targetIndex).compactMap { block(at: $0)?.id }
            } else if startIndex + 1 < targetIndex {
                (startIndex + 1..<targetIndex).compactMap { block(at: $0)?.id }
            } else {
                []
            }
            return .mixed(BlockInputMixedSelection(blockIDs: blockIDs, leadingTextRange: BlockInputTextRange(
                blockID: startBlockID,
                range: edgeRange
            ), trailingTextRange: targetRange))
        }

        let targetID = block(at: targetIndex)?.id
        let targetRange = targetID.flatMap {
            partialDragTargetRange(
                for: $0,
                at: targetIndex,
                direction: .upward,
                targetWindowLocation: targetWindowLocation
            )
        }
        let blockIDs: [BlockInputBlockID] = if targetRange == nil {
            (targetIndex...startIndex - 1).compactMap { block(at: $0)?.id }
        } else if targetIndex + 1 < startIndex {
            (targetIndex + 1..<startIndex).compactMap { block(at: $0)?.id }
        } else {
            []
        }
        return .mixed(BlockInputMixedSelection(
            blockIDs: blockIDs,
            leadingTextRange: targetRange,
            trailingTextRange: BlockInputTextRange(blockID: startBlockID, range: edgeRange)
        ))
    }

    private func partialDragTargetRange(
        for blockID: BlockInputBlockID,
        at index: Int,
        direction: BlockInputVerticalMovementDirection,
        targetWindowLocation: NSPoint
    ) -> BlockInputTextRange? {
        // Mouse drags should select to the exact character under the pointer. The keyboard path intentionally uses a
        // stable caret X instead, so keep this separate to avoid reintroducing pointer-drag quantization.
        guard let block = block(at: index),
              block.id == blockID,
              block.kind != .horizontalRule,
              let targetItem = visibleItem(for: blockID) else {
            return nil
        }
        let offset = targetItem.utf16Offset(atWindowLocation: targetWindowLocation)
        let range: NSRange
        switch direction {
        case .upward:
            range = NSRange(location: offset, length: block.utf16Length - offset)
        case .downward:
            range = NSRange(location: 0, length: offset)
        }
        guard range.length > 0 else {
            return nil
        }
        return BlockInputTextRange(blockID: blockID, range: range)
    }

    private func preferredTextContainerX(
        from item: BlockInputBlockItem?,
        selectedRange: NSRange?,
        targetIsAfterStart: Bool
    ) -> CGFloat? {
        guard let item, let selectedRange else {
            return nil
        }
        let offset = targetIsAfterStart ? NSMaxRange(selectedRange) : selectedRange.location
        return item.textContainerX(forUTF16Offset: offset)
    }

    private func blockSelectionDragTargetIndex(forWindowLocation windowLocation: CGPoint) -> Int? {
        let location = collectionView.convert(windowLocation, from: nil)
        if let indexPath = collectionView.indexPathForItem(at: location),
           block(at: indexPath.item) != nil {
            return indexPath.item
        }

        // Resolve against visible layout attributes only so range selection stays bounded in large documents.
        let searchRect = collectionView.visibleRect.insetBy(dx: 0, dy: -80)
        let attributes = collectionView.collectionViewLayout?
            .layoutAttributesForElements(in: searchRect)
            .filter { $0.representedElementCategory == .item }
            .compactMap { attribute -> (item: Int, frame: NSRect)? in
                guard let item = attribute.indexPath?.item else {
                    return nil
                }
                return (item, attribute.frame)
            }
            .sorted { $0.frame.minY < $1.frame.minY } ?? []
        guard !attributes.isEmpty else {
            return nil
        }

        for attribute in attributes where location.y < attribute.frame.midY {
            return attribute.item
        }
        return attributes.last?.item
    }
}

private extension BlockInputSelection {
    var isEmpty: Bool {
        switch self {
        case let .blocks(blockIDs):
            return blockIDs.isEmpty
        case let .mixed(selection):
            return selection.blockIDs.isEmpty
                && selection.leadingTextRange == nil
                && selection.trailingTextRange == nil
        case .cursor, .text:
            return false
        }
    }
}

private extension BlockInputBlock {
    // A collapsed range is the mouse-down anchor captured while NSTextView's native selection remains collapsed. Expand it
    // toward the drag target so mouse drags and Shift+Arrow selection share the same mixed-selection endpoint model.
    func partialDragSelectionRange(_ range: NSRange, targetIsAfterStart: Bool) -> NSRange? {
        let textLength = utf16Length
        let location = min(max(range.location, 0), textLength)
        let length = min(max(range.length, 0), max(textLength - location, 0))
        if length == 0 {
            if targetIsAfterStart, location < textLength {
                return NSRange(location: location, length: textLength - location)
            }
            if !targetIsAfterStart, location > 0 {
                return NSRange(location: 0, length: location)
            }
            return nil
        }
        let clampedRange = NSRange(location: location, length: length)
        // Preserve full selections as text endpoints so mouse drags match Shift+Arrow: crossing into the next block
        // starts with a partial target instead of immediately selecting the whole target block.
        return clampedRange
    }
}
