import XCTest
@testable import BlockInputKit

final class NumberedListReturnTests: XCTestCase {
    func testReturnInNumberedListItemRenumbersFollowingContiguousItems() {
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let fourthID = BlockInputBlockID(rawValue: "fourth")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(kind: .numberedListItem(start: 1), text: "One"),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 2), text: "Two"),
            BlockInputBlock(id: thirdID, kind: .numberedListItem(start: 3), text: "Three"),
            BlockInputBlock(id: fourthID, kind: .numberedListItem(start: 4), text: "Four"),
            BlockInputBlock(text: "Break"),
            BlockInputBlock(kind: .numberedListItem(start: 1), text: "Separate")
        ])

        let selection = document.handleReturn(in: secondID)

        XCTAssertEqual(document.blocks.map(\.kind), [
            .numberedListItem(start: 1),
            .numberedListItem(start: 2),
            .numberedListItem(start: 3),
            .numberedListItem(start: 4),
            .numberedListItem(start: 5),
            .paragraph,
            .numberedListItem(start: 1)
        ])
        XCTAssertEqual(document.blocks[2].text, "")
        XCTAssertEqual(document.blocks[3].id, thirdID)
        XCTAssertEqual(document.blocks[4].id, fourthID)
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[2].id, utf16Offset: 0)))
    }
}
