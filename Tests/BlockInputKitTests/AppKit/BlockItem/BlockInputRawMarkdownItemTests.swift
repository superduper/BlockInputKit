import AppKit
import XCTest
@testable import BlockInputKit

final class BlockInputRawMarkdownItemTests: XCTestCase {
    @MainActor
    func testRawMarkdownUsesEditableMonospacedWrappingPresentation() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "raw", kind: .rawMarkdown, text: "| A |\n| - |"),
            allowsReordering: true,
            delegate: BlockInputView()
        )

        let textView = try XCTUnwrap(item.testingTextView)
        let scrollView = try XCTUnwrap(item.testingTextScrollView)
        XCTAssertTrue(textView.isEditable)
        XCTAssertTrue(textView.isSelectable)
        XCTAssertFalse(textView.isHorizontallyResizable)
        XCTAssertFalse(scrollView.hasHorizontalScroller)
        XCTAssertEqual(textView.font?.fontName, BlockInputBlockItem.font(for: .rawMarkdown).fontName)
        XCTAssertTrue(item.testingCodeBackgroundView.isHidden)
    }

    @MainActor
    func testRawMarkdownDoesNotApplyInlineCodeStyling() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "raw", kind: .rawMarkdown, text: "Use `git status` now"),
            allowsReordering: true,
            delegate: BlockInputView()
        )

        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        XCTAssertNotEqual(textStorage.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertNotEqual(textStorage.attribute(.foregroundColor, at: 15, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertNil(textStorage.attribute(.backgroundColor, at: 5, effectiveRange: nil))
    }

    @MainActor
    func testRawMarkdownClearsCodePresentationOnReuse() throws {
        let view = BlockInputView()
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "code", kind: .code(language: "swift"), text: "let value = 42"),
            allowsReordering: true,
            delegate: view
        )

        item.configure(
            block: BlockInputBlock(id: "raw", kind: .rawMarkdown, text: "let value = 42"),
            allowsReordering: true,
            delegate: view
        )

        let scrollView = try XCTUnwrap(item.testingTextScrollView)
        let textView = try XCTUnwrap(item.testingTextView)
        let textStorage = try XCTUnwrap(textView.textStorage)
        XCTAssertTrue(item.testingCodeBackgroundView.isHidden)
        XCTAssertEqual(item.testingCodeBackgroundView.alphaValue, 0)
        XCTAssertFalse(scrollView.hasHorizontalScroller)
        XCTAssertTrue(textView.textContainer?.widthTracksTextView ?? false)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .labelColor)
    }
}
