import Foundation
import XCTest
@testable import BlockInputKit

final class BlockInputDocumentMergeTests: XCTestCase {
    func testMergeParagraphIntoPreviousEmptyNumberedListItem() {
        let listID = BlockInputBlockID(rawValue: "list")
        let paragraphID = BlockInputBlockID(rawValue: "paragraph")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: listID, kind: .numberedListItem(start: 1)),
            BlockInputBlock(id: paragraphID, text: "Toggle reordering from the toolbar")
        ])

        let selection = document.mergeBlockIntoPrevious(blockID: paragraphID)

        XCTAssertEqual(document.blocks.map(\.id), [listID])
        XCTAssertEqual(document.blocks[0].kind, .numberedListItem(start: 1))
        XCTAssertEqual(document.blocks[0].text, "Toggle reordering from the toolbar")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: listID, utf16Offset: 0)))
    }

    func testMergeParagraphIntoPreviousTextBlockKeepsJoinPointSelection() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])

        let selection = document.mergeBlockIntoPrevious(blockID: secondID)

        XCTAssertEqual(document.blocks.map(\.text), ["FirstSecond"])
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 5)))
    }

    func testMergeBlockIntoPreviousIgnoresFormattedCurrentBlock() {
        let listID = BlockInputBlockID(rawValue: "list")
        let quoteID = BlockInputBlockID(rawValue: "quote")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: listID, kind: .numberedListItem(start: 1)),
            BlockInputBlock(id: quoteID, kind: .quote, text: "Quote")
        ])

        let selection = document.mergeBlockIntoPrevious(blockID: quoteID)

        XCTAssertNil(selection)
        XCTAssertEqual(document.blocks.map(\.id), [listID, quoteID])
    }

    func testMergeParagraphIntoPreviousImageIsIgnored() {
        let imageID = BlockInputBlockID(rawValue: "image")
        let paragraphID = BlockInputBlockID(rawValue: "paragraph")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/image.png"))),
            BlockInputBlock(id: paragraphID, text: "")
        ])

        let selection = document.mergeBlockIntoPrevious(blockID: paragraphID)

        XCTAssertNil(selection)
        XCTAssertEqual(document.blocks.map(\.id), [imageID, paragraphID])
    }
}
