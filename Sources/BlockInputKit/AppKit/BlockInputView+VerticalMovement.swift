import AppKit

extension BlockInputView {
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestVerticalMovement direction: BlockInputVerticalMovementDirection,
        preferredTextContainerX: CGFloat?
    ) -> Bool {
        moveVertically(from: blockID, direction: direction, preferredTextContainerX: preferredTextContainerX)
    }

    func moveSelectedBlockVertically(_ direction: BlockInputVerticalMovementDirection) -> Bool {
        guard case let .blocks(blockIDs) = selection,
              blockIDs.count == 1,
              let blockID = blockIDs.first else {
            return false
        }
        return moveVertically(from: blockID, direction: direction, preferredTextContainerX: nil)
    }

    func moveSelectedTableUpIfNeeded() -> Bool {
        guard case let .blocks(blockIDs) = selection,
              blockIDs.count == 1,
              let blockID = blockIDs.first else {
            return false
        }
        refreshDocumentFromStore()
        guard block(withID: blockID)?.kind == .table,
              let index = index(of: blockID) else {
            return false
        }
        guard index > 0 else {
            return true
        }
        let didMove = moveSelectedBlockVertically(.upward)
        if didMove {
            tableKeyboardRowSelection = nil
        }
        return didMove
    }

    func handleMoveUpCommand() -> Bool {
        collapseMultiBlockSelection(direction: .upward)
            || moveSelectedTableUpIfNeeded()
            || moveSelectedBlockVertically(.upward)
    }

    private func moveVertically(
        from blockID: BlockInputBlockID,
        direction: BlockInputVerticalMovementDirection,
        preferredTextContainerX: CGFloat?
    ) -> Bool {
        refreshDocumentFromStore()
        guard let index = index(of: blockID) else {
            return false
        }
        let targetIndex = direction == .upward ? index - 1 : index + 1
        guard let targetBlock = block(at: targetIndex) else {
            return false
        }
        let resolvedPreferredTextContainerX = preferredNavigationX ?? preferredTextContainerX
        if targetBlock.kind == .horizontalRule {
            selectedHorizontalRuleIndex = targetIndex
            blockSelectionExpansion = nil
            applySelection(.blocks([targetBlock.id]), notify: true)
            if let targetItem = visibleItem(for: targetBlock.id, refreshConfiguration: false) {
                selectOnlyVisibleBlockItem(targetItem)
            }
            window?.makeFirstResponder(self)
            preferredNavigationX = resolvedPreferredTextContainerX
            return true
        }
        if targetBlock.kind.isImage {
            selectedHorizontalRuleIndex = targetIndex
            blockSelectionExpansion = nil
            applySelection(
                .cursor(BlockInputCursor(
                    blockID: targetBlock.id,
                    utf16Offset: direction == .upward ? targetBlock.cursorUTF16Length : 0
                )),
                notify: true
            )
            restoreVisibleSelection()
            publishFocusChange(true)
            preferredNavigationX = resolvedPreferredTextContainerX
            return true
        }
        let targetItem = visibleItem(for: targetBlock.id)
        let linePosition: BlockInputBlockItem.TextLinePosition = direction == .upward ? .last : .first
        let offset = targetItem?.utf16Offset(
            closestToTextContainerX: resolvedPreferredTextContainerX,
            linePosition: linePosition
        ) ?? (direction == .upward ? targetBlock.utf16Length : 0)
        focus(blockID: targetBlock.id, utf16Offset: offset)
        preferredNavigationX = resolvedPreferredTextContainerX
        return true
    }
}
