import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputTableCellTabInsertionTests: XCTestCase {
    func testTabFromFinalCellInsertsBodyRowBelowAndFocusesFirstNewCell() throws {
        let undoController = BlockInputUndoController()
        let mounted = makeMountedBlockInputView(
            document: BlockInputDocument(blocks: [Self.tableBlock(bodyRows: [["one", "two"], ["three", "four"]])]),
            undoController: undoController
        )
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let finalCell = try bodyCell(in: item, row: 1, column: 1)
        XCTAssertTrue(mounted.window.makeFirstResponder(finalCell))

        finalCell.doCommand(by: #selector(NSResponder.insertTab(_:)))

        let table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(table.bodyRows.map { $0.map(\.text) }, [["one", "two"], ["three", "four"], ["", ""]])
        XCTAssertEqual(
            mounted.view.selection,
            table.selection(
                blockID: "table",
                position: .init(row: .body(2), column: 0),
                localRange: NSRange(location: 0, length: 0)
            )
        )
        let updatedItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let focusedCell = try bodyCell(in: updatedItem, row: 2, column: 0)
        XCTAssertTrue(mounted.window.firstResponder === focusedCell)

        let undo = mounted.view.undoStructuralEdit()
        XCTAssertEqual(undo?.actionName, "Insert Row")
        let restoredTable = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(restoredTable.bodyRows.map { $0.map(\.text) }, [["one", "two"], ["three", "four"]])
    }

    func testTabFromFinalHeaderCellInHeaderOnlyTableInsertsFirstBodyRow() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock(bodyRows: [])])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let finalHeaderCell = try tableCell(in: item, row: 0, column: 1, columnCount: 2)
        XCTAssertTrue(mounted.window.makeFirstResponder(finalHeaderCell))

        finalHeaderCell.doCommand(by: #selector(NSResponder.insertTab(_:)))

        let table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(table.bodyRows.map { $0.map(\.text) }, [["", ""]])
        XCTAssertEqual(
            mounted.view.selection,
            table.selection(
                blockID: "table",
                position: .init(row: .body(0), column: 0),
                localRange: NSRange(location: 0, length: 0)
            )
        )
    }

    func testTabOnLastCellDoesNotInsertLiteralTabWhenRowInsertionIsRejected() throws {
        // Construct an item whose delegate has no document loaded, so row insertion returns false.
        // The cell text view IS editable; the bug causes super.doCommand(insertTab) to fall through
        // and insert a literal \t into the focused cell.
        let block = Self.tableBlock(bodyRows: [["one", "two"]])
        let item = BlockInputBlockItem.configuredForTesting(
            block: block,
            allowsReordering: true,
            delegate: BlockInputView()   // empty delegate — insertTableBodyRow returns false
        )
        item.view.frame = NSRect(x: 0, y: 0, width: 360, height: BlockInputBlockItem.height(
            for: block,
            textWidth: 280,
            blockVerticalInsetMultiplier: 1
        ))
        item.view.layoutSubtreeIfNeeded()

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 480, height: 360)),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = item.view

        let finalCell = try bodyCell(in: item, row: 0, column: 1)
        XCTAssertTrue(window.makeFirstResponder(finalCell))

        finalCell.doCommand(by: #selector(NSResponder.insertTab(_:)))

        XCTAssertFalse(finalCell.string.contains("\t"),
            "Tab on the last cell must not insert a literal tab when row insertion is rejected")
    }

    private static func tableBlock(bodyRows: [[String]]) -> BlockInputBlock {
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
