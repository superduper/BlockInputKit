import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputCodeCopyTests: XCTestCase {
    func testCommandCCopiesFullCodeTextSelectionAsFencedMarkdownFromTextFocus() throws {
        let code = BlockInputBlock(id: "code", kind: .code(language: "swift"), text: "let value = 1")
        let mounted = makeMountedBlockInputView(blocks: [code])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: code.utf16Length))

        try withCleanPasteboard { pasteboard in
            XCTAssertTrue(textView.performKeyEquivalent(with: try commandCEvent()))

            XCTAssertEqual(pasteboard.string(forType: .string), """
            ```swift
            let value = 1
            ```
            """)
        }
    }

    func testCommandCCopiesFullCodeBlockSelectionAsFencedMarkdownWithStoredLanguage() throws {
        let code = BlockInputBlock(id: "code", kind: .code(language: "swift package"), text: "let value = 1")
        let mounted = makeMountedBlockInputView(blocks: [code])
        mounted.view.applySelection(.blocks([code.id]), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        try withCleanPasteboard { pasteboard in
            XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandCEvent()))

            XCTAssertEqual(pasteboard.string(forType: .string), """
            ```swift package
            let value = 1
            ```
            """)
        }
    }

    func testCommandCCopiesPartialCodeTextSelectionAsPlainTextFromTextFocus() throws {
        let code = BlockInputBlock(id: "code", kind: .code(language: "swift"), text: "let value = 1")
        let mounted = makeMountedBlockInputView(blocks: [code])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 4, length: 5))

        try withCleanPasteboard { pasteboard in
            XCTAssertTrue(textView.performKeyEquivalent(with: try commandCEvent()))

            XCTAssertEqual(pasteboard.string(forType: .string), "value")
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
