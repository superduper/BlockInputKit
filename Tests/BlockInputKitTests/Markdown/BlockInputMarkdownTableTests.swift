import Foundation
import XCTest
@testable import BlockInputKit

final class BlockInputMarkdownTableTests: XCTestCase {
    func testMarkdownParsesAndExportsNormalizedTable() {
        let source = """
        | Name | Age |
        | --- | ---: |
        | Ada | 37 |
        | Grace | 85 |
        """

        let document = BlockInputDocument(markdown: source)

        XCTAssertEqual(document.blocks.map(\.kind), [.table])
        XCTAssertEqual(document.blocks[0].text, """
        | Name  | Age  |
        | ---   | ---: |
        | Ada   | 37   |
        | Grace | 85   |
        """)
        XCTAssertEqual(document.markdown, document.blocks[0].text)
    }

    func testMarkdownParsesTableWithTabSpacedDelimiter() {
        let source = "| Name | Done |\n|\t---\t|\t:---:\t|\n| Raw | yes |"

        let parsed = BlockInputDocument(markdown: source)

        XCTAssertEqual(parsed.blocks.map(\.kind), [.table])
        XCTAssertEqual(parsed.blocks[0].text, """
        | Name | Done  |
        | ---  | :---: |
        | Raw  | yes   |
        """)
        XCTAssertEqual(parsed.markdown, parsed.blocks[0].text)
    }

    func testMarkdownParsesTableAfterParagraphWithoutAbsorbingNeighboringSource() {
        let source = """
        Before
        | Name | Done |
        | --- | :---: |
        | Raw | yes |
        """

        let parsed = BlockInputDocument(markdown: source)

        XCTAssertEqual(parsed.blocks.map(\.kind), [.paragraph, .table])
        XCTAssertEqual(parsed.blocks[0].text, "Before")
        XCTAssertEqual(parsed.blocks[1].text, """
        | Name | Done  |
        | ---  | :---: |
        | Raw  | yes   |
        """)
        XCTAssertEqual(parsed.markdown, """
        Before

        | Name | Done  |
        | ---  | :---: |
        | Raw  | yes   |
        """)
    }

    func testTableModelPreservesAlignmentsEscapedPipesInlineCodeAndSourceRanges() throws {
        let table = try XCTUnwrap(BlockInputTable(markdown: """
        Label | Center | Right
        :--- | :---: | ---:
        literal \\| pipe | `a|b` | tail
        """))

        XCTAssertEqual(table.header.map(\.text), ["Label", "Center", "Right"])
        XCTAssertEqual(table.alignments, [.left, .center, .right])
        XCTAssertEqual(table.bodyRows.first?.map(\.text), ["literal | pipe", "`a|b`", "tail"])
        XCTAssertEqual(source(in: table.markdown, range: table.bodyRows[0][0].sourceRange), "literal \\| pipe")
        XCTAssertEqual(source(in: table.markdown, range: table.bodyRows[0][1].sourceRange), "`a|b`")
        XCTAssertEqual(table.markdown, """
        | Label           | Center | Right |
        | ---             | :---:  | ---:  |
        | literal \\| pipe | `a|b`  | tail  |
        """)
    }

    func testTableModelEscapesPipesAfterUnmatchedBackticks() throws {
        let table = BlockInputTable.normalized(
            header: ["A", "B"],
            bodyRows: [["`not code | literal", "tail"]],
            alignments: [.left, .left]
        )
        let reparsed = try XCTUnwrap(BlockInputTable(markdown: table.markdown))

        XCTAssertEqual(reparsed.bodyRows.first?.map(\.text), ["`not code | literal", "tail"])
        XCTAssertEqual(source(in: table.markdown, range: table.bodyRows[0][0].sourceRange), "`not code \\| literal")
    }

