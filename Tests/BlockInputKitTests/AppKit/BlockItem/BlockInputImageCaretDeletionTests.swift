import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputImageCaretDeletionTests: XCTestCase {
    func testDeleteAtAfterImageCaretDeletesImageBlock() throws {
        let paragraphID = BlockInputBlockID(rawValue: "paragraph")
        let imageID = BlockInputBlockID(rawValue: "image")
        let trailingID = BlockInputBlockID(rawValue: "trailing")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: paragraphID, text: "Above"),
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/image.png"))),
            BlockInputBlock(id: trailingID, text: "Below")
        ])
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: imageID, utf16Offset: 1)), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        mounted.view.keyDown(with: try keyDownEvent(keyCode: 117, characters: "\u{F728}"))

        XCTAssertEqual(mounted.view.document.blocks.map(\.id), [paragraphID, trailingID])
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: paragraphID, utf16Offset: 5)))
        XCTAssertEqual(mounted.window.firstResponder, mounted.view.visibleBlockItemForTesting(at: 0)?.testingTextView)
    }

    func testBackspaceAtAfterImageCaretCanBeUndone() throws {
        let paragraphID = BlockInputBlockID(rawValue: "paragraph")
        let imageID = BlockInputBlockID(rawValue: "image")
        let undoController = BlockInputUndoController()
        let mounted = makeMountedBlockInputView(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: paragraphID, text: "Above"),
                BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/image.png")))
            ]),
            undoController: undoController
        )
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: imageID, utf16Offset: 1)), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        mounted.view.keyDown(with: try keyDownEvent(keyCode: 51, characters: "\u{7F}"))
        let undo = mounted.view.undoStructuralEdit()

        XCTAssertEqual(undo?.actionName, "Delete Block")
        XCTAssertEqual(mounted.view.document.blocks.map(\.id), [paragraphID, imageID])
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: imageID, utf16Offset: 1)))
        XCTAssertEqual(mounted.view.visibleBlockItemForTesting(at: 1)?.testingImageCaretView.accessibilityLabel(), "After image")
    }

    func testDeleteAtAfterDuplicateImageCaretDeletesActiveRow() throws {
        let sharedID = BlockInputBlockID(rawValue: "shared")
        let middleID = BlockInputBlockID(rawValue: "middle")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: sharedID, kind: .image(BlockInputImage(source: "https://example.com/first.png", width: 120, height: 80))),
            BlockInputBlock(id: middleID, text: "Middle"),
            BlockInputBlock(id: sharedID, kind: .image(BlockInputImage(source: "https://example.com/second.png", width: 120, height: 80)))
        ])
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        secondItem.requestImageCaret(at: 1)

        mounted.view.keyDown(with: try keyDownEvent(keyCode: 117, characters: "\u{F728}"))

        XCTAssertEqual(mounted.view.document.blocks.map(\.id), [sharedID, middleID])
        XCTAssertEqual(mounted.view.document.blocks.map(\.kind), [
            .image(BlockInputImage(source: "https://example.com/first.png", width: 120, height: 80)),
            .paragraph
        ])
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: middleID, utf16Offset: 6)))
    }

    func testStoreBackedDeleteAtAfterImageCaretPublishesGranularDeletionForUniqueID() throws {
        let paragraphID = BlockInputBlockID(rawValue: "paragraph")
        let imageID = BlockInputBlockID(rawValue: "image")
        let trailingID = BlockInputBlockID(rawValue: "trailing")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: paragraphID, text: "Above"),
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/image.png"))),
            BlockInputBlock(id: trailingID, text: "Below")
        ]))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store))
        view.applySelection(.cursor(BlockInputCursor(blockID: imageID, utf16Offset: 1)), notify: false)
        store.resetCounts()

        view.keyDown(with: try keyDownEvent(keyCode: 51, characters: "\u{7F}"))

        XCTAssertEqual(store.deletedBlockIDs, [[imageID]])
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.document.blocks.map(\.id), [paragraphID, trailingID])
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: paragraphID, utf16Offset: 5)))
    }
}
