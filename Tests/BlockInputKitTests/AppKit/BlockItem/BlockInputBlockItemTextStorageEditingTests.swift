import XCTest
@testable import BlockInputKit

final class BlockInputItemTextStorageEditingTests: XCTestCase {
    // Regression guard: applyTextAttributes must not leave text storage in a permanently
    // begun-editing state. If endEditing is ever missed (e.g. via a thrown ObjC exception),
    // subsequent calls accumulate nesting and layout asserts or crashes.
    @MainActor
    func testApplyTextAttributesDoesNotLeaveEditingOpen() {
        let block = BlockInputBlock(kind: .paragraph, text: "**bold** and _italic_")
        let item = BlockInputBlockItem.configuredForTesting(
            block: block,
            allowsReordering: true,
            delegate: BlockInputView()
        )
        // Calling applyTextAttributes twice catches any over-nesting of beginEditing.
        item.applyTextAttributes(for: block)
        item.applyTextAttributes(for: block)
        // A broken text storage state would cause layout to assert or crash.
        XCTAssertNoThrow(item.view.layoutSubtreeIfNeeded())
    }
}
