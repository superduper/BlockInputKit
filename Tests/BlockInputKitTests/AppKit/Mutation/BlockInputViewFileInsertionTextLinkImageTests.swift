import Foundation
import XCTest
@testable import BlockInputKit

@MainActor
final class TextLinkImageInsertionTests: XCTestCase {
    func testInsertLocalFileURLsInsertsMultipleImagesInlineIntoActiveListItem() {
        let blockID = BlockInputBlockID(rawValue: "item")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, kind: .numberedListItem(start: 2), text: "Attach ")
            ]),
            imagePresentation: .textLinksWithPreviewStrip,
            undoController: undoController
        ))
        view.focus(blockID: blockID, utf16Offset: 7)

        let selection = view.insertLocalFileURLs([
            URL(fileURLWithPath: "/tmp/First Photo.png"),
            URL(fileURLWithPath: "/tmp/Second Photo.jpg")
        ])

        let expectedText = "Attach ![First Photo](file:///tmp/First%20Photo.png) ![Second Photo](file:///tmp/Second%20Photo.jpg) "
        XCTAssertEqual(view.document.blocks.count, 1)
        XCTAssertEqual(view.document.blocks[0].kind, .numberedListItem(start: 2))
        XCTAssertEqual(view.document.blocks[0].text, expectedText)
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: (expectedText as NSString).length)))
        XCTAssertEqual(view.imagePreviewStripView.itemCountForTesting, 2)

        let undo = view.undoStructuralEdit()

        XCTAssertEqual(undo?.actionName, "Insert Images")
        XCTAssertEqual(view.document.blocks[0].text, "Attach ")
    }

    func testInsertLocalFileURLsKeepsMultipleFallbackImagesInOneBlock() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: firstID, text: "First"),
                BlockInputBlock(id: secondID, text: "Second")
            ]),
            imagePresentation: .textLinksWithPreviewStrip,
            undoController: undoController
        ))

        let selection = view.insertLocalFileURLs([
            URL(fileURLWithPath: "/tmp/First Photo.png"),
            URL(fileURLWithPath: "/tmp/Second Photo.jpg")
        ], below: firstID)

        let expectedText = "![First Photo](file:///tmp/First%20Photo.png) ![Second Photo](file:///tmp/Second%20Photo.jpg) "
        XCTAssertEqual(view.document.blocks.count, 3)
        XCTAssertEqual(view.document.blocks.map(\.id).first, firstID)
        XCTAssertEqual(view.document.blocks.map(\.id).last, secondID)
        XCTAssertEqual(view.document.blocks[1].text, expectedText)
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: view.document.blocks[1].id, utf16Offset: 0)))
        XCTAssertEqual(view.imagePreviewStripView.itemCountForTesting, 2)

        let undo = view.undoStructuralEdit()

        XCTAssertEqual(undo?.actionName, "Insert Images")
        XCTAssertEqual(view.document.blocks.map(\.id), [firstID, secondID])
    }
}
