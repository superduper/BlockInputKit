import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputTableContextMenuInsertionTests: XCTestCase {
    func testInsertTableContextMenuReplacesEmptyTextBlockAndFocusesHeader() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "empty", text: "   ")
        ])
        let textView = try tableEditingTextView(in: mounted.view)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        let menu = try XCTUnwrap(textView.menu(for: try rightMouseDownEvent(windowNumber: mounted.window.windowNumber)))

        try performTableCellMenuItem(titled: "Insert Table", in: menu)

        XCTAssertEqual(mounted.view.document.blocks.count, 1)
        XCTAssertEqual(mounted.view.document.blocks[0].id, "empty")
        XCTAssertEqual(mounted.view.document.blocks[0].kind, .table)
        let table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(table.header.count, 2)
        XCTAssertEqual(table.bodyRows.count, 1)
        XCTAssertEqual(
            mounted.view.selection,
            table.selection(blockID: "empty", position: .init(row: .header, column: 0), localRange: NSRange(location: 0, length: 0))
        )
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let firstHeaderCell = try tableCell(in: item, row: 0, column: 0, columnCount: 2)
        XCTAssertTrue(mounted.window.firstResponder === firstHeaderCell)
    }

    func testContextMenuShowsInsertActionsBeforeDeletionActions() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock(bodyRows: [["one", "two"], ["three", "four"]])])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))

        let menu = try tableCellMenu(for: cell, windowNumber: mounted.window.windowNumber)
        let insertLinkIndex = try XCTUnwrap(menu.items.firstIndex { $0.title == "Insert Link" })

        XCTAssertEqual(menu.items[insertLinkIndex + 1].title, "Insert Row")
        XCTAssertEqual(menu.items[insertLinkIndex + 2].title, "Insert Column")
        XCTAssertEqual(menu.items[insertLinkIndex + 3].title, "Delete Row")
        XCTAssertEqual(menu.items[insertLinkIndex + 4].title, "Delete Column")
        XCTAssertEqual(menu.items[insertLinkIndex + 5].title, "Delete Table")
    }

    func testInsertRowFromBodyContextMenuInsertsBelowClickedRowAndFocusesFirstNewCell() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock(bodyRows: [["one", "two"], ["three", "four"]])])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 1)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))

        try performTableCellMenuItem(titled: "Insert Row", in: tableCellMenu(for: cell, windowNumber: mounted.window.windowNumber))

        let table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(table.bodyRows.map { $0.map(\.text) }, [["one", "two"], ["", ""], ["three", "four"]])
        XCTAssertEqual(
            mounted.view.selection,
            table.selection(blockID: "table", position: .init(row: .body(1), column: 0), localRange: NSRange(location: 0, length: 0))
        )
        let updatedItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let focusedCell = try bodyCell(in: updatedItem, row: 1, column: 0)
        XCTAssertTrue(mounted.window.firstResponder === focusedCell)
    }

    func testInsertRowFromHeaderContextMenuCreatesFirstBodyRow() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock(bodyRows: [])])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try tableCell(in: item, row: 0, column: 1, columnCount: 2)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))

        try performTableCellMenuItem(titled: "Insert Row", in: tableCellMenu(for: cell, windowNumber: mounted.window.windowNumber))

        let table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(table.bodyRows.map { $0.map(\.text) }, [["", ""]])
        XCTAssertEqual(
            mounted.view.selection,
            table.selection(blockID: "table", position: .init(row: .body(0), column: 0), localRange: NSRange(location: 0, length: 0))
        )
    }

    func testInsertColumnFromBodyContextMenuInsertsRightOfClickedColumnAndFocusesNewCell() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock(bodyRows: [["one", "two"]])])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))

        try performTableCellMenuItem(titled: "Insert Column", in: tableCellMenu(for: cell, windowNumber: mounted.window.windowNumber))

        let table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(table.header.map(\.text), ["H1", "", "H2"])
        XCTAssertEqual(table.bodyRows.map { $0.map(\.text) }, [["one", "", "two"]])
        XCTAssertEqual(table.alignments, [.left, .left, .left])
        XCTAssertEqual(
            mounted.view.selection,
            table.selection(blockID: "table", position: .init(row: .body(0), column: 1), localRange: NSRange(location: 0, length: 0))
        )
        let updatedItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let focusedCell = try bodyCell(in: updatedItem, row: 0, column: 1, columnCount: 3)
        XCTAssertTrue(mounted.window.firstResponder === focusedCell)
    }

    func testInsertColumnFromHeaderContextMenuFocusesNewHeaderCell() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock(bodyRows: [["one", "two"]])])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try tableCell(in: item, row: 0, column: 0, columnCount: 2)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))

        try performTableCellMenuItem(titled: "Insert Column", in: tableCellMenu(for: cell, windowNumber: mounted.window.windowNumber))

        let table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(table.header.map(\.text), ["H1", "", "H2"])
        XCTAssertEqual(
            mounted.view.selection,
            table.selection(blockID: "table", position: .init(row: .header, column: 1), localRange: NSRange(location: 0, length: 0))
        )
    }

    private static func tableBlock(
        bodyRows: [[String]]
    ) -> BlockInputBlock {
        BlockInputBlock(
            id: "table",
            kind: .table,
            text: BlockInputTable.normalized(
                header: ["H1", "H2"],
                bodyRows: bodyRows,
                alignments: [.left, .left]
            ).markdown
        )
    }
}
