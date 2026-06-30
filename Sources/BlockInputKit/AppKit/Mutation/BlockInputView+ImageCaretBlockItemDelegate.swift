import AppKit

extension BlockInputView {
    func blockItem(_ item: BlockInputBlockItem, blockID: BlockInputBlockID, didRequestImageCaretAt offset: Int) {
        refreshDocumentFromStore()
        let selectedIndex = collectionView.indexPath(for: item)?.item
        let selectedKind = selectedIndex.flatMap { block(at: $0)?.kind } ?? block(withID: blockID)?.kind
        guard selectedKind?.isImage == true else {
            return
        }
        selectedHorizontalRuleIndex = selectedIndex
        hideDropIndicator()
        blockSelectionExpansion = nil
        let clampedOffset = min(max(offset, 0), 1)
        applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: clampedOffset)), notify: true)
        item.setBlockSelection(false)
        item.setImageCaretOffset(clampedOffset)
        window?.makeFirstResponder(self)
        publishFocusChange(true)
    }

    func activeStandaloneBlockIndex(for blockID: BlockInputBlockID) -> Int? {
        if let selectedIndex = selectedHorizontalRuleIndex,
           block(at: selectedIndex)?.id == blockID,
           block(at: selectedIndex)?.kind.isSelectableStandaloneBlock == true {
            return selectedIndex
        }
        return index(of: blockID)
    }
}
