import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputTableCellDragSelectionTests: XCTestCase {
    func testDragAcrossTableCellsSelectsRectangularRange() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let firstCell = try bodyCell(in: item, row: 0, column: 0)
        let lastCell = try bodyCell(in: item, row: 1, column: 1)

        try drag(from: firstCell, to: lastCell, window: mounted.window)

        XCTAssertEqual(
            item.testingSelectedTableCellRange,
            BlockInputTableCellSelection(
                anchor: .init(row: .body(0), column: 0),
                focus: .init(row: .body(1), column: 1)
            )
        )
        XCTAssertEqual(item.testingTableCellViews.map(\.isCellSelectedForTesting), [
            false, false,
            true, true,
            true, true
        ])
    }

    func testDragAcrossTableRowSelectsRowCells() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let firstCell = try bodyCell(in: item, row: 0, column: 0)
        let lastCell = try bodyCell(in: item, row: 0, column: 1)

        try drag(from: firstCell, to: lastCell, window: mounted.window)

        XCTAssertEqual(item.testingTableCellViews.map(\.isCellSelectedForTesting), [
            false, false,
            true, true,
            false, false
        ])
    }

    func testDragAcrossTableColumnSelectsColumnCells() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let firstCell = try tableCell(in: item, row: 0, column: 1)
        let lastCell = try bodyCell(in: item, row: 1, column: 1)

        try drag(from: firstCell, to: lastCell, window: mounted.window)

        XCTAssertEqual(item.testingTableCellViews.map(\.isCellSelectedForTesting), [
            false, true,
            false, true,
            false, true
        ])
    }

    func testSameCellDragDoesNotPromoteToTableCellSelection() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)

        try drag(from: cell, to: cell, window: mounted.window)

        XCTAssertNil(item.testingSelectedTableCellRange)
        XCTAssertTrue(item.testingTableCellViews.allSatisfy { !$0.isCellSelectedForTesting })
    }

    func testShiftDownStartsAtCurrentCellThenExpandsAndCollapsesRows() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))

        cell.keyDown(with: try shiftDownEvent())
        XCTAssertEqual(
            item.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .body(0), column: 0), focus: .init(row: .body(0), column: 1))
        )
        XCTAssertEqual(item.testingTableCellViews.map(\.isCellSelectedForTesting), [
            false, false,
            true, true,
            false, false
        ])

        cell.keyDown(with: try shiftDownEvent())
        XCTAssertEqual(
            item.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .body(0), column: 0), focus: .init(row: .body(1), column: 1))
        )
        XCTAssertEqual(item.testingTableCellViews.map(\.isCellSelectedForTesting), [
            false, false,
            true, true,
            true, true
        ])

        cell.keyDown(with: try shiftUpEvent())
        XCTAssertEqual(
            item.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .body(0), column: 0), focus: .init(row: .body(0), column: 1))
        )

        cell.keyDown(with: try shiftUpEvent())
        XCTAssertEqual(
            item.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .body(0), column: 0), focus: .init(row: .header, column: 1))
        )
        XCTAssertEqual(item.testingTableCellViews.map(\.isCellSelectedForTesting), [
            true, true,
            true, true,
            false, false
        ])
    }

    func testShiftRightStartsAtCurrentCellThenExpandsAndCollapsesColumns() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))

        cell.keyDown(with: try shiftRightEvent())
        XCTAssertEqual(
            item.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .header, column: 0), focus: .init(row: .body(1), column: 0))
        )
        XCTAssertEqual(item.testingTableCellViews.map(\.isCellSelectedForTesting), [
            true, false,
            true, false,
            true, false
        ])

        cell.keyDown(with: try shiftRightEvent())
        XCTAssertEqual(mounted.view.selection, .blocks(["table"]))
        XCTAssertNil(item.testingSelectedTableCellRange)

        XCTAssertTrue(mounted.window.firstResponder === mounted.view)
    }

    func testShiftArrowKeyEquivalentThroughEditorRoutesToCellSelection() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        let table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))
        mounted.view.applySelection(.blocks(["table"]), notify: true)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftDownEvent()))

        XCTAssertEqual(
            item.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .body(0), column: 0), focus: .init(row: .body(0), column: 1))
        )
        XCTAssertEqual(
            mounted.view.selection,
            table.selection(blockID: "table", position: .init(row: .body(0), column: 0), localRange: cell.selectedRange())
        )
    }

    func testShiftArrowCommandThroughEditorRoutesToCellSelection() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))
        mounted.view.applySelection(.blocks(["table"]), notify: true)

        mounted.view.doCommand(by: #selector(NSResponder.moveRightAndModifySelection(_:)))

        XCTAssertEqual(
            item.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .header, column: 0), focus: .init(row: .body(1), column: 0))
        )
        XCTAssertNotEqual(mounted.view.selection, .blocks(["table"]))
    }

    func testShiftArrowForwardBackwardCommandsThroughEditorRouteToCellSelection() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let firstColumnCell = try bodyCell(in: item, row: 0, column: 0)
        let secondColumnCell = try bodyCell(in: item, row: 0, column: 1)
        XCTAssertTrue(mounted.window.makeFirstResponder(firstColumnCell))
        mounted.view.applySelection(.blocks(["table"]), notify: true)

        mounted.view.doCommand(by: #selector(NSResponder.moveForwardAndModifySelection(_:)))

        XCTAssertEqual(
            item.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .header, column: 0), focus: .init(row: .body(1), column: 0))
        )

        item.tableView.clearKeyboardCellSelection()
        XCTAssertTrue(mounted.window.makeFirstResponder(secondColumnCell))
        mounted.view.applySelection(.blocks(["table"]), notify: true)

        mounted.view.doCommand(by: #selector(NSResponder.moveBackwardAndModifySelection(_:)))

        XCTAssertEqual(
            item.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .header, column: 1), focus: .init(row: .body(1), column: 1))
        )
    }

    func testShiftArrowsSwitchBetweenRowAndColumnSelectionAxes() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))

        cell.keyDown(with: try shiftRightEvent())
        cell.keyDown(with: try shiftDownEvent())
        XCTAssertEqual(item.testingTableCellViews.map(\.isCellSelectedForTesting), [
            false, false,
            true, true,
            false, false
        ])

        cell.keyDown(with: try shiftLeftEvent())
        XCTAssertEqual(
            item.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .header, column: 0), focus: .init(row: .body(1), column: 0))
        )
        XCTAssertEqual(item.testingTableCellViews.map(\.isCellSelectedForTesting), [
            true, false,
            true, false,
            true, false
        ])
    }

    func testShiftArrowSelectionPromotesAllCellsToWholeTableSelection() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 1, column: 1)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))

        cell.keyDown(with: try shiftUpEvent())
        cell.keyDown(with: try shiftUpEvent())
        cell.keyDown(with: try shiftUpEvent())

        XCTAssertEqual(mounted.view.selection, .blocks(["table"]))
        XCTAssertTrue(mounted.window.firstResponder === mounted.view)
        XCTAssertNil(item.testingSelectedTableCellRange)
        XCTAssertTrue(item.testingTableCellViews.allSatisfy { !$0.isCellSelectedForTesting })
    }

    func testDraggingAcrossAllCellsPromotesToWholeTableSelection() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let firstCell = try tableCell(in: item, row: 0, column: 0)
        let lastCell = try bodyCell(in: item, row: 1, column: 1)

        try drag(from: firstCell, to: lastCell, window: mounted.window)

        XCTAssertEqual(mounted.view.selection, .blocks(["table"]))
        XCTAssertTrue(mounted.window.firstResponder === mounted.view)
        XCTAssertNil(item.testingSelectedTableCellRange)
        XCTAssertTrue(item.testingTableCellViews.allSatisfy { !$0.isCellSelectedForTesting })
    }

    private func drag(
        from sourceCell: BlockInputTableCellTextView,
        to targetCell: BlockInputTableCellTextView,
        window: NSWindow
    ) throws {
        let targetLocation = targetCell.windowCenter
        sourceCell.blockItem?.beginTableCellSelectionDrag(from: sourceCell)
        sourceCell.mouseDragged(with: try mouseDraggedEvent(location: targetLocation, windowNumber: window.windowNumber))
        sourceCell.mouseUp(with: try mouseUpEvent(location: targetLocation, windowNumber: window.windowNumber))
    }

    private func bodyCell(in item: BlockInputBlockItem, row: Int, column: Int) throws -> BlockInputTableCellTextView {
        try tableCell(in: item, row: row + 1, column: column)
    }

    private func tableCell(in item: BlockInputBlockItem, row: Int, column: Int) throws -> BlockInputTableCellTextView {
        let columnCount = 2
        let index = row * columnCount + column
        return try XCTUnwrap(item.testingTableCellTextViews.indices.contains(index) ? item.testingTableCellTextViews[index] : nil)
    }

    private static func tableBlock() -> BlockInputBlock {
        BlockInputBlock(
            id: "table",
            kind: .table,
            text: BlockInputTable.normalized(
                header: ["H1", "H2"],
                bodyRows: [["one", "two"], ["three", "four"]],
                alignments: [.left, .left]
            ).markdown
        )
    }
}

private extension NSView {
    var windowCenter: NSPoint {
        convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
    }
}
