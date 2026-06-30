import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputTableSelectionDeletionTests: XCTestCase {
    func testDeleteKeyRemovesWholeSelectedTableFromFocusedCell() throws {
        let paragraph = BlockInputBlock(id: "paragraph", text: "Start")
        let table = Self.tableBlock()
        let trailing = BlockInputBlock(id: "trailing", text: "After")
        let mounted = makeMountedBlockInputView(document: BlockInputDocument(blocks: [paragraph, table, trailing]))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))
        mounted.view.applySelection(.blocks(["table"]), notify: true)

        cell.keyDown(with: try keyDownEvent(keyCode: 117, characters: "\u{F728}"))

        XCTAssertEqual(mounted.view.document.blocks.map(\.id), ["paragraph", "trailing"])
        let undo = mounted.view.undoStructuralEdit()
        XCTAssertEqual(undo?.actionName, "Delete Table")
        XCTAssertEqual(mounted.view.document.blocks.map(\.id), ["paragraph", "table", "trailing"])
    }

    func testDeleteKeyRemovesTableAfterShiftArrowSelectsAllCells() throws {
        let paragraph = BlockInputBlock(id: "paragraph", text: "Start")
        let table = Self.tableBlock(bodyRows: [["one", "two"], ["three", "four"]])
        let trailing = BlockInputBlock(id: "trailing", text: "After")
        let mounted = makeMountedBlockInputView(document: BlockInputDocument(blocks: [paragraph, table, trailing]))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let cell = try bodyCell(in: item, row: 1, column: 1)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))

        cell.keyDown(with: try shiftUpEvent())
        cell.keyDown(with: try shiftUpEvent())
        cell.keyDown(with: try shiftUpEvent())
        let focusedEditor = try XCTUnwrap(mounted.window.firstResponder as? BlockInputView)
        focusedEditor.keyDown(with: try keyDownEvent(keyCode: 117, characters: "\u{F728}"))

        XCTAssertEqual(mounted.view.document.blocks.map(\.id), ["paragraph", "trailing"])
        let undo = mounted.view.undoStructuralEdit()
        XCTAssertEqual(undo?.actionName, "Delete Table")
        XCTAssertEqual(mounted.view.document.blocks.map(\.id), ["paragraph", "table", "trailing"])
    }

    func testDeleteKeyRemovesSelectedWholeBodyRow() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock(bodyRows: [["one", "two"], ["three", "four"]])])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))

        cell.keyDown(with: try shiftDownEvent())
        cell.keyDown(with: try keyDownEvent(keyCode: 117, characters: "\u{F728}"))

        let table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(table.bodyRows.map { $0.map(\.text) }, [["three", "four"]])
        let undo = mounted.view.undoStructuralEdit()
        XCTAssertEqual(undo?.actionName, "Delete Row")
        let restoredTable = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(restoredTable.bodyRows.map { $0.map(\.text) }, [["one", "two"], ["three", "four"]])
    }

    func testDeleteKeyRemovesSelectedWholeColumn() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock(bodyRows: [["one", "two"], ["three", "four"]])])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try tableCell(in: item, row: 0, column: 1, columnCount: 2)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))

        cell.keyDown(with: try shiftRightEvent())
        cell.keyDown(with: try keyDownEvent(keyCode: 117, characters: "\u{F728}"))

        let table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(table.header.map(\.text), ["H1"])
        XCTAssertEqual(table.bodyRows.map { $0.map(\.text) }, [["one"], ["three"]])
        let undo = mounted.view.undoStructuralEdit()
        XCTAssertEqual(undo?.actionName, "Delete Column")
        let restoredTable = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(restoredTable.header.map(\.text), ["H1", "H2"])
        XCTAssertEqual(restoredTable.bodyRows.map { $0.map(\.text) }, [["one", "two"], ["three", "four"]])
    }

    func testDeleteKeyConsumesSelectedHeaderRowWithoutDeletingIt() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock(bodyRows: [["one", "two"], ["three", "four"]])])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try tableCell(in: item, row: 0, column: 0, columnCount: 2)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))

        cell.keyDown(with: try shiftDownEvent())
        cell.keyDown(with: try keyDownEvent(keyCode: 117, characters: "\u{F728}"))

        let table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(table.header.map(\.text), ["H1", "H2"])
        XCTAssertEqual(table.bodyRows.map { $0.map(\.text) }, [["one", "two"], ["three", "four"]])
        XCTAssertNil(mounted.view.undoStructuralEdit())
    }

    private static func tableBlock(bodyRows: [[String]] = [["one", "two"]]) -> BlockInputBlock {
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
