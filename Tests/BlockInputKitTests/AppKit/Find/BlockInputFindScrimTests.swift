import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputFindScrimTests: XCTestCase {
    private func paragraphBlocks() -> [BlockInputBlock] {
        [
            BlockInputBlock(id: "a", kind: .paragraph, text: "foo alpha"),
            BlockInputBlock(id: "b", kind: .paragraph, text: "beta foo"),
            BlockInputBlock(id: "c", kind: .paragraph, text: "gamma foo delta")
        ]
    }

    // MARK: - Presence / lifecycle

    func testScrimPresentWhileFindActiveAbsentAfterClose() {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        XCTAssertNil(view.findScrimViewForTesting)

        view.presentFindBar(initialQuery: "foo")
        let scrim = view.findScrimViewForTesting
        XCTAssertNotNil(scrim)
        XCTAssertTrue(try XCTUnwrap(scrim).isDescendant(of: view))

        view.dismissFindBar()
        XCTAssertNil(view.findScrimViewForTesting)
    }

    func testScrimRemovedByEndFind() {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        view.presentFindBar(initialQuery: "foo")
        XCTAssertNotNil(view.findScrimViewForTesting)

        view.endFind()
        XCTAssertNil(view.findScrimViewForTesting)
    }

    // MARK: - Holes

    func testScrimHasHoleForVisibleMatch() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        view.presentFindBar(initialQuery: "foo")
        view.layoutSubtreeIfNeeded()

        let scrim = try XCTUnwrap(view.findScrimViewForTesting)
        let holes = scrim.holeRectsForTesting
        XCTAssertFalse(holes.isEmpty)
        XCTAssertTrue(holes.contains { $0.width > 0 && $0.height > 0 })
    }

    // MARK: - Hit testing

    func testScrimDoesNotInterceptHitTesting() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        view.presentFindBar(initialQuery: "foo")

        let scrim = try XCTUnwrap(view.findScrimViewForTesting)
        XCTAssertNil(scrim.hitTest(NSPoint(x: scrim.bounds.midX, y: scrim.bounds.midY)))
    }

    // MARK: - Navigation tracking

    func testScrimUpdatesOnNavigation() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        view.presentFindBar(initialQuery: "foo")
        view.layoutSubtreeIfNeeded()

        XCTAssertTrue(view.findNext())
        let scrim = try XCTUnwrap(view.findScrimViewForTesting)
        XCTAssertFalse(scrim.holeRectsForTesting.isEmpty)
    }

    // MARK: - Visibility (regression: scrim must not be hidden by editorChromeView)

    func testScrimIsActuallyVisibleWithNoEditorChrome() throws {
        // Regression: the scrim used to be a child of editorChromeView, which is `isHidden` when
        // the host configures no chrome surface (the demo's case), so the dim never appeared.
        // The scrim must be a direct child of the editor view and visible (no hidden ancestor).
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        view.presentFindBar(initialQuery: "foo")

        let scrim = try XCTUnwrap(view.findScrimViewForTesting)
        XCTAssertTrue(scrim.superview === view, "scrim must be a direct child of the editor view")
        XCTAssertFalse(scrim.isHidden, "scrim itself must be visible")
        // Walk ancestors up to the editor view: none may be hidden.
        var ancestor = scrim.superview
        while let current = ancestor, current !== view {
            XCTAssertFalse(current.isHidden, "no scrim ancestor may be hidden")
            ancestor = current.superview
        }
        XCTAssertFalse(view.isHidden)
        // The scrim covers the editor and sits below the find bar.
        XCTAssertEqual(scrim.bounds.size, view.bounds.size)
        if let bar = view.findBarViewForTesting,
           let scrimIndex = view.subviews.firstIndex(of: scrim),
           let barIndex = view.subviews.firstIndex(of: bar) {
            XCTAssertLessThan(scrimIndex, barIndex, "find bar must sit above the dim scrim")
        }
    }

    // MARK: - User interaction dismisses the dim but keeps highlights

    func testClickIntoBlockRemovesDimButKeepsHighlights() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        view.presentFindBar(initialQuery: "foo")
        view.layoutSubtreeIfNeeded()
        XCTAssertNotNil(view.findScrimViewForTesting)
        XCTAssertTrue(view.findControllerHasMatchesForTesting)

        // Simulate the user clicking/focusing into a block (begins editing).
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        view.blockItemDidBeginEditing(item, blockID: "a")

        // Dim and active-match overlay are gone...
        XCTAssertNil(view.findScrimViewForTesting, "clicking into a block must remove the dim scrim")
        XCTAssertNil(view.findActiveMatchOverlayForTesting, "clicking into a block must remove the active-match overlay")
        // ...but find state + highlights remain.
        XCTAssertTrue(view.findControllerHasMatchesForTesting, "matches must survive a click into the document")
        XCTAssertEqual(view.findMatchCount.total, 3, "highlighted matches must remain after the dim is dismissed")
    }
}
