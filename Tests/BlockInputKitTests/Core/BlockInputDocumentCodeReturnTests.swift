import XCTest
@testable import BlockInputKit

final class BlockInputDocumentCodeReturnTests: XCTestCase {
    func testReturnConvertsParagraphCodeFenceToCodeBlock() {
        let blockID = BlockInputBlockID(rawValue: "code")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "``` swift")
        ])

        let selection = document.handleReturn(in: blockID, utf16Offset: 9)

        XCTAssertEqual(document.blocks, [
            BlockInputBlock(id: blockID, kind: .code(language: "swift"))
        ])
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))
    }

    func testReturnConvertsParagraphCodeFenceWithoutLanguageToCodeBlock() {
        let blockID = BlockInputBlockID(rawValue: "code")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "```")
        ])

        _ = document.handleReturn(in: blockID, utf16Offset: 3)

        XCTAssertEqual(document.blocks, [
            BlockInputBlock(id: blockID, kind: .code(language: nil))
        ])
    }

    func testReturnDoesNotConvertCodeFenceWhenCaretIsNotAtEnd() {
        let blockID = BlockInputBlockID(rawValue: "code")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "``` swift")
        ])
        _ = document.handleReturn(in: blockID, utf16Offset: 3)

        XCTAssertEqual(document.blocks.count, 2)
        XCTAssertEqual(document.blocks[0].kind, .paragraph)
        XCTAssertEqual(document.blocks[0].text, "```")
        XCTAssertEqual(document.blocks[1].kind, .paragraph)
        XCTAssertEqual(document.blocks[1].text, " swift")
    }

    func testReturnDoesNotConvertCodeFenceWhenSelectionIsNotCollapsed() {
        let blockID = BlockInputBlockID(rawValue: "code")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "``` swift")
        ])

        _ = document.handleReturn(in: blockID, utf16Offset: 0, selectedUTF16Length: 9)

        XCTAssertEqual(document.blocks.count, 2)
        XCTAssertEqual(document.blocks[0].kind, .paragraph)
        XCTAssertEqual(document.blocks[0].text, "")
        XCTAssertEqual(document.blocks[1].kind, .paragraph)
        XCTAssertEqual(document.blocks[1].text, "")
    }

    func testReturnInEmptyCodeBlockExitsToParagraphAtSamePosition() {
        let blockID = BlockInputBlockID(rawValue: "code")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .code(language: "swift"))
        ])

        let selection = document.handleReturn(in: blockID)

        XCTAssertEqual(document.blocks, [BlockInputBlock(id: blockID, kind: .paragraph)])
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))
    }
}
