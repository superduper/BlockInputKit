import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputEditorCommandTests: XCTestCase {
    func testFormattingCommandMatchesKeyboardShortcutAndPublishesState() throws {
        let blockID = BlockInputBlockID(rawValue: "paragraph")
        let commandMounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "format")
        ])
        commandMounted.view.applySelection(.text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 0, length: 6)
        )), notify: false)

        XCTAssertEqual(commandMounted.view.state(for: .bold), .off)
        XCTAssertTrue(commandMounted.view.performCommand(.bold))
        XCTAssertEqual(commandMounted.view.document.blocks[0].text, "**format**")
        XCTAssertEqual(commandMounted.view.state(for: .bold), .on)

        let shortcutMounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "format")
        ])
        let item = try XCTUnwrap(shortcutMounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 0, length: 6))
        XCTAssertTrue(textView.performKeyEquivalent(with: try commandBEvent()))
        XCTAssertEqual(shortcutMounted.view.document.blocks[0].text, commandMounted.view.document.blocks[0].text)
    }

    func testLinkCommandsInsertRemoveAndOpenPrefilledModal() throws {
        let blockID = BlockInputBlockID(rawValue: "paragraph")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "docs")
        ])
        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 0, length: 4)
        )), notify: false)

        XCTAssertFalse(mounted.view.canPerformCommand(.insertLink(BlockInputInsertLinkCommand(
            urlString: "ftp://example.com"
        ))))
        XCTAssertTrue(mounted.view.performCommand(.insertLink(BlockInputInsertLinkCommand(
            urlString: "https://example.com"
        ))))
        XCTAssertEqual(mounted.view.document.blocks[0].text, "[docs](https://example.com)")

        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 2)), notify: false)
        XCTAssertTrue(mounted.view.performCommand(.removeLink))
        XCTAssertEqual(mounted.view.document.blocks[0].text, "docs")

        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 4)), notify: false)
        XCTAssertTrue(mounted.view.performCommand(.insertLink(BlockInputInsertLinkCommand(
            text: "Guide",
            urlString: "https://example.org",
            presentation: .modal
        ))))
        let modal = try XCTUnwrap(mounted.view.linkModalView)
        XCTAssertEqual(modal.textField.stringValue, "Guide")
        XCTAssertEqual(modal.urlField.stringValue, "https://example.org")
    }

    func testImageCommandsInsertDeleteAndOpenPrefilledModal() throws {
        let blockID = BlockInputBlockID(rawValue: "paragraph")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Before")
        ])
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 6)), notify: false)

        XCTAssertFalse(mounted.view.canPerformCommand(.insertImage(BlockInputInsertImageCommand(
            source: "ftp://example.com/image.png"
        ))))
        XCTAssertTrue(mounted.view.performCommand(.insertImage(BlockInputInsertImageCommand(
            source: "https://example.com/image.png",
            altText: "Example"
        ))))
        XCTAssertEqual(mounted.view.document.blocks.map(\.kind), [
            .paragraph,
            .image(BlockInputImage(source: "https://example.com/image.png", altText: "Example"))
        ])

        let imageID = mounted.view.document.blocks[1].id
        mounted.view.applySelection(.blocks([imageID]), notify: false)
        XCTAssertTrue(mounted.view.performCommand(.deleteImage))
        XCTAssertEqual(mounted.view.document.blocks.map(\.kind), [.paragraph])

        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 6)), notify: false)
        XCTAssertTrue(mounted.view.performCommand(.insertImage(BlockInputInsertImageCommand(
            source: "https://example.com/prefill.png",
            altText: "Prefill",
            presentation: .modal
        ))))
        let modal = try XCTUnwrap(mounted.view.imageModalView)
        XCTAssertEqual(modal.urlField.stringValue, "https://example.com/prefill.png")
        XCTAssertEqual(modal.altTextField.stringValue, "Prefill")
    }

    func testLinkModalPasteActionTargetsFocusedFieldEditor() throws {
        let blockID = BlockInputBlockID(rawValue: "paragraph")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "[docs](https://example.com)")
        ])
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 2)), notify: false)
        XCTAssertTrue(mounted.view.performCommand(.insertLink(BlockInputInsertLinkCommand(presentation: .modal))))

        let modal = try XCTUnwrap(mounted.view.linkModalView)
        _ = try focusAndSelectFieldContents(modal.urlField, in: mounted.window)

        try withPasteboardString("https://pasted.example") {
            mounted.view.blockInputPaste(nil)
        }

        XCTAssertEqual(editingString(in: modal.urlField), "https://pasted.example")
        XCTAssertEqual(mounted.view.document.blocks[0].text, "[docs](https://example.com)")
    }

    func testLinkModalCommandVPasteTargetsFocusedFieldEditor() throws {
        let blockID = BlockInputBlockID(rawValue: "paragraph")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "[docs](https://example.com)")
        ])
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 2)), notify: false)
        XCTAssertTrue(mounted.view.performCommand(.insertLink(BlockInputInsertLinkCommand(presentation: .modal))))

        let modal = try XCTUnwrap(mounted.view.linkModalView)
        _ = try focusAndSelectFieldContents(modal.urlField, in: mounted.window)

        try withPasteboardString("https://keyboard.example") {
            XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandVEvent()))
        }

        XCTAssertEqual(editingString(in: modal.urlField), "https://keyboard.example")
        XCTAssertNotNil(mounted.view.linkModalView)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "[docs](https://example.com)")
    }

    func testLinkModalFieldEditorCommandPasteTargetsFocusedFieldEditor() throws {
        let blockID = BlockInputBlockID(rawValue: "paragraph")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "[docs](https://example.com)")
        ])
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 2)), notify: false)
        XCTAssertTrue(mounted.view.performCommand(.insertLink(BlockInputInsertLinkCommand(presentation: .modal))))

        let modal = try XCTUnwrap(mounted.view.linkModalView)
        let fieldEditor = try focusAndSelectFieldContents(modal.urlField, in: mounted.window)

        try withPasteboardString("https://delegate.example") {
            XCTAssertTrue(modal.control(modal.urlField, textView: fieldEditor, doCommandBy: #selector(NSText.paste(_:))))
        }

        XCTAssertEqual(editingString(in: modal.urlField), "https://delegate.example")
        XCTAssertNotNil(mounted.view.linkModalView)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "[docs](https://example.com)")
    }

    func testImageModalPasteActionTargetsFocusedFieldEditor() throws {
        let blockID = BlockInputBlockID(rawValue: "paragraph")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Before")
        ])
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 6)), notify: false)
        XCTAssertTrue(mounted.view.performCommand(.insertImage(BlockInputInsertImageCommand(presentation: .modal))))

        let modal = try XCTUnwrap(mounted.view.imageModalView)
        _ = try focusAndSelectFieldContents(modal.urlField, in: mounted.window)

        try withPasteboardString("https://example.com/pasted.png") {
            mounted.view.blockInputPaste(nil)
        }

        XCTAssertEqual(editingString(in: modal.urlField), "https://example.com/pasted.png")
        XCTAssertEqual(mounted.view.document.blocks.map(\.kind), [.paragraph])
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Before")
    }

    func testImageModalCommandVPasteTargetsFocusedFieldEditor() throws {
        let blockID = BlockInputBlockID(rawValue: "paragraph")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Before")
        ])
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 6)), notify: false)
        XCTAssertTrue(mounted.view.performCommand(.insertImage(BlockInputInsertImageCommand(presentation: .modal))))

        let modal = try XCTUnwrap(mounted.view.imageModalView)
        _ = try focusAndSelectFieldContents(modal.urlField, in: mounted.window)

        try withPasteboardString("https://example.com/keyboard.png") {
            XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandVEvent()))
        }

        XCTAssertEqual(editingString(in: modal.urlField), "https://example.com/keyboard.png")
        XCTAssertNotNil(mounted.view.imageModalView)
        XCTAssertEqual(mounted.view.document.blocks.map(\.kind), [.paragraph])
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Before")
    }

    func testImageModalTextFieldsKeepOptionArrowWordNavigation() throws {
        let blockID = BlockInputBlockID(rawValue: "paragraph")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Before")
        ])
        mounted.view.focus(blockID: blockID, utf16Offset: 6)
        let originalSelection = mounted.view.selection
        XCTAssertTrue(mounted.view.performCommand(.insertImage(BlockInputInsertImageCommand(presentation: .modal))))
        let modal = try XCTUnwrap(mounted.view.imageModalView)

        for field in [modal.urlField, modal.altTextField] {
            XCTAssertTrue(mounted.window.makeFirstResponder(field))
            XCTAssertFalse(mounted.view.performKeyEquivalent(with: try optionLeftEvent()))
            XCTAssertFalse(mounted.view.performKeyEquivalent(with: try optionRightEvent()))
            XCTAssertIdentical(mounted.view.imageModalView, modal)
            XCTAssertEqual(mounted.view.selection, originalSelection)
        }
    }

    func testImageModalFieldEditorCommandPasteTargetsFocusedFieldEditor() throws {
        let blockID = BlockInputBlockID(rawValue: "paragraph")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Before")
        ])
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 6)), notify: false)
        XCTAssertTrue(mounted.view.performCommand(.insertImage(BlockInputInsertImageCommand(presentation: .modal))))

        let modal = try XCTUnwrap(mounted.view.imageModalView)
        let fieldEditor = try focusAndSelectFieldContents(modal.urlField, in: mounted.window)

        try withPasteboardString("https://example.com/delegate.png") {
            XCTAssertTrue(modal.control(modal.urlField, textView: fieldEditor, doCommandBy: #selector(NSText.paste(_:))))
        }

        XCTAssertEqual(editingString(in: modal.urlField), "https://example.com/delegate.png")
        XCTAssertNotNil(mounted.view.imageModalView)
        XCTAssertEqual(mounted.view.document.blocks.map(\.kind), [.paragraph])
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Before")
    }

    func testTextViewClipboardActionsRouteThroughEditorCommands() throws {
        let blockID = BlockInputBlockID(rawValue: "paragraph")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Copy Cut")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)

        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 0, length: 4)
        )), notify: false)
        textView.copy(nil)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Copy")

        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 5, length: 3)
        )), notify: false)
        textView.cut(nil)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Cut")
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Copy ")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Paste", forType: .string)
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 5)), notify: false)
        textView.paste(nil)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Copy Paste")
    }

    func testCommandXUsesEditorCutCommand() throws {
        let blockID = BlockInputBlockID(rawValue: "paragraph")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Cut Me")
        ])
        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 0, length: 3)
        )), notify: false)
        XCTAssertTrue(mounted.window.makeFirstResponder(mounted.view))

        try withPasteboardString("Previous") {
            XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandXEvent()))
            XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Cut")
        }
        XCTAssertEqual(mounted.view.document.blocks[0].text, " Me")
    }

    func testTextViewCommandXUsesEditorCutCommand() throws {
        let blockID = BlockInputBlockID(rawValue: "paragraph")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Cut Me")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        XCTAssertTrue(mounted.window.makeFirstResponder(textView))
        textView.setSelectedRange(NSRange(location: 0, length: 3))

        try withPasteboardString("Previous") {
            XCTAssertTrue(textView.performKeyEquivalent(with: try commandXEvent()))
            XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Cut")
        }
        XCTAssertEqual(mounted.view.document.blocks[0].text, " Me")
    }

    func testTableCommandsUseActiveCellSelection() throws {
        let table = BlockInputTable.normalized(
            header: ["H1", "H2"],
            bodyRows: [["one", "two"], ["three", "four"]],
            alignments: [.left, .left]
        )
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "table", kind: .table, text: table.markdown)
        ])
        mounted.view.applySelection(try XCTUnwrap(table.selection(
            blockID: "table",
            position: .init(row: .body(0), column: 0),
            localRange: NSRange(location: 0, length: 0)
        )), notify: false)

        XCTAssertTrue(mounted.view.performCommand(.insertRow))
        var updatedTable = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(updatedTable.bodyRows.map { $0.map(\.text) }, [["one", "two"], ["", ""], ["three", "four"]])

        XCTAssertTrue(mounted.view.performCommand(.insertColumn))
        updatedTable = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(updatedTable.header.map(\.text), ["H1", "", "H2"])

        XCTAssertTrue(mounted.view.performCommand(.deleteColumn))
        updatedTable = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(updatedTable.header.map(\.text), ["H1", "H2"])

        XCTAssertTrue(mounted.view.performCommand(.deleteTable))
        XCTAssertEqual(mounted.view.document.blocks.map(\.kind), [.paragraph])
    }

    func testContextMenuInsertTableAndCommandShareMutationPath() throws {
        let commandMounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "empty", text: "")
        ])
        XCTAssertTrue(commandMounted.view.performCommand(.insertTable))

        let menuMounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "empty", text: "")
        ])
        let textView = try tableEditingTextView(in: menuMounted.view)
        let menu = try XCTUnwrap(textView.menu(for: try rightMouseDownEvent(windowNumber: menuMounted.window.windowNumber)))
        try performTableCellMenuItem(titled: "Insert Table", in: menu)

        XCTAssertEqual(menuMounted.view.document.blocks[0].kind, commandMounted.view.document.blocks[0].kind)
        XCTAssertEqual(menuMounted.view.document.blocks[0].text, commandMounted.view.document.blocks[0].text)
    }

    func testExplicitStaleTableCommandContextDoesNotUseActiveSelectionFallback() throws {
        let table = BlockInputTable.normalized(
            header: ["H1", "H2"],
            bodyRows: [["one", "two"]],
            alignments: [.left, .left]
        )
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "paragraph", text: "Before"),
            BlockInputBlock(id: "table", kind: .table, text: table.markdown)
        ])
        mounted.view.applySelection(try XCTUnwrap(table.selection(
            blockID: "table",
            position: .init(row: .body(0), column: 0),
            localRange: NSRange(location: 0, length: 0)
        )), notify: false)

        XCTAssertFalse(mounted.view.performCommand(
            .insertRow,
            context: .init(tableContext: BlockInputTableMenuContext(
                blockID: "missing",
                position: .init(row: .body(0), column: 0)
            ))
        ))
        XCTAssertFalse(mounted.view.performCommand(
            .insertTable,
            context: .init(tableContext: BlockInputTableMenuContext(blockID: "missing"))
        ))

        XCTAssertEqual(mounted.view.document.blocks.map(\.id.rawValue), ["paragraph", "table"])
        XCTAssertEqual(mounted.view.document.blocks[1].text, table.markdown)
    }

    func testExplicitStaleImageDeleteContextDoesNotUseActiveSelectionFallback() {
        let imageID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/image.png", altText: "")))
        ])
        mounted.view.applySelection(.blocks([imageID]), notify: false)

        XCTAssertFalse(mounted.view.performCommand(
            .deleteImage,
            context: .init(imageBlockID: "missing", imageIndex: nil)
        ))
        XCTAssertEqual(mounted.view.document.blocks.map(\.id), [imageID])
    }

    private func focusAndSelectFieldContents(_ field: NSTextField, in window: NSWindow) throws -> NSTextView {
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView ?? window.firstResponder as? NSTextView)
        editor.setSelectedRange(NSRange(location: 0, length: (editor.string as NSString).length))
        return editor
    }

    private func editingString(in field: NSTextField) -> String {
        field.currentEditor()?.string ?? field.stringValue
    }

    private func withPasteboardString(_ string: String, body: () throws -> Void) throws {
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }
        try body()
    }
}
