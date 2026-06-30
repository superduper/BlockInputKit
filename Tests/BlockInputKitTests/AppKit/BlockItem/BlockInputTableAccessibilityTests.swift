import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputTableAccessibilityTests: XCTestCase {
    func testTableAccessibilityLabelsAndActions() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock(bodyRows: [["", "two"]])])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let tableView = item.testingTableView
        let headerCell = try tableCell(in: item, row: 0, column: 0, columnCount: 2)
        let bodyCell = try bodyCell(in: item, row: 0, column: 0)

        XCTAssertEqual(tableView.accessibilityRole(), .group)
        XCTAssertEqual(tableView.accessibilityLabel(), "Table, 2 rows, 2 columns")
        XCTAssertEqual(headerCell.accessibilityLabel(), "Table cell, header row 1, column 1")
        XCTAssertEqual(bodyCell.accessibilityLabel(), "Table cell, body row 1, column 1")
        XCTAssertEqual(item.testingAppendTableRowButton.accessibilityLabel(), "Append Table Row")
        XCTAssertEqual(item.testingAppendTableColumnButton.accessibilityLabel(), "Append Table Column")

        XCTAssertTrue(mounted.window.makeFirstResponder(bodyCell))
        bodyCell.doCommand(by: #selector(NSResponder.deleteForward(_:)))
        XCTAssertEqual(bodyCell.accessibilityLabel(), "Table cell, body row 1, column 1, row selected")

        let actions = try XCTUnwrap(tableView.accessibilityCustomActions())
        XCTAssertEqual(actions.map(\.name), ["Append Table Row", "Append Table Column"])
        let appendRowSelector = try XCTUnwrap(actions[0].selector)
        let appendRowTarget = try XCTUnwrap(actions[0].target as? NSObject)
        _ = appendRowTarget.perform(appendRowSelector, with: actions[0])

        let table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(table.bodyRows.count, 2)
    }

    func testAppendControlsHideAfterTableReuseReset() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let tableView = item.testingTableView
        let tableFrame = tableView.visibleTableFrame

        tableView.updateAppendControlVisibility(for: NSPoint(x: tableFrame.midX, y: tableFrame.maxY))
        XCTAssertFalse(item.testingAppendTableRowButton.isHidden)

        tableView.resetForReuse()

        XCTAssertTrue(item.testingAppendTableRowButton.isHidden)
        XCTAssertTrue(item.testingAppendTableColumnButton.isHidden)
        XCTAssertNil(tableView.accessibilityLabel())
        XCTAssertNil(tableView.accessibilityCustomActions())
    }

    private func bodyCell(in item: BlockInputBlockItem, row: Int, column: Int) throws -> BlockInputTableCellTextView {
        try tableCell(in: item, row: row + 1, column: column, columnCount: 2)
    }

    private func tableCell(in item: BlockInputBlockItem, row: Int, column: Int, columnCount: Int) throws -> BlockInputTableCellTextView {
        let index = row * columnCount + column
        return try XCTUnwrap(item.testingTableCellTextViews[safe: index])
    }

    private static func tableBlock(
        header: [String] = ["H1", "H2"],
        bodyRows: [[String]] = [["one", "two"]]
    ) -> BlockInputBlock {
        let columnCount = max(header.count, bodyRows.map(\.count).max() ?? 0)
        return BlockInputBlock(
            id: "table",
            kind: .table,
            text: BlockInputTable.normalized(
                header: header,
                bodyRows: bodyRows,
                alignments: Array(repeating: .left, count: columnCount)
            ).markdown
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
