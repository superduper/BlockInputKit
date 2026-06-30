import AppKit
import XCTest
@testable import BlockInputKit

/// The flow-layout crash with `NSScrollView.allowsMagnification` came from the collection view's bounds being
/// scaled. The layer-transform approach must NOT change the collection bounds, so the flow layout keeps
/// computing valid item sizes regardless of zoom.
@MainActor
final class BlockInputViewPinchZoomCrashTests: XCTestCase {
    private func mounted() -> BlockInputView {
        makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(kind: .heading(level: 1), text: "Title"),
                BlockInputBlock(id: "p", text: "A paragraph of body text that wraps across the column width."),
                BlockInputBlock(kind: .bulletedListItem, text: "A list item")
            ])
        )).view
    }

    func testLayerScaleDoesNotChangeCollectionBoundsOrItemSize() {
        let view = mounted()
        let boundsBefore = view.collectionView.bounds.width
        let sizeBefore = view.collectionView(
            view.collectionView,
            layout: view.collectionView.collectionViewLayout ?? NSCollectionViewFlowLayout(),
            sizeForItemAt: IndexPath(item: 0, section: 0)
        )

        // Apply the canvas zoom transform across the range.
        for scale in [1.5, 2.0, 3.0, 4.0] as [CGFloat] {
            view.collectionView.layer?.transform = CATransform3DMakeScale(scale, scale, 1)
            view.collectionView.layoutSubtreeIfNeeded()
        }

        // Bounds and item size are unchanged — the flow layout never sees scaled dimensions.
        XCTAssertEqual(view.collectionView.bounds.width, boundsBefore, accuracy: 0.5)
        let sizeAfter = view.collectionView(
            view.collectionView,
            layout: view.collectionView.collectionViewLayout ?? NSCollectionViewFlowLayout(),
            sizeForItemAt: IndexPath(item: 0, section: 0)
        )
        XCTAssertEqual(sizeAfter.width, sizeBefore.width, accuracy: 0.5)
        XCTAssertGreaterThan(sizeAfter.width, 0)
        XCTAssertLessThanOrEqual(sizeAfter.width, view.collectionView.bounds.width + 0.5)
    }
}
