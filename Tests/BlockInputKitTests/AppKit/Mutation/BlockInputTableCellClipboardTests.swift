import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputTableCellClipboardTests: XCTestCase {
    func testFullTableCellLinkLabelCopyUsesMarkdownSource() throws {
        let cellText = #"Open [a\[b\]c](https://example.com)"#
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock(cellText: cellText)])
        let cell = try bodyCell(in: mounted.view)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))
        cell.setSelectedRange((cellText as NSString).range(of: #"a\[b\]c"#))

        withCleanTableCellPasteboard { pasteboard in
            cell.copy(nil)
            XCTAssertEqual(pasteboard.string(forType: .string), #"[a\[b\]c](https://example.com)"#)
        }
    }

    func testPartialTableCellLinkLabelCopyUsesSelectedLabelLink() throws {
        let cellText = #"Open [a\[b\]c](https://example.com)"#
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock(cellText: cellText)])
        let cell = try bodyCell(in: mounted.view)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))
        cell.setSelectedRange((cellText as NSString).range(of: "b"))

        withCleanTableCellPasteboard { pasteboard in
            cell.copy(nil)
            XCTAssertEqual(pasteboard.string(forType: .string), "[b](https://example.com)")
        }
    }

    func testPartialTableCellCutUsesCellTextOnlyAndUpdatesTable() throws {
        let cellText = "alpha beta"
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock(cellText: cellText)])
        let cell = try bodyCell(in: mounted.view)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))
        cell.setSelectedRange((cellText as NSString).range(of: "alpha"))

        try withCleanTableCellPasteboard { pasteboard in
            cell.cut(nil)

            XCTAssertEqual(pasteboard.string(forType: .string), "alpha")
            let table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
            XCTAssertEqual(table.bodyRows[0][0].text, "beta")
        }
    }

    private func bodyCell(in view: BlockInputView) throws -> BlockInputTableCellTextView {
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        return try XCTUnwrap(item.testingTableCellTextViews.indices.contains(2) ? item.testingTableCellTextViews[2] : nil)
    }

    private static func tableBlock(cellText: String) -> BlockInputBlock {
        BlockInputBlock(
            id: "table",
            kind: .table,
            text: BlockInputTable.normalized(
                header: ["H1", "H2"],
                bodyRows: [[cellText, "two"]],
                alignments: [.left, .left]
            ).markdown
        )
    }
}