    func testTableModelPreservesEscapedPipesInsideInlineCode() throws {
        let table = try XCTUnwrap(BlockInputTable(markdown: #"""
        | A | B |
        | --- | --- |
        | `a\|b` | tail |
        """#))
        let reparsed = try XCTUnwrap(BlockInputTable(markdown: table.markdown))

        XCTAssertEqual(table.bodyRows.first?.map(\.text), [#"`a\|b`"#, "tail"])
        XCTAssertEqual(reparsed.bodyRows.first?.map(\.text), [#"`a\|b`"#, "tail"])
        XCTAssertEqual(source(in: table.markdown, range: table.bodyRows[0][0].sourceRange), #"`a\|b`"#)
    }

    func testTableModelRoundTripsBackslashBeforeLiteralPipe() throws {
        let table = BlockInputTable.normalized(
            header: ["A", "B"],
            bodyRows: [[#"path \| pipe"#, "tail"]],
            alignments: [.left, .left]
        )
        let reparsed = try XCTUnwrap(BlockInputTable(markdown: table.markdown))

        XCTAssertEqual(reparsed.bodyRows.first?.map(\.text), [#"path \| pipe"#, "tail"])
        XCTAssertEqual(source(in: table.markdown, range: table.bodyRows[0][0].sourceRange), #"path \\\| pipe"#)
    }

    func testMarkdownParsesMissingCellsIgnoresExtraCellsHeaderOnlyAndTrailingBlanks() {
        let missingCells = BlockInputDocument(markdown: """
        A | B | C
        --- | --- | ---
        1 | 2
        3 | 4 | 5 | 6

        After
        """)
        let headerOnly = BlockInputDocument(markdown: """
        | Only | Header |
        | --- | :---: |
        """)

        XCTAssertEqual(missingCells.blocks.map(\.kind), [.table, .paragraph])
        XCTAssertEqual(missingCells.blocks[0].text, """
        | A   | B   | C   |
        | --- | --- | --- |
        | 1   | 2   |     |
        | 3   | 4   | 5   |
        """)
        XCTAssertEqual(missingCells.blocks[1].text, "After")
        XCTAssertEqual(headerOnly.blocks.map(\.kind), [.table])
        XCTAssertEqual(headerOnly.blocks[0].text, """
        | Only | Header |
        | ---  | :---:  |
        """)
    }

    func testMalformedAndRawPreservedTableLikeMarkdownStaysRaw() {
        let malformed = BlockInputDocument(markdown: """
        | A | B |
        | - | - |
        | 1 | 2 |
        """)
        let code = BlockInputDocument(markdown: """
        ```
        | A | B |
        | --- | --- |
        ```
        """)
        let html = BlockInputDocument(markdown: """
        <section>
        | A | B |
        | --- | --- |
        </section>
        """)
        let footnote = BlockInputDocument(markdown: """
        [^note]: A | B
            | --- | --- |
        """)
        let ambiguousSetext = BlockInputDocument(markdown: """
        | A |
        ---
        """)

        XCTAssertEqual(malformed.blocks.map(\.kind), [.rawMarkdown])
        XCTAssertEqual(code.blocks.map(\.kind), [.code(language: nil)])
        XCTAssertEqual(html.blocks.map(\.kind), [.rawMarkdown])
        XCTAssertEqual(footnote.blocks.map(\.kind), [.rawMarkdown])
        XCTAssertEqual(ambiguousSetext.blocks.map(\.kind), [.rawMarkdown])
    }

    func testStreamingTableImportAndExportMatchSnapshotImport() async {
        let source = """
        # Before

        | A | B |
        | --- | :---: |
        | 1 | 2 |

        After
        """

        let streamed = await BlockInputDocument.parsingMarkdown(source)
        let snapshot = BlockInputDocument(markdown: source)
        let streamedMarkdown = await streamed.markdownSnapshot()

        XCTAssertEqual(streamed.blocks.map(\.kind), snapshot.blocks.map(\.kind))
        XCTAssertEqual(streamed.blocks.map(\.text), snapshot.blocks.map(\.text))
        XCTAssertEqual(streamedMarkdown, snapshot.markdown)
    }

    func testTableBlockCodableRoundTrips() throws {
        let block = BlockInputBlock(
            id: "table",
            kind: .table,
            text: """
            | A | B |
            | --- | --- |
            """
        )

        let data = try JSONEncoder().encode(block)
        let decoded = try JSONDecoder().decode(BlockInputBlock.self, from: data)

        XCTAssertEqual(decoded, block)
        XCTAssertFalse(decoded.isEmpty)
        XCTAssertEqual(decoded.indentationLevel, 0)
    }

    func testTableTypingShortcutConvertsWholeApplicableBlockAndFocusesFirstBodyCell() {
        let blockID = BlockInputBlockID(rawValue: "paragraph")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "")
        ])
        let source = """
        | H1 | H2 |
        | --- | --- |
        | B1 | B2 |
        """

        let shortcut = document.typingShortcut(
            for: blockID,
            proposedText: source,
            proposedUTF16Offset: (source as NSString).length
        )
        let selection = shortcut.flatMap { document.applyTypingShortcut(blockID: blockID, shortcut: $0) }
        let table = BlockInputTable(markdown: document.blocks[0].text)

        XCTAssertEqual(document.blocks[0].kind, .table)
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: table?.firstBodyCellRange?.location ?? -1)))
    }

    func testTableTypingShortcutAcceptsOuterBlankLinesFromPaste() {
        let blockID = BlockInputBlockID(rawValue: "paragraph")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "")
        ])
        let source = """

        | H1 | H2 |
        | --- | --- |
        | B1 | B2 |

        """

        let shortcut = document.typingShortcut(
            for: blockID,
            proposedText: source,
            proposedUTF16Offset: (source as NSString).length
        )
        _ = shortcut.flatMap { document.applyTypingShortcut(blockID: blockID, shortcut: $0) }

        XCTAssertEqual(document.blocks[0].kind, .table)
        XCTAssertEqual(document.blocks[0].text, """
        | H1  | H2  |
        | --- | --- |
        | B1  | B2  |
        """)
    }

    func testTableMutationsNormalizeMarkdownAndReturnFreshRanges() throws {
        let table = try XCTUnwrap(BlockInputTable(markdown: """
        | A | B |
        | --- | --- |
        | 1 | 2 |
        """))
        let replaced = try XCTUnwrap(table.replacingCellText(row: .body(0), column: 1, text: "line 1\nline | 2"))
        let appendedRow = replaced.appendingBodyRow()
        let appendedColumn = appendedRow.appendingColumn()
        let deletedRow = try XCTUnwrap(appendedColumn.deletingBodyRow(0, keepsLastBodyRow: true))
        let deletedColumn = try XCTUnwrap(deletedRow.deletingColumn(2))

        XCTAssertEqual(replaced.bodyRows[0][1].text, "line 1 line | 2")
        XCTAssertEqual(source(in: replaced.markdown, range: replaced.bodyRows[0][1].sourceRange), "line 1 line \\| 2")
        XCTAssertEqual(appendedRow.bodyRows.count, 2)
        XCTAssertEqual(appendedColumn.columnCount, 3)
        XCTAssertEqual(deletedRow.bodyRows.count, 1)
        XCTAssertEqual(deletedColumn.columnCount, 2)
        XCTAssertNotEqual(table.markdown, replaced.markdown)
    }
}

private func source(in text: String, range: NSRange) -> String {
    (text as NSString).substring(with: range)
}
