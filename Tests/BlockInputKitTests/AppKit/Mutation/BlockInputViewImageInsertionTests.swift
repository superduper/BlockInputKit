import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewImageInsertionTests: XCTestCase {
    func testInsertImageContextSplitsTextBlockIntoBeforeImageAndAfterBlocks() throws {
        let blockID = BlockInputBlockID(rawValue: "paragraph")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Before after")
        ])))
        let context = BlockInputImageContext(
            blockID: blockID,
            selectedRange: NSRange(location: 7, length: 0),
            sourceText: "Before after",
            anchorWindowRect: .zero
        )

        view.insertImage(BlockInputImage(source: "https://example.com/image.png", altText: "Alt"), context: context)

        XCTAssertEqual(view.document.blocks.map(\.text), ["Before ", "", "after"])
        XCTAssertEqual(view.document.blocks[0].id, blockID)
        XCTAssertEqual(view.document.blocks[1].kind, .image(BlockInputImage(source: "https://example.com/image.png", altText: "Alt")))
        XCTAssertEqual(view.document.blocks[2].kind, .paragraph)
        XCTAssertEqual(view.selection, .blocks([view.document.blocks[1].id]))
    }

    func testInsertImageContextAddsImageBelowUnsupportedBlock() {
        let blockID = BlockInputBlockID(rawValue: "code")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .code(language: "swift"), text: "let value = 1")
        ])))
        let context = BlockInputImageContext(
            blockID: blockID,
            selectedRange: NSRange(location: 4, length: 0),
            sourceText: "let value = 1",
            anchorWindowRect: .zero
        )

        view.insertImage(BlockInputImage(source: "https://example.com/image.png"), context: context)

        XCTAssertEqual(view.document.blocks[0].kind, .code(language: "swift"))
        XCTAssertEqual(view.document.blocks[1].kind, .image(BlockInputImage(source: "https://example.com/image.png")))
    }

    func testImageFileDropInsertsImageBlockBelowTextBlockInsteadOfInlineFileChip() throws {
        let blockID = BlockInputBlockID(rawValue: "paragraph")
        let imageURL = temporaryImageURL()
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Before after")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        _ = mounted.view.blockItem(item, blockID: blockID, didRequestInsertFileURLs: [imageURL], atUTF16Offset: 6)

        XCTAssertEqual(mounted.view.document.blocks.count, 2)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Before after")
        XCTAssertEqual(
            mounted.view.document.blocks[1].kind,
            .image(BlockInputImage(source: imageURL.absoluteString, altText: "dropped"))
        )
    }

    func testImageContextMenuProvidesInsertAndDeleteActions() throws {
        let paragraphID = BlockInputBlockID(rawValue: "paragraph")
        let imageID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: paragraphID, text: "Paragraph"),
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/image.png")))
        ])
        _ = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        _ = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let event = try mouseDownEvent(windowNumber: mounted.window.windowNumber)

        let insertItems = mounted.view.imageContextMenuItems(blockID: paragraphID, selectedRange: NSRange(location: 4, length: 0), event: event)
        let editorItems = mounted.view.linkContextMenuItems(blockID: paragraphID, selectedRange: NSRange(location: 4, length: 0), event: event)
        let deleteItems = mounted.view.imageContextMenuItems(blockID: imageID, selectedRange: NSRange(location: 0, length: 0), event: event)

        XCTAssertEqual(insertItems.map(\.title), ["Insert Image"])
        XCTAssertEqual(editorItems.map(\.title), ["Insert Link", "Insert Image", "Insert Table"])
        XCTAssertEqual(deleteItems.map(\.title), ["Delete Image"])
    }

    func testImageModalValidatesURLBeforeInsert() {
        let modal = BlockInputImageModalView()

        modal.configure(urlString: "not a url", altText: "Alt")
        XCTAssertFalse(modal.insertButton.isEnabled)

        modal.configure(urlString: "https://example.com/image.png", altText: "Alt")
        XCTAssertTrue(modal.insertButton.isEnabled)
        XCTAssertEqual(modal.frame.size, NSSize(width: 300, height: 148))
    }

    func testResizingImagePersistsDimensionsAndExportsAsHTML() throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/image.png", width: 320, height: 180)))
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        mounted.view.blockItem(item, blockID: imageID, didResizeImageToWidth: 400, height: 225)

        XCTAssertEqual(
            mounted.view.document.blocks[0].kind,
            .image(BlockInputImage(source: "https://example.com/image.png", width: 400, height: 225, sourceStyle: .html))
        )
        XCTAssertEqual(
            mounted.view.document.markdown,
            "<img src=\"https://example.com/image.png\" width=\"400\" height=\"225\" />"
        )
    }

    private func temporaryImageURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("dropped")
            .appendingPathExtension("png")
    }
}
