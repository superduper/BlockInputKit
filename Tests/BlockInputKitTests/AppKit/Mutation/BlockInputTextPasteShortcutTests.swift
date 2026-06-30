import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputTextPasteShortcutTests: XCTestCase {
    func testCommandVPastesPlainTextFromTextFocus() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(" Paste", forType: .string)
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandVEvent()))

        XCTAssertEqual(textView.string, "First Paste")
        XCTAssertEqual(mounted.view.document.blocks[0].text, "First Paste")
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 11)))
    }

    func testEditorCommandVPastesPlainTextIntoActiveSelection() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First")
        ])
        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 1, length: 3)
        )), notify: false)
        XCTAssertTrue(mounted.window.makeFirstResponder(mounted.view))
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString("oo", forType: .string)
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandVEvent()))

        let textView = try textView(in: mounted.view)
        XCTAssertEqual(textView.string, "Foot")
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Foot")
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 3)))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 3, length: 0))
    }

    private func textView(in view: BlockInputView) throws -> BlockInputTextView {
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        return try XCTUnwrap(item.testingTextView)
    }
}
