import AppKit
import XCTest
@testable import BlockInputKit

/// Real-world scenario tests that simulate a full editing session.
///
/// Each test loads a rich document, performs a realistic sequence of operations
/// (navigate, hop over tables, enter/exit tables, insert, delete, shuffle blocks),
/// then diffs the resulting block AST AND Markdown against expected state.
///
/// "Block AST" = ordered list of (kind, text) pairs.
/// "Markdown" = document.markdown — the canonical serialization.
@MainActor
final class DemoVimRealWorldTests: XCTestCase {

    // MARK: - Document fixtures

    /// A realistic article-like document used as the starting point for most scenarios.
    ///
    /// Layout (index → kind, text):
    ///  0  heading(1) "Meeting Notes"
    ///  1  heading(2) "Attendees"
    ///  2  bulletedListItem "Alice"
    ///  3  bulletedListItem "Bob"
    ///  4  heading(2) "Action Items"
    ///  5  paragraph  "See the table below."
    ///  6  table      (empty cell grid)
    ///  7  heading(2) "Conclusions"
    ///  8  paragraph  "To be determined."
    private func makeArticleDocument() -> [BlockInputBlock] {
        [
            BlockInputBlock(id: .init(rawValue: "doc-title"),
                            kind: .heading(level: 1), text: "Meeting Notes"),
            BlockInputBlock(id: .init(rawValue: "sec-attendees"),
                            kind: .heading(level: 2), text: "Attendees"),
            BlockInputBlock(id: .init(rawValue: "list-alice"),
                            kind: .bulletedListItem, text: "Alice"),
            BlockInputBlock(id: .init(rawValue: "list-bob"),
                            kind: .bulletedListItem, text: "Bob"),
            BlockInputBlock(id: .init(rawValue: "sec-actions"),
                            kind: .heading(level: 2), text: "Action Items"),
            BlockInputBlock(id: .init(rawValue: "para-table-intro"),
                            text: "See the table below."),
            BlockInputBlock(id: .init(rawValue: "action-table"),
                            kind: .table, text: ""),
            BlockInputBlock(id: .init(rawValue: "sec-conclusions"),
                            kind: .heading(level: 2), text: "Conclusions"),
            BlockInputBlock(id: .init(rawValue: "para-tbd"),
                            text: "To be determined."),
        ]
    }

    // MARK: - Snapshot helpers

    private struct BlockSnapshot: Equatable, CustomStringConvertible {
        let kind: BlockInputBlockKind
        let text: String
        var description: String { "\(kind): \"\(text)\"" }
    }

    private func blockAST(_ view: BlockInputView) -> [BlockSnapshot] {
        view.document.blocks.map { BlockSnapshot(kind: $0.kind, text: $0.text) }
    }

    private func markdown(_ view: BlockInputView) -> String {
        view.document.markdown
    }

    // MARK: - Navigation: hop over table block without entering it

