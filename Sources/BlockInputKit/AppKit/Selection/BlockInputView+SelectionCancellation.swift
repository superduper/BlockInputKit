import AppKit

extension BlockInputView {
    /// Cancels editor-owned multi-selection from keyboard-style commands.
    ///
    /// Mouse-down and reorder-start cancellation intentionally use the no-caret path below because AppKit still needs
    /// the original mouse event to place the caret or start the drag after this view clears selection chrome.
    func cancelMultiBlockSelection() -> Bool {
        switch selection {
        case let .blocks(blockIDs) where blockIDs.count > 1:
            return cancelSelection(to: cursorForSelectionCancellation(blockIDs: blockIDs))
        case let .mixed(mixedSelection):
            return cancelSelection(to: cursorForMixedSelectionCancellation(mixedSelection))
        case .blocks, .cursor, .text, nil:
            return false
        }
    }

    func cancelMultiBlockSelectionForMouseDown() -> Bool {
        clearMultiBlockSelectionWithoutCaret()
    }

    func cancelMultiBlockSelectionForReorderStart() -> Bool {
        clearMultiBlockSelectionWithoutCaret()
    }

    func collapseMultiBlockSelection(direction: BlockInputVerticalMovementDirection) -> Bool {
        let activeDirection = blockSelectionExpansion?.direction ?? direction
        switch selection {
        case let .blocks(blockIDs) where blockIDs.count > 1:
            return cancelSelection(to: cursorForCollapsedBlockSelection(blockIDs: blockIDs, direction: activeDirection))
        case let .mixed(mixedSelection):
            return cancelSelection(to: cursorForCollapsedMixedSelection(mixedSelection, direction: activeDirection))
        case .blocks, .cursor, .text, nil:
            return false
        }
    }

    private func clearMultiBlockSelectionWithoutCaret() -> Bool {
        switch selection {
        case let .blocks(blockIDs) where blockIDs.count > 1:
            applySelection(nil, notify: true)
            publishFocusChange(true)
            return true
        case .mixed:
            applySelection(nil, notify: true)
            publishFocusChange(true)
            return true
        case .blocks, .cursor, .text, nil:
            return false
        }
    }

    private func cancelSelection(to cursor: BlockInputCursor?) -> Bool {
        guard let cursor else {
            applySelection(nil, notify: true)
            window?.makeFirstResponder(self)
            return true
        }
        applySelection(.cursor(cursor), notify: true)
        focusVisibleItem(for: cursor)
        publishFocusChange(true)
        return true
    }

    private func cursorForSelectionCancellation(blockIDs: [BlockInputBlockID]) -> BlockInputCursor? {
        guard let blockID = blockIDs.first(where: { block(withID: $0)?.kind != .horizontalRule }) else {
            return nil
        }
        return BlockInputCursor(blockID: blockID, utf16Offset: 0)
    }

    private func cursorForMixedSelectionCancellation(_ selection: BlockInputMixedSelection) -> BlockInputCursor? {
        if let textRange = selection.leadingTextRange {
            return BlockInputCursor(blockID: textRange.blockID, utf16Offset: textRange.range.location)
        }
        if let textRange = selection.trailingTextRange {
            return BlockInputCursor(blockID: textRange.blockID, utf16Offset: textRange.range.location)
        }
        return cursorForSelectionCancellation(blockIDs: selection.blockIDs)
    }

    private func cursorForCollapsedBlockSelection(
        blockIDs: [BlockInputBlockID],
        direction: BlockInputVerticalMovementDirection
    ) -> BlockInputCursor? {
        let orderedIDs = blockIDs.sortedByDocumentOrder(in: self)
        switch direction {
        case .upward:
            return cursorAtStart(of: orderedIDs)
        case .downward:
            return cursorAtEnd(of: orderedIDs)
        }
    }

    private func cursorForCollapsedMixedSelection(
        _ selection: BlockInputMixedSelection,
        direction: BlockInputVerticalMovementDirection
    ) -> BlockInputCursor? {
        switch direction {
        case .upward:
            if let textRange = selection.leadingTextRange {
                return BlockInputCursor(blockID: textRange.blockID, utf16Offset: textRange.range.location)
            }
            return cursorAtStart(of: selection.blockIDs.sortedByDocumentOrder(in: self))
                ?? selection.trailingTextRange.map {
                    BlockInputCursor(blockID: $0.blockID, utf16Offset: $0.range.location)
                }
        case .downward:
            if let textRange = selection.trailingTextRange {
                return BlockInputCursor(blockID: textRange.blockID, utf16Offset: NSMaxRange(textRange.range))
            }
            return cursorAtEnd(of: selection.blockIDs.sortedByDocumentOrder(in: self))
                ?? selection.leadingTextRange.map {
                    BlockInputCursor(blockID: $0.blockID, utf16Offset: NSMaxRange($0.range))
                }
        }
    }

    private func cursorAtStart(of blockIDs: [BlockInputBlockID]) -> BlockInputCursor? {
        guard let blockID = blockIDs.first(where: { block(withID: $0)?.kind != .horizontalRule }) else {
            return nil
        }
        return BlockInputCursor(blockID: blockID, utf16Offset: 0)
    }

    private func cursorAtEnd(of blockIDs: [BlockInputBlockID]) -> BlockInputCursor? {
        guard let blockID = blockIDs.reversed().first(where: { block(withID: $0)?.kind != .horizontalRule }),
              let block = block(withID: blockID) else {
            return nil
        }
        return BlockInputCursor(blockID: blockID, utf16Offset: block.cursorUTF16Length)
    }
}

@MainActor
private extension Array where Element == BlockInputBlockID {
    func sortedByDocumentOrder(in view: BlockInputView) -> [BlockInputBlockID] {
        sorted { lhs, rhs in
            (view.index(of: lhs) ?? Int.max) < (view.index(of: rhs) ?? Int.max)
        }
    }
}
