import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputTableSourceMappingTests: XCTestCase {
    func testPublicSelectionInsideOneCellFocusesContainingCell() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        let range = try XCTUnwrap(table.sourceRange(
            forLocalRange: NSRange(location: 1, length: 2),
            in: .init(row: .body(0), column: 0)
        ))

        mounted.view.applySelection(.text(BlockInputTextRange(blockID: "table", range: range)), notify: true)
        mounted.view.restoreVisibleSelection()

        let cell = try bodyCell(in: item, row: 0, column: 0)
        XCTAssertTrue(mounted.window.firstResponder === cell)
        XCTAssertEqual(cell.selectedRange(), NSRange(location: 1, length: 2))
    }

    func testPublicSelectionOutsideCellContentBecomesWholeTableSelection() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock()])
        let markdown = mounted.view.document.blocks[0].text as NSString
        let delimiterOffset = markdown.range(of: "---").location

        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: "table", utf16Offset: delimiterOffset)), notify: true)

        XCTAssertEqual(mounted.view.selection, .blocks(["table"]))
    }

    func testPublicSelectionInsideEscapedCellCharacterBecomesWholeTableSelection() throws {
        let table = BlockInputTable.normalized(
            header: ["A", "B"],
            bodyRows: [["a|b", "tail"]],
            alignments: [.left, .left]
        )
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "table", kind: .table, text: table.markdown)
        ])
        let pipeRange = try XCTUnwrap(table.sourceRange(
            forLocalRange: NSRange(location: 1, length: 1),
            in: .init(row: .body(0), column: 0)
        ))

        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: "table", utf16Offset: pipeRange.location + 1)), notify: true)
        XCTAssertEqual(mounted.view.selection, .blocks(["table"]))

        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: "table",
            range: NSRange(location: pipeRange.location, length: 1)
        )), notify: true)
        XCTAssertEqual(mounted.view.selection, .blocks(["table"]))
    }

    func testTableSourceMappingRoundTripsBackslashBeforeLiteralPipe() throws {
        let table = BlockInputTable.normalized(
            header: ["A", "B"],
            bodyRows: [[#"path \| pipe"#, "tail"]],
            alignments: [.left, .left]
        )
        let localRange = NSRange(location: 5, length: 2)
        let sourceRange = try XCTUnwrap(table.sourceRange(forLocalRange: localRange, in: .init(row: .body(0), column: 0)))

        XCTAssertEqual((table.markdown as NSString).substring(with: sourceRange), #"\\\|"#)
        XCTAssertEqual(table.localRange(forSourceRange: sourceRange, in: .init(row: .body(0), column: 0)), localRange)
    }

    func testTableSourceMappingPreservesInlineCodeEscapedPipes() throws {
        let table = BlockInputTable.normalized(
            header: ["A", "B"],
            bodyRows: [[#"`a\|b`"#, "tail"]],
            alignments: [.left, .left]
        )
        let position = BlockInputTable.CellPosition(row: .body(0), column: 0)
        let localRange = NSRange(location: 2, length: 2)
        let sourceRange = try XCTUnwrap(table.sourceRange(forLocalRange: localRange, in: position))

        XCTAssertEqual((table.markdown as NSString).substring(with: sourceRange), #"\|"#)
        XCTAssertEqual(table.localRange(forSourceRange: sourceRange, in: position), localRange)
    }

    func testPublicMixedSelectionPromotesInvalidTableEndpointToWholeTableSelection() throws {
        let paragraph = BlockInputBlock(id: "paragraph", kind: .paragraph, text: "prefix")
        let mounted = makeMountedBlockInputView(blocks: [paragraph, Self.tableBlock()])
        let tableMarkdown = mounted.view.document.blocks[1].text as NSString
        let delimiterOffset = tableMarkdown.range(of: "---").location
        let leadingRange = BlockInputTextRange(blockID: "paragraph", range: NSRange(location: 1, length: 3))

        mounted.view.applySelection(.mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: leadingRange,
            trailingTextRange: BlockInputTextRange(blockID: "table", range: NSRange(location: delimiterOffset, length: 3))
        )), notify: true)

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: ["table"],
            leadingTextRange: leadingRange
        )))
    }

    private func bodyCell(in item: BlockInputBlockItem, row: Int, column: Int) throws -> BlockInputTableCellTextView {
        try tableCell(in: item, row: row + 1, column: column, columnCount: 2)
    }

    private func tableCell(in item: BlockInputBlockItem, row: Int, column: Int, columnCount: Int) throws -> BlockInputTableCellTextView {
        let index = row * columnCount + column
        return try XCTUnwrap(item.testingTableCellTextViews.indices.contains(index) ? item.testingTableCellTextViews[index] : nil)
    }

    private static func tableBlock() -> BlockInputBlock {
        BlockInputBlock(
            id: "table",
            kind: .table,
            text: BlockInputTable.normalized(
                header: ["H1", "H2"],
                bodyRows: [["one", "two"]],
                alignments: [.left, .left]
            ).markdown
        )
    }
}
