import AppKit
import XCTest
@testable import BlockInputKit

/// Canvas pinch zoom is a layer-transform on the document content driven by a magnification gesture
/// recognizer (NOT scroll magnification, which crashes the flow layout). It is configured from
/// `BlockInputConfiguration`, scales the content layer, and never touches the font or document.
@MainActor
final class BlockInputViewPinchZoomTests: XCTestCase {
    private func mounted(_ configuration: BlockInputConfiguration) -> BlockInputView {
        makeMountedBlockInputView(configuration: configuration).view
    }

    private func paragraphConfig(
        pinchToZoomEnabled: Bool = true,
        min: CGFloat = 1,
        max: CGFloat = 4
    ) -> BlockInputConfiguration {
        BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "p", text: "Body")]),
            pinchToZoomEnabled: pinchToZoomEnabled,
            pinchZoomMinimum: min,
            pinchZoomMaximum: max
        )
    }

    func testPinchZoomEnabledByDefault() {
        let view = mounted(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "p", text: "Hi")])
        ))
        XCTAssertTrue(view.pinchZoomController.isEnabled)
        XCTAssertEqual(view.pinchZoomController.minimumScale, 1, accuracy: 0.0001)
        XCTAssertEqual(view.pinchZoomController.maximumScale, 4, accuracy: 0.0001)
    }

    func testCustomRangeApplied() {
        let view = mounted(paragraphConfig(min: 0.5, max: 6))
        XCTAssertEqual(view.pinchZoomController.minimumScale, 0.5, accuracy: 0.0001)
        XCTAssertEqual(view.pinchZoomController.maximumScale, 6, accuracy: 0.0001)
    }

    func testDisablingResetsScaleAndTransform() {
        let view = mounted(paragraphConfig())
        view.collectionView.layer?.transform = CATransform3DMakeScale(2, 2, 1)
        view.configure(paragraphConfig(pinchToZoomEnabled: false))
        XCTAssertFalse(view.pinchZoomController.isEnabled)
        XCTAssertEqual(view.pinchZoomController.scale, 1, accuracy: 0.0001)
        let transform = view.collectionView.layer?.transform ?? CATransform3DIdentity
        XCTAssertTrue(CATransform3DIsIdentity(transform))
    }

    func testRangeClampedToSaneBounds() {
        let config = BlockInputConfiguration(pinchZoomMinimum: 3, pinchZoomMaximum: 0.2)
        XCTAssertEqual(config.pinchZoomMinimum, 1, accuracy: 0.0001)
        XCTAssertEqual(config.pinchZoomMaximum, 1, accuracy: 0.0001)
    }

    func testResetRestoresIdentityTransform() {
        let view = mounted(paragraphConfig())
        view.collectionView.layer?.transform = CATransform3DMakeScale(2.5, 2.5, 1)
        view.pinchZoomController.reset()
        XCTAssertEqual(view.pinchZoomController.scale, 1, accuracy: 0.0001)
        let transform = view.collectionView.layer?.transform ?? CATransform3DIdentity
        XCTAssertTrue(CATransform3DIsIdentity(transform))
    }

    func testPinchZoomDoesNotChangeFontOrDocument() {
        let view = mounted(paragraphConfig())
        let fontBefore = view.visibleBlockItemForTesting(at: 0)?.textView.font
        view.collectionView.layer?.transform = CATransform3DMakeScale(2, 2, 1)
        let fontAfter = view.visibleBlockItemForTesting(at: 0)?.textView.font
        XCTAssertEqual(fontBefore?.pointSize, fontAfter?.pointSize)  // canvas zoom, not font zoom
        XCTAssertEqual(view.document.blocks.first?.text, "Body")
    }

    func testTighteningMaxScaleReclampsCurrentZoom() {
        let view = mounted(paragraphConfig(min: 1, max: 4))
        view.pinchZoomController.applyScaleForTesting(4)
        // Reconfiguring a tighter max while zoomed past it must pull the committed scale back into range.
        view.configure(paragraphConfig(min: 1, max: 2))
        XCTAssertEqual(view.pinchZoomController.scale, 2, accuracy: 0.0001)
    }

    func testDetachStopsControllerAndRemovesRecognizer() {
        let view = mounted(paragraphConfig())
        view.pinchZoomController.applyScaleForTesting(2)
        view.pinchZoomController.detach()
        // After detach the recognizer is removed and the controller is inert (no crash, scale frozen).
        XCTAssertTrue((view.gestureRecognizers).allSatisfy { !($0 is NSMagnificationGestureRecognizer) })
    }
}
