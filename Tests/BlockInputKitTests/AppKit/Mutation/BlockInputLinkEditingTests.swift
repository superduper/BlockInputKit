import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputLinkEditingTests: XCTestCase {
    func testCopyingVisibleLinkLabelCopiesMarkdownSource() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open [a\\[b\\]c](https://example.com)")
        ])
        let textView = try textView(in: mounted.view)
        textView.setSelectedRange(NSRange(location: 6, length: 7))

        try withCleanPasteboard { pasteboard in
            textView.copy(nil)
            XCTAssertEqual(pasteboard.string(forType: .string), "[a\\[b\\]c](https://example.com)")
        }
    }

    func testCopyingPartialVisibleLinkLabelCopiesMarkdownWithSelectedLabel() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open [a\\[b\\]c](https://example.com)")
        ])
        let textView = try textView(in: mounted.view)
        textView.setSelectedRange(NSRange(location: 9, length: 1))

        try withCleanPasteboard { pasteboard in
            textView.copy(nil)
            XCTAssertEqual(pasteboard.string(forType: .string), "[b](https://example.com)")
        }
    }

    func testEditorOwnedLinkLabelCopyCopiesMarkdownSource() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Open [docs](https://example.com)")
        ])
        mounted.view.applySelection(
            .text(BlockInputTextRange(blockID: blockID, range: NSRange(location: 6, length: 4))),
            notify: false
        )
        mounted.window.makeFirstResponder(mounted.view)

        try withCleanPasteboard { pasteboard in
            XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandCEvent()))
            XCTAssertEqual(pasteboard.string(forType: .string), "[docs](https://example.com)")
        }
    }

    func testCopyingRelativeFileLinkLabelCopiesMarkdownSource() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: "Open [a\\[b\\]c](assets/README.md)")
            ]),
            fileBaseURL: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let textView = try textView(in: mounted.view)
        textView.setSelectedRange(NSRange(location: 6, length: 7))

        try withCleanPasteboard { pasteboard in
            textView.copy(nil)
            XCTAssertEqual(pasteboard.string(forType: .string), "[a\\[b\\]c](assets/README.md)")
        }
    }

    func testCopyingFileChipLabelCopiesMarkdownSource() throws {
        let text = "Open [README.md](file:///tmp/README.md)"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let textView = try textView(in: mounted.view)
        textView.setSelectedRange((text as NSString).range(of: "README.md"))

        try withCleanPasteboard { pasteboard in
            textView.copy(nil)
            XCTAssertEqual(pasteboard.string(forType: .string), "[README.md](file:///tmp/README.md)")
        }
    }

    func testCopyingSlashCommandLinkChipLabelCopiesMarkdownSource() throws {
        let text = "Run [/table](host-app://commands/table) now"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let textView = try textView(in: mounted.view)
        textView.setSelectedRange((text as NSString).range(of: "/table"))

        try withCleanPasteboard { pasteboard in
            textView.copy(nil)
            XCTAssertEqual(pasteboard.string(forType: .string), "[/table](host-app://commands/table)")
        }
    }

    func testCopyingRawSlashCommandChipKeepsPlainText() throws {
        let text = "/review files"
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: text)
            ]),
            rawSlashCommandChips: true,
            slashCommandAvailability: .anywhere
        ))
        let textView = try textView(in: mounted.view)
        textView.setSelectedRange((text as NSString).range(of: "/review"))

        try withCleanPasteboard { pasteboard in
            textView.copy(nil)
            XCTAssertEqual(pasteboard.string(forType: .string), "/review")
        }
    }

    func testCopyingWholeLinkBlockKeepsMarkdownSource() throws {
        let text = "[docs](https://example.com)"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let textView = try textView(in: mounted.view)
        textView.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))

        try withCleanPasteboard { pasteboard in
            textView.copy(nil)
            XCTAssertEqual(pasteboard.string(forType: .string), text)
        }
    }

    func testCopyingTableCellLinkLabelCopiesMarkdownSource() throws {
        let cellText = "Open [docs](https://example.com)"
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock(cellText: cellText)])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        mounted.window.makeFirstResponder(cell)
        cell.setSelectedRange((cellText as NSString).range(of: "docs"))

        try withCleanPasteboard { pasteboard in
            cell.copy(nil)
            XCTAssertEqual(pasteboard.string(forType: .string), "[docs](https://example.com)")
        }
    }

    func testCopyingTableCellSlashCommandChipLabelCopiesMarkdownSource() throws {
        let cellText = "Run [/table](host-app://commands/table)"
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock(cellText: cellText)])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        mounted.window.makeFirstResponder(cell)
        cell.setSelectedRange((cellText as NSString).range(of: "/table"))

        try withCleanPasteboard { pasteboard in
            cell.copy(nil)
            XCTAssertEqual(pasteboard.string(forType: .string), "[/table](host-app://commands/table)")
        }
    }

    private func textView(in view: BlockInputView) throws -> BlockInputTextView {
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        return try XCTUnwrap(item.testingTextView)
    }

    private func withCleanPasteboard(_ body: (NSPasteboard) throws -> Void) throws {
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
