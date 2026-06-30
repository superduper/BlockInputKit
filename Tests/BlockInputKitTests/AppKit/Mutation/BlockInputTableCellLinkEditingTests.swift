import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputTableCellLinkEditingTests: XCTestCase {
    func testPlainClickInTableCellOpensLinkModal() throws {
        // Table-cell link editing is reached through the modal on a plain click only in the legacy interaction
        // model (linkHoverEditAffordance off). Mount legacy so this editing-flow assertion still holds; the new
        // plain-click-opens model is covered for regular links in BlockInputLinkClickTests.
        let cellText = "Open [docs](https://example.com)"
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                Self.tableBlock(bodyRows: [[cellText, "two"]])
            ]),
            linkHoverEditAffordance: false
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        let location = try windowLocation(forLocalOffset: contentLocation("docs", in: cellText), in: cell, window: mounted.window)

        cell.mouseUp(with: try mouseUpEvent(location: location, windowNumber: mounted.window.windowNumber))

        let modal = try XCTUnwrap(mounted.view.linkModalView)
        XCTAssertEqual(modal.textField.stringValue, "docs")
        XCTAssertEqual(modal.urlField.stringValue, "https://example.com")
    }

    func testCommandClickInTableCellOpensURL() throws {
        let cellText = "Open [docs](https://example.com)"
        let mounted = makeMountedBlockInputView(blocks: [
            Self.tableBlock(bodyRows: [[cellText, "two"]])
        ])
        var openedURL: URL?
        mounted.view.linkURLOpener = {
            openedURL = $0
            return true
        }
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        let location = try windowLocation(forLocalOffset: contentLocation("docs", in: cellText), in: cell, window: mounted.window)

        cell.mouseDown(with: try mouseDownEvent(
            location: location,
            windowNumber: mounted.window.windowNumber,
            modifierFlags: .command
        ))

        XCTAssertEqual(openedURL?.absoluteString, "https://example.com")
        XCTAssertNil(mounted.view.linkModalView)
    }

    func testURLPasteInTableCellPreservesLiteralPipeLabel() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock(bodyRows: [["a|b", "two"]])])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))
        cell.setSelectedRange(NSRange(location: 0, length: 3))

        withCleanTableCellPasteboard { pasteboard in
            pasteboard.setString("https://example.com", forType: .string)
            cell.paste(nil)
        }

        let table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(table.bodyRows[0][0].text, "[a|b](https://example.com)")
        XCTAssertTrue(mounted.view.document.blocks[0].text.contains("[a\\|b](https://example.com)"))
    }

    func testLinkModalAndRemovalUseUnescapedTableCellPipeLabel() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            Self.tableBlock(bodyRows: [["[a|b](https://example.com)", "two"]])
        ])
        let table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        let selectedRange = try XCTUnwrap(table.sourceRange(
            forLocalRange: NSRange(location: 2, length: 0),
            in: .init(row: .body(0), column: 0)
        ))
        let context = try XCTUnwrap(mounted.view.linkContext(
            blockID: "table",
            selectedRange: selectedRange,
            event: nil,
            prefersClickedOffset: false
        ))

        mounted.view.showLinkModal(context: context)
        let modal = try XCTUnwrap(mounted.view.linkModalView)
        XCTAssertEqual(modal.textField.stringValue, "a|b")

        XCTAssertTrue(mounted.view.removeLink(context: context))
        let updatedTable = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(updatedTable.bodyRows[0][0].text, "a|b")
    }

    private func bodyCell(in item: BlockInputBlockItem, row: Int, column: Int) throws -> BlockInputTableCellTextView {
        let index = (row + 1) * 2 + column
        return try XCTUnwrap(item.testingTableCellTextViews.indices.contains(index) ? item.testingTableCellTextViews[index] : nil)
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

    private func contentLocation(_ content: String, in text: String) -> Int {
        (text as NSString).range(of: content).location
    }

    private func windowLocation(
        forLocalOffset offset: Int,
        in cell: BlockInputTableCellTextView,
        window: NSWindow
    ) throws -> NSPoint {
        let rect = cell.firstRect(forCharacterRange: NSRange(location: offset, length: 0), actualRange: nil)
        guard rect != .zero, !rect.isNull, !rect.isInfinite else {
            return cell.convert(NSPoint(x: cell.textContainerOrigin.x, y: cell.textContainerOrigin.y + 8), to: nil)
        }
        let point = window.convertPoint(fromScreen: rect.origin)
        return NSPoint(x: point.x, y: point.y + 4)
    }
}
