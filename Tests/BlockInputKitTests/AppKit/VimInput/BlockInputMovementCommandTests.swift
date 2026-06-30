import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputMovementCommandTests: XCTestCase {
    func testMoveRightAdvancesCaretWithinBlock() throws {
        let blockID = BlockInputBlockID(rawValue: "b1")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "hello")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        mounted.view.performCommand(.moveRight)

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 1)))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 1, length: 0))
    }

    func testMoveLeftMovesCaretWithinBlock() throws {
        let blockID = BlockInputBlockID(rawValue: "b1")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "hello")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        mounted.view.performCommand(.moveLeft)

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 2)))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 2, length: 0))
    }

    func testMoveWordRightJumpsToWordBoundary() throws {
        let blockID = BlockInputBlockID(rawValue: "b1")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "hello world")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        mounted.view.performCommand(.moveWordRight)

        XCTAssertEqual(textView.selectedRange().location, 5)
    }

    func testMoveToLineStartMovesCaretToBeginningOfLine() throws {
        let blockID = BlockInputBlockID(rawValue: "b1")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "hello world")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 6, length: 0))

        mounted.view.performCommand(.moveToLineStart)

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0))
    }

    func testExtendSelectionRightExpandsSelection() throws {
        let blockID = BlockInputBlockID(rawValue: "b1")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "hello")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        mounted.view.performCommand(.extendSelectionRight)

        // Character-by-character selection expansion is tracked in the view's selection model as a mixed selection,
        // not in the text view's native selected range (which the view supersedes with its own anchor/active tracking).
        XCTAssertEqual(
            mounted.view.selection,
            .mixed(BlockInputMixedSelection(
                blockIDs: [],
                leadingTextRange: BlockInputTextRange(blockID: blockID, range: NSRange(location: 0, length: 1))
            ))
        )
    }

    func testDeleteWordBackwardDeletesLeftWord() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(text: "hello world")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 11, length: 0))

        mounted.view.performCommand(.deleteWordBackward)

        XCTAssertEqual(textView.string, "hello ")
    }

    func testCanPerformMovementCommandWhenCursorActive() throws {
        let blockID = BlockInputBlockID(rawValue: "b1")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "hello")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertTrue(mounted.view.canPerformCommand(.moveRight))
        XCTAssertTrue(mounted.view.canPerformCommand(.moveLeft))
        XCTAssertTrue(mounted.view.canPerformCommand(.extendSelectionRight))
    }

    func testMovementCommandsUnavailableWithNoActiveBlock() {
        let mounted = makeMountedBlockInputView(blocks: [])

        XCTAssertFalse(mounted.view.canPerformCommand(.moveRight))
        XCTAssertFalse(mounted.view.canPerformCommand(.moveLeft))
    }

    func testDeleteCharForwardDeletesCharacterToRight() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(text: "hello")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        mounted.view.performCommand(.deleteCharForward)

        XCTAssertEqual(textView.string, "ello")
    }

    func testDeleteCharBackwardDeletesCharacterToLeft() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(text: "hello")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        mounted.view.performCommand(.deleteCharBackward)

        XCTAssertEqual(textView.string, "hell")
    }

    func testInsertBlockBelowAddsNewBlockBelow() throws {
        let blockID = BlockInputBlockID(rawValue: "b1")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "first")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        mounted.window.makeFirstResponder(item.testingTextView)

        mounted.view.performCommand(.insertBlockBelow)

        XCTAssertEqual(mounted.view.document.blocks.count, 2)
        if case let .cursor(cursor) = mounted.view.selection {
            XCTAssertNotEqual(cursor.blockID, blockID)
            XCTAssertEqual(cursor.utf16Offset, 0)
        } else {
            XCTFail("Expected cursor selection in newly inserted block")
        }
    }

    func testInsertBlockAboveAddsNewBlockBeforeCurrentBlock() throws {
        let blockID = BlockInputBlockID(rawValue: "b1")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "first")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        mounted.window.makeFirstResponder(item.testingTextView)

        mounted.view.performCommand(.insertBlockAbove)

        XCTAssertEqual(mounted.view.document.blocks.count, 2)
        // The new block is at index 0; original block is pushed to index 1.
        XCTAssertEqual(mounted.view.document.blocks[1].id, blockID)
        if case let .cursor(cursor) = mounted.view.selection {
            XCTAssertNotEqual(cursor.blockID, blockID)
            XCTAssertEqual(cursor.utf16Offset, 0)
        } else {
            XCTFail("Expected cursor selection in newly inserted block")
        }
    }

    func testInsertBlockBelowUnavailableWhenNotEditable() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(text: "hello")
        ])
        mounted.view.isEditable = false

        XCTAssertFalse(mounted.view.canPerformCommand(.insertBlockBelow))
        XCTAssertFalse(mounted.view.canPerformCommand(.insertBlockAbove))
    }
}
