import AppKit
import XCTest
@testable import BlockInputKit

/// Tests for the blank-line auto-split feature: when a paragraph block's text gains
/// `\n\n`, it is split into separate paragraph blocks at each blank line.
@MainActor
final class BlockInputBlankLineSplitTests: XCTestCase {

    // MARK: - Helpers

    private func makeView(text: String, blockID: BlockInputBlockID = .init(rawValue: "para")) -> BlockInputView {
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: text)
        ])))
        return view
    }

    private func makeItem(for view: BlockInputView) -> BlockInputBlockItem {
        BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: false,
            delegate: view
        )
    }

    private func simulateTextChange(_ item: BlockInputBlockItem, text: String, cursorOffset: Int) {
        guard let textView = item.testingTextView else {
            return XCTFail("Block item has no mounted text view")
        }
        textView.string = text
        textView.setSelectedRange(NSRange(location: cursorOffset, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
    }

    // MARK: - Basic split

    func testDoublNewlineAtEndSplitsIntoTwoBlocks() throws {
        let id = BlockInputBlockID(rawValue: "p")
        let view = makeView(text: "Hello", blockID: id)
        let item = makeItem(for: view)

        // Simulate: text becomes "Hello\n\n" (cursor after second newline)
        simulateTextChange(item, text: "Hello\n\n", cursorOffset: 7)

        XCTAssertEqual(view.document.blocks.count, 2, "must split into 2 blocks")
        XCTAssertEqual(view.document.blocks[0].text, "Hello")
        XCTAssertEqual(view.document.blocks[0].kind, .paragraph)
        XCTAssertEqual(view.document.blocks[1].text, "")
        XCTAssertEqual(view.document.blocks[1].kind, .paragraph)
        // Cursor in second (empty) block
        XCTAssertEqual(
            view.selection,
            .cursor(BlockInputCursor(blockID: view.document.blocks[1].id, utf16Offset: 0))
        )
    }

    func testDoublNewlineInMiddleSplitsAtBlankLine() throws {
        let view = makeView(text: "Hello")
        let item = makeItem(for: view)

        simulateTextChange(item, text: "Hello\n\nWorld", cursorOffset: 12)

        XCTAssertEqual(view.document.blocks.count, 2, "must split into 2 blocks")
        XCTAssertEqual(view.document.blocks[0].text, "Hello")
        XCTAssertEqual(view.document.blocks[1].text, "World")
        XCTAssertEqual(
            view.selection,
            .cursor(BlockInputCursor(blockID: view.document.blocks[1].id, utf16Offset: 5))
        )
    }

    func testMultipleDoubleNewlinesSplitIntoManyBlocks() throws {
        let view = makeView(text: "")
        let item = makeItem(for: view)

        simulateTextChange(item, text: "Para1\n\nPara2\n\nPara3", cursorOffset: 19)

        XCTAssertEqual(view.document.blocks.count, 3)
        XCTAssertEqual(view.document.blocks[0].text, "Para1")
        XCTAssertEqual(view.document.blocks[1].text, "Para2")
        XCTAssertEqual(view.document.blocks[2].text, "Para3")
        XCTAssertEqual(
            view.selection,
            .cursor(BlockInputCursor(blockID: view.document.blocks[2].id, utf16Offset: 5))
        )
    }

    func testCursorInFirstComponentStaysInFirstBlock() throws {
        let view = makeView(text: "")
        let item = makeItem(for: view)

        simulateTextChange(item, text: "Para1\n\nPara2", cursorOffset: 3)

        XCTAssertEqual(view.document.blocks.count, 2)
        XCTAssertEqual(
            view.selection,
            .cursor(BlockInputCursor(blockID: view.document.blocks[0].id, utf16Offset: 3))
        )
    }

    func testCursorInSeparatorLandsAtStartOfNextBlock() throws {
        let view = makeView(text: "")
        let item = makeItem(for: view)

        // Offset 6 is inside the "\n\n" separator (after "Para1" len=5)
        simulateTextChange(item, text: "Para1\n\nPara2", cursorOffset: 6)

        XCTAssertEqual(view.document.blocks.count, 2)
        XCTAssertEqual(
            view.selection,
            .cursor(BlockInputCursor(blockID: view.document.blocks[1].id, utf16Offset: 0))
        )
    }

    // MARK: - Non-paragraph blocks are not split

    func testHeadingWithDoubleNewlineIsNotSplit() throws {
        let id = BlockInputBlockID(rawValue: "h1")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: id, kind: .heading(level: 1), text: "Title")
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: false,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.string = "Title\n\nSubtitle"
        textView.setSelectedRange(NSRange(location: 15, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        // Heading blocks must not be split
        XCTAssertEqual(view.document.blocks.count, 1, "heading block must not be split on \\n\\n")
    }

    // MARK: - Single newline does not split

    func testSingleNewlineDoesNotSplit() throws {
        let view = makeView(text: "Hello")
        let item = makeItem(for: view)

        simulateTextChange(item, text: "Hello\nWorld", cursorOffset: 11)

        XCTAssertEqual(view.document.blocks.count, 1, "single \\n must not split the block")
        XCTAssertEqual(view.document.blocks[0].text, "Hello\nWorld")
    }

    // MARK: - Undo restores original block

    func testUndoRestoresSingleBlock() throws {
        let id = BlockInputBlockID(rawValue: "para")
        let view = makeView(text: "Hello", blockID: id)
        let item = makeItem(for: view)

        simulateTextChange(item, text: "Hello\n\nWorld", cursorOffset: 12)
        XCTAssertEqual(view.document.blocks.count, 2)

        view.performCommand(.undo)

        XCTAssertEqual(view.document.blocks.count, 1, "undo must restore single block")
        XCTAssertEqual(view.document.blocks[0].text, "Hello")
    }

    // MARK: - O (insert line above) via moveToLineStart + insertLineBreak + moveUp

    func testInsertLineAboveAddsNewlineBeforeCurrentLine() {
        let blockID = BlockInputBlockID(rawValue: "para")
        let view = makeView(text: "Hello", blockID: blockID)
        let item = makeItem(for: view)

        // Simulate O: moveToBlockContentStart → cursor at 0, insertLineBreak → "\nHello", cursor at 1
        // The text change fires with "\nHello" at proposedOffset 1.
        simulateTextChange(item, text: "\nHello", cursorOffset: 1)

        // "\nHello" has no \n\n, so it stays as one block (not split)
        XCTAssertEqual(view.document.blocks.count, 1, "single \\n must not split")
        XCTAssertEqual(view.document.blocks[0].text, "\nHello")
    }

    func testInsertLineAboveThenDoubleNewlineSplits() {
        // After O creates "\nHello", pressing O again on the empty top line:
        // → moveToBlockContentStart (pos 0), insertLineBreak → "\n\nHello" (cursor at 1)
        // Cursor at offset 1 (second \n in separator) lands at start of next component.
        // The vim adapter's subsequent moveUp then moves cursor up to the empty block.
        let view = makeView(text: "\nHello")
        let item = makeItem(for: view)

        simulateTextChange(item, text: "\n\nHello", cursorOffset: 1)

        XCTAssertEqual(view.document.blocks.count, 2, "\\n\\n must split")
        XCTAssertEqual(view.document.blocks[0].text, "")
        XCTAssertEqual(view.document.blocks[1].text, "Hello")
        // Cursor lands in "Hello" block; vim adapter's moveUp brings it to the empty block above.
        XCTAssertEqual(
            view.selection,
            .cursor(BlockInputCursor(blockID: view.document.blocks[1].id, utf16Offset: 0))
        )
    }
}
