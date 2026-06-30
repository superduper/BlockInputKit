import XCTest
@testable import BlockInputKit

/// Covers the code/quote/frontMatter Return ESCAPE threshold: Return inserts a newline normally
/// (including on a blank line) until the block already ends in two trailing blank lines AND the caret
/// is at the very end; only then does Return escape into a paragraph below, dropping the trailing
/// blanks. Empty-block exits and list behavior are covered by the existing Return test suites.
final class BlockInputReturnEscapeThresholdTests: XCTestCase {
    func testReturnInCodeBlockInsertsNewlineInsteadOfExiting() {
        let blockID = BlockInputBlockID(rawValue: "code")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .code(language: "swift"), text: "let value = 1")
        ])

        _ = document.handleReturn(in: blockID, utf16Offset: 13)

        XCTAssertEqual(document.blocks, [
            BlockInputBlock(id: blockID, kind: .code(language: "swift"), text: "let value = 1\n")
        ])
    }

    func testReturnOnSingleTrailingBlankLineAtEndAddsAnotherBlankLine() {
        // One trailing blank line is not yet the escape gesture; Return keeps inserting newlines.
        let blockID = BlockInputBlockID(rawValue: "code")
        let text = "code\n"
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .code(language: nil), text: text)
        ])

        let selection = document.handleReturn(in: blockID, utf16Offset: (text as NSString).length)

        XCTAssertEqual(document.blocks.count, 1)
        XCTAssertEqual(document.blocks[0].text, "code\n\n")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 6)))
    }

    func testReturnOnMiddleBlankLineNeverEscapes() {
        // A blank line in the MIDDLE of the block must never escape, even with surrounding blanks.
        let blockID = BlockInputBlockID(rawValue: "code")
        let text = "a\n\nb"
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .code(language: nil), text: text)
        ])

        let selection = document.handleReturn(in: blockID, utf16Offset: 2)

        XCTAssertEqual(document.blocks.count, 1)
        XCTAssertEqual(document.blocks[0].text, "a\n\n\nb")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 3)))
    }

    func testReturnEscapesAfterTwoTrailingBlankLinesAtEnd() {
        let blockID = BlockInputBlockID(rawValue: "code")
        let text = "let value = 1\n\n"
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .code(language: "swift"), text: text)
        ])

        let selection = document.handleReturn(in: blockID, utf16Offset: (text as NSString).length)

        XCTAssertEqual(document.blocks.count, 2)
        XCTAssertEqual(document.blocks[0], BlockInputBlock(id: blockID, kind: .code(language: "swift"), text: "let value = 1"))
        XCTAssertEqual(document.blocks[1].kind, .paragraph)
        XCTAssertEqual(document.blocks[1].text, "")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[1].id, utf16Offset: 0)))
    }

    func testTwoTrailingBlanksButCaretNotAtEndDoesNotEscape() {
        // The trailing blanks exist, but the caret sits before them, so Return still inserts a newline.
        let blockID = BlockInputBlockID(rawValue: "code")
        let text = "a\n\n"
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .code(language: nil), text: text)
        ])

        let selection = document.handleReturn(in: blockID, utf16Offset: 1)

        XCTAssertEqual(document.blocks.count, 1)
        XCTAssertEqual(document.blocks[0].text, "a\n\n\n")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 2)))
    }

    func testThreeConsecutiveReturnsAtEndOfCodeBlockExit() {
        // The user-facing contract: starting from non-blank content, the third Return escapes.
        let blockID = BlockInputBlockID(rawValue: "code")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .code(language: nil), text: "x")
        ])

        // First Return: x -> x\n (one trailing blank line).
        _ = document.handleReturn(in: blockID, utf16Offset: document.blocks[0].utf16Length)
        XCTAssertEqual(document.blocks.count, 1)
        XCTAssertEqual(document.blocks[0].text, "x\n")

        // Second Return: x\n -> x\n\n (two trailing blank lines).
        _ = document.handleReturn(in: blockID, utf16Offset: document.blocks[0].utf16Length)
        XCTAssertEqual(document.blocks.count, 1)
        XCTAssertEqual(document.blocks[0].text, "x\n\n")

        // Third Return: escape, trailing blanks dropped, caret in the new paragraph.
        let escapeSelection = document.handleReturn(in: blockID, utf16Offset: document.blocks[0].utf16Length)
        XCTAssertEqual(document.blocks.count, 2)
        XCTAssertEqual(document.blocks[0].text, "x")
        XCTAssertEqual(document.blocks[0].kind, .code(language: nil))
        XCTAssertEqual(document.blocks[1].kind, .paragraph)
        XCTAssertEqual(escapeSelection, .cursor(BlockInputCursor(blockID: document.blocks[1].id, utf16Offset: 0)))
    }

    func testQuoteReturnEscapesAfterTwoTrailingBlankLines() {
        let blockID = BlockInputBlockID(rawValue: "quote")
        let text = "Quoted\n\n"
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .quote, text: text)
        ])

        let selection = document.handleReturn(in: blockID, utf16Offset: (text as NSString).length)

        XCTAssertEqual(document.blocks.count, 2)
        XCTAssertEqual(document.blocks[0], BlockInputBlock(id: blockID, kind: .quote, text: "Quoted"))
        XCTAssertEqual(document.blocks[1].kind, .paragraph)
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[1].id, utf16Offset: 0)))
    }

    func testEscapePreservesInternalNewlinesAboveTrailingBlanks() {
        // The escape must drop only the two trailing blank lines, never an earlier real line break.
        let blockID = BlockInputBlockID(rawValue: "code")
        let text = "a\nb\n\n"
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .code(language: nil), text: text)
        ])

        let selection = document.handleReturn(in: blockID, utf16Offset: (text as NSString).length)

        XCTAssertEqual(document.blocks.count, 2)
        XCTAssertEqual(document.blocks[0].text, "a\nb")
        XCTAssertEqual(document.blocks[1].kind, .paragraph)
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[1].id, utf16Offset: 0)))
    }

    func testCarriageReturnLineFeedTrailingBlanksEscape() {
        // \r\n pairs each count as a single line ending when detecting the two-blank-line threshold.
        let blockID = BlockInputBlockID(rawValue: "code")
        let text = "code\r\n\r\n"
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .code(language: nil), text: text)
        ])

        let selection = document.handleReturn(in: blockID, utf16Offset: (text as NSString).length)

        XCTAssertEqual(document.blocks.count, 2)
        XCTAssertEqual(document.blocks[0].text, "code")
        XCTAssertEqual(document.blocks[1].kind, .paragraph)
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[1].id, utf16Offset: 0)))
    }
}
