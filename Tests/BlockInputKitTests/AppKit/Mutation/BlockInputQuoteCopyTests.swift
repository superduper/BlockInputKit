import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputQuoteCopyTests: XCTestCase {
    func testCommandCCopiesFullQuoteTextSelectionAsMarkdownWhenEditorViewIsFirstResponder() throws {
        let quote = BlockInputBlock(id: "quote", kind: .quote, text: "Quoted")
        let mounted = makeMountedBlockInputView(blocks: [quote])
        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: quote.id,
            range: NSRange(location: 0, length: quote.utf16Length)
        )), notify: false)
        mounted.window.makeFirstResponder(mounted.view)
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandCEvent()))

        XCTAssertEqual(pasteboard.string(forType: .string), "> Quoted")
    }

    func testCommandCCopiesFullQuoteTextSelectionAsMarkdownFromTextFocus() throws {
        let quote = BlockInputBlock(id: "quote", kind: .quote, text: "Quoted")
        let mounted = makeMountedBlockInputView(blocks: [quote])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: quote.utf16Length))
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandCEvent()))

        XCTAssertEqual(pasteboard.string(forType: .string), "> Quoted")
    }

    func testCommandCCopiesFullMultilineQuoteTextSelectionAsMarkdownFromTextFocus() throws {
        let quote = BlockInputBlock(id: "quote", kind: .quote, text: "First\nSecond")
        let mounted = makeMountedBlockInputView(blocks: [quote])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: quote.utf16Length))
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandCEvent()))

        XCTAssertEqual(pasteboard.string(forType: .string), "> First\n> Second")
    }

    func testCommandCCopiesPartialQuoteTextSelectionAsPlainTextFromTextFocus() throws {
        let quote = BlockInputBlock(id: "quote", kind: .quote, text: "Quoted")
        let mounted = makeMountedBlockInputView(blocks: [quote])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 3))
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandCEvent()))

        XCTAssertEqual(pasteboard.string(forType: .string), "Quo")
    }

    func testCutActionCutsFullQuoteTextSelectionAsMarkdownFromTextFocus() throws {
        let quote = BlockInputBlock(id: "quote", kind: .quote, text: "Quoted")
        let mounted = makeMountedBlockInputView(blocks: [quote])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: quote.utf16Length))
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        textView.cut(nil)

        XCTAssertEqual(pasteboard.string(forType: .string), "> Quoted")
        XCTAssertEqual(mounted.view.document.blocks[0].text, "")
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: quote.id, utf16Offset: 0)))
    }
}
