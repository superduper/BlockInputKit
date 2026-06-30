import AppKit

/// Flow layout tuned for large block documents where scrolling must not trigger a full relayout.
final class BlockInputCollectionViewFlowLayout: NSCollectionViewFlowLayout {
    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        guard let oldBounds = collectionView?.bounds else {
            return super.shouldInvalidateLayout(forBoundsChange: newBounds)
        }
        return abs(oldBounds.width - newBounds.width) > 0.5
            || abs(oldBounds.height - newBounds.height) > 0.5
    }
}
