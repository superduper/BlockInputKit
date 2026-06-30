import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class WordMovementDirectSelectorTests: XCTestCase {
    func testEditorViewDoesNotHandleOptionRightWhenTextViewOwnsFocus() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "Alpha"),
            BlockInputBlock(id: secondID, text: "Beta")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(firstItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        XCTAssertFalse(mounted.view.performKeyEquivalent(with: try optionRightEvent()))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 5)))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 5, length: 0))
        XCTAssertEqual(mounted.window.firstResponder, textView)
    }

    func testDirectMoveWordRightAtBlockEndMovesToNextBlockFirstWordEnd() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "Alpha beta"),
            BlockInputBlock(id: secondID, text: "Gamma delta")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(firstItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 10, length: 0))

        textView.moveWordRight(nil)

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: secondID, utf16Offset: 5)))
        XCTAssertEqual(secondItem.testingTextView?.selectedRange(), NSRange(location: 5, length: 0))
        XCTAssertEqual(mounted.window.firstResponder, secondItem.testingTextView)
    }

    func testDirectMoveWordLeftAtBlockStartMovesToPreviousBlockLastWordStart() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "Alpha beta"),
            BlockInputBlock(id: secondID, text: "Gamma delta")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(secondItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.moveWordLeft(nil)

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 6)))
        XCTAssertEqual(firstItem.testingTextView?.selectedRange(), NSRange(location: 6, length: 0))
        XCTAssertEqual(mounted.window.firstResponder, firstItem.testingTextView)
    }

    func testDirectMoveWordRightInsideTableCellLinkStaysInsideCell() throws {
        let cellText = "Open [docs](https://example.com)"
        let tableBlock = BlockInputBlock(
            id: "table",
            kind: .table,
            text: BlockInputTable.normalized(
                header: ["H1", "H2"],
                bodyRows: [[cellText, "two"]],
                alignments: [.left, .left]
            ).markdown
        )
        let mounted = makeMountedBlockInputView(blocks: [tableBlock])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        let linkRange = try XCTUnwrap(inlineLinkRange(in: cellText))
        mounted.window.makeFirstResponder(cell)
        cell.setSelectedRange(NSRange(location: linkRange.contentRange.location, length: 0))

        cell.moveWordRight(nil)

        XCTAssertEqual(cell.selectedRange(), NSRange(location: NSMaxRange(linkRange.contentRange), length: 0))
        XCTAssertEqual(mounted.window.firstResponder, cell)
    }

    private func inlineLinkRange(in text: String) -> BlockInputInlineMarkdownRange? {
        BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: text,
            excluding: BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange)
        )
        .first { $0.style == .link }
    }
}
