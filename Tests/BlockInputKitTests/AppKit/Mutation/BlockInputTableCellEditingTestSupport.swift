import AppKit
import XCTest
@testable import BlockInputKit

extension BlockInputTable {
    func selection(
        blockID: BlockInputBlockID,
        position: BlockInputTable.CellPosition,
        localRange: NSRange
    ) -> BlockInputSelection? {
        guard let sourceRange = sourceRange(forLocalRange: localRange, in: position) else {
            return nil
        }
        if sourceRange.length == 0 {
            return .cursor(BlockInputCursor(blockID: blockID, utf16Offset: sourceRange.location))
        }
        return .text(BlockInputTextRange(blockID: blockID, range: sourceRange))
    }
}

func withCleanTableCellPasteboard(_ body: (NSPasteboard) throws -> Void) rethrows {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    defer { pasteboard.clearContents() }
    try body(pasteboard)
}

func performTableCellMenuItem(titled title: String, in menu: NSMenu) throws {
    let item = try XCTUnwrap(menu.item(withTitle: title))
    guard let target = item.target, let action = item.action else {
        XCTFail("Menu item \(title) is missing a target/action")
        return
    }
    _ = target.perform(action, with: item)
}

@MainActor
func tableCellMenu(for cell: BlockInputTableCellTextView, windowNumber: Int) throws -> NSMenu {
    try XCTUnwrap(cell.menu(for: try rightMouseDownEvent(
        location: cell.convert(NSPoint(x: cell.bounds.midX, y: cell.bounds.midY), to: nil),
        windowNumber: windowNumber
    )))
}

@MainActor
func tableEditingTextView(in view: BlockInputView) throws -> BlockInputTextView {
    let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
    return item.textView
}

@MainActor
func tableCell(
    in item: BlockInputBlockItem,
    row: Int,
    column: Int,
    columnCount: Int
) throws -> BlockInputTableCellTextView {
    let index = row * columnCount + column
    return try XCTUnwrap(item.testingTableCellTextViews.indices.contains(index) ? item.testingTableCellTextViews[index] : nil)
}

@MainActor
func bodyCell(
    in item: BlockInputBlockItem,
    row: Int,
    column: Int,
    columnCount: Int = 2
) throws -> BlockInputTableCellTextView {
    try tableCell(in: item, row: row + 1, column: column, columnCount: columnCount)
}
