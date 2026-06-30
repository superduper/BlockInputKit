import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputCollectionViewFlowLayoutTests: XCTestCase {
    func testScrollOriginChangesDoNotInvalidateLayout() {
        let collectionView = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let layout = BlockInputCollectionViewFlowLayout()
        collectionView.collectionViewLayout = layout

        let shouldInvalidate = layout.shouldInvalidateLayout(
            forBoundsChange: NSRect(x: 0, y: 200, width: 400, height: 300)
        )

        XCTAssertFalse(shouldInvalidate)
    }

    func testWidthChangesInvalidateLayout() {
        let collectionView = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let layout = BlockInputCollectionViewFlowLayout()
        collectionView.collectionViewLayout = layout

        let shouldInvalidate = layout.shouldInvalidateLayout(
            forBoundsChange: NSRect(x: 0, y: 0, width: 500, height: 300)
        )

        XCTAssertTrue(shouldInvalidate)
    }
}
