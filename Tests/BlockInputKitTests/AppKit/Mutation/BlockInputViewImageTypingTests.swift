import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewImageTypingTests: XCTestCase {
    func testTypingMarkdownImageAsEntireParagraphConvertsBlockAndSelectsImage() {
        let blockID = BlockInputBlockID(rawValue: "block")
        let imageURL = "https://af.codes/images/portfolio/streettriple.jpg"
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "")
        ])))

        let selection = view.applyTypingShortcutIfNeeded(
            blockID: blockID,
            proposedText: "![bike](\(imageURL))",
            proposedUTF16Offset: ("![bike](\(imageURL))" as NSString).length,
            selectionBefore: .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0))
        )

        XCTAssertEqual(view.document.blocks.count, 1)
        XCTAssertEqual(
            view.document.blocks[0].kind,
            .image(BlockInputImage(source: imageURL, altText: "bike"))
        )
        XCTAssertEqual(view.document.blocks[0].text, "")
        XCTAssertEqual(selection, .blocks([blockID]))
    }

    func testTypingMarkdownImageInParagraphSplitsBlockAndSelectsImage() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Before")
        ])))

        let selection = view.applyTypingShortcutIfNeeded(
            blockID: blockID,
            proposedText: "Before ![Alt](image.png) after",
            proposedUTF16Offset: 30,
            selectionBefore: .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 6))
        )

        XCTAssertEqual(view.document.blocks.map(\.kind), [
            .paragraph,
            .image(BlockInputImage(source: "image.png", altText: "Alt")),
            .paragraph
        ])
        XCTAssertEqual(view.document.blocks.map(\.text), ["Before", "", "after"])
        XCTAssertEqual(selection, .blocks([view.document.blocks[1].id]))
    }

    func testTextLinkImagePresentationSuppressesTypingImageBlockConversion() {
        let blockID = BlockInputBlockID(rawValue: "block")
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Before")
        ])
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: document,
            imagePresentation: .textLinksWithPreviewStrip
        ))

        let selection = view.applyTypingShortcutIfNeeded(
            blockID: blockID,
            proposedText: "Before ![Alt](image.png) after",
            proposedUTF16Offset: 30,
            selectionBefore: .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 6))
        )

        XCTAssertNil(selection)
        XCTAssertEqual(view.document, document)
    }

    func testStoreBackedTypingMarkdownImageUsesGranularReplacementAndInsertion() {
        let blockID = BlockInputBlockID(rawValue: "block")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Before")
        ]))
        var mutations: [BlockInputDocumentChange] = []
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            documentStore: store,
            onDocumentMutation: { mutations.append($0) }
        ))
        store.resetCounts()

        _ = view.applyTypingShortcutIfNeeded(
            blockID: blockID,
            proposedText: "Before ![Alt](image.png) after",
            proposedUTF16Offset: 30,
            selectionBefore: nil
        )

        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replaceBlockIDs, [blockID])
        XCTAssertEqual(store.insertedBlockBatches.count, 1)
        XCTAssertEqual(store.insertedBlockBatches[0].index, 1)
        XCTAssertEqual(mutations.count, 2)
        XCTAssertEqual(store.document.blocks.map(\.kind), view.document.blocks.map(\.kind))
    }
}
