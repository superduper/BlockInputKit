import AppKit
import XCTest
@testable import BlockInputKit

/// Coverage for the selection-aware `.formatCode` command: single-line selections toggle inline
/// backticks, multi-line selections toggle a fenced code block, and availability follows the
/// active selection.
@MainActor
final class BlockInputFormatCodeCommandTests: XCTestCase {
    private let blockID = BlockInputBlockID(rawValue: "block")

    func testSingleLineSelectionWrapsInBackticksAndReportsOn() {
        let mounted = mounted(text: "word", range: NSRange(location: 0, length: 4))

        XCTAssertEqual(mounted.view.state(for: .formatCode), .off)
        XCTAssertTrue(mounted.view.performCommand(.formatCode))

        XCTAssertEqual(mounted.view.document.blocks[0].text, "`word`")
        XCTAssertEqual(
            mounted.view.selection,
            .text(BlockInputTextRange(blockID: blockID, range: NSRange(location: 1, length: 4)))
        )
        XCTAssertEqual(mounted.view.state(for: .formatCode), .on)
    }

    func testSingleLineFormatCodeTogglesBackOff() {
        let mounted = mounted(text: "word", range: NSRange(location: 0, length: 4))

        XCTAssertTrue(mounted.view.performCommand(.formatCode))
        XCTAssertEqual(mounted.view.document.blocks[0].text, "`word`")

        // Applying again over the now-backticked content removes the backticks.
        XCTAssertTrue(mounted.view.performCommand(.formatCode))
        XCTAssertEqual(mounted.view.document.blocks[0].text, "word")
        XCTAssertEqual(
            mounted.view.selection,
            .text(BlockInputTextRange(blockID: blockID, range: NSRange(location: 0, length: 4)))
        )
        XCTAssertEqual(mounted.view.state(for: .formatCode), .off)
    }

    func testSingleLineFormatCodeIsUndoable() {
        let undoController = BlockInputUndoController()
        let mounted = mounted(text: "word", range: NSRange(location: 0, length: 4), undoController: undoController)

        XCTAssertTrue(mounted.view.performCommand(.formatCode))
        XCTAssertEqual(mounted.view.document.blocks[0].text, "`word`")

        let undo = mounted.view.undoStructuralEdit()
        XCTAssertEqual(undo?.actionName, "Format Text")
        XCTAssertEqual(mounted.view.document.blocks[0].text, "word")
    }

    func testMultiLineSelectionConvertsBlockToCode() {
        let mounted = mounted(text: "one\ntwo", range: NSRange(location: 0, length: 7))

        XCTAssertEqual(mounted.view.state(for: .formatCode), .off)
        XCTAssertTrue(mounted.view.performCommand(.formatCode))

        XCTAssertEqual(mounted.view.document.blocks[0].kind, .code(language: nil))
        XCTAssertEqual(mounted.view.document.blocks[0].text, "one\ntwo")
        XCTAssertEqual(mounted.view.state(for: .formatCode), .on)
    }

    func testMultiLineFormatCodeTogglesBackToParagraph() {
        let mounted = mounted(text: "one\ntwo", range: NSRange(location: 0, length: 7))

        XCTAssertTrue(mounted.view.performCommand(.formatCode))
        XCTAssertEqual(mounted.view.document.blocks[0].kind, .code(language: nil))

        // Re-applying over the multi-line selection toggles the code block back to a paragraph.
        XCTAssertTrue(mounted.view.performCommand(.formatCode))
        XCTAssertEqual(mounted.view.document.blocks[0].kind, .paragraph)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "one\ntwo")
    }

    func testMultiLineFormatCodeIsUndoable() {
        let undoController = BlockInputUndoController()
        let mounted = mounted(text: "one\ntwo", range: NSRange(location: 0, length: 7), undoController: undoController)

        XCTAssertTrue(mounted.view.performCommand(.formatCode))
        XCTAssertEqual(mounted.view.document.blocks[0].kind, .code(language: nil))

        let undo = mounted.view.undoStructuralEdit()
        XCTAssertEqual(undo?.actionName, "Format Block")
        XCTAssertEqual(mounted.view.document.blocks[0].kind, .paragraph)
    }

    func testSingleLineSelectionInsideCodeBlockTogglesFenceOff() {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, kind: .code(language: nil), text: "one\ntwo")
        ])
        // A single-line (no-newline) selection inside an existing code block must still toggle the
        // whole fence off, not fall through to the inline branch (which would no-op).
        mounted.view.applySelection(
            .text(BlockInputTextRange(blockID: blockID, range: NSRange(location: 0, length: 3))),
            notify: false
        )
        XCTAssertEqual(mounted.view.state(for: .formatCode), .on)

        XCTAssertTrue(mounted.view.performCommand(.formatCode))
        XCTAssertEqual(mounted.view.document.blocks[0].kind, .paragraph)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "one\ntwo")
        XCTAssertEqual(mounted.view.state(for: .formatCode), .off)
    }

    func testCanPerformIsFalseForCaretAndTrueForTextSelection() {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "word")
        ])
        mounted.view.applySelection(
            .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)),
            notify: false
        )
        XCTAssertFalse(mounted.view.canPerformCommand(.formatCode))
        XCTAssertEqual(mounted.view.state(for: .formatCode), .unavailable)

        mounted.view.applySelection(
            .text(BlockInputTextRange(blockID: blockID, range: NSRange(location: 0, length: 4))),
            notify: false
        )
        XCTAssertTrue(mounted.view.canPerformCommand(.formatCode))
    }

    func testCanPerformIsFalseForUnsupportedBlockSelection() {
        let imageID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/a.png", altText: "")))
        ])
        mounted.view.applySelection(.blocks([imageID]), notify: false)
        XCTAssertFalse(mounted.view.canPerformCommand(.formatCode))
        XCTAssertEqual(mounted.view.state(for: .formatCode), .unavailable)
    }

    func testInlineCodeShortcutAddRemoveParity() {
        let mounted = mounted(text: "word", range: NSRange(location: 0, length: 4))

        XCTAssertTrue(mounted.view.performTextFormattingShortcut(.inlineCode))
        XCTAssertEqual(mounted.view.document.blocks[0].text, "`word`")
        XCTAssertEqual(
            mounted.view.selection,
            .text(BlockInputTextRange(blockID: blockID, range: NSRange(location: 1, length: 4)))
        )

        XCTAssertTrue(mounted.view.performTextFormattingShortcut(.inlineCode))
        XCTAssertEqual(mounted.view.document.blocks[0].text, "word")
        XCTAssertEqual(
            mounted.view.selection,
            .text(BlockInputTextRange(blockID: blockID, range: NSRange(location: 0, length: 4)))
        )
    }

    private func mounted(
        text: String,
        range: NSRange,
        undoController: BlockInputUndoController = BlockInputUndoController()
    ) -> (view: BlockInputView, window: NSWindow) {
        let mounted = makeMountedBlockInputView(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: blockID, text: text)]),
            undoController: undoController
        )
        mounted.view.applySelection(
            .text(BlockInputTextRange(blockID: blockID, range: range)),
            notify: false
        )
        return mounted
    }
}
