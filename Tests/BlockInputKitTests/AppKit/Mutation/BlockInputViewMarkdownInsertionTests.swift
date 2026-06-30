import Foundation
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewMarkdownInsertionTests: XCTestCase {
    func testInsertMarkdownBelowActiveBlockPublishesAndRegistersUndo() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        var publishedDocument: BlockInputDocument?
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: firstID, text: "First"),
                BlockInputBlock(id: secondID, text: "Second")
            ]),
            undoController: undoController,
            onDocumentChange: { publishedDocument = $0 }
        ))
        view.focus(blockID: firstID, utf16Offset: 5)

        let selection = view.insertMarkdown("""
        > Inserted quote

        - Inserted bullet
        """)

        XCTAssertEqual(view.document.blocks.count, 4)
        XCTAssertEqual(view.document.blocks.map(\.id).first, firstID)
        XCTAssertEqual(view.document.blocks.map(\.id).last, secondID)
        XCTAssertEqual(view.document.blocks[1].kind, .quote)
        XCTAssertEqual(view.document.blocks[1].text, "Inserted quote")
        XCTAssertEqual(view.document.blocks[2].kind, .bulletedListItem)
        XCTAssertEqual(view.document.blocks[2].text, "Inserted bullet")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: view.document.blocks[1].id, utf16Offset: 0)))
        XCTAssertEqual(publishedDocument, view.document)

        let undo = view.undoStructuralEdit()

        XCTAssertEqual(undo?.actionName, "Insert Markdown")
        XCTAssertEqual(view.document.blocks.map(\.id), [firstID, secondID])
    }

    func testInsertMarkdownReplacesDefaultEmptyParagraph() {
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        var publishedDocument: BlockInputDocument?
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(),
            undoController: undoController,
            onDocumentChange: { publishedDocument = $0 }
        ))

        let selection = view.insertMarkdown("Inserted")

        XCTAssertEqual(view.document.blocks.count, 1)
        XCTAssertEqual(view.document.blocks[0].text, "Inserted")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: view.document.blocks[0].id, utf16Offset: 0)))
        XCTAssertEqual(publishedDocument, view.document)

        let undo = view.undoStructuralEdit()

        XCTAssertEqual(undo?.actionName, "Insert Markdown")
        XCTAssertEqual(view.document.blocks.count, 1)
        XCTAssertEqual(view.document.blocks[0].kind, .paragraph)
        XCTAssertEqual(view.document.blocks[0].text, "")
    }

    func testInsertMarkdownKeepsFrontMatterWhenReplacingDefaultEmptyParagraph() {
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument()))

        let selection = view.insertMarkdown("""
        ---
        title: Demo
        ---
        Body
        """)

        XCTAssertEqual(view.document.blocks.map(\.kind), [.frontMatter, .paragraph])
        XCTAssertEqual(view.document.blocks[0].text, "title: Demo")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: view.document.blocks[0].id, utf16Offset: 0)))
    }

    func testInsertMarkdownParsesTableBlocks() {
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument()))

        let selection = view.insertMarkdown("""
        | First | Second |
        | --- | --- |
        | One | Two |
        """)

        XCTAssertEqual(view.document.blocks.map(\.kind), [.table])
        XCTAssertEqual(view.document.blocks[0].text, """
        | First | Second |
        | ---   | ---    |
        | One   | Two    |
        """)
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: view.document.blocks[0].id, utf16Offset: 0)))
    }

    func testInsertMarkdownBelowExplicitBlockIgnoresActiveBlock() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ])))
        view.focus(blockID: firstID, utf16Offset: 5)

        let selection = view.insertMarkdown("Inserted", below: secondID)

        XCTAssertEqual(view.document.blocks.count, 4)
        let insertedID = view.document.blocks[2].id
        XCTAssertNotEqual(insertedID, firstID)
        XCTAssertNotEqual(insertedID, secondID)
        XCTAssertNotEqual(insertedID, thirdID)
        XCTAssertEqual(view.document.blocks.map(\.id), [firstID, secondID, insertedID, thirdID])
        XCTAssertEqual(view.document.blocks[2].text, "Inserted")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: insertedID, utf16Offset: 0)))
    }

    func testInsertMarkdownWithoutSelectionUsesDefaultActiveBlock() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])))

        let selection = view.insertMarkdown("Inserted")

        XCTAssertEqual(view.document.blocks.count, 3)
        let insertedID = view.document.blocks[1].id
        XCTAssertEqual(view.document.blocks.map(\.id), [firstID, insertedID, secondID])
        XCTAssertEqual(view.document.blocks[1].text, "Inserted")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: insertedID, utf16Offset: 0)))
    }

    func testInsertMarkdownWithExplicitMissingBlockDoesNothing() {
        let blockID = BlockInputBlockID(rawValue: "first")
        let view = BlockInputView()
        var publishCount = 0
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "First")
            ]),
            onDocumentChange: { _ in publishCount += 1 }
        ))

        let selection = view.insertMarkdown("Inserted", below: "missing")

        XCTAssertNil(selection)
        XCTAssertEqual(publishCount, 0)
        XCTAssertEqual(view.document.blocks.map(\.id), [blockID])
    }

    func testInsertMarkdownWithExplicitMissingBlockDoesNotReplaceDefaultEmptyParagraph() {
        let view = BlockInputView()
        var publishCount = 0
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(),
            onDocumentChange: { _ in publishCount += 1 }
        ))
        let originalDocument = view.document

        let selection = view.insertMarkdown("Inserted", below: "missing")

        XCTAssertNil(selection)
        XCTAssertEqual(publishCount, 0)
        XCTAssertEqual(view.document, originalDocument)
    }

    func testInsertMarkdownIgnoresWhitespaceOnlyInput() {
        let blockID = BlockInputBlockID(rawValue: "first")
        let view = BlockInputView()
        var publishCount = 0
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "First")
            ]),
            onDocumentChange: { _ in publishCount += 1 }
        ))

        let selection = view.insertMarkdown(" \n\t ")

        XCTAssertNil(selection)
        XCTAssertEqual(publishCount, 0)
        XCTAssertEqual(view.document.blocks.map(\.id), [blockID])
    }
}
