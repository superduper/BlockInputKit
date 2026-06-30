import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputVimSearchTests: XCTestCase {
    private func paragraphBlocks() -> [BlockInputBlock] {
        [
            BlockInputBlock(id: "a", kind: .paragraph, text: "foo alpha"),
            BlockInputBlock(id: "b", kind: .paragraph, text: "beta foo"),
            BlockInputBlock(id: "c", kind: .paragraph, text: "gamma foo delta")
        ]
    }

    // MARK: - Begin

    func testBeginVimSearchShowsLineWithSlash() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        XCTAssertFalse(view.isVimSearchLinePresented)

        view.beginVimSearch()

        XCTAssertTrue(view.isVimSearchLinePresented)
        let line = try XCTUnwrap(view.vimSearchLineForTesting)
        XCTAssertEqual(line.textForTesting, "/")
    }

    // MARK: - Live update

    func testUpdateVimSearchHighlightsLiveAndShowsQueryWithoutMovingCaret() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        // Seat a caret somewhere stable.
        XCTAssertTrue(view.setCursorOffset(0, in: "c"))
        let before = view.selection

        view.beginVimSearch()
        view.updateVimSearch("foo")

        // Live highlights are painted on a visible matched block.
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        XCTAssertFalse(item.findHighlightRangesForTesting.isEmpty)

        // Line shows the typed query.
        let line = try XCTUnwrap(view.vimSearchLineForTesting)
        XCTAssertEqual(line.textForTesting, "/foo")

        // Caret did NOT move while typing (incsearch is highlight-only).
        XCTAssertEqual(view.selection, before)

        // No scrim / zoom overlay installed on the vim path.
        XCTAssertNil(view.findScrimViewForTesting)
        XCTAssertNil(view.findActiveMatchOverlayForTesting)
    }

    // MARK: - Commit

    func testCommitVimSearchJumpsToFirstMatchAndShowsCount() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        view.beginVimSearch()
        view.updateVimSearch("foo")
        view.commitVimSearch()

        // Selection jumped to the first match's block.
        if case let .text(range) = try XCTUnwrap(view.selection) {
            XCTAssertEqual(range.blockID, "a")
        } else {
            XCTFail("expected a text selection on the first match")
        }

        let line = try XCTUnwrap(view.vimSearchLineForTesting)
        XCTAssertTrue(line.textForTesting.contains("foo"))
        XCTAssertTrue(line.textForTesting.contains("1/3"), "line was \(line.textForTesting)")
        XCTAssertTrue(view.isVimSearchLinePresented)
    }

    func testCommitEmptyQueryCancelsInsteadOfShowingNoMatches() throws {
        // Bare `/` then Return (no query typed) should just hide the line, not show "  no matches".
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        view.beginVimSearch()
        view.commitVimSearch()

        XCTAssertFalse(view.isVimSearchLinePresented, "committing an empty query hides the line")
        XCTAssertEqual(view.findMatchCount.total, 0)
    }

    // MARK: - Cancel / clear

    func testCancelVimSearchClearsHighlightsAndHidesLine() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        view.beginVimSearch()
        view.updateVimSearch("foo")
        view.commitVimSearch()

        view.cancelVimSearch()

        XCTAssertFalse(view.isVimSearchLinePresented)
        XCTAssertEqual(view.findMatchCount.total, 0)
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        XCTAssertTrue(item.findHighlightRangesForTesting.isEmpty)
    }

    func testClearVimSearchHighlightHidesLine() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        view.beginVimSearch()
        view.updateVimSearch("foo")
        view.commitVimSearch()

        view.clearVimSearchHighlight()

        XCTAssertFalse(view.isVimSearchLinePresented)
        XCTAssertEqual(view.findMatchCount.total, 0)
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        XCTAssertTrue(item.findHighlightRangesForTesting.isEmpty)
    }

    // MARK: - Navigation count refresh

    func testFindNextUpdatesVimLineCountWhenPresented() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        view.beginVimSearch()
        view.updateVimSearch("foo")
        view.commitVimSearch()

        XCTAssertTrue(view.findNext())

        let line = try XCTUnwrap(view.vimSearchLineForTesting)
        XCTAssertTrue(line.textForTesting.contains("2/3"), "line was \(line.textForTesting)")
    }

    // MARK: - Hit testing

    func testVimSearchLineDoesNotInterceptHitTesting() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        view.beginVimSearch()

        let line = try XCTUnwrap(view.vimSearchLineForTesting)
        XCTAssertNil(line.hitTest(NSPoint(x: line.bounds.midX, y: line.bounds.midY)))
    }
}
