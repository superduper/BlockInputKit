import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputQuoteChromeTests: XCTestCase {
    func testSingleLineQuoteBarUsesMinimumVisualHeightCenteredOnTextLine() throws {
        let block = BlockInputBlock(id: "quote", kind: .quote, text: "Quoted")
        let item = BlockInputBlockItem.configuredForTesting(
            block: block,
            allowsReordering: true,
            delegate: BlockInputView()
        )
        mountForLayoutTesting(
            item,
            size: NSSize(width: 420, height: BlockInputBlockItem.height(for: block, textWidth: 340))
        )

        let quoteBar = try XCTUnwrap(item.testingQuoteBarView)
        let textRect = try textUsedRect(in: item)
        let firstLineRect = try firstTextLineRect(in: item)
        let handle = try XCTUnwrap(item.testingHandleView)

        XCTAssertGreaterThan(quoteBar.frame.height, textRect.height)
        XCTAssertGreaterThanOrEqual(quoteBar.frame.minY, item.view.bounds.minY)
        XCTAssertLessThanOrEqual(quoteBar.frame.maxY, item.view.bounds.maxY)
        XCTAssertEqual(quoteBar.frame.midY, firstLineRect.midY, accuracy: 1)
        XCTAssertEqual(handle.frame.midY, firstLineRect.midY, accuracy: 1)
    }

    func testSelectedSingleLineQuoteBarTextAndHandleShareVerticalCenter() throws {
        let block = BlockInputBlock(
            id: "quote",
            kind: .quote,
            text: "Selected quote"
        )
        let item = BlockInputBlockItem.configuredForTesting(
            block: block,
            allowsReordering: true,
            isSelected: true,
            delegate: BlockInputView()
        )
        item.setReorderHandleVisible(true)
        mountForLayoutTesting(
            item,
            size: NSSize(width: 420, height: BlockInputBlockItem.height(for: block, textWidth: 340))
        )

        let quoteBar = try XCTUnwrap(item.testingQuoteBarView)
        let handle = try XCTUnwrap(item.testingHandleView)
        let firstLineRect = try firstTextLineRect(in: item)

        XCTAssertEqual(quoteBar.frame.midY, firstLineRect.midY, accuracy: 1)
        XCTAssertEqual(handle.frame.midY, firstLineRect.midY, accuracy: 1)
    }
}
