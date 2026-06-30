import AppKit
import XCTest
@testable import BlockInputKit

/// Tests for the find-bar refinements: the labeled "Replace" checkbox, Escape from the replace
/// field, clearing stale highlights when a matched block is edited, and scrolling an off-screen
/// match into view.
@MainActor
final class BlockInputFindBarFixesTests: XCTestCase {
    private func paragraphBlocks() -> [BlockInputBlock] {
        [
            BlockInputBlock(id: "a", kind: .paragraph, text: "foo alpha"),
            BlockInputBlock(id: "b", kind: .paragraph, text: "beta foo"),
            BlockInputBlock(id: "c", kind: .paragraph, text: "gamma foo delta")
        ]
    }

    private func commandFEvent() throws -> NSEvent {
        try keyEquivalentEvent(keyCode: 3, characters: "f", modifierFlags: .command)
    }

    // MARK: - Replace is gated by a labeled "Replace" checkbox

    func testReplaceToggleIsACheckboxLabeledReplace() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        XCTAssertTrue(view.performKeyEquivalent(with: try commandFEvent()))
        let bar = try XCTUnwrap(view.findBarViewForTesting)

        let checkbox = bar.replaceCheckboxForTesting
        XCTAssertEqual(checkbox.title, "Replace", "the replace toggle must be a labeled checkbox")
        XCTAssertEqual(checkbox.state, .off, "replace must be off (find-only) by default")
        XCTAssertFalse(bar.isReplaceExpandedForTesting)
        XCTAssertTrue(checkbox.isDescendant(of: bar))
    }

    // MARK: - Escape from the replace field closes the bar and removes the dim

    func testEscapeFromReplaceFieldClosesBarAndRemovesDim() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        view.presentFindBar(initialQuery: "foo")
        let bar = try XCTUnwrap(view.findBarViewForTesting)
        bar.toggleReplaceForTesting()
        XCTAssertNotNil(view.findScrimViewForTesting)
        XCTAssertTrue(mounted.window.makeFirstResponder(bar.replaceFieldForTesting))

        // Esc routed through the replace field's field editor.
        bar.simulateEscapeForTesting()

        XCTAssertFalse(view.isFindBarPresented, "Esc from the replace field must close the find bar")
        XCTAssertNil(view.findScrimViewForTesting, "closing the bar must remove the dim overlay")
        XCTAssertNil(view.findActiveMatchOverlayForTesting)
        XCTAssertEqual(view.findMatchCount.total, 0, "find state must be cleared on close")
    }

    func testReturnInReplaceFieldReplacesCurrentMatch() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        view.presentFindBar(initialQuery: "foo")
        let bar = try XCTUnwrap(view.findBarViewForTesting)
        bar.toggleReplaceForTesting()
        bar.setReplaceTextForTesting("BAR")
        XCTAssertTrue(mounted.window.makeFirstResponder(bar.replaceFieldForTesting))

        // Return in the replace field should Replace (not cycle matches).
        bar.simulateReplaceFieldReturnForTesting()

        XCTAssertEqual(view.document.block(withID: "a")?.text, "BAR alpha")
    }

    // MARK: - Editing a matched block clears its stale highlight

    func testEditingMatchedBlockClearsStaleHighlight() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        view.presentFindBar(initialQuery: "foo")
        view.layoutSubtreeIfNeeded()

        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        XCTAssertFalse(item.findHighlightRangesForTesting.isEmpty, "block 'a' starts highlighted for 'foo'")

        // Simulate the user editing block 'a' so it no longer contains "foo" (e.g. delete a letter).
        let textView = try XCTUnwrap(item.testingTextView)
        XCTAssertTrue(mounted.window.makeFirstResponder(textView))
        view.blockItem(item, blockID: "a", didChangeText: "fXo alpha", selectionBefore: nil)
        view.layoutSubtreeIfNeeded()

        let refreshedItem = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        XCTAssertTrue(
            refreshedItem.findHighlightRangesForTesting.isEmpty,
            "an edited-away match must lose its highlight"
        )
        XCTAssertEqual(view.findMatchCount.total, 2, "match count drops when a match is edited away")
    }

    // MARK: - Off-screen match scrolls into view

    func testFindScrollsOffScreenMatchIntoView() throws {
        // A tall document: the only match is far below the fold. Finding it must scroll the
        // document so its block becomes visible.
        var blocks: [BlockInputBlock] = (0..<60).map {
            BlockInputBlock(id: BlockInputBlockID(rawValue: "filler-\($0)"), kind: .paragraph, text: "filler line \($0)")
        }
        blocks.append(BlockInputBlock(id: "needle", kind: .paragraph, text: "the unique zzzneedle here"))
        let mounted = makeMountedBlockInputView(blocks: blocks)
        let view = mounted.view
        view.layoutSubtreeIfNeeded()

        // Precondition: the needle block is NOT visible initially.
        let visibleBefore = view.collectionView.visibleItems()
            .compactMap { ($0 as? BlockInputBlockItem)?.representedBlockID }
        XCTAssertFalse(visibleBefore.contains("needle"), "precondition: needle is below the fold")

        view.presentFindBar(initialQuery: "zzzneedle")
        view.layoutSubtreeIfNeeded()

        let visibleAfter = view.collectionView.visibleItems()
            .compactMap { ($0 as? BlockInputBlockItem)?.representedBlockID }
        XCTAssertTrue(visibleAfter.contains("needle"), "finding an off-screen match must scroll it into view")
        XCTAssertEqual(view.findMatchCount.total, 1)
    }
}
