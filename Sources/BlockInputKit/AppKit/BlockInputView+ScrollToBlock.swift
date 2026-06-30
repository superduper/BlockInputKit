import AppKit

extension BlockInputView {
    /// Scrolls the document so the given block is centered in the viewport. Reuses the collection
    /// view's item scroll (works before lazy content height is realized). Returns `false` if the
    /// block is not present in the document.
    ///
    /// `animated` is reserved for future use; the underlying collection scroll is immediate today.
    @discardableResult
    public func scrollToBlock(_ id: BlockInputBlockID, animated: Bool = true) -> Bool {
        guard let index = index(of: id) else { return false }
        let indexPath = IndexPath(item: index, section: 0)
        guard indexPath.item < collectionView.numberOfItems(inSection: 0) else { return false }
        collectionView.scrollToItems(at: [indexPath], scrollPosition: .centeredVertically)
        collectionView.layoutSubtreeIfNeeded()
        return true
    }
}
