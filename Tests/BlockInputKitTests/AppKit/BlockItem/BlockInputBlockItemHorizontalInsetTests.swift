import XCTest
@testable import BlockInputKit

final class BlockInputBlockItemHorizontalInsetTests: XCTestCase {
    @MainActor
    func testCustomHorizontalInsetControlsPlainRowsWithoutReordering() throws {
        let inset: CGFloat = 28
        let item = configuredParagraphItem(allowsReordering: false, editorHorizontalInset: inset)

        XCTAssertEqual(try textContentMinX(in: item), inset, accuracy: 0.5)
        XCTAssertEqual(try textContentTrailingInset(in: item), inset, accuracy: 0.5)
    }

    @MainActor
    func testReorderingGutterUsesConfiguredInsetWhenItFits() throws {
        let inset: CGFloat = 64
        let item = configuredParagraphItem(allowsReordering: true, editorHorizontalInset: inset)
        let handleView = try XCTUnwrap(item.testingHandleView)

        XCTAssertEqual(try textContentMinX(in: item), inset, accuracy: 0.5)
        XCTAssertEqual(try textContentTrailingInset(in: item), inset, accuracy: 0.5)
        XCTAssertLessThanOrEqual(handleView.frame.maxX, inset + 0.5)
        XCTAssertEqual(handleView.frame.midX, inset / 2, accuracy: 0.5)
    }

    @MainActor
    func testDefaultReorderingGutterFitsInsideConfiguredInset() throws {
        let item = configuredParagraphItem(allowsReordering: true, editorHorizontalInset: 20)
        let handleView = try XCTUnwrap(item.testingHandleView)

        XCTAssertEqual(
            try textContentMinX(in: item),
            20,
            accuracy: 0.5
        )
        XCTAssertEqual(
            try textContentTrailingInset(in: item),
            20,
            accuracy: 0.5
        )
        XCTAssertEqual(handleView.frame.midX, 10, accuracy: 0.5)
    }

    @MainActor
    func testReorderingGutterGrowsWhenConfiguredInsetIsTooSmall() throws {
        let item = configuredParagraphItem(allowsReordering: true, editorHorizontalInset: 12)
        let handleView = try XCTUnwrap(item.testingHandleView)
        let expectedInset = BlockInputBlockItem.horizontalChromeWidthWithHandle

        XCTAssertEqual(
            try textContentMinX(in: item),
            expectedInset,
            accuracy: 0.5
        )
        XCTAssertEqual(
            try textContentTrailingInset(in: item),
            expectedInset,
            accuracy: 0.5
        )
        XCTAssertEqual(handleView.frame.midX, expectedInset / 2, accuracy: 0.5)
    }

    @MainActor
    private func configuredParagraphItem(
        allowsReordering: Bool,
        editorHorizontalInset: CGFloat
    ) -> BlockInputBlockItem {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: "Plain"),
            allowsReordering: allowsReordering,
            editorHorizontalInset: editorHorizontalInset,
            delegate: BlockInputView()
        )
        item.view.frame = NSRect(x: 0, y: 0, width: 420, height: 60)
        item.view.layoutSubtreeIfNeeded()
        return item
    }

    @MainActor
    private func textContentMinX(in item: BlockInputBlockItem) throws -> CGFloat {
        let scrollView = try XCTUnwrap(item.testingTextScrollView)
        let textView = try XCTUnwrap(item.testingTextView)
        let lineFragmentPadding = textView.textContainer?.lineFragmentPadding ?? 0
        return scrollView.frame.minX + textView.textContainerInset.width + lineFragmentPadding
    }

    @MainActor
    private func textContentTrailingInset(in item: BlockInputBlockItem) throws -> CGFloat {
        let scrollView = try XCTUnwrap(item.testingTextScrollView)
        let textView = try XCTUnwrap(item.testingTextView)
        let lineFragmentPadding = textView.textContainer?.lineFragmentPadding ?? 0
        return item.view.bounds.maxX - scrollView.frame.maxX + textView.textContainerInset.width + lineFragmentPadding
    }
}
