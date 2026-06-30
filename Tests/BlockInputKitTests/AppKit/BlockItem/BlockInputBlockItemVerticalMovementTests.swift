import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputBlockItemVerticalMovementTests: XCTestCase {
    func testUpFromTrailingBlankLineStaysInsideBlock() throws {
        let block = BlockInputBlock(id: "code", kind: .code(language: nil), text: "let one = 1\n")
        let item = BlockInputBlockItem.configuredForTesting(
            block: block,
            allowsReordering: true,
            delegate: BlockInputView()
        )
        item.view.frame = NSRect(
            x: 0,
            y: 0,
            width: 900,
            height: BlockInputBlockItem.height(for: block, textWidth: 820)
        )
        item.view.layoutSubtreeIfNeeded()
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: block.utf16Length, length: 0))

        XCTAssertFalse(item.canMoveVerticallyOutOfBlock(.upward))
        XCTAssertTrue(item.canMoveVerticallyOutOfBlock(.downward))
    }
}
