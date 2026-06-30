import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputCodeHighlightMutationTests: XCTestCase {
    func testCodeBlockSyntaxHighlightingUpdatesAfterTextChange() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "code", kind: .code(language: "swift"), text: "let value = 1")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let textStorage = try XCTUnwrap(textView.textStorage)
        let originalKeywordColor = try XCTUnwrap(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        let originalBaseColor = try XCTUnwrap(textStorage.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor)
        XCTAssertNotEqual(originalKeywordColor, originalBaseColor)

        textView.string = "var value = 1"
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        let updatedKeywordColor = try XCTUnwrap(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        let updatedBaseColor = try XCTUnwrap(textStorage.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "var value = 1")
        XCTAssertNotEqual(updatedKeywordColor, updatedBaseColor)
    }

    func testCodeBlockSyntaxHighlightingClearsStaleTokenColorAfterTextChange() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "code", kind: .code(language: "swift"), text: "let value = 1")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let textStorage = try XCTUnwrap(textView.textStorage)

        textView.string = "cat value = 1"
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        let staleKeywordColor = try XCTUnwrap(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        let baseColor = try XCTUnwrap(textStorage.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor)
        XCTAssertEqual(staleKeywordColor, baseColor)
    }

    func testCodeBlockSyntaxHighlightingKeepsSmartQuotedStringAfterTextChange() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "code", kind: .code(language: "swift"), text: "")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let textStorage = try XCTUnwrap(textView.textStorage)
        let source = "println(\u{201C}test\u{201D})"

        textView.string = source
        textView.setSelectedRange(NSRange(location: (source as NSString).length, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        let stringColor = try XCTUnwrap(
            textStorage.attribute(
                .foregroundColor,
                at: ("println(" as NSString).length,
                effectiveRange: nil
            ) as? NSColor
        )
        let baseColor = try XCTUnwrap(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        XCTAssertEqual(mounted.view.document.blocks[0].text, source)
        XCTAssertNotEqual(stringColor, baseColor)
    }
}
