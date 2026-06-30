import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputLinkBoundaryDeletionTests: XCTestCase {
    func testBackspaceAtFileChipBoundarySelectsThenDeletes() throws {
        let text = "Open [README.md](file:///tmp/README.md) now"
        let mounted = makeMountedBlockInputView(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: text)
            ]),
            undoController: BlockInputUndoController()
        )
        let textView = try activeTextView(in: mounted, text: text)
        let chipRange = (text as NSString).range(of: "[README.md](file:///tmp/README.md)")
        // Caret at the chip's outer trailing edge (visually right after the chip).
        textView.setSelectedRange(NSRange(location: NSMaxRange(chipRange), length: 0))

        // First Backspace selects the whole chip, does NOT delete.
        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), [text])
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(blockID: "block", range: chipRange)))

        // Second Backspace deletes the now-selected chip.
        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["Open  now"])
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: "block", utf16Offset: 5)))

        // The chip deletion is undoable.
        _ = mounted.view.undoTextEditInActiveBlock()
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), [text])
    }

    func testDeleteForwardAtFileChipBoundarySelectsThenDeletes() throws {
        let text = "Open [README.md](file:///tmp/README.md) now"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let textView = try activeTextView(in: mounted, text: text)
        let chipRange = (text as NSString).range(of: "[README.md](file:///tmp/README.md)")
        // Caret at the chip's outer leading edge (the `[`), visually right before the chip.
        textView.setSelectedRange(NSRange(location: chipRange.location, length: 0))

        textView.doCommand(by: #selector(NSResponder.deleteForward(_:)))
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), [text])
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(blockID: "block", range: chipRange)))

        textView.doCommand(by: #selector(NSResponder.deleteForward(_:)))
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["Open  now"])
    }

    func testBackspaceInsideFileLinkLabelDeletesCharacterOnly() throws {
        let text = "Open [cat](file:///tmp/cat.png) now"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let textView = try activeTextView(in: mounted, text: text)
        let caretOffset = (text as NSString).range(of: "cat").location + 2
        textView.setSelectedRange(NSRange(location: caretOffset, length: 0))

        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["Open [ct](file:///tmp/cat.png) now"])
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: "block", utf16Offset: caretOffset - 1)))
    }

    func testDeleteForwardInsideMarkdownImageLabelDeletesCharacterOnly() throws {
        let text = "Open ![cat](file:///tmp/cat.png) now"
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: text)
            ]),
            imagePresentation: .textLinksWithPreviewStrip
        ))
        let textView = try activeTextView(in: mounted, text: text)
        let caretOffset = (text as NSString).range(of: "cat").location + 1
        textView.setSelectedRange(NSRange(location: caretOffset, length: 0))

        textView.doCommand(by: #selector(NSResponder.deleteForward(_:)))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["Open ![ct](file:///tmp/cat.png) now"])
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: "block", utf16Offset: caretOffset)))
    }

    func testBackspaceAtSlashCommandChipBoundarySelectsThenDeletes() throws {
        let text = "Run [/table](host-app://commands/table) now"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let textView = try activeTextView(in: mounted, text: text)
        let chipRange = (text as NSString).range(of: "[/table](host-app://commands/table)")
        textView.setSelectedRange(NSRange(location: NSMaxRange(chipRange), length: 0))

        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), [text])
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(blockID: "block", range: chipRange)))

        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["Run  now"])
    }

    func testDeleteForwardAtRegularLinkBoundaryRemovesWholeLink() throws {
        let text = "Open [docs](https://example.com) now"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let textView = try activeTextView(in: mounted, text: text)
        textView.setSelectedRange(NSRange(location: (text as NSString).range(of: "docs").location, length: 0))

        textView.doCommand(by: #selector(NSResponder.deleteForward(_:)))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["Open  now"])
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: "block", utf16Offset: 5)))
    }

    func testBackspaceAtRegularLinkBoundaryRemovesWholeLink() throws {
        let text = "Open [docs](https://example.com) now"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let textView = try activeTextView(in: mounted, text: text)
        textView.setSelectedRange(NSRange(location: NSMaxRange((text as NSString).range(of: "docs")), length: 0))

        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["Open  now"])
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: "block", utf16Offset: 5)))
    }

    func testBackspaceAtRegularLinkSourceBoundaryRemovesWholeLink() throws {
        let text = "Open [docs](https://example.com) now"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let textView = try activeTextView(in: mounted, text: text)
        let linkRange = (text as NSString).range(of: "[docs](https://example.com)")
        textView.setSelectedRange(NSRange(location: NSMaxRange(linkRange), length: 0))

        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["Open  now"])
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: "block", utf16Offset: 5)))
    }

    func testDeletingSelectionAcrossFileLinksRemovesWholeLinkSources() throws {
        let text = "Focus [One.md](file:///tmp/One.md) [Two.md](file:///tmp/Two.md) done"
        let mounted = makeMountedBlockInputView(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: text)
            ]),
            undoController: BlockInputUndoController()
        )
        let textView = try activeTextView(in: mounted, text: text)
        let selectionStart = (text as NSString).range(of: "One.md").location
        let secondLabelRange = (text as NSString).range(of: "Two.md")
        let selectedRange = NSRange(location: selectionStart, length: NSMaxRange(secondLabelRange) - selectionStart)
        textView.setSelectedRange(selectedRange)

        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["Focus  done"])
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: "block", utf16Offset: 6)))

        _ = mounted.view.undoTextEditInActiveBlock()
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), [text])
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(blockID: "block", range: selectedRange)))
    }

    func testLeftArrowOnSelectedChipPlacesCaretBeforeClosingBracketToEditLabel() throws {
        let text = "Open [README.md](file:///tmp/README.md) now"
        let mounted = makeMountedBlockInputView(blocks: [BlockInputBlock(id: "block", text: text)])
        let textView = try activeTextView(in: mounted, text: text)
        textView.setSelectedRange(NSRange(location: NSMaxRange((text as NSString).range(of: "[README.md](file:///tmp/README.md)")), length: 0))

        // Backspace selects the chip.
        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        // Left arrow drops the caret to the end of the visible label (right after `README.md`, before `]`).
        textView.doCommand(by: #selector(NSResponder.moveLeft(_:)))
        let labelEnd = NSMaxRange((text as NSString).range(of: "README.md"))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: labelEnd, length: 0))

        // Now Backspace erases label characters (the `d` of `.md`) without deleting the chip node.
        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["Open [README.m](file:///tmp/README.md) now"])
    }

    func testRightArrowOnSelectedChipCollapsesPastIt() throws {
        let text = "Open [README.md](file:///tmp/README.md) now"
        let mounted = makeMountedBlockInputView(blocks: [BlockInputBlock(id: "block", text: text)])
        let textView = try activeTextView(in: mounted, text: text)
        textView.setSelectedRange(NSRange(location: NSMaxRange((text as NSString).range(of: "[README.md](file:///tmp/README.md)")), length: 0))

        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))  // select chip
        textView.doCommand(by: #selector(NSResponder.moveRight(_:)))       // collapse past it
        let chipEnd = NSMaxRange((text as NSString).range(of: "[README.md](file:///tmp/README.md)"))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: chipEnd, length: 0))
    }

    private func activeTextView(
        in mounted: (view: BlockInputView, window: NSWindow),
        text: String
    ) throws -> BlockInputTextView {
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        XCTAssertTrue(mounted.window.makeFirstResponder(textView))
        XCTAssertEqual(textView.string, text)
        return textView
    }
}
