import AppKit

extension BlockInputView {
    func applyPromotedSelection(
        _ selection: BlockInputSelection,
        anchorBlockID: BlockInputBlockID,
        direction: BlockInputVerticalMovementDirection,
        scrollIndex: Int,
        preferredTextContainerX: CGFloat? = nil
    ) -> Bool {
        applySelection(selection, notify: true)
        blockSelectionExpansion = BlockInputBlockSelectionExpansion(anchorBlockID: anchorBlockID, direction: direction)
        preferredNavigationX = preferredTextContainerX
        scrollBlockSelectionBoundaryToVisible(scrollIndex)
        window?.makeFirstResponder(self)
        publishFocusChange(true)
        return true
    }

    func scrollBlockSelectionBoundaryToVisible(_ index: Int) {
        guard index >= 0,
              index < blockCount else {
            return
        }
        collectionView.scrollToItems(at: [IndexPath(item: index, section: 0)], scrollPosition: .nearestVerticalEdge)
        collectionView.layoutSubtreeIfNeeded()
    }
}
