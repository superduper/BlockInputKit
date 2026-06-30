import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputPartialLinkCopyTests: XCTestCase {
    func testEditorOwnedPartialLinkLabelCopyUsesSelectedLabel() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Open [docs](https://example.com)")
        ])
        mounted.view.applySelection(
            .text(BlockInputTextRange(blockID: blockID, range: NSRange(location: 7, length: 2))),
            notify: false
        )
        mounted.window.makeFirstResponder(mounted.view)

        try withCleanPasteboard { pasteboard in
            XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandCEvent()))
            XCTAssertEqual(pasteboard.string(forType: .string), "[oc](https://example.com)")
        }
    }

    func testCopyingPartialFileChipLabelUsesSelectedLabel() throws {
        let text = "Open [README.md](file:///tmp/README.md)"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let textView = try textView(in: mounted.view)
        textView.setSelectedRange((text as NSString).range(of: "README"))

        withCleanPasteboard { pasteboard in
            textView.copy(nil)
            XCTAssertEqual(pasteboard.string(forType: .string), "[README](file:///tmp/README.md)")
        }
    }

    func testCopyingPartialSlashCommandChipLabelUsesSelectedLabel() throws {
        let text = "Run [/table](host-app://commands/table) now"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let textView = try textView(in: mounted.view)
        textView.setSelectedRange((text as NSString).range(of: "/ta"))

        withCleanPasteboard { pasteboard in
            textView.copy(nil)
            XCTAssertEqual(pasteboard.string(forType: .string), "[/ta](host-app://commands/table)")
        }
    }

    func testCopyingSelectionAcrossPartialLinksAndChipsDoesNotExposeHiddenMarkdownSource() throws {
        let text = "Include [a normal link](https://github.com/afollestad/BlockInputKit), " +
            "[README.md](file:///tmp/README.md), and [/quote](host-app://commands/quote)."
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let textView = try textView(in: mounted.view)
        let source = text as NSString
        let start = source.range(of: "mal link").location
        let slashRange = source.range(of: "/qu")
        textView.setSelectedRange(NSRange(location: start, length: NSMaxRange(slashRange) - start))

        withCleanPasteboard { pasteboard in
            textView.copy(nil)
            XCTAssertEqual(
                pasteboard.string(forType: .string),
                "[mal link](https://github.com/afollestad/BlockInputKit), " +
                    "[README.md](file:///tmp/README.md), and [/qu](host-app://commands/quote)"
            )
        }
    }

    func testEditorOwnedSelectionAcrossPartialLinksAndChipsDoesNotExposeHiddenMarkdownSource() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let text = "Include [a normal link](https://github.com/afollestad/BlockInputKit), " +
            "[README.md](file:///tmp/README.md), and [/quote](host-app://commands/quote)."
        let source = text as NSString
        let start = source.range(of: "mal link").location
        let slashRange = source.range(of: "/qu")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: text)
        ])
        mounted.view.applySelection(
            .text(BlockInputTextRange(blockID: blockID, range: NSRange(location: start, length: NSMaxRange(slashRange) - start))),
            notify: false
        )
        mounted.window.makeFirstResponder(mounted.view)

        try withCleanPasteboard { pasteboard in
            XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandCEvent()))
            XCTAssertEqual(
                pasteboard.string(forType: .string),
                "[mal link](https://github.com/afollestad/BlockInputKit), " +
                    "[README.md](file:///tmp/README.md), and [/qu](host-app://commands/quote)"
            )
        }
    }

    func testCopyingTableCellPartialLinkLabelUsesSelectedLabel() throws {
        let cellText = "Open [docs](https://example.com)"
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock(cellText: cellText)])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        mounted.window.makeFirstResponder(cell)
        cell.setSelectedRange(NSRange(location: 7, length: 2))

        withCleanPasteboard { pasteboard in
            cell.copy(nil)
            XCTAssertEqual(pasteboard.string(forType: .string), "[oc](https://example.com)")
        }
    }

    private func withCleanPasteboard(_ body: (NSPasteboard) throws -> Void) rethrows {
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }
        try body(pasteboard)
    }

    private func textView(in view: BlockInputView) throws -> BlockInputTextView {
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        return try XCTUnwrap(item.testingTextView)
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
