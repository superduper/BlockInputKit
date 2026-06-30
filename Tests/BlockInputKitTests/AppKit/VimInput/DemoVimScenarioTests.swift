import AppKit
import XCTest
@testable import BlockInputKit

/// Scenario-level tests for the framework commands that back vim keybindings.
///
/// Each test documents the vim key sequence in its name and asserts the resulting
/// cursor position, selection, or document text — matching what the adapter calls.
@MainActor
final class DemoVimScenarioTests: XCTestCase {

    // MARK: - 0 and $ (moveToBlockContentStart / End)

    func testVim0MovesToStartOfBlockContent() throws {
        // vim `0` → moveToBlockContentStart: places caret at offset 0 regardless of visual line
        let blockID = BlockInputBlockID(rawValue: "b1")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "hello world")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 6, length: 0))

        mounted.view.performCommand(.moveToBlockContentStart)

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0))
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))
    }

    func testVimDollarMovesToEndOfBlockContent() throws {
        // vim `$` → moveToBlockContentEnd: places caret at end regardless of visual line
        let blockID = BlockInputBlockID(rawValue: "b1")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "hello world")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        mounted.view.performCommand(.moveToBlockContentEnd)

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 11, length: 0))
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 11)))
    }

    // MARK: - dd (deleteCurrentBlock)

    func testVimDDRemovesBlockAndLandsCursorInNextBlock() throws {
        // vim `dd` → deleteCurrentBlock: deletes block, cursor lands in adjacent block
        let id1 = BlockInputBlockID(rawValue: "b1")
        let id2 = BlockInputBlockID(rawValue: "b2")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: id1, text: "first"),
            BlockInputBlock(id: id2, text: "second")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        mounted.window.makeFirstResponder(item.testingTextView)

        mounted.view.performCommand(.deleteCurrentBlock)

        XCTAssertEqual(mounted.view.document.blocks.count, 1)
        XCTAssertEqual(mounted.view.document.blocks[0].id, id2)
        if case let .cursor(cursor) = mounted.view.selection {
            XCTAssertEqual(cursor.blockID, id2)
        } else {
            XCTFail("Expected cursor in remaining block, got \(String(describing: mounted.view.selection))")
        }
    }

    func testVimDDOnSingleBlockClearsContentInsteadOfRemoving() throws {
        // vim `dd` on sole block: content is cleared, block count stays 1
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(text: "only block")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        mounted.window.makeFirstResponder(item.testingTextView)

        mounted.view.performCommand(.deleteCurrentBlock)

        XCTAssertEqual(mounted.view.document.blocks.count, 1)
        XCTAssertEqual(mounted.view.document.blocks[0].utf16Length, 0)
    }

    // MARK: - dw (extendSelectionWordRight + cut)

    func testVimDWDeletesWordToRight() throws {
        // vim `dw` → extend selection by word then cut
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(text: "hello world")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        mounted.view.performCommand(.extendSelectionWordRight)
        mounted.view.performCommand(.cut)

        // AppKit extendSelectionWordRight selects to end-of-word (before trailing space)
        XCTAssertEqual(textView.string, " world")
    }

    func testVimD3WDeletesThreeWords() throws {
        // vim `d3w` → extendSelectionWordRight × 3 then cut
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(text: "one two three four")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        for _ in 0..<3 { mounted.view.performCommand(.extendSelectionWordRight) }
        mounted.view.performCommand(.cut)

        // AppKit word selection stops before trailing space, so one leading space remains
        XCTAssertEqual(textView.string, " four")
    }

    // MARK: - V (selectCurrentBlock)

    func testVimVSelectsCurrentBlockAsBlockSelection() throws {
        // vim `V` → selectCurrentBlock: sets selection to .blocks([blockID])
        let blockID = BlockInputBlockID(rawValue: "b1")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "hello")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        mounted.window.makeFirstResponder(item.testingTextView)

        mounted.view.performCommand(.selectCurrentBlock)

        XCTAssertEqual(mounted.view.selection, .blocks([blockID]))
    }

    // MARK: - j / k across a table block

    func testJApproachingTableBlockSelectsTableNotCell() throws {
        // vim `j` when next block is a table:
        // adapter calls moveAfterCurrentBlock + selectCurrentBlock → .blocks([tableID])
        let id1 = BlockInputBlockID(rawValue: "b1")
        let tableID = BlockInputBlockID(rawValue: "t1")
        let id3 = BlockInputBlockID(rawValue: "b3")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: id1, text: "paragraph"),
            BlockInputBlock(id: tableID, kind: .table, text: ""),
            BlockInputBlock(id: id3, text: "after")
        ])
        let item1 = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        mounted.window.makeFirstResponder(item1.testingTextView)

        // Simulate adapter's singleDown() when next block is a table
        mounted.view.performCommand(.moveAfterCurrentBlock)
        mounted.view.performCommand(.selectCurrentBlock)

        XCTAssertEqual(mounted.view.selection, .blocks([tableID]))
    }

    func testJFromTableBlockSelectionSkipsToBlockAfterTable() throws {
        // vim `j` when table is currently block-selected: moveAfterCurrentBlock → cursor in next block
        let tableID = BlockInputBlockID(rawValue: "t1")
        let id3 = BlockInputBlockID(rawValue: "b3")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: BlockInputBlockID(rawValue: "b1"), text: "paragraph"),
            BlockInputBlock(id: tableID, kind: .table, text: ""),
            BlockInputBlock(id: id3, text: "after")
        ])
        // Start with table already block-selected (simulates second j press)
        mounted.view.applySelectionForTesting(.blocks([tableID]))

        mounted.view.performCommand(.moveAfterCurrentBlock)

        if case let .cursor(cursor) = mounted.view.selection {
            XCTAssertEqual(cursor.blockID, id3)
            XCTAssertEqual(cursor.utf16Offset, 0)
        } else {
            XCTFail("Expected cursor in block after table, got \(String(describing: mounted.view.selection))")
        }
    }

    func testKApproachingTableFromBelowBlockSelectsTable() throws {
        // vim `k` when previous block is a table:
        // adapter calls moveBeforeCurrentBlock + selectCurrentBlock → .blocks([tableID])
        let tableID = BlockInputBlockID(rawValue: "t1")
        let id3 = BlockInputBlockID(rawValue: "b3")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: BlockInputBlockID(rawValue: "b1"), text: "paragraph"),
            BlockInputBlock(id: tableID, kind: .table, text: ""),
            BlockInputBlock(id: id3, text: "after")
        ])
        // Set selection directly so view.selection is synchronously updated before commands
        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: id3, utf16Offset: 0)))

        // Simulate adapter's singleUp() when previous block is a table
        mounted.view.performCommand(.moveBeforeCurrentBlock)
        mounted.view.performCommand(.selectCurrentBlock)

        XCTAssertEqual(mounted.view.selection, .blocks([tableID]))
    }

    // MARK: - > and < (increaseIndent / decreaseIndent)

    func testVimIndentIncreasesListItemLevel() throws {
        // vim `>` → increaseIndent: bumps indentation level of list item by 1
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(kind: .bulletedListItem, text: "item", indentationLevel: 0)
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        mounted.window.makeFirstResponder(item.testingTextView)

        mounted.view.performCommand(.increaseIndent)

        XCTAssertEqual(mounted.view.document.blocks[0].indentationLevel(forLine: 0), 1)
    }

    func testVimDedentDecreasesListItemLevel() throws {
        // vim `<` → decreaseIndent: reduces indentation level of list item by 1
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(kind: .bulletedListItem, text: "item", indentationLevel: 1)
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        mounted.window.makeFirstResponder(item.testingTextView)

        mounted.view.performCommand(.decreaseIndent)

        XCTAssertEqual(mounted.view.document.blocks[0].indentationLevel(forLine: 0), 0)
    }

    // MARK: - u (undo)

    func testVimUUndoesInsertedText() throws {
        // vim `u` → undo: rolls back the last text edit
        let blockID = BlockInputBlockID(rawValue: "b1")
        let undoController = BlockInputUndoController()
        let mounted = makeMountedBlockInputView(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: blockID, text: "hello")]),
            undoController: undoController
        )
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        textView.insertText(" world", replacementRange: NSRange(location: 5, length: 0))
        XCTAssertEqual(textView.string, "hello world")

        mounted.view.performCommand(.undo)

        XCTAssertEqual(textView.string, "hello")
    }

    func testVimMultipleUUndoesMultipleSteps() throws {
        // vim `3u` → undo × 3: each undo rolls back one edit
        let undoController = BlockInputUndoController()
        let mounted = makeMountedBlockInputView(
            document: BlockInputDocument(blocks: [BlockInputBlock(text: "")]),
            undoController: undoController
        )
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.insertText("a", replacementRange: NSRange(location: 0, length: 0))
        textView.insertText("b", replacementRange: NSRange(location: 1, length: 0))
        textView.insertText("c", replacementRange: NSRange(location: 2, length: 0))
        XCTAssertEqual(textView.string, "abc")

        for _ in 0..<3 { mounted.view.performCommand(.undo) }

        XCTAssertEqual(textView.string, "")
    }

    // MARK: - moveBeforeCurrentBlock

    func testMoveBeforeCurrentBlockLandsCursorInPreviousBlock() throws {
        // vim `k` skipping: moveBeforeCurrentBlock places cursor at start of previous block
        let id1 = BlockInputBlockID(rawValue: "b1")
        let id2 = BlockInputBlockID(rawValue: "b2")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: id1, text: "first"),
            BlockInputBlock(id: id2, text: "second")
        ])
        // Set selection directly so view.selection is synchronously updated before commands
        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: id2, utf16Offset: 0)))

        mounted.view.performCommand(.moveBeforeCurrentBlock)

        if case let .cursor(cursor) = mounted.view.selection {
            XCTAssertEqual(cursor.blockID, id1)
            XCTAssertEqual(cursor.utf16Offset, 0)
        } else {
            XCTFail("Expected cursor in first block, got \(String(describing: mounted.view.selection))")
        }
    }

    // MARK: - o on an image block (no phantom paragraph above the image)

    func testVimOOnImageBlockInsertsEmptyParagraphBelowImage() throws {
        // vim `o` → moveToBlockContentEnd + insertBlockBelow.
        // Regression: on an opaque image block the content-end move is a no-op (no editable
        // text view), so insertBlockBelow ran with caret offset 0 and "leading return" pushed
        // the image DOWN, leaving a phantom empty paragraph in the image's place that trapped
        // the cursor. `o` must instead insert a NEW empty paragraph *below* the image and land
        // the caret there, leaving the image (and its heading) untouched and in place.
        let headingID = BlockInputBlockID(rawValue: "img-heading")
        let imageID = BlockInputBlockID(rawValue: "img-block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: headingID, kind: .heading(level: 2), text: "Images"),
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(
                source: "willriver_falls.jpg",
                altText: "Willriver Falls",
                width: 480,
                height: 320
            )))
        ])

        // Cursor sits on the image block (as it would after navigating onto it).
        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: imageID, utf16Offset: 0)))

        // o: content-end move (no-op on image) then structural insert below.
        mounted.view.performCommand(.moveToBlockContentEnd)
        mounted.view.performCommand(.insertBlockBelow)

        let blocks = mounted.view.document.blocks
        XCTAssertEqual(blocks.count, 3, "o must add exactly one block")
        XCTAssertEqual(blocks[0].id, headingID, "heading must stay first")
        XCTAssertEqual(blocks[0].kind, .heading(level: 2), "heading kind must be untouched")
        XCTAssertEqual(blocks[1].id, imageID, "image must stay in place, not be pushed down")
        XCTAssertTrue(blocks[1].kind.isImage, "the image block must remain an image, not become a phantom paragraph")
        XCTAssertEqual(blocks[2].kind, .paragraph, "the inserted block must be an empty paragraph")
        XCTAssertTrue(blocks[2].isEmpty, "the inserted paragraph must be empty")

        if case let .cursor(cursor) = mounted.view.selection {
            XCTAssertEqual(cursor.blockID, blocks[2].id, "caret must land in the newly inserted paragraph below the image")
        } else {
            XCTFail("Expected a cursor selection after o, got \(String(describing: mounted.view.selection))")
        }
    }
}

// MARK: - Test helpers

extension BlockInputView {
    /// Directly sets selection for testing without requiring a first-responder text view.
    func applySelectionForTesting(_ selection: BlockInputSelection) {
        applySelection(selection, notify: true)
    }
}