    func testJJHopsOverTableBlockWithoutEnteringItOrInsertingCharacters() throws {
        // Scenario: cursor starts in "Action Items" heading (index 4), presses j twice:
        //   j1: moves to paragraph "See the table below." (index 5)
        //   j2: from paragraph that precedes the table → should block-select the table
        // Then one more j: from block-selected table → skip to "Conclusions" heading
        // Result: cursor in "Conclusions", no characters inserted anywhere.
        let mounted = makeMountedBlockInputView(blocks: makeArticleDocument())
        let secActionsID = BlockInputBlockID(rawValue: "sec-actions")
        let tableID = BlockInputBlockID(rawValue: "action-table")
        let secConclusionsID = BlockInputBlockID(rawValue: "sec-conclusions")

        let astBefore = blockAST(mounted.view)
        let mdBefore = markdown(mounted.view)

        // j1: move down into the paragraph before the table
        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: secActionsID, utf16Offset: 0)))
        mounted.view.performCommand(.moveDown)

        // j2: paragraph → table is next → block-select table
        // (mirrors adapter's singleDown: moveAfterCurrentBlock + selectCurrentBlock)
        mounted.view.performCommand(.moveAfterCurrentBlock)
        mounted.view.performCommand(.selectCurrentBlock)
        XCTAssertEqual(mounted.view.selection, .blocks([tableID]),
                       "j from para-before-table must block-select the table, not enter it")

        // j3: block-selected table → skip to first block after table
        mounted.view.performCommand(.moveAfterCurrentBlock)
        if case let .cursor(cursor) = mounted.view.selection {
            XCTAssertEqual(cursor.blockID, secConclusionsID,
                           "j from block-selected table must land in Conclusions heading")
        } else {
            XCTFail("Expected cursor in Conclusions, got \(String(describing: mounted.view.selection))")
        }

        // Document must be completely unchanged
        XCTAssertEqual(blockAST(mounted.view), astBefore, "Block AST must not change on j/j/j navigation")
        XCTAssertEqual(markdown(mounted.view), mdBefore, "Markdown must not change on j/j/j navigation")
    }

    // MARK: - Click into table: selection enters a table cell

    func testSimulatedClickIntoTableEntersCursorInsideCell() throws {
        // Scenario: cursor is in a paragraph; user clicks into a table cell by setting
        // a cursor selection whose blockID is the table block.
        // Block AST and Markdown must not change; only selection changes.
        let mounted = makeMountedBlockInputView(blocks: makeArticleDocument())
        let tableID = BlockInputBlockID(rawValue: "action-table")
        let paraBefore = BlockInputBlockID(rawValue: "para-table-intro")

        let astBefore = blockAST(mounted.view)
        let mdBefore = markdown(mounted.view)

        // Simulate being outside the table
        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: paraBefore, utf16Offset: 0)))
        XCTAssertNotEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: tableID, utf16Offset: 0)))

        // Simulate click into the table (cursor placed inside it)
        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: tableID, utf16Offset: 0)))
        if case let .cursor(cursor) = mounted.view.selection {
            XCTAssertEqual(cursor.blockID, tableID, "selection must be inside the table block")
        }

        // Document content must be unchanged
        XCTAssertEqual(blockAST(mounted.view), astBefore, "clicking into table must not change Block AST")
        XCTAssertEqual(markdown(mounted.view), mdBefore, "clicking into table must not change Markdown")
    }

    // MARK: - Click out of table: Escape to block-select, then navigate away

    func testEscapeFromTableToBlockSelectionThenNavigateAway() throws {
        // Scenario: cursor is inside a table cell; user presses Escape (exits to normal mode
        // which block-selects the table), then presses j to skip past it.
        let mounted = makeMountedBlockInputView(blocks: makeArticleDocument())
        let tableID = BlockInputBlockID(rawValue: "action-table")
        let secConclusionsID = BlockInputBlockID(rawValue: "sec-conclusions")

        let astBefore = blockAST(mounted.view)

        // Simulate cursor inside table
        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: tableID, utf16Offset: 0)))

        // Escape in normal mode → selectCurrentBlock (simulates "exit table to block selection")
        mounted.view.performCommand(.selectCurrentBlock)
        XCTAssertEqual(mounted.view.selection, .blocks([tableID]),
                       "after Escape from table, table must be block-selected")

        // j from block-selected table → skip to next block
        mounted.view.performCommand(.moveAfterCurrentBlock)
        if case let .cursor(cursor) = mounted.view.selection {
            XCTAssertEqual(cursor.blockID, secConclusionsID, "j past table must land in Conclusions")
        }

        XCTAssertEqual(blockAST(mounted.view), astBefore, "Block AST must not change on table exit + j")
    }

    // MARK: - Insert new block below, then type content

    func testInsertBlockBelowAndVerifyMarkdown() throws {
        // Scenario: cursor in "Attendees" heading; insert "Charlie" bulletedListItem below it
        // using insertBlockBelowWithContent (what the vim adapter dispatches after typing in the
        // new block). "Charlie" must appear between "Attendees" and "Alice" in AST and Markdown.
        let mounted = makeMountedBlockInputView(blocks: makeArticleDocument())
        let secAttendeesID = BlockInputBlockID(rawValue: "sec-attendees")
        let charlieText = "Charlie"
        let insertedKind = BlockInputBlockKind.bulletedListItem

        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: secAttendeesID, utf16Offset: 0)))

        // o + content: insert structural block with kind and text
        mounted.view.performCommand(.insertBlockBelowWithContent(kind: insertedKind, text: charlieText))

        // AST check: "Charlie" bulletedListItem appears between "Attendees" and "Alice"
        let ast = blockAST(mounted.view)
        XCTAssertEqual(ast.count, makeArticleDocument().count + 1,
                       "document must have one more block after insert")
        let charlieIdx = ast.firstIndex { $0.text == charlieText }
        XCTAssertNotNil(charlieIdx, "Charlie must appear in block AST")
        if let idx = charlieIdx {
            XCTAssertEqual(ast[idx].kind, insertedKind, "inserted block must be a bulletedListItem")
            let aliceIdx = ast.firstIndex { $0.text == "Alice" } ?? Int.max
            XCTAssertLessThan(idx, aliceIdx, "Charlie must appear before Alice in the AST")
        }

        // Markdown check
        let md = markdown(mounted.view)
        XCTAssertTrue(md.contains(charlieText), "Markdown must include 'Charlie' after insert")
        XCTAssertTrue(md.contains("## Attendees"), "Attendees heading must still appear in Markdown")
        XCTAssertTrue(md.contains("Alice"), "Alice must still appear in Markdown")
    }

    // MARK: - Delete a heading and verify it's gone from AST and Markdown

    func testDDOnHeadingRemovesItFromASTAndMarkdown() throws {
        // Scenario: cursor in "Conclusions" heading (index 7); dd removes it.
        // "Conclusions" must disappear from both block AST and Markdown.
        let mounted = makeMountedBlockInputView(blocks: makeArticleDocument())
        let secConclusionsID = BlockInputBlockID(rawValue: "sec-conclusions")

        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: secConclusionsID, utf16Offset: 0)))

        mounted.view.performCommand(.deleteCurrentBlock)

        // AST check
        let ast = blockAST(mounted.view)
        XCTAssertEqual(ast.count, makeArticleDocument().count - 1, "block count must decrease by 1")
        XCTAssertFalse(ast.contains { $0.text == "Conclusions" },
                       "'Conclusions' must not appear in block AST after dd")

        // Markdown check
        XCTAssertFalse(markdown(mounted.view).contains("## Conclusions"),
                       "Markdown must not contain '## Conclusions' after dd")
        XCTAssertTrue(markdown(mounted.view).contains("To be determined."),
                      "Content after deleted heading must still appear in Markdown")
    }

    // MARK: - Shuffle: move a heading down past a table using dd + p

    func testDDHeadingAndPasteBelowTablePreservesKind() throws {
        // Scenario: dd on "Action Items" heading (index 4), then paste it below the table (index 6→7).
        // The pasted block must be a heading(level:2) with text "Action Items".
        let mounted = makeMountedBlockInputView(blocks: makeArticleDocument())
        let secActionsID = BlockInputBlockID(rawValue: "sec-actions")
        let secConclusionsID = BlockInputBlockID(rawValue: "sec-conclusions")

        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: secActionsID, utf16Offset: 0)))

        // dd: capture kind + text, cut block
        let capturedKind = BlockInputBlockKind.heading(level: 2)
        let capturedText = "Action Items"
        mounted.view.performCommand(.selectCurrentBlock)
        mounted.view.performCommand(.cut)

        XCTAssertFalse(blockAST(mounted.view).contains { $0.text == "Action Items" },
                       "Action Items must be removed from AST after dd")
        XCTAssertFalse(markdown(mounted.view).contains("## Action Items"),
                       "Action Items must be removed from Markdown after dd")

        // Navigate to Conclusions (now shifted up one position after deletion)
        let conclusionsBlock = mounted.view.document.blocks.first { $0.id == secConclusionsID }
        XCTAssertNotNil(conclusionsBlock, "Conclusions must still exist")
        if let block = conclusionsBlock {
            mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: block.id, utf16Offset: 0)))
        }

        // p: structural paste below Conclusions
        mounted.view.performCommand(.insertBlockBelowWithContent(kind: capturedKind, text: capturedText))

        // AST check
        let ast = blockAST(mounted.view)
        let pasted = ast.first { $0.text == capturedText }
        XCTAssertNotNil(pasted, "'Action Items' must reappear after structural paste")
        XCTAssertEqual(pasted?.kind, .heading(level: 2), "pasted block must be heading(level:2)")
        let conclusionsIdx = ast.firstIndex { $0.text == "Conclusions" } ?? Int.max
        let pastedIdx = ast.firstIndex { $0.text == capturedText } ?? -1
        XCTAssertGreaterThan(pastedIdx, conclusionsIdx, "pasted heading must appear after Conclusions")

        // Markdown check
        let md = markdown(mounted.view)
        XCTAssertTrue(md.contains("## \(capturedText)"), "Markdown must render '## Action Items'")
        XCTAssertTrue(md.contains("## Conclusions"), "Markdown must retain '## Conclusions'")
    }

    // MARK: - Full workflow: navigate, delete bullet, insert new bullet, verify Markdown

    func testFullEditWorkflowOnBulletedList() throws {
        // Scenario: navigate to "Bob" bullet, dd to remove it, insert "Carol" below "Alice".
        // Markdown before: "- Alice\n- Bob"
        // Markdown after: "- Alice\n- Carol"
        let mounted = makeMountedBlockInputView(blocks: makeArticleDocument())
        let listBobID = BlockInputBlockID(rawValue: "list-bob")
        let listAliceID = BlockInputBlockID(rawValue: "list-alice")
        let carolText = "Carol"

        let mdBefore = markdown(mounted.view)
        XCTAssertTrue(mdBefore.contains("Bob"), "Markdown must contain 'Bob' before edit")
        XCTAssertTrue(mdBefore.contains("Alice"), "Markdown must contain 'Alice' before edit")

        // dd Bob
        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: listBobID, utf16Offset: 0)))
        mounted.view.performCommand(.deleteCurrentBlock)
        XCTAssertFalse(markdown(mounted.view).contains("Bob"), "'Bob' must be gone after dd")

        // Navigate to Alice, insert Carol below
        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: listAliceID, utf16Offset: 0)))
        mounted.view.performCommand(.insertBlockBelowWithContent(kind: .bulletedListItem, text: carolText))

        // AST check
        let ast = blockAST(mounted.view)
        XCTAssertFalse(ast.contains { $0.text == "Bob" }, "Bob must not appear in block AST")
        let carolBlock = ast.first { $0.text == carolText }
        XCTAssertNotNil(carolBlock, "Carol must appear in block AST")
        XCTAssertEqual(carolBlock?.kind, .bulletedListItem, "Carol must be a bulletedListItem")

        // Markdown check
        let mdAfter = markdown(mounted.view)
        XCTAssertFalse(mdAfter.contains("Bob"), "Markdown must not contain 'Bob' after edit")
        XCTAssertTrue(mdAfter.contains(carolText), "Markdown must contain 'Carol' after insert")
        XCTAssertTrue(mdAfter.contains("Alice"), "Markdown must retain 'Alice'")
    }

    // MARK: - Table block-selected: dd removes table, surrounding blocks intact

    func testDDOnBlockSelectedTableRemovesTablePreservingNeighbors() throws {
        // Scenario: table is block-selected (arrived via vim j); dd removes it.
        // "Action Items" heading and "Conclusions" heading must remain intact.
        let mounted = makeMountedBlockInputView(blocks: makeArticleDocument())
        let tableID = BlockInputBlockID(rawValue: "action-table")

        mounted.view.applySelectionForTesting(.blocks([tableID]))

        mounted.view.performCommand(.deleteCurrentBlock)

        // AST check
        let ast = blockAST(mounted.view)
        XCTAssertEqual(ast.count, makeArticleDocument().count - 1, "block count must decrease by 1")
        XCTAssertFalse(ast.contains { $0.kind == .table }, "table must be removed from block AST")
        XCTAssertTrue(ast.contains { $0.text == "Action Items" }, "Action Items heading must survive")
        XCTAssertTrue(ast.contains { $0.text == "Conclusions" }, "Conclusions heading must survive")

        // Markdown check
        let md = markdown(mounted.view)
        XCTAssertTrue(md.contains("## Action Items"), "Markdown must retain '## Action Items'")
        XCTAssertTrue(md.contains("## Conclusions"), "Markdown must retain '## Conclusions'")
    }

    // MARK: - Undo after delete restores block AST and Markdown

    func testUndoAfterDeleteRestoresASTAndMarkdown() throws {
        // Scenario: dd on "Conclusions" heading, then u (undo). Both AST and Markdown must
        // be identical to the state before dd.
        let mounted = makeMountedBlockInputView(blocks: makeArticleDocument())
        let secConclusionsID = BlockInputBlockID(rawValue: "sec-conclusions")

        let astBefore = blockAST(mounted.view)
        let mdBefore = markdown(mounted.view)

        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: secConclusionsID, utf16Offset: 0)))
        mounted.view.performCommand(.deleteCurrentBlock)
        mounted.view.performCommand(.undo)

        XCTAssertEqual(blockAST(mounted.view), astBefore, "Block AST must be fully restored after undo")
        XCTAssertEqual(markdown(mounted.view), mdBefore, "Markdown must be fully restored after undo")
    }

    // MARK: - Mixed operations: navigate + insert + delete + verify final state

    func testMixedOperationsProduceCorrectASTAndMarkdown() throws {
        // Scenario: a realistic editing session on the article document:
        //  1. Navigate past the table (j/j over it)
        //  2. dd the "Conclusions" heading
        //  3. Insert "Summary" heading below "To be determined."
        //  4. Verify final AST and Markdown
        let mounted = makeMountedBlockInputView(blocks: makeArticleDocument())
        let tableID = BlockInputBlockID(rawValue: "action-table")
        let paraIntroID = BlockInputBlockID(rawValue: "para-table-intro")
        let secConclusionsID = BlockInputBlockID(rawValue: "sec-conclusions")
        let paraTBDID = BlockInputBlockID(rawValue: "para-tbd")

        let summaryText = "Summary"
        let summaryHeadingKind = BlockInputBlockKind.heading(level: 2)

        // Step 1: start in para-table-intro, hop over table (j → select table, j → skip past)
        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: paraIntroID, utf16Offset: 0)))
        mounted.view.performCommand(.moveAfterCurrentBlock)
        mounted.view.performCommand(.selectCurrentBlock)
        XCTAssertEqual(mounted.view.selection, .blocks([tableID]))
        mounted.view.performCommand(.moveAfterCurrentBlock)  // now in Conclusions
        if case let .cursor(cursor) = mounted.view.selection {
            XCTAssertEqual(cursor.blockID, secConclusionsID, "must land in Conclusions after hopping table")
        }

        // Step 2: dd Conclusions
        mounted.view.performCommand(.deleteCurrentBlock)
        XCTAssertFalse(blockAST(mounted.view).contains { $0.text == "Conclusions" })

        // Step 3: insert "Summary" heading below "To be determined."
        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: paraTBDID, utf16Offset: 0)))
        mounted.view.performCommand(.insertBlockBelowWithContent(kind: summaryHeadingKind, text: summaryText))

        // AST assertions
        let ast = blockAST(mounted.view)
        XCTAssertFalse(ast.contains { $0.text == "Conclusions" }, "Conclusions must be gone")
        let summaryBlock = ast.last { $0.text == summaryText }
        XCTAssertNotNil(summaryBlock, "Summary must be in block AST")
        XCTAssertEqual(summaryBlock?.kind, .heading(level: 2), "Summary must be heading(level:2)")

        // Markdown assertions
        let md = markdown(mounted.view)
        XCTAssertFalse(md.contains("## Conclusions"), "Markdown must not contain Conclusions")
        XCTAssertTrue(md.contains("## \(summaryText)"), "Markdown must contain '## Summary'")
        XCTAssertTrue(md.contains("# Meeting Notes"), "Title heading must be preserved in Markdown")
        XCTAssertTrue(md.contains("## Attendees"), "Attendees heading must be preserved in Markdown")
        XCTAssertTrue(md.contains("To be determined."), "TBD paragraph must be preserved in Markdown")
    }
}
