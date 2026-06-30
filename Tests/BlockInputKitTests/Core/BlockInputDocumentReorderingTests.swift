import XCTest
@testable import BlockInputKit

final class BlockInputDocumentReorderingTests: XCTestCase {
    func testFrontMatterMoveHelperRejectsOutOfRangeIndexes() {
        let blocks = [
            BlockInputBlock(id: "front", kind: .frontMatter, text: "title: Demo"),
            BlockInputBlock(id: "body", text: "Body")
        ]

        XCTAssertFalse(BlockInputDocument.canMovePreservingLeadingFrontMatter(sourceIndex: -1, targetIndex: 0, in: blocks))
        XCTAssertFalse(BlockInputDocument.canMovePreservingLeadingFrontMatter(sourceIndex: 0, targetIndex: 2, in: blocks))
        XCTAssertFalse(BlockInputDocument.canMovePreservingLeadingFrontMatter(sourceIndex: 1, targetIndex: -1, in: blocks))
    }

    func testMoveTopLevelNumberedItemAboveSiblingRenumbersMovedBlock() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, kind: .numberedListItem(start: 1), text: "One"),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 2), text: "Two"),
            BlockInputBlock(id: thirdID, kind: .numberedListItem(start: 3), text: "Three")
        ])

        let selection = document.moveBlock(blockID: thirdID, to: 0)

        XCTAssertEqual(document.blocks.map(\.id), [thirdID, firstID, secondID])
        XCTAssertEqual(document.blocks.map(\.kind), [
            .numberedListItem(start: 1),
            .numberedListItem(start: 2),
            .numberedListItem(start: 3)
        ])
        XCTAssertEqual(selection, .blocks([thirdID]))
    }

    func testMoveTopLevelNumberedItemAboveMiddleSiblingRenumbersMovedBlock() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, kind: .numberedListItem(start: 1), text: "One"),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 2), text: "Two"),
            BlockInputBlock(id: thirdID, kind: .numberedListItem(start: 3), text: "Three")
        ])

        let selection = document.moveBlock(blockID: thirdID, to: 1)

        XCTAssertEqual(document.blocks.map(\.id), [firstID, thirdID, secondID])
        XCTAssertEqual(document.blocks.map(\.kind), [
            .numberedListItem(start: 1),
            .numberedListItem(start: 2),
            .numberedListItem(start: 3)
        ])
        XCTAssertEqual(selection, .blocks([thirdID]))
    }

    func testMoveFirstTopLevelNumberedItemBelowSiblingRenumbersRun() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, kind: .numberedListItem(start: 1), text: "One"),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 2), text: "Two"),
            BlockInputBlock(id: thirdID, kind: .numberedListItem(start: 3), text: "Three")
        ])

        let selection = document.moveBlock(blockID: firstID, to: 2)

        XCTAssertEqual(document.blocks.map(\.id), [secondID, thirdID, firstID])
        XCTAssertEqual(document.blocks.map(\.kind), [
            .numberedListItem(start: 1),
            .numberedListItem(start: 2),
            .numberedListItem(start: 3)
        ])
        XCTAssertEqual(selection, .blocks([firstID]))
    }

    func testMoveFirstCustomStartNumberedItemBelowSiblingPreservesRunStart() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, kind: .numberedListItem(start: 4), text: "Four"),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 5), text: "Five"),
            BlockInputBlock(id: thirdID, kind: .numberedListItem(start: 6), text: "Six")
        ])

        let selection = document.moveBlock(blockID: firstID, to: 2)

        XCTAssertEqual(document.blocks.map(\.id), [secondID, thirdID, firstID])
        XCTAssertEqual(document.blocks.map(\.kind), [
            .numberedListItem(start: 4),
            .numberedListItem(start: 5),
            .numberedListItem(start: 6)
        ])
        XCTAssertEqual(selection, .blocks([firstID]))
    }

    func testMoveBulletedSeparatorFromNumberedRunRenumbersSourceList() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let bulletID = BlockInputBlockID(rawValue: "bullet")
        let secondID = BlockInputBlockID(rawValue: "second")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, kind: .numberedListItem(start: 1), text: "One"),
            BlockInputBlock(id: bulletID, kind: .bulletedListItem, text: "Bullet"),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 9), text: "Nine")
        ])

        let selection = document.moveBlock(blockID: bulletID, to: 2)

        XCTAssertEqual(document.blocks.map(\.id), [firstID, secondID, bulletID])
        XCTAssertEqual(document.blocks.map(\.kind), [
            .numberedListItem(start: 1),
            .numberedListItem(start: 2),
            .bulletedListItem
        ])
        XCTAssertEqual(selection, .blocks([bulletID]))
    }
}
