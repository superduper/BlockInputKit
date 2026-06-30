import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputFindActiveMatchTests: XCTestCase {
    private func paragraphBlocks() -> [BlockInputBlock] {
        [
            BlockInputBlock(id: "a", kind: .paragraph, text: "foo alpha"),
            BlockInputBlock(id: "b", kind: .paragraph, text: "beta foo"),
            BlockInputBlock(id: "c", kind: .paragraph, text: "gamma foo delta")
        ]
    }

    // MARK: - Presence / lifecycle

    func testActiveMatchOverlayPresentWhileFindActiveAbsentAfterClose() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        XCTAssertNil(view.findActiveMatchOverlayForTesting)

        view.presentFindBar(initialQuery: "foo")
        let overlay = try XCTUnwrap(view.findActiveMatchOverlayForTesting)
        XCTAssertTrue(overlay.isDescendant(of: view))
        XCTAssertTrue(overlay.wantsLayer)

        view.dismissFindBar()
        XCTAssertNil(view.findActiveMatchOverlayForTesting)
    }

    func testActiveMatchOverlayRemovedByEndFind() {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        view.presentFindBar(initialQuery: "foo")
        XCTAssertNotNil(view.findActiveMatchOverlayForTesting)

        view.endFind()
        XCTAssertNil(view.findActiveMatchOverlayForTesting)
    }

    // MARK: - Frame tracking

    func testActiveMatchOverlayFrameTracksActiveMatch() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        view.presentFindBar(initialQuery: "foo")
        view.layoutSubtreeIfNeeded()

        let overlay = try XCTUnwrap(view.findActiveMatchOverlayForTesting)
        XCTAssertGreaterThan(overlay.frame.width, 0)
        XCTAssertGreaterThan(overlay.frame.height, 0)

        let firstFrame = overlay.frame
        XCTAssertTrue(view.findNext())
        view.layoutSubtreeIfNeeded()
        let secondOverlay = try XCTUnwrap(view.findActiveMatchOverlayForTesting)
        XCTAssertGreaterThan(secondOverlay.frame.width, 0)
        XCTAssertGreaterThan(secondOverlay.frame.height, 0)
        XCTAssertNotEqual(secondOverlay.frame, firstFrame)
    }

    // MARK: - Pulse

    func testPulseTriggeredOnNavigation() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        view.presentFindBar(initialQuery: "foo")
        view.layoutSubtreeIfNeeded()

        let overlay = try XCTUnwrap(view.findActiveMatchOverlayForTesting)
        XCTAssertEqual(overlay.pulseCount, 1)

        XCTAssertTrue(view.findNext())
        XCTAssertEqual(overlay.pulseCount, 2)

        XCTAssertTrue(view.findPrevious())
        XCTAssertEqual(overlay.pulseCount, 3)

        // Scroll-driven reposition must NOT pulse.
        view.updateFindActiveMatchOverlay(animated: false)
        XCTAssertEqual(overlay.pulseCount, 3)
    }

    // MARK: - Hit testing

    func testActiveMatchOverlayDoesNotInterceptHitTesting() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        view.presentFindBar(initialQuery: "foo")

        let overlay = try XCTUnwrap(view.findActiveMatchOverlayForTesting)
        XCTAssertNil(overlay.hitTest(NSPoint(x: overlay.bounds.midX, y: overlay.bounds.midY)))
    }
}
