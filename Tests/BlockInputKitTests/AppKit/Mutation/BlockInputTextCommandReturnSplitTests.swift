import AppKit
import XCTest
@testable import BlockInputKit

/// Mid-block Return splitting through the live NSTextView -> delegate path for paragraphs and headings.
@MainActor
final class BlockInputTextCommandReturnSplitTests: XCTestCase {
    func testReturnCommandMidParagraphSplitsTextThroughDelegatePath() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "HelloWorld")
            ]),
            undoController: undoController
        ))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(view.document.blocks.count, 2)
        XCTAssertEqual(view.document.blocks[0].id, blockID)
        XCTAssertEqual(view.document.blocks[0].text, "Hello")
        XCTAssertEqual(view.document.blocks[1].kind, .paragraph)
        XCTAssertEqual(view.document.blocks[1].text, "World")
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: view.document.blocks[1].id, utf16Offset: 0)))

        _ = view.undoStructuralEdit()

        XCTAssertEqual(view.document.blocks.count, 1)
        XCTAssertEqual(view.document.blocks[0].text, "HelloWorld")
    }

    func testReturnCommandMidHeadingSplitsIntoHeadingAndParagraphThroughDelegatePath() throws {
        let blockID = BlockInputBlockID(rawValue: "heading")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .heading(level: 1), text: "TitleRest")
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(view.document.blocks.count, 2)
        XCTAssertEqual(view.document.blocks[0].kind, .heading(level: 1))
        XCTAssertEqual(view.document.blocks[0].text, "Title")
        XCTAssertEqual(view.document.blocks[1].kind, .paragraph)
        XCTAssertEqual(view.document.blocks[1].text, "Rest")
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: view.document.blocks[1].id, utf16Offset: 0)))
    }
}
