import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewScrollToBlockTests: XCTestCase {
    func testScrollToKnownBlockReturnsTrue() {
        let blocks = (0..<40).map {
            BlockInputBlock(id: BlockInputBlockID(rawValue: "b\($0)"), text: "line \($0)")
        }
        let (view, _) = makeMountedBlockInputView(document: BlockInputDocument(blocks: blocks))
        let target = BlockInputBlockID(rawValue: "b35")
        XCTAssertTrue(view.scrollToBlock(target, animated: false))
    }

    func testScrollToUnknownBlockReturnsFalse() {
        let (view, _) = makeMountedBlockInputView(
            document: BlockInputDocument(blocks: [BlockInputBlock(text: "x")])
        )
        XCTAssertFalse(view.scrollToBlock(BlockInputBlockID(rawValue: "nope"), animated: false))
    }
}
