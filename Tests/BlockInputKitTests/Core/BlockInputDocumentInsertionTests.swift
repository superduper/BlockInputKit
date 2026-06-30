import Foundation
import XCTest
@testable import BlockInputKit

final class BlockInputDocumentInsertionTests: XCTestCase {
    func testInsertBlockAtStartKeepsLeadingFrontMatterPinned() {
        let frontID = BlockInputBlockID(rawValue: "front")
        let insertedID = BlockInputBlockID(rawValue: "inserted")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: frontID, kind: .frontMatter, text: "title: Demo"),
            BlockInputBlock(id: "body", text: "Body")
        ])

        let selection = document.insertBlock(BlockInputBlock(id: insertedID, text: "Inserted"), at: 0)

        XCTAssertEqual(document.blocks.map(\.id), [frontID, insertedID, "body"])
        XCTAssertEqual(document.blocks.map(\.kind), [.frontMatter, .paragraph, .paragraph])
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: insertedID, utf16Offset: 0)))
    }

    func testInsertBlocksAtStartKeepsLeadingFrontMatterPinned() {
        let frontID = BlockInputBlockID(rawValue: "front")
        let firstInsertedID = BlockInputBlockID(rawValue: "first-inserted")
        let secondInsertedID = BlockInputBlockID(rawValue: "second-inserted")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: frontID, kind: .frontMatter, text: "title: Demo"),
            BlockInputBlock(id: "body", text: "Body")
        ])

        let selection = document.insertBlocks([
            BlockInputBlock(id: firstInsertedID, text: "First"),
            BlockInputBlock(id: secondInsertedID, text: "Second")
        ], at: 0)

        XCTAssertEqual(document.blocks.map(\.id), [frontID, firstInsertedID, secondInsertedID, "body"])
        XCTAssertEqual(document.blocks.map(\.kind), [.frontMatter, .paragraph, .paragraph, .paragraph])
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: firstInsertedID, utf16Offset: 0)))
    }

    func testInsertBlocksClampsIndexAndFocusesFirstInsertedBlock() {
        let existingID = BlockInputBlockID(rawValue: "existing")
        let firstInsertedID = BlockInputBlockID(rawValue: "first-inserted")
        let secondInsertedID = BlockInputBlockID(rawValue: "second-inserted")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: existingID, text: "Existing")
        ])

        let selection = document.insertBlocks([
            BlockInputBlock(id: firstInsertedID, kind: .quote, text: "First"),
            BlockInputBlock(id: secondInsertedID, kind: .code(language: "swift"), text: "Second")
        ], at: -100)

        XCTAssertEqual(document.blocks.map(\.id), [firstInsertedID, secondInsertedID, existingID])
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: firstInsertedID, utf16Offset: 0)))
    }

    func testInsertBlocksClampsPastEndIndex() {
        let existingID = BlockInputBlockID(rawValue: "existing")
        let insertedID = BlockInputBlockID(rawValue: "inserted")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: existingID, text: "Existing")
        ])

        let selection = document.insertBlocks([
            BlockInputBlock(id: insertedID, text: "Inserted")
        ], at: 100)

        XCTAssertEqual(document.blocks.map(\.id), [existingID, insertedID])
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: insertedID, utf16Offset: 0)))
    }

    func testInsertBlocksIgnoresEmptyInput() {
        let existingID = BlockInputBlockID(rawValue: "existing")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: existingID, text: "Existing")
        ])

        let selection = document.insertBlocks([], at: 0)

        XCTAssertNil(selection)
        XCTAssertEqual(document.blocks.map(\.id), [existingID])
    }
}
