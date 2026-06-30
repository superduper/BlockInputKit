import AppKit
import XCTest
@testable import BlockInputKit

final class BlockInputFrontMatterItemTests: XCTestCase {
    @MainActor
    func testFrontMatterUsesEditableMonospacedPresentationWithDivider() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "front", kind: .frontMatter, text: "title: Demo"),
            allowsReordering: true,
            delegate: BlockInputView()
        )

        let textView = try XCTUnwrap(item.testingTextView)
        let divider = try XCTUnwrap(item.testingFrontMatterDividerView)
        XCTAssertTrue(textView.isEditable)
        XCTAssertTrue(textView.isSelectable)
        XCTAssertEqual(textView.font?.fontName, BlockInputBlockItem.font(for: .frontMatter).fontName)
        XCTAssertFalse(divider.isHidden)
        XCTAssertEqual(divider.alphaValue, 1)
        XCTAssertNil(divider.hitTest(NSPoint(x: divider.bounds.midX, y: divider.bounds.midY)))
    }

    @MainActor
    func testLoadedMarkdownFrontMatterDoesNotRenderSyntheticTrailingBlankLine() throws {
        let document = BlockInputDocument(markdown: """
        ---
        name: review-github-pr
        model: opus
        argument-hint: "[PR URL]"
        ---

        Body
        """)
        let mounted = makeMountedBlockInputView(blocks: document.blocks)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)

        XCTAssertEqual(textView.string, "name: review-github-pr\nmodel: opus\nargument-hint: \"[PR URL]\"")
        XCTAssertFalse(textView.string.hasSuffix("\n"))
    }

    @MainActor
    func testFrontMatterDoesNotExposeReorderHandle() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "front", kind: .frontMatter, text: "title: Demo"),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let handle = try XCTUnwrap(item.testingHandleView)

        XCTAssertFalse(handle.isEnabled)
        XCTAssertTrue(handle.isHidden)
        XCTAssertNil(handle.toolTip)
        XCTAssertEqual(item.testingHandleWidthConstraint?.constant, BlockInputBlockItem.handleWidth)
    }

    @MainActor
    func testFrontMatterHeightReservesDividerSpace() {
        let frontMatter = BlockInputBlock(id: "front", kind: .frontMatter, text: "title: Demo")
        let rawMarkdown = BlockInputBlock(id: "raw", kind: .rawMarkdown, text: "title: Demo")

        let frontMatterHeight = BlockInputBlockItem.height(for: frontMatter, textWidth: 320)
        let rawMarkdownHeight = BlockInputBlockItem.height(for: rawMarkdown, textWidth: 320)

        XCTAssertEqual(
            frontMatterHeight - rawMarkdownHeight,
            (BlockInputBlockItem.frontMatterDividerVerticalInset * 2) + BlockInputBlockItem.frontMatterDividerHeight,
            accuracy: 0.5
        )
    }

    @MainActor
    func testFrontMatterStylesTopLevelKeysAndColons() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "front", kind: .frontMatter, text: "title: Demo\n  - continuation"),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)

        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .systemBlue)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? NSColor, .secondaryLabelColor)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 7, effectiveRange: nil) as? NSColor, .labelColor)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 12, effectiveRange: nil) as? NSColor, .labelColor)
    }

    @MainActor
    func testFrontMatterAppliesAndClearsValidationWarningAttributesOnReuse() throws {
        let view = BlockInputView()
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "front", kind: .frontMatter, text: "invalid"),
            allowsReordering: true,
            delegate: view
        )
        let warningStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        item.testingTextView?.typingAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        XCTAssertEqual(warningStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .systemOrange)
        XCTAssertNotNil(warningStorage.attribute(.underlineStyle, at: 0, effectiveRange: nil))

        item.configure(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: "invalid"),
            allowsReordering: true,
            delegate: view
        )

        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        XCTAssertTrue(try XCTUnwrap(item.testingFrontMatterDividerView).isHidden)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .labelColor)
        XCTAssertNil(textStorage.attribute(.underlineStyle, at: 0, effectiveRange: nil))
        XCTAssertNil(item.testingTextView?.typingAttributes[.underlineStyle])
    }

    @MainActor
    func testFrontMatterEmptyValueLineShowsValidationWarning() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "front", kind: .frontMatter, text: "model:"),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)

        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .systemOrange)
        XCTAssertNotNil(textStorage.attribute(.underlineStyle, at: 0, effectiveRange: nil))
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? NSColor, .secondaryLabelColor)
        XCTAssertNil(textStorage.attribute(.underlineStyle, at: 5, effectiveRange: nil))
    }
}
