import AppKit

extension BlockInputView {
    func handleImageCaretKeyDown(_ event: NSEvent) -> Bool {
        if handleSelectedImageHorizontalMovement(event) {
            return true
        }
        guard case let .cursor(cursor) = selection,
              block(withID: cursor.blockID)?.kind.isImage == true else {
            return false
        }
        if handleImageCaretMovement(event, cursor: cursor) {
            return true
        }
        if event.blockInputIsReturn {
            guard isEditable else {
                return false
            }
            if let selection = insertBlockBelowCurrentBlock() {
                scrollImageCaretReturnSelectionToVisible(selection)
                restoreVisibleSelection()
            }
            return true
        }
        if event.isBackspaceOrDelete {
            if cursor.utf16Offset <= 0 {
                return moveImageCaretToPreviousBlock(cursor)
            }
            return deleteImageBlockAtCaret(cursor) != nil
        }
        guard let text = event.blockInputInsertedText else {
            return false
        }
        guard isEditable else {
            return false
        }
        return insertTextAtImageCaret(text, cursor: cursor) != nil
    }

    func insertTextAtImageCaret(_ text: String, cursor: BlockInputCursor) -> BlockInputSelection? {
        guard isEditable,
              !text.isEmpty,
              let index = activeImageCaretIndex(for: cursor.blockID),
              block(at: index)?.kind.isImage == true else {
            return nil
        }
        let paragraph = BlockInputBlock(text: text)
        let insertionIndex = cursor.utf16Offset <= 0 ? index : index + 1
        return performStructuralEdit(
            named: "Insert Text",
            storeSyncAction: { _, _, _ in .insertBlocks([paragraph], insertionIndex: insertionIndex) },
            edit: { document in
                guard document.insertBlocks([paragraph], at: insertionIndex) != nil else {
                    return nil
                }
                return .cursor(BlockInputCursor(
                    blockID: paragraph.id,
                    utf16Offset: paragraph.utf16Length
                ))
            }
        )
    }

    func pasteTextAtImageCaretIfNeeded() -> Bool {
        guard isEditable,
              case let .cursor(cursor) = selection,
              block(withID: cursor.blockID)?.kind.isImage == true,
              let text = NSPasteboard.general.string(forType: .string),
              !text.isEmpty else {
            return false
        }
        return insertTextAtImageCaret(text, cursor: cursor) != nil
    }

    private func deleteImageBlockAtCaret(_ cursor: BlockInputCursor) -> BlockInputSelection? {
        guard isEditable else {
            return nil
        }
        refreshDocumentFromStore()
        guard let deletionIndex = activeImageCaretIndex(for: cursor.blockID),
              let deletedBlock = block(at: deletionIndex),
              deletedBlock.kind.isImage else {
            return nil
        }
        return performStructuralEdit(
            named: "Delete Block",
            storeSyncAction: { beforeDocument, afterDocument, _ in
                if beforeDocument.blocks.count == 1,
                   let replacementBlock = afterDocument.block(withID: deletedBlock.id) {
                    return .replaceBlock(replacementBlock)
                }
                if beforeDocument.blocks.filter({ $0.id == deletedBlock.id }).count == 1 {
                    return .deleteBlocks([deletedBlock.id])
                }
                return .replaceDocument
            },
            edit: { document in
                document.deleteBlock(at: deletionIndex)
            }
        )
    }

