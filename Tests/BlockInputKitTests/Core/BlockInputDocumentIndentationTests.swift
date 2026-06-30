import Foundation
import XCTest
@testable import BlockInputKit

final class BlockInputDocumentIndentationTests: XCTestCase {
    func testOutdentAtRootLevelIsNoOp() {
        let blockID = BlockInputBlockID(rawValue: "root")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "Root", indentationLevel: 0)
        ])

        let selection = document.outdentBlock(blockID: blockID)

        XCTAssertNil(selection)
        XCTAssertEqual(document.blocks[0].indentationLevel, 0)
    }

    func testIndentWithActiveOffsetOnlyIndentsCurrentListLine() {
        let blockID = BlockInputBlockID(rawValue: "list")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "One\nTwo\nThree")
        ])

        let selection = document.indentBlock(blockID: blockID, activeUTF16Offset: 5)

        XCTAssertEqual(document.blocks[0].indentationLevel, 0)
        XCTAssertEqual(document.blocks[0].lineIndentationLevels, [0, 1, 0])
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 5)))
    }

    func testIndentNumberedListItemStartsNestedSequenceAtOne() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, kind: .numberedListItem(start: 1), text: "One"),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 2), text: "Two")
        ])

        _ = document.indentBlock(blockID: secondID)

        XCTAssertEqual(document.blocks[1].kind, .numberedListItem(start: 1))
        XCTAssertEqual(document.blocks[1].indentationLevel, 1)
    }

    func testIndentNumberedListItemContinuesExistingNestedSequence() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, kind: .numberedListItem(start: 1), text: "One"),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 1), text: "Two", indentationLevel: 1),
            BlockInputBlock(id: thirdID, kind: .numberedListItem(start: 3), text: "Three")
        ])

        _ = document.indentBlock(blockID: thirdID)

        XCTAssertEqual(document.blocks[2].kind, .numberedListItem(start: 2))
        XCTAssertEqual(document.blocks[2].indentationLevel, 1)
    }

    func testOutdentNumberedListItemContinuesRootSequence() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, kind: .numberedListItem(start: 1), text: "One"),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 1), text: "Two", indentationLevel: 1),
            BlockInputBlock(id: thirdID, kind: .numberedListItem(start: 2), text: "Three", indentationLevel: 1)
        ])

        _ = document.outdentBlock(blockID: thirdID)

        XCTAssertEqual(document.blocks[2].kind, .numberedListItem(start: 2))
        XCTAssertEqual(document.blocks[2].indentationLevel, 0)
    }

    func testOutdentNumberedListItemRenumbersRemainingNestedSiblings() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, kind: .numberedListItem(start: 1), text: "One"),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 1), text: "Two", indentationLevel: 1),
            BlockInputBlock(id: thirdID, kind: .numberedListItem(start: 2), text: "Three", indentationLevel: 1)
        ])

        _ = document.outdentBlock(blockID: secondID)

        XCTAssertEqual(document.blocks.map(\.kind), [
            .numberedListItem(start: 1),
            .numberedListItem(start: 2),
            .numberedListItem(start: 1)
        ])
        XCTAssertEqual(document.blocks.map(\.indentationLevel), [0, 0, 1])
    }

    func testOutdentWithActiveOffsetOnlyOutdentsCurrentListLine() {
        let blockID = BlockInputBlockID(rawValue: "list")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(
                id: blockID,
                kind: .bulletedListItem,
                text: "One\nTwo\nThree",
                lineIndentationLevels: [0, 2, 0]
            )
        ])

        let selection = document.outdentBlock(blockID: blockID, activeUTF16Offset: 5)

        XCTAssertEqual(document.blocks[0].lineIndentationLevels, [0, 1, 0])
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 5)))
    }

    func testOutdentNumberedLineContinuesPerLineSiblingSequence() {
        let targetID = BlockInputBlockID(rawValue: "target")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: "parent", kind: .numberedListItem(start: 1), text: "Parent"),
            BlockInputBlock(
                id: "previous-child",
                kind: .numberedListItem(start: 1),
                text: "Previous child",
                lineIndentationLevels: [1]
            ),
            BlockInputBlock(
                id: targetID,
                kind: .numberedListItem(start: 1),
                text: "Target",
                lineIndentationLevels: [2]
            )
        ])

        _ = document.outdentBlock(blockID: targetID, activeUTF16Offset: 3)

        XCTAssertEqual(document.blocks[2].kind, .numberedListItem(start: 2))
        XCTAssertEqual(document.blocks[2].lineIndentationLevels, [1])
    }

    func testIndentSingleLineWithPerLineIndentationKeepsLineOverride() {
        let targetID = BlockInputBlockID(rawValue: "target")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(
                id: targetID,
                kind: .bulletedListItem,
                text: "Target",
                lineIndentationLevels: [1]
            )
        ])

        _ = document.indentBlock(blockID: targetID, activeUTF16Offset: 3)

        XCTAssertEqual(document.blocks[0].indentationLevel, 0)
        XCTAssertEqual(document.blocks[0].lineIndentationLevels, [2])
    }

    func testIndentIgnoresNonListBlocks() {
        let blockID = BlockInputBlockID(rawValue: "quote")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .quote, text: "Quote")
        ])

        let selection = document.indentBlock(blockID: blockID)

        XCTAssertNil(selection)
        XCTAssertEqual(document.blocks[0].indentationLevel, 0)
    }

    func testIndentAndOutdentIgnoreRawMarkdownBlocks() {
        let blockID = BlockInputBlockID(rawValue: "raw")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .rawMarkdown, text: "| A |\n| - |")
        ])

        let indentSelection = document.indentBlock(blockID: blockID, activeUTF16Offset: 0)
        let outdentSelection = document.outdentBlock(blockID: blockID, activeUTF16Offset: 0)

        XCTAssertNil(indentSelection)
        XCTAssertNil(outdentSelection)
        XCTAssertEqual(document.blocks[0].kind, .rawMarkdown)
        XCTAssertEqual(document.blocks[0].indentationLevel, 0)
        XCTAssertEqual(document.blocks[0].lineIndentationLevels, [])
    }
}
