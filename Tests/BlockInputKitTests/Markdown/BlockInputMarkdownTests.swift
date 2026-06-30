import Foundation
import XCTest
@testable import BlockInputKit

final class BlockInputMarkdownTests: XCTestCase {
    func testMarkdownRoundTripsSupportedBlockKinds() {
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(id: "intro", kind: .paragraph, text: "Intro"),
            BlockInputBlock(id: "heading", kind: .heading(level: 2), text: "Heading"),
            BlockInputBlock(id: "code", kind: .code(language: "swift"), text: "let value = 1"),
            BlockInputBlock(id: "rule", kind: .horizontalRule),
            BlockInputBlock(id: "quote", kind: .quote, text: "Quoted\nText"),
            BlockInputBlock(id: "bullet", kind: .bulletedListItem, text: "Bullet", indentationLevel: 1),
            BlockInputBlock(id: "number", kind: .numberedListItem(start: 3), text: "Numbered"),
            BlockInputBlock(id: "check", kind: .checklistItem(isChecked: true), text: "Done")
        ])

        let markdown = document.markdown
        let parsed = BlockInputDocument(markdown: markdown)

        XCTAssertEqual(parsed.blocks.map(\.kind), document.blocks.map(\.kind))
        XCTAssertEqual(parsed.blocks.map(\.text), document.blocks.map(\.text))
        XCTAssertEqual(parsed.blocks.map(\.indentationLevel), document.blocks.map(\.indentationLevel))
    }

    func testMarkdownPreservesCodeFenceLanguageInfoString() {
        let parsed = BlockInputDocument(markdown: """
        ``` swift package
        let value = 1
        ```
        """)

        XCTAssertEqual(parsed.blocks.map(\.kind), [.code(language: "swift package")])
        XCTAssertEqual(parsed.blocks.map(\.text), ["let value = 1"])
        XCTAssertEqual(parsed.markdown, """
        ```swift package
        let value = 1
        ```
        """)
    }

    func testMarkdownParsesEmptyCodeFencesAsContent() {
        let empty = BlockInputDocument(markdown: """
        ```
        ```
        """)
        let blankLine = BlockInputDocument(markdown: "```\n\n\n```")

        XCTAssertEqual(empty.blocks.map(\.kind), [.code(language: nil)])
        XCTAssertEqual(empty.blocks.map(\.text), [""])
        XCTAssertFalse(empty.isEffectivelyEmpty)
        XCTAssertEqual(empty.markdown, "```\n\n```")
        XCTAssertEqual(blankLine.blocks.map(\.kind), [.code(language: nil)])
        XCTAssertEqual(blankLine.blocks.map(\.text), ["\n"])
        XCTAssertFalse(blankLine.isEffectivelyEmpty)
        XCTAssertEqual(blankLine.markdown, "```\n\n\n```")
    }

    func testMarkdownRoundTripKeepsAdjacentParagraphBlocksSeparate() {
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(id: "first", kind: .paragraph, text: "First"),
            BlockInputBlock(id: "second", kind: .paragraph, text: "Second")
        ])

        let parsed = BlockInputDocument(markdown: document.markdown)

        XCTAssertEqual(parsed.blocks.map(\.kind), [.paragraph, .paragraph])
        XCTAssertEqual(parsed.blocks.map(\.text), ["First", "Second"])
    }

    func testMarkdownParsesAdjacentListLinesAsSeparateBlocks() {
        let parsed = BlockInputDocument(markdown: """
        - One
          - Two
        3. Three
          1. Four
        """)

        XCTAssertEqual(parsed.blocks.map(\.kind), [
            .bulletedListItem,
            .bulletedListItem,
            .numberedListItem(start: 3),
            .numberedListItem(start: 1)
        ])
        XCTAssertEqual(parsed.blocks.map(\.text), ["One", "Two", "Three", "Four"])
        XCTAssertEqual(parsed.blocks.map(\.indentationLevel), [0, 1, 0, 1])
    }

    func testMarkdownExportsAdjacentListBlocksWithoutBlankLines() {
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(id: "bullet-1", kind: .bulletedListItem, text: "One"),
            BlockInputBlock(id: "bullet-2", kind: .bulletedListItem, text: "Two", indentationLevel: 1),
            BlockInputBlock(id: "number-1", kind: .numberedListItem(start: 3), text: "Three"),
            BlockInputBlock(id: "number-2", kind: .numberedListItem(start: 1), text: "Four", indentationLevel: 1),
            BlockInputBlock(id: "check", kind: .checklistItem(isChecked: false), text: "Todo")
        ])

        let markdown = document.markdown

        XCTAssertEqual(markdown, """
        - One
          - Two
        3. Three
          1. Four
        - [ ] Todo
        """)
    }

    func testMarkdownKeepsChecklistItemsSeparate() {
        let parsed = BlockInputDocument(markdown: "- [ ] Todo\n- [ ] Later\n- [x] Done")

        XCTAssertEqual(parsed.blocks.map(\.kind), [
            .checklistItem(isChecked: false),
            .checklistItem(isChecked: false),
            .checklistItem(isChecked: true)
        ])
        XCTAssertEqual(parsed.blocks.map(\.text), ["Todo", "Later", "Done"])
    }

    func testMarkdownExportsLegacyPerLineListIndentation() {
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(
                id: "bullet",
                kind: .bulletedListItem,
                text: "One\nTwo\nThree",
                lineIndentationLevels: [0, 1, 2]
            )
        ])

        let markdown = document.markdown

        XCTAssertEqual(markdown, "- One\n  - Two\n    - Three")
    }

    func testMarkdownImportTreatsCRLFAsSeparateListBlocks() {
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(
                id: "bullet",
                kind: .bulletedListItem,
                text: "One\r\nTwo",
                lineIndentationLevels: [0, 1]
            )
        ])

        let markdown = document.markdown
        let parsed = BlockInputDocument(markdown: "- One\r\n  - Two")

        XCTAssertEqual(markdown, "- One\n  - Two")
        XCTAssertEqual(parsed.blocks.map(\.text), ["One", "Two"])
        XCTAssertEqual(parsed.blocks.map(\.indentationLevel), [0, 1])
    }

    func testMarkdownExportsLegacyNestedOrderedListIndentationWithPerLevelCounters() {
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(
                id: "number",
                kind: .numberedListItem(start: 1),
                text: "One\nTwo\nThree\nFour\nFive",
                lineIndentationLevels: [0, 1, 2, 1, 0]
            )
        ])

        let markdown = document.markdown

        XCTAssertEqual(markdown, "1. One\n  1. Two\n    1. Three\n  2. Four\n2. Five")
    }

    func testMarkdownExportsLegacyIndentedOrderedListStartAtBaselineIndentation() {
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(
                id: "number",
                kind: .numberedListItem(start: 3),
                text: "One\nTwo\nThree",
                lineIndentationLevels: [1, 2, 1]
            )
        ])

        let markdown = document.markdown

        XCTAssertEqual(markdown, "  3. One\n    1. Two\n  4. Three")
    }

    func testMarkdownKeepsUnexpectedNumberedListSequenceSeparate() {
        let parsed = BlockInputDocument(markdown: "1. One\n3. Three")

        XCTAssertEqual(parsed.blocks.count, 2)
        XCTAssertEqual(parsed.blocks[0].kind, .numberedListItem(start: 1))
        XCTAssertEqual(parsed.blocks[0].text, "One")
        XCTAssertEqual(parsed.blocks[1].kind, .numberedListItem(start: 3))
        XCTAssertEqual(parsed.blocks[1].text, "Three")
    }

    func testMarkdownRoundTripKeepsInlineStylingMarkersLiteral() {
        let expectedTexts = [
            "*italic text*",
            "_italic text_",
            "**bold text**",
            "***bold and italic***",
            "<u>underlined text</u>",
            "<ins>underlined text</ins>",
            "~~struck text~~",
            "**_bold and italic_**",
            "**<u>bold and underlined</u>**",
            "~~*strikethrough and italic*~~"
        ]
        let source = expectedTexts.joined(separator: "\n\n")

        let parsed = BlockInputDocument(markdown: source)

        XCTAssertEqual(parsed.blocks.map(\.kind), Array(repeating: .paragraph, count: expectedTexts.count))
        XCTAssertEqual(parsed.blocks.map(\.text), expectedTexts)
        XCTAssertEqual(parsed.markdown, source)
    }
}