    private func handleSelectedImageHorizontalMovement(_ event: NSEvent) -> Bool {
        guard let direction = event.plainHorizontalMovementDirection,
              case let .blocks(blockIDs) = selection,
              blockIDs.count == 1,
              let blockID = blockIDs.first,
              block(withID: blockID)?.kind.isImage == true else {
            return false
        }
        let offset = direction == .leftward ? 0 : 1
        applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: offset)), notify: true)
        restoreVisibleSelection()
        window?.makeFirstResponder(self)
        publishFocusChange(true)
        return true
    }

    private func handleImageCaretMovement(_ event: NSEvent, cursor: BlockInputCursor) -> Bool {
        if let direction = event.plainHorizontalMovementDirection {
            let offset = direction == .leftward ? 0 : 1
            guard cursor.utf16Offset != offset else {
                return false
            }
            applySelection(.cursor(BlockInputCursor(blockID: cursor.blockID, utf16Offset: offset)), notify: true)
            restoreVisibleSelection()
            return true
        }
        guard let direction = event.plainVerticalMovementDirection else {
            return false
        }
        switch (direction, cursor.utf16Offset) {
        case (.upward, 1):
            applySelection(.cursor(BlockInputCursor(blockID: cursor.blockID, utf16Offset: 0)), notify: true)
            restoreVisibleSelection()
            return true
        case (.downward, 0):
            applySelection(.cursor(BlockInputCursor(blockID: cursor.blockID, utf16Offset: 1)), notify: true)
            restoreVisibleSelection()
            return true
        default:
            return moveVerticallyFromImageCaret(cursor, direction: direction)
        }
    }

    private func moveVerticallyFromImageCaret(
        _ cursor: BlockInputCursor,
        direction: BlockInputVerticalMovementDirection
    ) -> Bool {
        guard let index = activeImageCaretIndex(for: cursor.blockID) else {
            return false
        }
        let targetIndex = direction == .upward ? index - 1 : index + 1
        guard let targetBlock = block(at: targetIndex) else {
            return false
        }
        if targetBlock.kind == .horizontalRule {
            selectedHorizontalRuleIndex = targetIndex
            blockSelectionExpansion = nil
            applySelection(.blocks([targetBlock.id]), notify: true)
            if let targetItem = visibleItem(for: targetBlock.id, refreshConfiguration: false) {
                selectOnlyVisibleBlockItem(targetItem)
            }
            window?.makeFirstResponder(self)
            publishFocusChange(true)
            return true
        }
        if targetBlock.kind.isImage {
            let offset = direction == .upward ? 1 : 0
            selectedHorizontalRuleIndex = targetIndex
            applySelection(.cursor(BlockInputCursor(blockID: targetBlock.id, utf16Offset: offset)), notify: true)
            restoreVisibleSelection()
            publishFocusChange(true)
            return true
        }
        focus(blockID: targetBlock.id, utf16Offset: direction == .upward ? targetBlock.cursorUTF16Length : 0)
        return true
    }

    private func moveImageCaretToPreviousBlock(_ cursor: BlockInputCursor) -> Bool {
        guard let index = activeImageCaretIndex(for: cursor.blockID),
              index > 0,
              let previousBlock = block(at: index - 1) else {
            return false
        }
        if previousBlock.kind == .horizontalRule {
            selectedHorizontalRuleIndex = index - 1
            blockSelectionExpansion = nil
            applySelection(.blocks([previousBlock.id]), notify: true)
            if let previousItem = visibleItem(for: previousBlock.id, refreshConfiguration: false) {
                selectOnlyVisibleBlockItem(previousItem)
            }
            window?.makeFirstResponder(self)
            publishFocusChange(true)
            return true
        }
        if previousBlock.kind.isImage {
            selectedHorizontalRuleIndex = index - 1
            applySelection(
                .cursor(BlockInputCursor(blockID: previousBlock.id, utf16Offset: previousBlock.cursorUTF16Length)),
                notify: true
            )
            restoreVisibleSelection()
            publishFocusChange(true)
            return true
        }
        focus(blockID: previousBlock.id, utf16Offset: previousBlock.cursorUTF16Length)
        return true
    }

    private func activeImageCaretIndex(for blockID: BlockInputBlockID) -> Int? {
        if let selectedIndex = selectedHorizontalRuleIndex,
           block(at: selectedIndex)?.id == blockID,
           block(at: selectedIndex)?.kind.isImage == true {
            return selectedIndex
        }
        return index(of: blockID)
    }

    private func scrollImageCaretReturnSelectionToVisible(_ selection: BlockInputSelection) {
        guard case let .cursor(cursor) = selection,
              let index = index(of: cursor.blockID) else {
            return
        }
        let indexPath = IndexPath(item: index, section: 0)
        collectionView.layoutSubtreeIfNeeded()
        guard let frame = collectionView.collectionViewLayout?.layoutAttributesForItem(at: indexPath)?.frame else {
            collectionView.scrollToItems(at: [indexPath], scrollPosition: .nearestVerticalEdge)
            collectionView.layoutSubtreeIfNeeded()
            return
        }
        collectionView.scrollToVisible(frame)
        collectionView.layoutSubtreeIfNeeded()
    }
}

private extension NSEvent {
    var blockInputIsReturn: Bool {
        keyCode == 36 || keyCode == 76 || charactersIgnoringModifiers == "\r" || charactersIgnoringModifiers == "\n"
    }
}
