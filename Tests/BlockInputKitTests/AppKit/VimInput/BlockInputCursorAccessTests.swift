import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputCursorAccessTests: XCTestCase {

    // MARK: activeBlockText

    func testActiveBlockTextReturnsStoredTextWhenBlockNotMounted() {
        let blockID = BlockInputBlockID(rawValue: "b1")
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "stored")
        ])))
        XCTAssertEqual(view.activeBlockText, "stored")
    }

    func testActiveBlockTextReturnsLiveTextViewContent() throws {
        let blockID = BlockInputBlockID(rawValue: "b1")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "hello")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        textView.insertText("X", replacementRange: textView.selectedRange())

        XCTAssertEqual(mounted.view.activeBlockText, "helXlo")
    }

    func testActiveBlockTextFallsBackToFirstBlockWhenSelectionIsNil() {
        let blockID = BlockInputBlockID(rawValue: "b1")
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "fallback")
        ])))
        // No selection set; activeBlockID falls through to block(at:0).
        XCTAssertNil(view.selection)
        XCTAssertEqual(view.activeBlockText, "fallback")
    }

    // MARK: cursorOffset

    func testCursorOffsetReflectsCaretPosition() throws {
        let blockID = BlockInputBlockID(rawValue: "b1")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "hello")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        XCTAssertEqual(mounted.view.cursorOffset, 3)
    }

    func testCursorOffsetCoheresWithActiveBlockTextAfterLiveEdit() throws {
        let blockID = BlockInputBlockID(rawValue: "b1")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "hello")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        // "hello" → "helXlo", cursor lands at offset 4
        textView.insertText("X", replacementRange: textView.selectedRange())

        let text = try XCTUnwrap(mounted.view.activeBlockText)
        let offset = try XCTUnwrap(mounted.view.cursorOffset)
        XCTAssertEqual(text, "helXlo")
        XCTAssertEqual(offset, 4)
        // Character at cursorOffset in live text must be "l"
        let utf16 = Array(text.utf16)
        XCTAssertEqual(utf16[offset], UInt16(("l" as Unicode.Scalar).value))
    }

    func testCursorOffsetIsNilForBlockSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "b1")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "hello")
        ])
        mounted.view.applySelection(.blocks([firstID]), notify: false)

        XCTAssertNil(mounted.view.cursorOffset)
    }

    func testCursorOffsetReturnsAnchorForTextSelection() throws {
        let blockID = BlockInputBlockID(rawValue: "b1")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "hello")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 1, length: 3))

        XCTAssertEqual(mounted.view.cursorOffset, 1)
    }

    // MARK: setCursorOffset

    func testSetCursorOffsetMovesBothModelAndTextView() throws {
        let blockID = BlockInputBlockID(rawValue: "b1")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "hello")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        let result = mounted.view.setCursorOffset(3, in: blockID)

        XCTAssertTrue(result)
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 3)))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 3, length: 0))
    }

    func testSetCursorOffsetReturnsFalseForOutOfRangeOffset() {
        let blockID = BlockInputBlockID(rawValue: "b1")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "hello")
        ])

        XCTAssertFalse(mounted.view.setCursorOffset(99, in: blockID))
        XCTAssertFalse(mounted.view.setCursorOffset(-1, in: blockID))
    }

    func testSetCursorOffsetReturnsFalseForUnknownBlock() {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(text: "hello")
        ])
        let unknownID = BlockInputBlockID(rawValue: "unknown")

        XCTAssertFalse(mounted.view.setCursorOffset(0, in: unknownID))
    }

    // MARK: setTextSelection

    func testSetTextSelectionMovesBothModelAndTextView() throws {
        let blockID = BlockInputBlockID(rawValue: "b1")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "hello")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)

        let result = mounted.view.setTextSelection(1..<4, in: blockID)

        XCTAssertTrue(result)
        XCTAssertEqual(
            mounted.view.selection,
            .text(BlockInputTextRange(blockID: blockID, range: NSRange(location: 1, length: 3)))
        )
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 1, length: 3))
    }

    func testSetTextSelectionReturnsFalseForEmptyRange() {
        let blockID = BlockInputBlockID(rawValue: "b1")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "hello")
        ])

        XCTAssertFalse(mounted.view.setTextSelection(2..<2, in: blockID))
    }

    func testSetTextSelectionReturnsFalseForOutOfBoundsRange() {
        let blockID = BlockInputBlockID(rawValue: "b1")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "hello")
        ])

        XCTAssertFalse(mounted.view.setTextSelection(3..<99, in: blockID))
    }
}
