import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputTableCellCommandArrowTests: XCTestCase {
    func testCommandArrowsInsideCellMoveWithinCell() throws {
        let cases: [(event: NSEvent, expectedRange: NSRange)] = [
            (try commandUpEvent(), NSRange(location: 0, length: 0)),
            (try commandDownEvent(), NSRange(location: 3, length: 0)),
            (try commandLeftEvent(), NSRange(location: 0, length: 0)),
            (try commandRightEvent(), NSRange(location: 3, length: 0))
        ]

        for testCase in cases {
            let mounted = makeMountedBlockInputView(blocks: [
                Self.tableBlock(),
                BlockInputBlock(id: "after", text: "After")
            ])
            let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
            let cell = try bodyCell(in: item, row: 0, column: 1)
            let table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
            XCTAssertTrue(mounted.window.makeFirstResponder(cell))

            cell.setSelectedRange(NSRange(location: 1, length: 0))
            cell.keyDown(with: testCase.event)

            XCTAssertEqual(cell.selectedRange(), testCase.expectedRange)
            XCTAssertEqual(
                mounted.view.selection,
                table.selection(
                    blockID: "table",
                    position: .init(row: .body(0), column: 1),
                    localRange: testCase.expectedRange
                )
            )
            XCTAssertTrue(mounted.window.firstResponder === cell)
        }
    }

    func testCommandArrowKeyEquivalentInsideCellStaysLocal() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        let table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))
        cell.setSelectedRange(NSRange(location: 1, length: 0))

        XCTAssertTrue(cell.performKeyEquivalent(with: try commandRightEvent()))

        XCTAssertEqual(cell.selectedRange(), NSRange(location: 3, length: 0))
        XCTAssertEqual(
            mounted.view.selection,
            table.selection(
                blockID: "table",
                position: .init(row: .body(0), column: 0),
                localRange: NSRange(location: 3, length: 0)
            )
        )
    }

    func testCommandArrowKeyEquivalentThroughEditorStaysLocal() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        let table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))
        cell.setSelectedRange(NSRange(location: 1, length: 0))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandRightEvent()))

        XCTAssertEqual(cell.selectedRange(), NSRange(location: 3, length: 0))
        XCTAssertEqual(
            mounted.view.selection,
            table.selection(
                blockID: "table",
                position: .init(row: .body(0), column: 0),
                localRange: NSRange(location: 3, length: 0)
            )
        )
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
