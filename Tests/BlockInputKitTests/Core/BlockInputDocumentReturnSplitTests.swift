import XCTest
@testable import BlockInputKit

/// Mid-block Return splitting for paragraphs and headings: text before the caret stays in the current
/// block, text after it moves into a new paragraph below (a non-empty selection is consumed).
final class BlockInputDocumentReturnSplitTests: XCTestCase {
    func testReturnMidParagraphSplitsTextAtCaret() {
        let firstID = BlockInputBlockID(rawValue: "first")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "HelloWorld")
        ])

        let selection = document.handleReturn(in: firstID, utf16Offset: 5)

        XCTAssertEqual(document.blocks.count, 2)
        XCTAssertEqual(document.blocks[0].text, "Hello")
        XCTAssertEqual(document.blocks[1].kind, .paragraph)
        XCTAssertEqual(document.blocks[1].text, "World")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[1].id, utf16Offset: 0)))
    }

    func testReturnMidHeadingSplitsIntoHeadingAndParagraph() {
        let headingID = BlockInputBlockID(rawValue: "heading")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: headingID, kind: .heading(level: 2), text: "TitleRest")
        ])

        let selection = document.handleReturn(in: headingID, utf16Offset: 5)

        XCTAssertEqual(document.blocks.count, 2)
        XCTAssertEqual(document.blocks[0].kind, .heading(level: 2))
        XCTAssertEqual(document.blocks[0].text, "Title")
        XCTAssertEqual(document.blocks[1].kind, .paragraph)
        XCTAssertEqual(document.blocks[1].text, "Rest")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[1].id, utf16Offset: 0)))
    }

    func testReturnWithSelectionConsumesSelectedTextWhenSplitting() {
        let firstID = BlockInputBlockID(rawValue: "first")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "HelloXXXWorld")
        ])

        // Caret at 5, selecting the "XXX" (length 3): the selection is consumed by the break.
        let selection = document.handleReturn(in: firstID, utf16Offset: 5, selectedUTF16Length: 3)

        XCTAssertEqual(document.blocks[0].text, "Hello")
        XCTAssertEqual(document.blocks[1].text, "World")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[1].id, utf16Offset: 0)))
    }

    func testReturnAtEndOfParagraphInsertsEmptyParagraph() {
        // Regression guard: end-of-block Return still appends an empty paragraph (suffix is empty).
        let firstID = BlockInputBlockID(rawValue: "first")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "Hello")
        ])

        let selection = document.handleReturn(in: firstID, utf16Offset: 5)

        XCTAssertEqual(document.blocks.count, 2)
        XCTAssertEqual(document.blocks[0].text, "Hello")
        XCTAssertEqual(document.blocks[1].text, "")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[1].id, utf16Offset: 0)))
    }
}
