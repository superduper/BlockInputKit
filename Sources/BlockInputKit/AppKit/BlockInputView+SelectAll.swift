import AppKit

extension BlockInputView {
    func blockItemDidRequestSelectAll(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) {
        refreshDocumentFromStore()
        guard let block = block(withID: blockID) else {
            return
        }
        if item.currentText != block.text {
            configureBlockItem(item, block: block)
        }
        if collapseSelectAllForSingleEmptyDocument(blockID: blockID, item: item) {
            return
        }
        let nextSelection = tableAwareSelectAll(currentBlockID: blockID)
        applySelection(nextSelection, notify: true)
        if case let .text(range) = nextSelection,
           range.blockID == blockID {
            item.setSelectedRange(range.range)
        } else if case .blocks = nextSelection, window != nil {
            restoreVisibleSelection()
        }
    }

    func selectAllFromActiveSelection() -> Bool {
        refreshDocumentFromStore()
        if let blockID = activeBlockID,
           collapseSelectAllForSingleEmptyDocument(blockID: blockID) {
            return true
        }
        guard let blockID = activeBlockID,
              let nextSelection = tableAwareSelectAll(currentBlockID: blockID) else {
            return false
        }
        applySelection(nextSelection, notify: true)
        restoreVisibleSelection()
        return true
    }

    private func collapseSelectAllForSingleEmptyDocument(
        blockID: BlockInputBlockID,
        item: BlockInputBlockItem? = nil
    ) -> Bool {
        guard isSingleEmptyPlaceholderEligibleDocument,
              block(withID: blockID)?.isPlaceholderEligibleEmptyTextBlock == true else {
            return false
        }
        let cursor = BlockInputCursor(blockID: blockID, utf16Offset: 0)
        applySelection(.cursor(cursor), notify: true)
        if let item, item.representedBlockID == blockID {
            item.setSelectedRange(NSRange(location: 0, length: 0))
        } else {
            restoreVisibleSelection()
        }
        return true
    }

    private func tableAwareSelectAll(currentBlockID blockID: BlockInputBlockID) -> BlockInputSelection? {
        if selectAllBehavior == .document {
            let blockIDs = loadedBlockIDs
            return blockIDs.isEmpty ? nil : .blocks(blockIDs)
        }
        if block(withID: blockID)?.kind == .table,
           selection == .blocks([blockID]) {
            let allBlockIDs = loadedBlockIDs
            return .blocks(allBlockIDs)
        }
        return document.selectAll(
            currentBlockID: blockID,
            currentSelection: selection,
            behavior: selectAllBehavior
        )
    }
}
