import XCTest
@testable import BlockInputKit

/// Mid-block Return splitting that lands INSIDE an open inline-markdown span: both halves must stay valid
/// Markdown (the span is closed at the prefix end and reopened at the suffix start), and the caret lands
/// after the reopened opening delimiters so the user keeps typing inside the span.
final class BlockInputDocumentReturnSplitMarkupTests: XCTestCase {
    func testSplitInsideBoldClosesAndReopens() {
        let id = BlockInputBlockID(rawValue: "b")
        var document = BlockInputDocument(blocks: [BlockInputBlock(id: id, text: "**bold text**")])

        // Caret inside content: "**bold| text**" -> offset 6.
        let selection = document.handleReturn(in: id, utf16Offset: 6)

        XCTAssertEqual(document.blocks[0].text, "**bold**")
        XCTAssertEqual(document.blocks[1].text, "** text**")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[1].id, utf16Offset: 2)))
    }

    func testSplitInsideInlineCodeClosesAndReopens() {
        let id = BlockInputBlockID(rawValue: "c")
        var document = BlockInputDocument(blocks: [BlockInputBlock(id: id, text: "`abcd`")])

        let selection = document.handleReturn(in: id, utf16Offset: 3)

        XCTAssertEqual(document.blocks[0].text, "`ab`")
        XCTAssertEqual(document.blocks[1].text, "`cd`")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[1].id, utf16Offset: 1)))
    }

    func testSplitOnDelimiterBoundaryDoesNotRewrap() {
        let id = BlockInputBlockID(rawValue: "d")
        var document = BlockInputDocument(blocks: [BlockInputBlock(id: id, text: "**bold**rest")])

        // Caret at offset 8 == end of the closing `**`, i.e. just after the span (not inside content).
        let selection = document.handleReturn(in: id, utf16Offset: 8)

        XCTAssertEqual(document.blocks[0].text, "**bold**")
        XCTAssertEqual(document.blocks[1].text, "rest")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[1].id, utf16Offset: 0)))
    }

    func testSplitAtContentStartBoundaryDoesNotRewrap() {
        let id = BlockInputBlockID(rawValue: "e")
        var document = BlockInputDocument(blocks: [BlockInputBlock(id: id, text: "**bold**")])

        // Caret at offset 2 == start of content (boundary, not strictly inside) -> no rewrap.
        let selection = document.handleReturn(in: id, utf16Offset: 2)

        XCTAssertEqual(document.blocks[0].text, "**")
        XCTAssertEqual(document.blocks[1].text, "bold**")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[1].id, utf16Offset: 0)))
    }

    func testSpanFullyBeforeCaretIsUntouched() {
        let id = BlockInputBlockID(rawValue: "f")
        var document = BlockInputDocument(blocks: [BlockInputBlock(id: id, text: "**bold** plain text")])

        // Caret at offset 12 ("**bold** pla|in text"): the bold span ends well before it, so no rewrap.
        let selection = document.handleReturn(in: id, utf16Offset: 12)

        XCTAssertEqual(document.blocks[0].text, "**bold** pla")
        XCTAssertEqual(document.blocks[1].text, "in text")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[1].id, utf16Offset: 0)))
    }

    func testNestedComposedBoldItalicReopensBalanced() {
        let id = BlockInputBlockID(rawValue: "g")
        var document = BlockInputDocument(blocks: [BlockInputBlock(id: id, text: "***word***")])

        // Caret inside content "***wo|rd***" -> offset 5.
        let selection = document.handleReturn(in: id, utf16Offset: 5)

        // Innermost (bold **) closes first, outer (italic _) closes last on the prefix; the suffix reopens
        // outer-first so italic wraps bold: "_**" prefix-balanced, suffix "_**rd***".
        XCTAssertEqual(document.blocks[0].text, "***wo**_")
        XCTAssertEqual(document.blocks[1].text, "_**rd***")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[1].id, utf16Offset: 3)))
    }

    func testSelectionConsumedAndSpanRebalanced() {
        let id = BlockInputBlockID(rawValue: "h")
        var document = BlockInputDocument(blocks: [BlockInputBlock(id: id, text: "**aXXXb**")])

        // Caret at 4 ("**aX|XXb**"), selecting "XX" (length 2): consumed by the break, suffix starts at 6.
        let selection = document.handleReturn(in: id, utf16Offset: 4, selectedUTF16Length: 2)

        XCTAssertEqual(document.blocks[0].text, "**aX**")
        XCTAssertEqual(document.blocks[1].text, "**b**")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[1].id, utf16Offset: 2)))
    }

    func testSplitInsideStrikethroughClosesAndReopens() {
        let id = BlockInputBlockID(rawValue: "s")
        var document = BlockInputDocument(blocks: [BlockInputBlock(id: id, text: "~~abcd~~")])

        let selection = document.handleReturn(in: id, utf16Offset: 4)

        XCTAssertEqual(document.blocks[0].text, "~~ab~~")
        XCTAssertEqual(document.blocks[1].text, "~~cd~~")
        // Caret lands after the reopened "~~" opening delimiter (length 2).
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[1].id, utf16Offset: 2)))
    }

    func testSplitInsideUnderlineClosesAndReopensWithMultiCharDelimiter() {
        let id = BlockInputBlockID(rawValue: "u")
        var document = BlockInputDocument(blocks: [BlockInputBlock(id: id, text: "<u>abcd</u>")])

        // Caret inside content "<u>ab|cd</u>" -> offset 5.
        let selection = document.handleReturn(in: id, utf16Offset: 5)

        XCTAssertEqual(document.blocks[0].text, "<u>ab</u>")
        XCTAssertEqual(document.blocks[1].text, "<u>cd</u>")
        // Caret lands after the reopened "<u>" opening delimiter (length 3).
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[1].id, utf16Offset: 3)))
    }

    func testOnlyTheStraddledSiblingSpanIsRewrapped() {
        let id = BlockInputBlockID(rawValue: "j")
        var document = BlockInputDocument(blocks: [BlockInputBlock(id: id, text: "**aa** **bcd**")])

        // Caret inside the SECOND span "**aa** **bc|d**" -> offset 11; the first span is untouched.
        let selection = document.handleReturn(in: id, utf16Offset: 11)

        XCTAssertEqual(document.blocks[0].text, "**aa** **bc**")
        XCTAssertEqual(document.blocks[1].text, "**d**")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[1].id, utf16Offset: 2)))
    }

    func testLinkSpanIsNotRewrapped() {
        let id = BlockInputBlockID(rawValue: "i")
        var document = BlockInputDocument(blocks: [BlockInputBlock(id: id, text: "[label](https://x.test)")])

        // Caret inside the link label -> link must be left alone (no auto close/reopen).
        let selection = document.handleReturn(in: id, utf16Offset: 4)

        XCTAssertEqual(document.blocks[0].text, "[lab")
        XCTAssertEqual(document.blocks[1].text, "el](https://x.test)")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[1].id, utf16Offset: 0)))
    }
}
