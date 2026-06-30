import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputTextEditingShortcutTests: XCTestCase {
    func testCopyActionCopiesTextSelectionWhenEditorViewIsFirstResponder() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First")
        ])
        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 1, length: 3)
        )), notify: false)
        mounted.window.makeFirstResponder(mounted.view)
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        mounted.view.blockInputCopy(nil)

        XCTAssertEqual(pasteboard.string(forType: .string), "irs")
    }

    func testCopyResponderActionCopiesTextSelectionWhenEditorViewIsFirstResponder() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First")
        ])
        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 1, length: 3)
        )), notify: false)
        mounted.window.makeFirstResponder(mounted.view)
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        NSApp.sendAction(#selector(NSText.copy(_:)), to: mounted.view, from: nil)

        XCTAssertEqual(pasteboard.string(forType: .string), "irs")
    }

    func testCommandCCopiesTextSelectionWhenEditorViewIsFirstResponder() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First")
        ])
        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 1, length: 3)
        )), notify: false)
        mounted.window.makeFirstResponder(mounted.view)
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandCEvent()))

        XCTAssertEqual(pasteboard.string(forType: .string), "irs")
    }

    func testCommandCCopiesBlockSelectionAsMarkdown() throws {
        let first = BlockInputBlock(id: "first", text: "First")
        let second = BlockInputBlock(id: "second", text: "Second")
        let mounted = makeMountedBlockInputView(blocks: [first, second])
        mounted.view.applySelection(.blocks([first.id, second.id]), notify: false)
        mounted.window.makeFirstResponder(mounted.view)
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandCEvent()))

        XCTAssertEqual(pasteboard.string(forType: .string), BlockInputDocument(blocks: [first, second]).markdown)
    }

    func testCommandCCopiesValidBlockSelectionInDocumentOrder() throws {
        let first = BlockInputBlock(id: "first", text: "First")
        let second = BlockInputBlock(id: "second", text: "Second")
        let mounted = makeMountedBlockInputView(blocks: [first, second])
        mounted.view.applySelection(.blocks([second.id, first.id]), notify: false)
        mounted.window.makeFirstResponder(mounted.view)
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandCEvent()))

        XCTAssertEqual(pasteboard.string(forType: .string), BlockInputDocument(blocks: [first, second]).markdown)
    }

    func testCommandCCopiesMixedSelectionAsMarkdownWithoutWholeEndpointText() throws {
        let first = BlockInputBlock(id: "first", text: "First")
        let second = BlockInputBlock(id: "second", text: "Second")
        let mounted = makeMountedBlockInputView(blocks: [first, second])
        mounted.view.applySelection(.mixed(BlockInputMixedSelection(
            blockIDs: [second.id],
            leadingTextRange: BlockInputTextRange(blockID: first.id, range: NSRange(location: 2, length: 3))
        )), notify: false)
        mounted.window.makeFirstResponder(mounted.view)
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandCEvent()))

        XCTAssertEqual(pasteboard.string(forType: .string), "rst\n\nSecond")
    }

    func testCommandCCopiesMixedPartialListEndpointWithoutMarkerWhenRangeStartsInsideBlock() throws {
        let checklist = BlockInputBlock(id: "check", kind: .checklistItem(isChecked: false), text: "Checklist data")
        let mounted = makeMountedBlockInputView(blocks: [checklist])
        mounted.view.applySelection(.mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: checklist.id, range: NSRange(location: 10, length: 4))
        )), notify: false)
        mounted.window.makeFirstResponder(mounted.view)
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandCEvent()))

        XCTAssertEqual(pasteboard.string(forType: .string), "data")
    }

    func testPasteActionPastesIntoTextSelectionWhenEditorViewIsFirstResponder() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First")
        ])
        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 1, length: 3)
        )), notify: false)
        mounted.window.makeFirstResponder(mounted.view)
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString("oo", forType: .string)
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        mounted.view.blockInputPaste(nil)

        XCTAssertEqual(mounted.view.document.blocks[0].text, "Foot")
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 3)))
    }

    func testCutActionDeletesBlockSelectionAfterCopyingMarkdown() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        mounted.view.applySelection(.blocks([firstID]), notify: false)
        mounted.window.makeFirstResponder(mounted.view)
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        mounted.view.blockInputCut(nil)

        XCTAssertEqual(pasteboard.string(forType: .string), "First")
        XCTAssertEqual(mounted.view.document.blocks.map(\.id), [secondID])
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: secondID, utf16Offset: 0)))
    }

    func testCutActionDeletesMixedSelectionAfterCopyingMarkdown() throws {
        let first = BlockInputBlock(id: "first", text: "First")
        let second = BlockInputBlock(id: "second", text: "Second")
        let mounted = makeMountedBlockInputView(blocks: [first, second])
        mounted.view.applySelection(.mixed(BlockInputMixedSelection(
            blockIDs: [second.id],
            leadingTextRange: BlockInputTextRange(blockID: first.id, range: NSRange(location: 2, length: 3))
        )), notify: false)
        mounted.window.makeFirstResponder(mounted.view)
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        mounted.view.blockInputCut(nil)

        XCTAssertEqual(pasteboard.string(forType: .string), "rst\n\nSecond")
        XCTAssertEqual(mounted.view.document.blocks.map(\.id), [first.id])
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Fi")
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: first.id, utf16Offset: 2)))
    }

    func testCutActionJoinsMixedSelectionPartialEdgeRemainders() throws {
        let first = BlockInputBlock(id: "first", text: "First")
        let second = BlockInputBlock(id: "second", text: "Second")
        let mounted = makeMountedBlockInputView(blocks: [first, second])
        mounted.view.applySelection(.mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: first.id, range: NSRange(location: 2, length: 3)),
            trailingTextRange: BlockInputTextRange(blockID: second.id, range: NSRange(location: 0, length: 3))
        )), notify: false)
        mounted.window.makeFirstResponder(mounted.view)
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        mounted.view.blockInputCut(nil)

        XCTAssertEqual(pasteboard.string(forType: .string), "rst\n\nSec")
        XCTAssertEqual(mounted.view.document.blocks.map(\.id), [first.id])
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Fiond")
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: first.id, utf16Offset: 2)))
    }

    func testCopyResponderActionCopiesSelectedTextFromTextFocus() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "first", text: "First")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 1, length: 3))
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        NSApp.sendAction(#selector(NSText.copy(_:)), to: textView, from: nil)

        XCTAssertEqual(pasteboard.string(forType: .string), "irs")
    }

    func testCopyActionCopiesSelectedTextFromTextFocus() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "first", text: "First")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 1, length: 3))
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        textView.copy(nil)

        XCTAssertEqual(pasteboard.string(forType: .string), "irs")
    }

    func testCommandCCopiesSelectedTextFromTextFocus() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "first", text: "First")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 1, length: 3))
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandCEvent()))

        XCTAssertEqual(pasteboard.string(forType: .string), "irs")
    }

    func testPasteActionPastesTextFromTextFocus() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(" Paste", forType: .string)
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        textView.paste(nil)

        XCTAssertEqual(textView.string, "First Paste")
        XCTAssertEqual(mounted.view.document.blocks[0].text, "First Paste")
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 11)))
    }

    func testCutActionCutsSelectedTextFromTextFocus() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 1, length: 3))
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        textView.cut(nil)

        XCTAssertEqual(pasteboard.string(forType: .string), "irs")
        XCTAssertEqual(textView.string, "Ft")
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Ft")
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 1)))
    }

    func testCutActionWithNoSelectionDoesNotDeleteTextFromTextFocus() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 1, length: 0))

        textView.cut(nil)

        XCTAssertEqual(textView.string, "First")
        XCTAssertEqual(mounted.view.document.blocks[0].text, "First")
    }

    func testPasteResponderActionPastesTextFromTextFocus() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(" Paste", forType: .string)
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        NSApp.sendAction(#selector(NSText.paste(_:)), to: textView, from: nil)

        XCTAssertEqual(textView.string, "First Paste")
        XCTAssertEqual(mounted.view.document.blocks[0].text, "First Paste")
    }
}
