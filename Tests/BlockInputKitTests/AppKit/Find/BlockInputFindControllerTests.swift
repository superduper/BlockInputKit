import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputFindControllerTests: XCTestCase {
    // MARK: - Fixtures

    private func paragraphDocumentBlocks() -> [BlockInputBlock] {
        [
            BlockInputBlock(id: "a", kind: .paragraph, text: "foo alpha"),
            BlockInputBlock(id: "b", kind: .paragraph, text: "beta foo"),
            BlockInputBlock(id: "c", kind: .paragraph, text: "gamma foo foo delta")
        ]
    }

    // MARK: - 1. beginFind + updateFindQuery selects first match

    func testUpdateFindQuerySelectsFirstMatchTextRange() {
        let mounted = makeMountedBlockInputView(blocks: paragraphDocumentBlocks())
        let view = mounted.view
        view.beginFind()
        view.updateFindQuery("foo")

        guard case let .text(range) = view.selection else {
            return XCTFail("Expected a text selection on the first match, got \(String(describing: view.selection))")
        }
        XCTAssertEqual(range.blockID, "a")
        XCTAssertEqual(range.range, NSRange(location: 0, length: 3))
        XCTAssertEqual(view.findMatchCount.current, 1)
        XCTAssertEqual(view.findMatchCount.total, 4)
    }

    // MARK: - 2. findNext advances and wraps

    func testFindNextAdvancesAndWraps() {
        let mounted = makeMountedBlockInputView(blocks: paragraphDocumentBlocks())
        let view = mounted.view
        view.beginFind(initialQuery: "foo")

        XCTAssertEqual(selectedBlockID(view), "a")

        XCTAssertTrue(view.findNext())
        XCTAssertEqual(selectedBlockID(view), "b")
        XCTAssertEqual(view.findMatchCount.current, 2)

        XCTAssertTrue(view.findNext())
        XCTAssertEqual(selectedBlockID(view), "c")
        XCTAssertEqual(view.findMatchCount.current, 3)

        XCTAssertTrue(view.findNext())
        XCTAssertEqual(selectedBlockID(view), "c")
        XCTAssertEqual(view.findMatchCount.current, 4)

        // Wrap from last back to first.
        XCTAssertTrue(view.findNext())
        XCTAssertEqual(selectedBlockID(view), "a")
        XCTAssertEqual(view.findMatchCount.current, 1)
    }

    // MARK: - 3. findPrevious from first wraps to last

    func testFindPreviousFromFirstWrapsToLast() {
        let mounted = makeMountedBlockInputView(blocks: paragraphDocumentBlocks())
        let view = mounted.view
        view.beginFind(initialQuery: "foo")
        XCTAssertEqual(view.findMatchCount.current, 1)

        XCTAssertTrue(view.findPrevious())
        XCTAssertEqual(view.findMatchCount.current, 4)
        XCTAssertEqual(selectedBlockID(view), "c")
    }

    // MARK: - 4. match count updates

    func testMatchCountUpdatesOnNavigation() {
        let mounted = makeMountedBlockInputView(blocks: paragraphDocumentBlocks())
        let view = mounted.view
        view.beginFind(initialQuery: "foo")
        XCTAssertEqual(view.findMatchCount.current, 1)
        XCTAssertEqual(view.findMatchCount.total, 4)
        view.findNext()
        XCTAssertEqual(view.findMatchCount.current, 2)
        view.findPrevious()
        XCTAssertEqual(view.findMatchCount.current, 1)
    }

    // MARK: - 5. no matches keeps selection + count (0,0)

    func testNoMatchesKeepsSelectionAndReportsZeroCount() {
        let mounted = makeMountedBlockInputView(blocks: paragraphDocumentBlocks())
        let view = mounted.view
        view.focus(blockID: "b", utf16Offset: 1)
        let selectionBefore = view.selection

        view.beginFind()
        view.updateFindQuery("zzz-not-present")

        XCTAssertEqual(view.selection, selectionBefore)
        XCTAssertEqual(view.findMatchCount.current, 0)
        XCTAssertEqual(view.findMatchCount.total, 0)
        XCTAssertFalse(view.findNext())
        XCTAssertFalse(view.findPrevious())
    }

    // MARK: - 6. endFind clears state

    func testEndFindClearsState() {
        let mounted = makeMountedBlockInputView(blocks: paragraphDocumentBlocks())
        let view = mounted.view
        view.beginFind(initialQuery: "foo")
        XCTAssertEqual(view.findMatchCount.total, 4)

        view.endFind()
        XCTAssertEqual(view.findMatchCount.current, 0)
        XCTAssertEqual(view.findMatchCount.total, 0)
        XCTAssertFalse(view.findNext())
    }

    // MARK: - 7. table match selects into the cell

    func testTableMatchSelectsIntoExpectedCell() throws {
        let table = BlockInputTable.normalized(
            header: ["Name", "Role"],
            bodyRows: [["Ada", "needle engineer"], ["Bob", "designer"]],
            alignments: [.left, .left]
        )
        let block = BlockInputBlock(id: "table", kind: .table, text: table.markdown)
        let mounted = makeMountedBlockInputView(blocks: [block])
        let view = mounted.view

        view.beginFind(initialQuery: "needle")

        guard case let .text(range) = view.selection else {
            return XCTFail("Expected a table text selection, got \(String(describing: view.selection))")
        }
        XCTAssertEqual(range.blockID, "table")

        let reconstructed = try XCTUnwrap(BlockInputTable(markdown: block.text))
        let position = try XCTUnwrap(reconstructed.cellPosition(containingSourceRange: range.range))
        XCTAssertEqual(position, BlockInputTable.CellPosition(row: .body(0), column: 1))
    }

    // MARK: - 8. active match carries temporary background highlight

    func testActiveMatchCarriesTemporaryBackgroundHighlight() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphDocumentBlocks())
        let view = mounted.view
        view.beginFind()
        view.updateFindQuery("foo")

        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        var effectiveRange = NSRange(location: 0, length: 0)
        let attribute = textView.layoutManager?.temporaryAttribute(
            .backgroundColor,
            atCharacterIndex: 0,
            effectiveRange: &effectiveRange
        )
        XCTAssertNotNil(attribute, "Active match should carry a temporary .backgroundColor attribute")
        XCTAssertEqual(effectiveRange, NSRange(location: 0, length: 3))
    }

    // MARK: - Helpers

    private func selectedBlockID(_ view: BlockInputView) -> BlockInputBlockID? {
        if case let .text(range) = view.selection {
            return range.blockID
        }
        return nil
    }
}
