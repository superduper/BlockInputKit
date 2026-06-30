import AppKit
import XCTest
@testable import BlockInputKit

/// Pan-when-zoomed: `panBy` only moves while zoomed, accumulates, and clamps to the extra content the scale
/// reveals so the canvas can't be dragged past its edges.
@MainActor
final class BlockInputCanvasPanTests: XCTestCase {
    private func mounted() -> BlockInputView {
        makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "p", text: "Body text for the canvas")])
        )).view
    }

    func testPanIsNoOpWhenNotZoomed() {
        let controller = mounted().pinchZoomController
        XCTAssertFalse(controller.isZoomed)
        XCTAssertFalse(controller.panByForTesting(deltaX: 50, deltaY: 50))
        XCTAssertEqual(controller.panOffset, .zero)
    }

    func testPanAccumulatesWhileZoomed() {
        let view = mounted()
        let controller = view.pinchZoomController
        setScale(controller, 2)
        XCTAssertTrue(controller.isZoomed)
        XCTAssertTrue(controller.panByForTesting(deltaX: 10, deltaY: -8))
        XCTAssertTrue(controller.panByForTesting(deltaX: 5, deltaY: -2))
        XCTAssertEqual(controller.panOffset.width, 15, accuracy: 0.5)
        XCTAssertEqual(controller.panOffset.height, -10, accuracy: 0.5)
    }

    func testPanClampsToContentEdges() {
        let view = mounted()
        let controller = view.pinchZoomController
        setScale(controller, 2)
        // Push far past any plausible edge; the offset must clamp to (bounds*(scale-1))/2.
        controller.panByForTesting(deltaX: 100_000, deltaY: 100_000)
        let maxX = view.collectionView.bounds.width * (2 - 1) / 2
        let maxY = view.collectionView.bounds.height * (2 - 1) / 2
        XCTAssertEqual(controller.panOffset.width, maxX, accuracy: 0.5)
        XCTAssertEqual(controller.panOffset.height, maxY, accuracy: 0.5)
    }

    func testResetClearsPan() {
        let view = mounted()
        let controller = view.pinchZoomController
        setScale(controller, 2)
        controller.panByForTesting(deltaX: 30, deltaY: 30)
        controller.reset()
        XCTAssertEqual(controller.panOffset, .zero)
        XCTAssertEqual(controller.scale, 1, accuracy: 0.0001)
        XCTAssertFalse(controller.isZoomed)
    }

    /// Drives the controller's scale via a magnification gesture stand-in (scale is private(set), so go
    /// through the public pan path after forcing a zoom with reset+pinch is not exposed; use KVC-free helper).
    private func setScale(_ controller: BlockInputPinchZoomController, _ scale: CGFloat) {
        controller.applyScaleForTesting(scale)
    }
}
