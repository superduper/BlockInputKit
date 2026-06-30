import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
extension BlockInputTableCellEditingTests {
    func testSelectAllDocumentBehaviorSelectsDocumentFromFocusedCell() throws {
        let paragraph = BlockInputBlock(id: "paragraph", text: "Start")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [paragraph, Self.tableBlock()]),
            selectAllBehavior: .document
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))

        cell.doCommand(by: #selector(NSResponder.selectAll(_:)))

        XCTAssertEqual(mounted.view.selection, .blocks(["paragraph", "table"]))
    }
}
