import AppKit

extension BlockInputView {
    func invalidateVisibleCursorRects() {
        guard let window else {
            collectionView.needsDisplay = true
            return
        }
        for view in [self, scrollView, scrollView.contentView, collectionView] {
            window.invalidateCursorRects(for: view)
        }
        for item in collectionView.visibleItems().compactMap({ $0 as? BlockInputBlockItem }) {
            item.invalidateCursorRects()
        }
    }
}
