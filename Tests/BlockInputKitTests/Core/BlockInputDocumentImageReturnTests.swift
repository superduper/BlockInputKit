import XCTest
@testable import BlockInputKit

final class BlockInputDocumentImageReturnTests: XCTestCase {
    func testReturnBeforeImageMovesImageDownBelowEmptyParagraph() {
        let blockID = BlockInputBlockID(rawValue: "image")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .image(BlockInputImage(source: "https://example.com/image.png")))
        ])

        let selection = document.handleReturn(in: blockID, utf16Offset: 0)

        XCTAssertEqual(document.blocks.count, 2)
        XCTAssertEqual(document.blocks[0], BlockInputBlock(id: blockID, kind: .paragraph))
        XCTAssertEqual(document.blocks[1].kind, .image(BlockInputImage(source: "https://example.com/image.png")))
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))
    }

    func testReturnAfterImageInsertsEmptyParagraphBelowImage() {
        let blockID = BlockInputBlockID(rawValue: "image")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .image(BlockInputImage(source: "https://example.com/image.png")))
        ])

        let selection = document.handleReturn(in: blockID, utf16Offset: 1)

        XCTAssertEqual(document.blocks.count, 2)
        XCTAssertEqual(document.blocks[0].kind, .image(BlockInputImage(source: "https://example.com/image.png")))
        XCTAssertEqual(document.blocks[1].kind, .paragraph)
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[1].id, utf16Offset: 0)))
    }

    func testDeletingEmptyBlockAfterImageReturnsCaretAfterImage() {
        let imageID = BlockInputBlockID(rawValue: "image")
        let paragraphID = BlockInputBlockID(rawValue: "paragraph")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/image.png"))),
            BlockInputBlock(id: paragraphID, text: "")
        ])

        let selection = document.deleteEmptyBlockForBackspaceOrDelete(blockID: paragraphID)

        XCTAssertEqual(document.blocks.map(\.id), [imageID])
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: imageID, utf16Offset: 1)))
    }

    func testDeletingSelectedBlocksAfterImageReturnsCaretAfterImage() {
        let imageID = BlockInputBlockID(rawValue: "image")
        let firstDeletedID = BlockInputBlockID(rawValue: "first-deleted")
        let secondDeletedID = BlockInputBlockID(rawValue: "second-deleted")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/image.png"))),
            BlockInputBlock(id: firstDeletedID, text: "First"),
            BlockInputBlock(id: secondDeletedID, text: "Second")
        ])

        let selection = document.deleteBlocks(blockIDs: [firstDeletedID, secondDeletedID])

        XCTAssertEqual(document.blocks.map(\.id), [imageID])
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: imageID, utf16Offset: 1)))
    }
}
