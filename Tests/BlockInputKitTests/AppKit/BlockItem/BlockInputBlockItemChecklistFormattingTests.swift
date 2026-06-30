import XCTest
@testable import BlockInputKit

final class BlockInputChecklistFormattingTests: XCTestCase {
    @MainActor
    func testChecklistHeightUsesCompactVerticalMetrics() {
        let paragraphHeight = BlockInputBlockItem.height(
            for: BlockInputBlock(kind: .paragraph, text: "Task"),
            textWidth: 240
        )
        let checklistHeight = BlockInputBlockItem.height(
            for: BlockInputBlock(kind: .checklistItem(isChecked: false), text: "Task"),
            textWidth: 240
        )

        XCTAssertLessThan(checklistHeight, paragraphHeight)
        XCTAssertGreaterThanOrEqual(checklistHeight, 28)
    }

    @MainActor
    func testOrderedAndUnorderedListHeightsUseTextListVerticalMetrics() {
        let paragraphHeight = BlockInputBlockItem.height(
            for: BlockInputBlock(kind: .paragraph, text: "Task"),
            textWidth: 240
        )
        let unorderedHeight = BlockInputBlockItem.height(
            for: BlockInputBlock(kind: .bulletedListItem, text: "Task"),
            textWidth: 240
        )
        let orderedHeight = BlockInputBlockItem.height(
            for: BlockInputBlock(kind: .numberedListItem(start: 1), text: "Task"),
            textWidth: 240
        )
        let checklistHeight = BlockInputBlockItem.height(
            for: BlockInputBlock(kind: .checklistItem(isChecked: false), text: "Task"),
            textWidth: 240
        )

        XCTAssertLessThan(unorderedHeight, paragraphHeight)
        XCTAssertLessThan(unorderedHeight, checklistHeight)
        XCTAssertEqual(unorderedHeight, orderedHeight)
    }

    @MainActor
    func testChecklistTextInsetIsResetWhenItemIsReconfigured() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "check", kind: .checklistItem(isChecked: false), text: "Task"),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textView = try XCTUnwrap(item.testingTextView)

        XCTAssertEqual(textView.textContainerInset, BlockInputBlockItem.checklistTextContainerInset)

        item.configure(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: "Plain"),
            allowsReordering: true,
            delegate: BlockInputView()
        )

        XCTAssertEqual(textView.textContainerInset, BlockInputBlockItem.textBlockTextContainerInset)
    }

    @MainActor
    func testChecklistCheckboxIsVerticallyCenteredWithFirstTextLine() throws {
        let block = BlockInputBlock(
            id: "check",
            kind: .checklistItem(isChecked: false),
            text: "Checklist data round-trips through Markdown"
        )
        let item = BlockInputBlockItem.configuredForTesting(
            block: block,
            allowsReordering: true,
            delegate: BlockInputView()
        )
        item.view.frame = NSRect(
            x: 0,
            y: 0,
            width: 500,
            height: BlockInputBlockItem.height(for: block, textWidth: 420)
        )
        item.view.layoutSubtreeIfNeeded()

        let checkbox = try XCTUnwrap(item.testingChecklistButton)
        let textView = try XCTUnwrap(item.testingTextView)
        let textLineMidY = try firstTextLineMidY(in: textView, convertedTo: item.view)
        let checkboxMidY = checkbox.convert(checkbox.bounds, to: item.view).midY

        XCTAssertEqual(checkboxMidY, textLineMidY, accuracy: 1.5)
    }

    @MainActor
    func testChecklistCheckboxTopOffsetTracksFontLineHeight() {
        let smallFont = NSFont.systemFont(ofSize: 11)
        let largeFont = NSFont.systemFont(ofSize: 24)

        XCTAssertGreaterThan(
            BlockInputBlockItemVerticalMetrics.checklist.checklistButtonTopConstant(
                font: largeFont,
                checkboxHeight: BlockInputBlockItem.checklistButtonHeight
            ),
            BlockInputBlockItemVerticalMetrics.checklist.checklistButtonTopConstant(
                font: smallFont,
                checkboxHeight: BlockInputBlockItem.checklistButtonHeight
            )
        )
    }
}

@MainActor
private func firstTextLineMidY(in textView: NSTextView, convertedTo targetView: NSView) throws -> CGFloat {
    let layoutManager = try XCTUnwrap(textView.layoutManager)
    let textContainer = try XCTUnwrap(textView.textContainer)
    layoutManager.ensureLayout(for: textContainer)
    let glyphRange = layoutManager.glyphRange(for: textContainer)
    let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
    let lineRectInTextView = lineRect.offsetBy(
        dx: textView.textContainerOrigin.x,
        dy: textView.textContainerOrigin.y
    )
    return textView.convert(lineRectInTextView, to: targetView).midY
}
