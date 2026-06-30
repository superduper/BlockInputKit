import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputCodeBlockResizeTests: XCTestCase {
    func testUndoAfterCutResizesMountedCodeBlockWhenLineCountRestores() throws {
        let codeID = BlockInputBlockID(rawValue: "code")
        let singleLineText = "let first = 1"
        let cutText = "\nlet second = 2"
        let initialText = singleLineText + cutText
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: codeID, kind: .code(language: nil), text: initialText),
            BlockInputBlock(id: "next", text: "Next")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let initialNextMinY = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1)).view.frame.minY

        try withCleanPasteboard { _ in
            mounted.window.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: singleLineText.utf16.count, length: cutText.utf16.count))
            textView.cut(nil)
            mounted.view.collectionView.layoutSubtreeIfNeeded()

            let shrunkNextMinY = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1)).view.frame.minY
            XCTAssertEqual(mounted.view.document.blocks[0].text, singleLineText)
            XCTAssertLessThan(shrunkNextMinY, initialNextMinY)

            XCTAssertTrue(textView.tryToPerform(#selector(BlockInputTextView.blockInputUndo(_:)), with: nil))
            mounted.view.collectionView.layoutSubtreeIfNeeded()

            let restoredHeight = BlockInputBlockItem.height(
                for: BlockInputBlock(id: codeID, kind: .code(language: nil), text: initialText),
                textWidth: 664
            )
            let restoredItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
            let restoredNextItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
            XCTAssertEqual(mounted.view.document.blocks[0].text, initialText)
            XCTAssertEqual(restoredItem.view.frame.height, restoredHeight, accuracy: 0.5)
            XCTAssertGreaterThan(restoredNextItem.view.frame.minY, shrunkNextMinY)
        }
    }

    func testRedoAfterUndoResizesMountedCodeBlockWhenLineCountShrinksAgain() throws {
        let codeID = BlockInputBlockID(rawValue: "code")
        let singleLineText = "let first = 1"
        let cutText = "\nlet second = 2"
        let initialText = singleLineText + cutText
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: codeID, kind: .code(language: nil), text: initialText),
            BlockInputBlock(id: "next", text: "Next")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)

        try withCleanPasteboard { _ in
            mounted.window.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: singleLineText.utf16.count, length: cutText.utf16.count))
            textView.cut(nil)
            XCTAssertTrue(textView.tryToPerform(#selector(BlockInputTextView.blockInputUndo(_:)), with: nil))
            mounted.view.collectionView.layoutSubtreeIfNeeded()
            let restoredNextMinY = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1)).view.frame.minY

            XCTAssertTrue(textView.tryToPerform(#selector(BlockInputTextView.blockInputRedo(_:)), with: nil))
            mounted.view.collectionView.layoutSubtreeIfNeeded()

            let singleLineHeight = BlockInputBlockItem.height(
                for: BlockInputBlock(id: codeID, kind: .code(language: nil), text: singleLineText),
                textWidth: 664
            )
            let redoneItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
            let redoneNextItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
            XCTAssertEqual(mounted.view.document.blocks[0].text, singleLineText)
            XCTAssertEqual(redoneItem.view.frame.height, singleLineHeight, accuracy: 0.5)
            XCTAssertLessThan(redoneNextItem.view.frame.minY, restoredNextMinY)
        }
    }

    func testCutAndPasteResizesMountedCodeBlockWhenLineCountChanges() throws {
        let codeID = BlockInputBlockID(rawValue: "code")
        let nextID = BlockInputBlockID(rawValue: "next")
        let singleLineText = "let first = 1"
        let pastedText = "\nlet second = 2"
        let initialText = singleLineText + pastedText
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: codeID, kind: .code(language: nil), text: initialText),
            BlockInputBlock(id: nextID, text: "Next")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let nextItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let initialCodeHeight = item.view.frame.height
        let initialNextMinY = nextItem.view.frame.minY

        try withCleanPasteboard { pasteboard in
            mounted.window.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: singleLineText.utf16.count, length: pastedText.utf16.count))
            textView.cut(nil)
            mounted.view.collectionView.layoutSubtreeIfNeeded()

            let singleLineHeight = BlockInputBlockItem.height(
                for: BlockInputBlock(id: codeID, kind: .code(language: nil), text: singleLineText),
                textWidth: 664
            )
            let shrunkItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
            let movedUpNextItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
            let movedUpNextMinY = movedUpNextItem.view.frame.minY
            XCTAssertEqual(pasteboard.string(forType: .string), pastedText)
            XCTAssertEqual(mounted.view.document.blocks[0].text, singleLineText)
            XCTAssertLessThan(singleLineHeight, initialCodeHeight)
            XCTAssertEqual(shrunkItem.view.frame.height, singleLineHeight, accuracy: 0.5)
            XCTAssertLessThan(movedUpNextMinY, initialNextMinY)

            textView.paste(nil)
            mounted.view.collectionView.layoutSubtreeIfNeeded()

            let restoredHeight = BlockInputBlockItem.height(
                for: BlockInputBlock(id: codeID, kind: .code(language: nil), text: initialText),
                textWidth: 664
            )
            let restoredItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
            let movedDownNextItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
            XCTAssertEqual(mounted.view.document.blocks[0].text, initialText)
            XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: codeID, utf16Offset: initialText.utf16.count)))
            XCTAssertEqual(restoredItem.view.frame.height, restoredHeight, accuracy: 0.5)
            XCTAssertGreaterThan(restoredItem.view.frame.height, singleLineHeight)
            XCTAssertGreaterThan(movedDownNextItem.view.frame.minY, movedUpNextMinY)
        }
    }
}

private func withCleanPasteboard(_ body: (NSPasteboard) throws -> Void) rethrows {
    let pasteboard = NSPasteboard.general
    let previousString = pasteboard.string(forType: .string)
    pasteboard.clearContents()
    defer {
        pasteboard.clearContents()
        if let previousString {
            pasteboard.setString(previousString, forType: .string)
        }
    }
    try body(pasteboard)
}
