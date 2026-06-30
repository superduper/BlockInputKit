import AppKit
import XCTest
@testable import BlockInputKit

/// End-to-end scenario tests for `o` / `O` open-line semantics.
///
/// These test the full command chain on a mounted view (not just the text-change handler)
/// to verify that visual-line wrapping is never broken and that cursor lands in the right place.
@MainActor
final class BlockInputOpenLineScenarioTests: XCTestCase {

    // MARK: - `o`: open line below

    func testOpenLineBelowOnShortParagraphAddsLineAtEnd() throws {
        let blockID = BlockInputBlockID(rawValue: "p")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Hello world")
        ])
        let view = mounted.view

        // Place cursor in the middle of the text (as if the user pressed `j`/`w`)
        view.performCommand(.moveToBlockContentStart)
        view.performCommand(.moveRight)  // cursor at offset 1

        // o: moveToBlockContentEnd + insertLineBreak
        view.performCommand(.moveToBlockContentEnd)
        view.performCommand(.insertLineBreak)

        // Single \n, no split — still one block
        XCTAssertEqual(view.document.blocks.count, 1)
        XCTAssertEqual(view.document.blocks[0].id, blockID)
        XCTAssertEqual(view.document.blocks[0].text, "Hello world\n")
        // Cursor is on the new empty line (offset after the newline = 12)
        XCTAssertEqual(
            view.selection,
            .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 12))
        )
    }

    func testOpenLineBelowDoesNotSplitWrappedParagraphMidWord() throws {
        // Create text long enough that it wraps at 400pt wide
        let longText = String(repeating: "Lorem ipsum dolor sit amet ", count: 5)
        let blockID = BlockInputBlockID(rawValue: "p")
        let mounted = makeMountedBlockInputView(
            configuration: BlockInputConfiguration(
                document: BlockInputDocument(blocks: [
                    BlockInputBlock(id: blockID, text: longText)
                ])
            ),
            size: NSSize(width: 400, height: 480)
        )
        let view = mounted.view

        // Place cursor at the start (first visual wrap line)
        view.performCommand(.moveToBlockContentStart)

        // o: move to block content end (NOT visual-line end), insert \n
        view.performCommand(.moveToBlockContentEnd)
        view.performCommand(.insertLineBreak)

        // Must not split the paragraph — still one block
        XCTAssertEqual(view.document.blocks.count, 1, "o must not split a wrapped paragraph")
        let text = view.document.blocks[0].text
        // The \n must be at the very end, not somewhere inside the paragraph
        XCTAssertTrue(text.hasSuffix("\n"), "newline must be appended at paragraph end, not mid-wrap")
        XCTAssertFalse(text.contains("\n\n"), "must not create a blank line (would trigger split)")
    }

    func testOpenLineBelowThenTypingDoesNotSplit() throws {
        let blockID = BlockInputBlockID(rawValue: "p")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First line")
        ])
        let view = mounted.view
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))

        // Simulate o: cursor to end, insert \n (cursor lands after the \n)
        view.performCommand(.moveToBlockContentEnd)
        view.performCommand(.insertLineBreak)

        // Simulate typing "Second" on the new line
        let textView = try XCTUnwrap(item.testingTextView)
        textView.string = "First line\nSecond"
        textView.setSelectedRange(NSRange(location: 17, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        // Still one block (single \n, no \n\n)
        XCTAssertEqual(view.document.blocks.count, 1)
        XCTAssertEqual(view.document.blocks[0].text, "First line\nSecond")
    }

    func testOpenLineBelowThenReturnSplitsBlock() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: .init(rawValue: "p"), text: "Hello")
        ])
        let view = mounted.view
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))

        // Simulate o → cursor after "Hello", insert \n → text is "Hello\n"
        view.performCommand(.moveToBlockContentEnd)
        view.performCommand(.insertLineBreak)

        // Now simulate typing a blank line (\n\n) which triggers the auto-split
        let textView = try XCTUnwrap(item.testingTextView)
        textView.string = "Hello\n\n"
        textView.setSelectedRange(NSRange(location: 7, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        // Auto-split fires: 2 blocks
        XCTAssertEqual(view.document.blocks.count, 2)
        XCTAssertEqual(view.document.blocks[0].text, "Hello")
        XCTAssertEqual(view.document.blocks[1].text, "")
    }

    // MARK: - `O`: open line above

    func testOpenLineAboveOnNonEmptyParagraphAddsLineAtStart() throws {
        let blockID = BlockInputBlockID(rawValue: "p")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Hello world")
        ])
        let view = mounted.view

        // Place cursor in the middle of the text
        view.performCommand(.moveToBlockContentEnd)
        view.performCommand(.moveLeft)  // cursor near end

        // O: moveToBlockContentStart + insertLineBreak + moveUp
        view.performCommand(.moveToBlockContentStart)
        view.performCommand(.insertLineBreak)
        // After insertLineBreak at offset 0, text is "\nHello world", cursor at 1

        // No \n\n → still one block
        XCTAssertEqual(view.document.blocks.count, 1)
        XCTAssertEqual(view.document.blocks[0].id, blockID)
        XCTAssertEqual(view.document.blocks[0].text, "\nHello world")
    }

    func testOpenLineAboveDoesNotBreakWrappedParagraphAtVisualLineStart() throws {
        let longText = String(repeating: "Lorem ipsum dolor sit amet ", count: 5)
        let blockID = BlockInputBlockID(rawValue: "p")
        let mounted = makeMountedBlockInputView(
            configuration: BlockInputConfiguration(
                document: BlockInputDocument(blocks: [
                    BlockInputBlock(id: blockID, text: longText)
                ])
            ),
            size: NSSize(width: 400, height: 480)
        )
        let view = mounted.view

        // Place cursor somewhere on the second visual wrap line (if any)
        view.performCommand(.moveToBlockContentEnd)

        // O: go to paragraph content start (not visual-line start), insert \n at offset 0
        view.performCommand(.moveToBlockContentStart)
        view.performCommand(.insertLineBreak)

        XCTAssertEqual(view.document.blocks.count, 1, "O must not split a wrapped paragraph")
        XCTAssertTrue(
            view.document.blocks[0].text.hasPrefix("\n"),
            "newline must be prepended at paragraph start, not mid-wrap"
        )
    }

    func testOpenLineAboveOnEmptyBlockInsertsNewBlockAbove() throws {
        let emptyID = BlockInputBlockID(rawValue: "empty")
        let belowID = BlockInputBlockID(rawValue: "below")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: emptyID, text: ""),
            BlockInputBlock(id: belowID, text: "Below")
        ])
        let view = mounted.view

        // Focus the empty block
        view.performCommand(.moveToDocumentStart)
        XCTAssertEqual(view.document.blocks.count, 2)

        // O on empty block: should insert a new block above via insertBlockAbove
        // (The adapter checks text.isEmpty and falls back to insertBlockAbove)
        view.performCommand(.insertBlockAbove)

        XCTAssertEqual(view.document.blocks.count, 3, "O on empty block must insert a new block above")
        XCTAssertEqual(view.document.blocks[1].id, emptyID, "original empty block stays at index 1")
        XCTAssertEqual(view.document.blocks[2].id, belowID, "below block shifts to index 2")
    }
}
