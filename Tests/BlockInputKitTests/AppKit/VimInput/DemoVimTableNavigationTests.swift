import AppKit
import XCTest
@testable import BlockInputKit

/// Scenario tests for vim normal-mode navigation that must NOT insert characters.
///
/// Each test snapshots document content before an operation and asserts it is
/// unchanged after — proving that normal-mode keys are consumed and not inserted.
/// Separate assertions verify the correct selection / cursor position.
@MainActor
final class DemoVimTableNavigationTests: XCTestCase {

    // MARK: - Helpers

    /// Full document text content, joined across blocks.
    private func documentText(_ view: BlockInputView) -> [String] {
        view.document.blocks.map(\.text)
    }

    // MARK: - j/k must not insert characters

    func testJInNormalModeDoesNotInsertCharacterIntoText() throws {
        // Scenario: user has two paragraphs; pressing vim `j` (moveDown) must move the
        // cursor without inserting a literal "j" into the first block.
        let id1 = BlockInputBlockID(rawValue: "b1")
        let id2 = BlockInputBlockID(rawValue: "b2")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: id1, text: "first line"),
            BlockInputBlock(id: id2, text: "second line")
        ])
        let item1 = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView1 = try XCTUnwrap(item1.testingTextView)
        mounted.window.makeFirstResponder(textView1)
        textView1.setSelectedRange(NSRange(location: 0, length: 0))

        let contentBefore = documentText(mounted.view)

        // Simulate vim `j` — adapter would call moveDown
        mounted.view.performCommand(.moveDown)

        let contentAfter = documentText(mounted.view)
        XCTAssertEqual(contentAfter, contentBefore, "Block content must not change on vim j")
    }

    func testKInNormalModeDoesNotInsertCharacterIntoText() throws {
        // Scenario: cursor on second block; vim `k` moves up, must not insert "k".
        let id1 = BlockInputBlockID(rawValue: "b1")
        let id2 = BlockInputBlockID(rawValue: "b2")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: id1, text: "first line"),
            BlockInputBlock(id: id2, text: "second line")
        ])
        let item2 = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView2 = try XCTUnwrap(item2.testingTextView)
        mounted.window.makeFirstResponder(textView2)
        textView2.setSelectedRange(NSRange(location: 0, length: 0))

        let contentBefore = documentText(mounted.view)

        mounted.view.performCommand(.moveUp)

        XCTAssertEqual(documentText(mounted.view), contentBefore, "Block content must not change on vim k")
    }

    func testLInNormalModeDoesNotInsertCharacterIntoText() throws {
        // Scenario: vim `l` (moveRight) must not insert "l".
        let blockID = BlockInputBlockID(rawValue: "b1")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "hello")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        let contentBefore = documentText(mounted.view)

        mounted.view.performCommand(.moveRight)

        XCTAssertEqual(documentText(mounted.view), contentBefore, "Block content must not change on vim l")
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 1)))
    }

    // MARK: - j/k skipping a table block

    func testJFromParagraphAboveTableBlockSelectsTable() throws {
        // Scenario: document is [paragraph, table, paragraph].
        // vim `j` from paragraph[0] must block-select the table — content unchanged.
        let id1 = BlockInputBlockID(rawValue: "b1")
        let tableID = BlockInputBlockID(rawValue: "t1")
        let id3 = BlockInputBlockID(rawValue: "b3")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: id1, text: "above"),
            BlockInputBlock(id: tableID, kind: .table, text: ""),
            BlockInputBlock(id: id3, text: "below")
        ])
        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: id1, utf16Offset: 0)))

        let contentBefore = documentText(mounted.view)

        // adapter singleDown(): next block is table → moveAfterCurrentBlock + selectCurrentBlock
        mounted.view.performCommand(.moveAfterCurrentBlock)
        mounted.view.performCommand(.selectCurrentBlock)

        XCTAssertEqual(documentText(mounted.view), contentBefore, "j toward table must not insert characters")
        XCTAssertEqual(mounted.view.selection, .blocks([tableID]), "table must be block-selected, not entered")
    }

    func testJFromBlockSelectedTableSkipsPastToNextParagraph() throws {
        // Scenario: table is already block-selected (user pressed j once to get here).
        // vim `j` again must move cursor to block after table — content unchanged.
        let tableID = BlockInputBlockID(rawValue: "t1")
        let id3 = BlockInputBlockID(rawValue: "b3")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: BlockInputBlockID(rawValue: "b1"), text: "above"),
            BlockInputBlock(id: tableID, kind: .table, text: ""),
            BlockInputBlock(id: id3, text: "below")
        ])
        // Simulate state after first j: table is block-selected
        mounted.view.applySelectionForTesting(.blocks([tableID]))

        let contentBefore = documentText(mounted.view)

        // adapter singleDown(): current block is table → moveAfterCurrentBlock
        mounted.view.performCommand(.moveAfterCurrentBlock)

        XCTAssertEqual(documentText(mounted.view), contentBefore, "j from block-selected table must not insert characters")
        if case let .cursor(cursor) = mounted.view.selection {
            XCTAssertEqual(cursor.blockID, id3, "cursor must land in block after table")
            XCTAssertEqual(cursor.utf16Offset, 0)
        } else {
            XCTFail("Expected cursor in paragraph after table, got \(String(describing: mounted.view.selection))")
        }
    }

    func testKFromParagraphBelowTableBlockSelectsTable() throws {
        // Scenario: cursor in paragraph[2] (below table). vim `k` must block-select the table.
        let tableID = BlockInputBlockID(rawValue: "t1")
        let id3 = BlockInputBlockID(rawValue: "b3")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: BlockInputBlockID(rawValue: "b1"), text: "above"),
            BlockInputBlock(id: tableID, kind: .table, text: ""),
            BlockInputBlock(id: id3, text: "below")
        ])
        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: id3, utf16Offset: 0)))

        let contentBefore = documentText(mounted.view)

        // adapter singleUp(): previous block is table → moveBeforeCurrentBlock + selectCurrentBlock
        mounted.view.performCommand(.moveBeforeCurrentBlock)
        mounted.view.performCommand(.selectCurrentBlock)

        XCTAssertEqual(documentText(mounted.view), contentBefore, "k toward table must not insert characters")
        XCTAssertEqual(mounted.view.selection, .blocks([tableID]))
    }

    func testKFromBlockSelectedTableSkipsPastToPreviousParagraph() throws {
        // Scenario: table is block-selected. vim `k` must land cursor in block before table.
        let id1 = BlockInputBlockID(rawValue: "b1")
        let tableID = BlockInputBlockID(rawValue: "t1")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: id1, text: "above"),
            BlockInputBlock(id: tableID, kind: .table, text: ""),
            BlockInputBlock(id: BlockInputBlockID(rawValue: "b3"), text: "below")
        ])
        mounted.view.applySelectionForTesting(.blocks([tableID]))

        let contentBefore = documentText(mounted.view)

        // adapter singleUp(): current block is table → moveBeforeCurrentBlock
        mounted.view.performCommand(.moveBeforeCurrentBlock)

        XCTAssertEqual(documentText(mounted.view), contentBefore, "k from block-selected table must not insert characters")
        if case let .cursor(cursor) = mounted.view.selection {
            XCTAssertEqual(cursor.blockID, id1, "cursor must land in block before table")
        } else {
            XCTFail("Expected cursor before table, got \(String(describing: mounted.view.selection))")
        }
    }

    // MARK: - Paste after table navigation (real use-case)

    func testPasteAfterNavigatingPastTable() throws {
        // Scenario: user yanks "hello" from block 0, navigates j/j past a table, pastes into block 2.
        // Content diff: block[2] gains pasted text; nothing else changes.
        let id1 = BlockInputBlockID(rawValue: "b1")
        let tableID = BlockInputBlockID(rawValue: "t1")
        let id3 = BlockInputBlockID(rawValue: "b3")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: id1, text: "hello"),
            BlockInputBlock(id: tableID, kind: .table, text: ""),
            BlockInputBlock(id: id3, text: "")
        ])
        // Step 1: select block 0 and copy its content
        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: id1, utf16Offset: 0)))
        let item1 = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let tv1 = try XCTUnwrap(item1.testingTextView)
        mounted.window.makeFirstResponder(tv1)
        tv1.setSelectedRange(NSRange(location: 0, length: 5))
        mounted.view.performCommand(.copy)

        // Step 2: move to block after table (two j presses in adapter)
        //   j1: moveAfterCurrentBlock → on table; selectCurrentBlock → .blocks([tableID])
        mounted.view.performCommand(.moveAfterCurrentBlock)
        mounted.view.performCommand(.selectCurrentBlock)
        XCTAssertEqual(mounted.view.selection, .blocks([tableID]))
        //   j2: moveAfterCurrentBlock → cursor at id3
        mounted.view.performCommand(.moveAfterCurrentBlock)

        let contentBeforePaste = documentText(mounted.view)

        // Step 3: paste
        let item3 = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        let tv3 = try XCTUnwrap(item3.testingTextView)
        mounted.window.makeFirstResponder(tv3)
        mounted.view.performCommand(.paste)

        let contentAfterPaste = documentText(mounted.view)

        // Blocks 0 and 1 (table) must be unchanged
        XCTAssertEqual(contentAfterPaste[0], contentBeforePaste[0], "block 0 must not change after paste")
        XCTAssertEqual(contentAfterPaste[1], contentBeforePaste[1], "table block must not change after paste")
        // Block 2 must now contain pasted text
        XCTAssertFalse(contentAfterPaste[2].isEmpty, "pasted block should contain text")
        XCTAssertTrue(contentAfterPaste[2].contains("hello"), "pasted block should contain yanked content")
    }

    func testDeleteTableBlockWithDD() throws {
        // Scenario: table is block-selected (by vim j); user presses vim `dd`.
        // The adapter dispatches deleteCurrentBlock when selection is already .blocks.
        // Content diff: table block disappears, surrounding blocks unchanged.
        let id1 = BlockInputBlockID(rawValue: "b1")
        let tableID = BlockInputBlockID(rawValue: "t1")
        let id3 = BlockInputBlockID(rawValue: "b3")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: id1, text: "above"),
            BlockInputBlock(id: tableID, kind: .table, text: ""),
            BlockInputBlock(id: id3, text: "below")
        ])
        mounted.view.applySelectionForTesting(.blocks([tableID]))

        // dd on a block-selected table → deleteCurrentBlock (adapter chooses this for .blocks selection)
        mounted.view.performCommand(.deleteCurrentBlock)

        XCTAssertEqual(mounted.view.document.blocks.count, 2, "table block must be removed")
        XCTAssertEqual(mounted.view.document.blocks[0].text, "above")
        XCTAssertEqual(mounted.view.document.blocks[1].text, "below")
    }

    func testFullJJDDWorkflow() throws {
        // Scenario: start at paragraph 0, j to select table, j to skip to paragraph 1,
        // then dd to delete that paragraph. Verifies the full navigation + mutation chain.
        let id1 = BlockInputBlockID(rawValue: "b1")
        let tableID = BlockInputBlockID(rawValue: "t1")
        let id3 = BlockInputBlockID(rawValue: "b3")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: id1, text: "keep me"),
            BlockInputBlock(id: tableID, kind: .table, text: ""),
            BlockInputBlock(id: id3, text: "delete me")
        ])
        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: id1, utf16Offset: 0)))

        // j1: select table
        mounted.view.performCommand(.moveAfterCurrentBlock)
        mounted.view.performCommand(.selectCurrentBlock)
        XCTAssertEqual(mounted.view.selection, .blocks([tableID]))

        // j2: skip past table to id3
        mounted.view.performCommand(.moveAfterCurrentBlock)
        if case let .cursor(cursor) = mounted.view.selection {
            XCTAssertEqual(cursor.blockID, id3)
        }

        // dd: delete id3
        mounted.view.performCommand(.deleteCurrentBlock)

        XCTAssertEqual(mounted.view.document.blocks.count, 2)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "keep me")
        XCTAssertEqual(mounted.view.document.blocks[0].id, id1)
        // table remains
        XCTAssertEqual(mounted.view.document.blocks[1].id, tableID)
    }

    // MARK: - Vim table mode (escape hatch into native table editing)

    /// A real (cell-bearing) table block used by table-mode tests; the empty `text: ""` tables
    /// above have no cells to focus.
    private func tableModeTableBlock(id: String) -> BlockInputBlock {
        BlockInputBlock(
            id: BlockInputBlockID(rawValue: id),
            kind: .table,
            text: BlockInputTable.normalized(
                header: ["H1", "H2"],
                bodyRows: [["one", "two"]],
                alignments: [.left, .left]
            ).markdown
        )
    }

    func testEnterTableCellFromBlockFocusFocusesFirstCell() throws {
        // The primitive vim `i` runs when a table is block-focused: focus(blockID:, utf16Offset: 0)
        // must drop the native caret into the table's first cell so native editing takes over.
        let tableID = BlockInputBlockID(rawValue: "t1")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: BlockInputBlockID(rawValue: "b1"), text: "above"),
            tableModeTableBlock(id: "t1"),
            BlockInputBlock(id: BlockInputBlockID(rawValue: "b3"), text: "below")
        ])
        // Normal-mode "block focus" on the table.
        mounted.view.applySelectionForTesting(.blocks([tableID]))

        let contentBefore = documentText(mounted.view)

        // Adapter's `.enterTableCell` execution.
        XCTAssertTrue(mounted.view.focusFirstTableCell(in: tableID), "focusFirstTableCell must succeed for a real table")

        XCTAssertEqual(documentText(mounted.view), contentBefore, "entering a table cell must not change content")
        // Caret is now inside the table (selection maps to the table block's source).
        if case let .cursor(cursor) = mounted.view.selection {
            XCTAssertEqual(cursor.blockID, tableID, "caret must be inside the table block")
        } else if case let .text(range) = mounted.view.selection {
            XCTAssertEqual(range.blockID, tableID, "caret must be inside the table block")
        } else {
            XCTFail("Expected a cursor/text selection inside the table, got \(String(describing: mounted.view.selection))")
        }
        // The window's first responder is a table cell text view (native editing is live).
        XCTAssertTrue(
            mounted.window.firstResponder is BlockInputTableCellTextView,
            "first responder must be a table cell text view after entering table mode"
        )
    }

    func testExitTableCellReturnsToBlockFocusAndEditorFirstResponder() throws {
        // The primitive vim `Esc` in table mode: from a focused cell, selectCurrentBlock +
        // makeFirstResponder(view) must re-select the table as block-focus and hand the keyboard
        // back to the editor so vim resumes.
        let tableID = BlockInputBlockID(rawValue: "t1")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: BlockInputBlockID(rawValue: "b1"), text: "above"),
            tableModeTableBlock(id: "t1"),
            BlockInputBlock(id: BlockInputBlockID(rawValue: "b3"), text: "below")
        ])
        // Start inside a table cell (table mode).
        XCTAssertTrue(mounted.view.focusFirstTableCell(in: tableID))
        XCTAssertTrue(mounted.window.firstResponder is BlockInputTableCellTextView, "precondition: caret in a cell")

        let contentBefore = documentText(mounted.view)

        // Adapter's table-mode Esc exit.
        XCTAssertTrue(mounted.view.selectTableAsBlock(tableID))

        XCTAssertEqual(documentText(mounted.view), contentBefore, "exiting table mode must not change content")
        XCTAssertEqual(mounted.view.selection, .blocks([tableID]), "table must be block-focused again after Esc")
        XCTAssertTrue(mounted.window.firstResponder === mounted.view, "editor must be first responder so vim resumes")
        XCTAssertFalse(
            mounted.window.firstResponder is BlockInputTableCellTextView,
            "the cell text view must no longer be first responder"
        )
    }
}
