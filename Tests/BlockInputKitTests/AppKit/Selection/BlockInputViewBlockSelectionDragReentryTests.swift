import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockSelectionDragReentryTests: XCTestCase {
    func testBlockSelectionDragIgnoresReentrantSelectionCallbackUpdates() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let secondTextView = try XCTUnwrap(secondItem.testingTextView)
        let targetLocation = try windowLocation(forUTF16Offset: 3, in: secondTextView)

        firstItem.beginBlockSelectionDrag()
        firstItem.isUpdatingBlockSelectionDrag = true
        XCTAssertFalse(firstItem.updateBlockSelectionDrag(
            with: try mouseDraggedEvent(location: targetLocation, windowNumber: mounted.window.windowNumber),
            selectedRange: NSRange(location: 2, length: 1)
        ))
        XCTAssertTrue(firstItem.isTrackingBlockSelectionDrag)
        XCTAssertTrue(firstItem.isUpdatingBlockSelectionDrag)

        firstItem.finishBlockSelectionDrag()

        XCTAssertFalse(firstItem.isTrackingBlockSelectionDrag)
        XCTAssertFalse(firstItem.isUpdatingBlockSelectionDrag)
    }
}
