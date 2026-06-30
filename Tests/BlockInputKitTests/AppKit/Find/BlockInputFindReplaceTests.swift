import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputFindReplaceTests: XCTestCase {
    // MARK: - Fixtures

    private func paragraphBlocks() -> [BlockInputBlock] {
        [
            BlockInputBlock(id: "a", kind: .paragraph, text: "foo alpha"),
            BlockInputBlock(id: "b", kind: .paragraph, text: "beta foo"),
            BlockInputBlock(id: "c", kind: .paragraph, text: "gamma foo delta")
        ]
    }

    private func text(_ view: BlockInputView, _ id: BlockInputBlockID) -> String? {
        view.document.block(withID: id)?.text
    }

    private func tableBlock() -> BlockInputBlock {
        BlockInputBlock(
            id: "table",
            kind: .table,
            text: BlockInputTable.normalized(
                header: ["H1", "H2"],
                bodyRows: [["foo one", "two"]],
                alignments: [.left, .left]
            ).markdown
        )
    }

    // MARK: - 1. Replace current match replaces only the active occurrence and advances

    func testReplaceCurrentMatchReplacesOnlyActiveOccurrenceAndAdvances() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        view.beginFind(initialQuery: "foo")
        XCTAssertEqual(view.findMatchCount.current, 1)
        XCTAssertEqual(view.findMatchCount.total, 3)

        XCTAssertTrue(view.replaceCurrentMatch(with: "BAR"))

        XCTAssertEqual(text(view, "a"), "BAR alpha")
        XCTAssertEqual(text(view, "b"), "beta foo")
        XCTAssertEqual(text(view, "c"), "gamma foo delta")
        // Two matches remain; the active match advanced to the next occurrence.
        XCTAssertEqual(view.findMatchCount.total, 2)
        XCTAssertEqual(view.findController.activeMatch?.blockID, "b")
    }

    // MARK: - 2. Undo after replace reverts the single block text

    func testUndoAfterReplaceCurrentMatchRestoresText() throws {
        let undoController = BlockInputUndoController()
        let mounted = makeMountedBlockInputView(
            document: BlockInputDocument(blocks: paragraphBlocks()),
            undoController: undoController
        )
        let view = mounted.view
        view.beginFind(initialQuery: "foo")

        XCTAssertTrue(view.replaceCurrentMatch(with: "BAR"))
        XCTAssertEqual(text(view, "a"), "BAR alpha")

        view.blockInputUndo(nil)
        XCTAssertEqual(text(view, "a"), "foo alpha")
    }

    // MARK: - 3. Replace All across blocks reverts in a single undo

    func testReplaceAllAcrossBlocksRevertsInSingleUndo() throws {
        let undoController = BlockInputUndoController()
        let mounted = makeMountedBlockInputView(
            document: BlockInputDocument(blocks: paragraphBlocks()),
            undoController: undoController
        )
        let view = mounted.view
        view.beginFind(initialQuery: "foo")
        XCTAssertEqual(view.findMatchCount.total, 3)

        XCTAssertTrue(view.replaceAllMatches(with: "BAR"))

        XCTAssertEqual(text(view, "a"), "BAR alpha")
        XCTAssertEqual(text(view, "b"), "beta BAR")
        XCTAssertEqual(text(view, "c"), "gamma BAR delta")
        XCTAssertEqual(view.findMatchCount.total, 0)

        // A single undo reverts every block.
        view.blockInputUndo(nil)
        XCTAssertEqual(text(view, "a"), "foo alpha")
        XCTAssertEqual(text(view, "b"), "beta foo")
        XCTAssertEqual(text(view, "c"), "gamma foo delta")
    }

    // MARK: - 4. Replace within a table cell

    func testReplaceCurrentMatchInTableCellUpdatesMarkdown() throws {
        let mounted = makeMountedBlockInputView(blocks: [tableBlock()])
        let view = mounted.view
        view.beginFind(initialQuery: "foo")
        let match = try XCTUnwrap(view.findController.activeMatch)
        XCTAssertEqual(match.blockID, "table")

        XCTAssertTrue(view.replaceCurrentMatch(with: "BAR"))

        let expected = BlockInputTable.normalized(
            header: ["H1", "H2"],
            bodyRows: [["BAR one", "two"]],
            alignments: [.left, .left]
        ).markdown
        XCTAssertEqual(text(view, "table"), expected)
    }

    // MARK: - 5. Replace All with multiple matches in one block (descending order)

    func testReplaceAllMultipleMatchesInOneBlockUsesDescendingOrder() throws {
        let undoController = BlockInputUndoController()
        let mounted = makeMountedBlockInputView(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "a", kind: .paragraph, text: "foo foo foo")
            ]),
            undoController: undoController
        )
        let view = mounted.view
        view.beginFind(initialQuery: "foo")
        XCTAssertEqual(view.findMatchCount.total, 3)

        XCTAssertTrue(view.replaceAllMatches(with: "bar"))
        XCTAssertEqual(text(view, "a"), "bar bar bar")

        view.blockInputUndo(nil)
        XCTAssertEqual(text(view, "a"), "foo foo foo")
    }

    // MARK: - Replace is gated on findEnabled / no active match

    func testReplaceWithoutActiveMatchReturnsFalse() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        view.beginFind(initialQuery: "zzz-no-match")
        XCTAssertFalse(view.replaceCurrentMatch(with: "BAR"))
        XCTAssertFalse(view.replaceAllMatches(with: "BAR"))
    }
}
