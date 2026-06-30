import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewSelectionCancellationTests: XCTestCase {
    func testEscapeCancelsMultiBlockSelectionFromEditorResponder() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        mounted.view.applySelection(.blocks([firstID, secondID]), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        mounted.view.keyDown(with: try escapeEvent())

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 0)))
        XCTAssertEqual(mounted.window.firstResponder, mounted.view.visibleBlockItemForTesting(at: 0)?.testingTextView)
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 0), false)
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 1), false)
    }

    func testEscapeCancelsMultiBlockSelectionFromTextViewResponder() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.view.applySelection(.blocks([firstID, secondID]), notify: false)
        mounted.window.makeFirstResponder(textView)

        textView.doCommand(by: #selector(NSResponder.cancelOperation(_:)))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 0)))
        XCTAssertEqual(mounted.window.firstResponder, textView)
    }

    func testEscapeDoesNotCancelSingleBlockSelection() throws {
        let blockID = BlockInputBlockID(rawValue: "rule")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, kind: .horizontalRule)
        ])
        mounted.view.applySelection(.blocks([blockID]), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        mounted.view.keyDown(with: try escapeEvent())

        XCTAssertEqual(mounted.view.selection, .blocks([blockID]))
    }

    func testEscapeCancelsMixedSelectionToPartialEndpoint() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        mounted.view.applySelection(.mixed(BlockInputMixedSelection(
            blockIDs: [secondID],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 2, length: 3))
        )), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        mounted.view.keyDown(with: try escapeEvent())

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 2)))
        XCTAssertEqual(mounted.window.firstResponder, mounted.view.visibleBlockItemForTesting(at: 0)?.testingTextView)
    }

    func testPlainUpCancelsMixedSelectionAtActiveDownwardEdge() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftDownEvent()))
        mounted.window.makeFirstResponder(mounted.view)

        mounted.view.keyDown(with: try plainUpEvent())

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: secondID, utf16Offset: 1)))
        XCTAssertEqual(mounted.window.firstResponder, mounted.view.visibleBlockItemForTesting(at: 1)?.testingTextView)
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 0), false)
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 1), false)
    }

    func testPlainDownCancelsMixedSelectionAtActiveUpwardEdge() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftUpEvent()))
        mounted.window.makeFirstResponder(mounted.view)

        mounted.view.keyDown(with: try plainDownEvent())

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 4)))
        XCTAssertEqual(mounted.window.firstResponder, mounted.view.visibleBlockItemForTesting(at: 0)?.testingTextView)
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 0), false)
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 1), false)
    }

    func testTextBlockClickCancellationClearsMultiBlockSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(secondItem.testingTextView)
        mounted.view.applySelection(.blocks([firstID, secondID]), notify: false)

        XCTAssertTrue(textView.requestCancelSelectionFromOwningBlock())

        XCTAssertNotEqual(mounted.view.selection, .blocks([firstID, secondID]))
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 0), false)
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 1), false)
    }

    func testMouseDownCancellationLetsClickedTextViewPlaceCaret() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(secondItem.testingTextView)
        mounted.view.applySelection(.blocks([firstID, secondID]), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        XCTAssertTrue(textView.requestMouseDownCancelSelectionFromOwningBlock())
        XCTAssertNil(mounted.view.selection)
        XCTAssertEqual(mounted.window.firstResponder, mounted.view)

        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: secondID, utf16Offset: 3)))
        XCTAssertEqual(mounted.window.firstResponder, textView)
    }

    func testMouseDownCancellationClearsStaleNativeTextSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let firstTextView = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0)?.testingTextView)
        let secondTextView = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1)?.testingTextView)
        mounted.view.applySelection(.mixed(BlockInputMixedSelection(
            blockIDs: [secondID],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 1, length: 4))
        )), notify: false)
        mounted.window.makeFirstResponder(mounted.view)
        firstTextView.setSelectedRange(NSRange(location: 1, length: 4))
        secondTextView.setSelectedRange(NSRange(location: 0, length: 3))

        XCTAssertTrue(secondTextView.requestMouseDownCancelSelectionFromOwningBlock())

        XCTAssertNil(mounted.view.selection)
        XCTAssertEqual(firstTextView.selectedRange(), NSRange(location: 1, length: 0))
        XCTAssertEqual(secondTextView.selectedRange(), NSRange(location: 0, length: 0))
    }

    private func itemSelectionBackgroundVisible(in view: BlockInputView, at index: Int) -> Bool {
        view.visibleBlockItemForTesting(at: index)?.testingSelectionBackgroundView.isHidden == false
    }
}
