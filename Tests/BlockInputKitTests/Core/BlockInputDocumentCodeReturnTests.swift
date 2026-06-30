import XCTest
@testable import BlockInputKit

final class BlockInputDocumentCodeReturnTests: XCTestCase {
    func testReturnInEmptyCodeBlockExitsToParagraphAtSamePosition() {
        let blockID = BlockInputBlockID(rawValue: "code")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .code(language: "swift"))
        ])

        let selection = document.handleReturn(in: blockID)

        XCTAssertEqual(document.blocks, [BlockInputBlock(id: blockID, kind: .paragraph)])
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))
    }
}
