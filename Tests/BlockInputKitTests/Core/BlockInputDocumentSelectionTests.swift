import Foundation
import XCTest
@testable import BlockInputKit

final class BlockInputDocumentSelectionTests: XCTestCase {
    func testSelectAllEscalatesFromCurrentBlockToAllBlocks() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "Hello"),
            BlockInputBlock(id: secondID, text: "World")
        ])

        let firstSelection = document.selectAll(currentBlockID: firstID, currentSelection: nil)
        let secondSelection = document.selectAll(currentBlockID: firstID, currentSelection: firstSelection)

        XCTAssertEqual(firstSelection, .text(BlockInputTextRange(
            blockID: firstID,
            range: NSRange(location: 0, length: 5)
        )))
        XCTAssertEqual(secondSelection, .blocks([firstID, secondID]))
    }

    func testSelectAllKeepsAllBlocksSelectedWhenAlreadyEscalated() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "Hello"),
            BlockInputBlock(id: secondID, text: "World")
        ])

        let selection = document.selectAll(
            currentBlockID: firstID,
            currentSelection: .blocks([firstID, secondID])
        )

        XCTAssertEqual(selection, .blocks([firstID, secondID]))
    }

    func testSelectAllPromotesEmptyCurrentBlockToAllBlocks() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: ""),
            BlockInputBlock(id: secondID, text: "World")
        ])

        let selection = document.selectAll(currentBlockID: firstID, currentSelection: nil)

        XCTAssertEqual(selection, .blocks([firstID, secondID]))
    }

    func testSelectAllDocumentBehaviorSelectsAllBlocksImmediately() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "Hello"),
            BlockInputBlock(id: secondID, text: "World")
        ])

        let selection = document.selectAll(
            currentBlockID: firstID,
            currentSelection: nil,
            behavior: .document
        )

        XCTAssertEqual(selection, .blocks([firstID, secondID]))
    }

    func testSelectAllEscalatesSelectedHorizontalRuleToAllBlocks() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let ruleID = BlockInputBlockID(rawValue: "rule")
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "Hello"),
            BlockInputBlock(id: ruleID, kind: .horizontalRule)
        ])

        let selection = document.selectAll(
            currentBlockID: ruleID,
            currentSelection: .blocks([ruleID])
        )

        XCTAssertEqual(selection, .blocks([firstID, ruleID]))
    }
}
