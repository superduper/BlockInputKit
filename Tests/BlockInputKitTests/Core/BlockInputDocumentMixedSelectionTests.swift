import Foundation
import XCTest
@testable import BlockInputKit

final class BlockInputDocumentMixedSelectionTests: XCTestCase {
    func testDeleteMixedSelectionJoinsPartialEdgeRemainders() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])

        let cursor = document.deleteMixedSelection(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 2, length: 3)),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 3))
        ))

        XCTAssertEqual(document.blocks, [BlockInputBlock(id: firstID, text: "Fiond")])
        XCTAssertEqual(cursor, BlockInputCursor(blockID: firstID, utf16Offset: 2))
    }
}
