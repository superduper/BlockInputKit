import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputLinkModalEditingTests: XCTestCase {
    func testContextMenuShowsInsertAndRemoveLinkWhenCaretIsOnLink() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open [docs](https://example.com)")
        ])
        let textView = try textView(in: mounted.view)
        textView.setSelectedRange(NSRange(location: 7, length: 0))
        let menu = try XCTUnwrap(textView.menu(for: try rightMouseDownEvent(
            location: try windowLocation(forUTF16Offset: 7, in: textView),
            windowNumber: mounted.window.windowNumber
        )))

        let insertIndex = try XCTUnwrap(menu.items.firstIndex { $0.title == "Insert Link" })
        XCTAssertEqual(menu.items[insertIndex + 1].title, "Insert Image")
        XCTAssertEqual(menu.items[insertIndex + 2].title, "Insert Table")
        XCTAssertEqual(menu.items[insertIndex + 3].title, "Remove Link")

        try performMenuItem(titled: "Remove Link", in: menu)

        XCTAssertEqual(mounted.view.document.blocks[0].text, "Open docs")
    }

    func testContextMenuDoesNotShowRemoveLinkForSelectedLinkText() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open [docs](https://example.com)")
        ])
        let textView = try textView(in: mounted.view)
        XCTAssertTrue(mounted.window.makeFirstResponder(textView))
        textView.setSelectedRange(NSRange(location: 6, length: 4))

        let menu = try XCTUnwrap(textView.menu(for: try rightMouseDownEvent(
            location: try windowLocation(forUTF16Offset: 7, in: textView),
            windowNumber: mounted.window.windowNumber
        )))

        XCTAssertNotNil(menu.item(withTitle: "Insert Link"))
        XCTAssertNil(menu.item(withTitle: "Remove Link"))
    }

    func testInsertLinkMenuOpensModalAndSaveInsertsLink() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open docs")
        ])
        let textView = try textView(in: mounted.view)
        textView.setSelectedRange(NSRange(location: 5, length: 4))
        let menu = try XCTUnwrap(textView.menu(for: try rightMouseDownEvent(
            location: try windowLocation(forUTF16Offset: 6, in: textView),
            windowNumber: mounted.window.windowNumber
        )))

        try performMenuItem(titled: "Insert Link", in: menu)
        let modal = try XCTUnwrap(mounted.view.linkModalView)
        XCTAssertEqual(modal.textField.stringValue, "docs")

        modal.urlField.stringValue = "https://example.com"
        modal.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: modal.urlField))
        modal.saveButton.performClick(nil)

        XCTAssertEqual(mounted.view.document.blocks[0].text, "Open [docs](https://example.com)")
        XCTAssertNil(mounted.view.linkModalView)
    }

    func testSavingLinkModalRestoresFocusToResultingLinkText() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open docs")
        ])
        let textView = try textView(in: mounted.view)
        textView.setSelectedRange(NSRange(location: 5, length: 4))
        let context = try XCTUnwrap(mounted.view.linkContext(
            blockID: "block",
            selectedRange: NSRange(location: 5, length: 4),
            event: nil,
            prefersClickedOffset: false
        ))

        mounted.view.showLinkModal(context: context)
        let modal = try XCTUnwrap(mounted.view.linkModalView)
        modal.urlField.stringValue = "https://example.com"
        modal.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: modal.urlField))
        modal.saveButton.performClick(nil)

        XCTAssertNil(mounted.view.linkModalView)
        XCTAssertTrue(mounted.window.firstResponder === textView)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 6, length: 4))
    }

    func testInsertLinkMenuAtCaretShowsOpenButtonInCreateModal() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open docs")
        ])
        let textView = try textView(in: mounted.view)
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        let menu = try XCTUnwrap(textView.menu(for: try rightMouseDownEvent(
            location: try windowLocation(forUTF16Offset: 5, in: textView),
            windowNumber: mounted.window.windowNumber
        )))

        try performMenuItem(titled: "Insert Link", in: menu)
        let modal = try XCTUnwrap(mounted.view.linkModalView)

        XCTAssertFalse(modal.openButton.isHidden)
        XCTAssertFalse(modal.openButton.isEnabled)

        modal.urlField.stringValue = "https:example.com"
        modal.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: modal.urlField))
        XCTAssertFalse(modal.openButton.isEnabled)

        modal.urlField.stringValue = "https://example.com"
        modal.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: modal.urlField))
        XCTAssertTrue(modal.openButton.isEnabled)
    }

    func testEditModalOpensAndRemovesExistingLink() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open [docs](https://example.com)")
        ])
        var openedURL: URL?
        mounted.view.linkURLOpener = {
            openedURL = $0
            return true
        }
        let context = try XCTUnwrap(mounted.view.linkContext(
            blockID: "block",
            selectedRange: NSRange(location: 7, length: 0),
            event: nil,
            prefersClickedOffset: false
        ))

        mounted.view.showLinkModal(context: context)
        let modal = try XCTUnwrap(mounted.view.linkModalView)
        modal.layoutSubtreeIfNeeded()
        let removeButtonCenter = NSPoint(x: modal.removeButton.bounds.midX, y: modal.removeButton.bounds.midY)
        XCTAssertIdentical(modal.removeButton.hitTest(removeButtonCenter), modal.removeButton)

        modal.openButton.performClick(nil)
        XCTAssertEqual(openedURL?.absoluteString, "https://example.com")

        modal.removeButton.performClick(nil)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Open docs")
        XCTAssertNil(mounted.view.linkModalView)
    }

    func testEditModalSaveUpdatesExistingLinkTextAndDestination() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open [docs](https://example.com)")
        ])
        let textView = try textView(in: mounted.view)
        let context = try XCTUnwrap(mounted.view.linkContext(
            blockID: "block",
            selectedRange: NSRange(location: 7, length: 0),
            event: nil,
            prefersClickedOffset: false
        ))

        mounted.view.showLinkModal(context: context)
        let modal = try XCTUnwrap(mounted.view.linkModalView)
        modal.textField.stringValue = "guide"
        modal.urlField.stringValue = "file:///tmp/guide.md"
        modal.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: modal.urlField))
        modal.saveButton.performClick(nil)

        XCTAssertNil(mounted.view.linkModalView)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Open [guide](file:///tmp/guide.md)")
        XCTAssertTrue(mounted.window.firstResponder === textView)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 6, length: 5))
    }

    func testEditModalPreservesRelativeFileDestinationWithFileBaseURL() throws {
        let baseURL = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: "Open [docs](assets/README.md)")
            ]),
            fileBaseURL: baseURL
        ))
        var openedURL: URL?
        mounted.view.linkURLOpener = {
            openedURL = $0
            return true
        }
        let context = try XCTUnwrap(mounted.view.linkContext(
            blockID: "block",
            selectedRange: NSRange(location: 7, length: 0),
            event: nil,
            prefersClickedOffset: false
        ))

        mounted.view.showLinkModal(context: context)
        let modal = try XCTUnwrap(mounted.view.linkModalView)
        XCTAssertEqual(modal.urlField.stringValue, "assets/README.md")
        XCTAssertTrue(modal.openButton.isEnabled)
        XCTAssertTrue(modal.saveButton.isEnabled)

        modal.openButton.performClick(nil)
        XCTAssertEqual(openedURL, baseURL.appendingPathComponent("assets").appendingPathComponent("README.md"))

        modal.textField.stringValue = "guide"
        modal.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: modal.textField))
        modal.saveButton.performClick(nil)

        XCTAssertEqual(mounted.view.document.blocks[0].text, "Open [guide](assets/README.md)")
    }

    func testRemovingLinkFromModalRestoresFocusToPlainText() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open [docs](https://example.com)")
        ])
        let textView = try textView(in: mounted.view)
        let context = try XCTUnwrap(mounted.view.linkContext(
            blockID: "block",
            selectedRange: NSRange(location: 7, length: 0),
            event: nil,
            prefersClickedOffset: false
        ))

        mounted.view.showLinkModal(context: context)
        let modal = try XCTUnwrap(mounted.view.linkModalView)
        modal.removeButton.performClick(nil)

        XCTAssertNil(mounted.view.linkModalView)
        XCTAssertTrue(mounted.window.firstResponder === textView)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 5, length: 4))
    }

    func testLinkModalDismissesWhenSelectionMovesOutsideContext() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open [docs](https://example.com)"),
            BlockInputBlock(id: "other", text: "Other")
        ])
        let context = try XCTUnwrap(mounted.view.linkContext(
            blockID: "block",
            selectedRange: NSRange(location: 7, length: 0),
            event: nil,
            prefersClickedOffset: false
        ))

        mounted.view.showLinkModal(context: context)
        XCTAssertNotNil(mounted.view.linkModalView)

        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: "other", utf16Offset: 0)), notify: true)
        XCTAssertNil(mounted.view.linkModalView)
    }

    func testSavingStaleLinkModalDismissesWithoutMutation() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open [docs](https://example.com)")
        ])
        let context = try XCTUnwrap(mounted.view.linkContext(
            blockID: "block",
            selectedRange: NSRange(location: 7, length: 0),
            event: nil,
            prefersClickedOffset: false
        ))

        mounted.view.showLinkModal(context: context)
        let modal = try XCTUnwrap(mounted.view.linkModalView)
        modal.urlField.stringValue = "https://changed.example"
        mounted.view.documentStore?.replaceBlock(BlockInputBlock(id: "block", text: "Open docs"))
        modal.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: modal.urlField))
        modal.saveButton.performClick(nil)

        XCTAssertNil(mounted.view.linkModalView)
        XCTAssertEqual(mounted.view.block(withID: "block")?.text, "Open docs")
    }

    func testSavingStaleCreateModalDismissesWithoutMutation() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Open docs")
        ])
        let context = try XCTUnwrap(mounted.view.linkContext(
            blockID: blockID,
            selectedRange: NSRange(location: 5, length: 4),
            event: nil,
            prefersClickedOffset: false
        ))

        mounted.view.showLinkModal(context: context)
        let modal = try XCTUnwrap(mounted.view.linkModalView)
        modal.urlField.stringValue = "https://example.com"
        mounted.view.documentStore?.replaceBlock(BlockInputBlock(id: blockID, text: "Open changed"))
        modal.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: modal.urlField))
        modal.saveButton.performClick(nil)

        XCTAssertNil(mounted.view.linkModalView)
        XCTAssertEqual(mounted.view.block(withID: blockID)?.text, "Open changed")
    }

    func testEscapeFromFocusedModalFieldDismissesWithoutMutation() throws {
        let originalText = "Open [docs](https://example.com)"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: originalText)
        ])
        let context = try XCTUnwrap(mounted.view.linkContext(
            blockID: "block",
            selectedRange: NSRange(location: 7, length: 0),
            event: nil,
            prefersClickedOffset: false
        ))

        mounted.view.showLinkModal(context: context)
        let modal = try XCTUnwrap(mounted.view.linkModalView)
        modal.textField.stringValue = "Changed"
        modal.urlField.stringValue = "https://changed.example"

        XCTAssertTrue(modal.control(modal.textField, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:))))

        XCTAssertNil(mounted.view.linkModalView)
        XCTAssertEqual(mounted.view.document.blocks[0].text, originalText)
    }

    func testRightArrowAfterEscapeFromEditModalLeavesInlineChip() throws {
        let text = "Open [AGENTS.md](file:///tmp/AGENTS.md) after"
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: text)
        ])
        let textView = try textView(in: mounted.view)
        let labelRange = (text as NSString).range(of: "AGENTS.md")
        let linkRange = try XCTUnwrap(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text).first)
        let context = try XCTUnwrap(mounted.view.linkContext(
            blockID: blockID,
            selectedRange: NSRange(location: labelRange.location, length: 0),
            event: nil,
            prefersClickedOffset: false
        ))

        mounted.view.showLinkModal(context: context)
        let modal = try XCTUnwrap(mounted.view.linkModalView)
        XCTAssertTrue(modal.control(modal.textField, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertEqual(textView.selectedRange(), labelRange)

        textView.keyDown(with: try plainRightEvent())
        XCTAssertEqual(textView.selectedRange(), NSRange(location: NSMaxRange(labelRange), length: 0))

        textView.keyDown(with: try plainRightEvent())
        let nextCharacterRange = (text as NSString).rangeOfComposedCharacterSequence(at: NSMaxRange(linkRange.fullRange))
        let expectedRange = NSRange(location: NSMaxRange(nextCharacterRange), length: 0)
        XCTAssertEqual(textView.selectedRange(), expectedRange)
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: expectedRange.location)))
    }

    func testEscapeFromStaleEditModalClampsRestoredSelection() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Open [docs](https://example.com)")
        ])
        let context = try XCTUnwrap(mounted.view.linkContext(
            blockID: blockID,
            selectedRange: NSRange(location: 7, length: 0),
            event: nil,
            prefersClickedOffset: false
        ))

        mounted.view.showLinkModal(context: context)
        let modal = try XCTUnwrap(mounted.view.linkModalView)
        mounted.view.documentStore?.replaceBlock(BlockInputBlock(id: blockID, text: "Open"))

        XCTAssertTrue(modal.control(modal.textField, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:))))

        XCTAssertNil(mounted.view.linkModalView)
        XCTAssertEqual(mounted.view.block(withID: blockID)?.text, "Open")
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 4)))
    }

    func testEscapeFromCreateModalRestoresSelectedText() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Open docs")
        ])
        let selectedRange = NSRange(location: 5, length: 4)
        let context = try XCTUnwrap(mounted.view.linkContext(
            blockID: blockID,
            selectedRange: selectedRange,
            event: nil,
            prefersClickedOffset: false
        ))

        mounted.view.showLinkModal(context: context)
        let modal = try XCTUnwrap(mounted.view.linkModalView)

        XCTAssertTrue(modal.control(modal.textField, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:))))

        XCTAssertNil(mounted.view.linkModalView)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Open docs")
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(blockID: blockID, range: selectedRange)))
    }

    private func textView(in view: BlockInputView) throws -> BlockInputTextView {
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        return try XCTUnwrap(item.testingTextView)
    }

    private func performMenuItem(titled title: String, in menu: NSMenu) throws {
        let item = try XCTUnwrap(menu.item(withTitle: title))
        let action = try XCTUnwrap(item.action)
        XCTAssertTrue(NSApp.sendAction(action, to: item.target, from: item))
    }
}
