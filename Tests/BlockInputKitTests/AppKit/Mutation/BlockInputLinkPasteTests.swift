import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputLinkPasteTests: XCTestCase {
    func testPastingURLOverSelectedTextCreatesMarkdownLinkAndPlacesCaretAfterLink() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Open docs")
        ])
        let textView = try textView(in: mounted.view)
        XCTAssertTrue(mounted.window.makeFirstResponder(textView))
        textView.setSelectedRange(NSRange(location: 5, length: 4))

        try withPasteboardString("https://example.com") {
            textView.paste(nil)
        }

        assertPastedLinkText("Open [docs](https://example.com)", blockID: blockID, in: mounted.view, textView: textView)
    }

    func testCommandVPastesURLOverSelectedTextAsLinkAndPlacesCaretAfterLink() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Open docs")
        ])
        let textView = try textView(in: mounted.view)
        XCTAssertTrue(mounted.window.makeFirstResponder(textView))
        textView.setSelectedRange(NSRange(location: 5, length: 4))

        try withPasteboardString("https://example.com") {
            XCTAssertTrue(textView.performKeyEquivalent(with: try commandVEvent()))
        }

        assertPastedLinkText("Open [docs](https://example.com)", blockID: blockID, in: mounted.view, textView: textView)
    }

    func testEditorCommandVPastesURLOverSelectedTextAsLinkAndPlacesCaretAfterLink() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Open docs")
        ])
        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 5, length: 4)
        )), notify: false)
        XCTAssertTrue(mounted.window.makeFirstResponder(mounted.view))

        try withPasteboardString("https://example.com") {
            XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandVEvent()))
        }

        assertPastedLinkText(
            "Open [docs](https://example.com)",
            blockID: blockID,
            in: mounted.view,
            textView: try textView(in: mounted.view)
        )
    }

    func testContextMenuPastePastesURLOverSelectedTextAsLinkAndPlacesCaretAfterLink() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Open docs")
        ])
        let textView = try textView(in: mounted.view)
        XCTAssertTrue(mounted.window.makeFirstResponder(textView))
        textView.setSelectedRange(NSRange(location: 5, length: 4))

        let menu = try XCTUnwrap(textView.menu(for: try rightMouseDownEvent(
            location: try windowLocation(forUTF16Offset: 6, in: textView),
            windowNumber: mounted.window.windowNumber
        )))
        let pasteItem = try XCTUnwrap(menu.items.first { $0.action == #selector(NSText.paste(_:)) })

        try withPasteboardString("https://example.com") {
            XCTAssertTrue(NSApp.sendAction(#selector(NSText.paste(_:)), to: pasteItem.target ?? textView, from: pasteItem))
        }

        assertPastedLinkText("Open [docs](https://example.com)", blockID: blockID, in: mounted.view, textView: textView)
    }

    func testPastingURLOverSelectedTextInMiddlePlacesCaretBeforeTrailingText() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open docs today")
        ])
        let textView = try textView(in: mounted.view)
        XCTAssertTrue(mounted.window.makeFirstResponder(textView))
        textView.setSelectedRange(NSRange(location: 5, length: 4))

        try withPasteboardString("https://example.com") {
            textView.paste(nil)
        }

        let expectedText = "Open [docs](https://example.com) today"
        XCTAssertEqual(mounted.view.document.blocks[0].text, expectedText)
        assertCaret(
            in: mounted.view,
            textView: textView,
            blockID: "block",
            utf16Offset: ("Open [docs](https://example.com)" as NSString).length
        )
    }

    func testPastingURLOverSelectedTextEscapesMarkdownLinkLabelAndPlacesCaretAfterLink() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open a[b]c")
        ])
        let textView = try textView(in: mounted.view)
        XCTAssertTrue(mounted.window.makeFirstResponder(textView))
        textView.setSelectedRange(NSRange(location: 5, length: 5))

        try withPasteboardString("https://example.com") {
            textView.paste(nil)
        }

        assertPastedLinkText("Open [a\\[b\\]c](https://example.com)", blockID: "block", in: mounted.view, textView: textView)
    }

    func testPastingURLWithParenthesesEscapesMarkdownLinkDestinationAndPlacesCaretAfterLink() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open ")
        ])
        let textView = try textView(in: mounted.view)
        XCTAssertTrue(mounted.window.makeFirstResponder(textView))
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        try withPasteboardString("https://example.com/a(b)") {
            textView.paste(nil)
        }

        let expectedText = "Open [https://example.com/a(b)](https://example.com/a\\(b\\))"
        assertPastedLinkText(expectedText, blockID: "block", in: mounted.view, textView: textView)
        XCTAssertNotNil(mounted.view.linkRange(
            in: mounted.view.document.blocks[0].text,
            containing: NSRange(location: 6, length: 0)
        ))
    }

    func testPastingURLAtCollapsedCursorCreatesLinkWithURLTextAndPlacesCaretAfterLink() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open ")
        ])
        let textView = try textView(in: mounted.view)
        XCTAssertTrue(mounted.window.makeFirstResponder(textView))
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        try withPasteboardString("https://example.com") {
            textView.paste(nil)
        }

        assertPastedLinkText("Open [https://example.com](https://example.com)", blockID: "block", in: mounted.view, textView: textView)
    }

    func testPastingURLInsidePendingMarkdownImageSyntaxCreatesImageBlock() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let imageURL = "https://af.codes/images/portfolio/streettriple.jpg"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "![bike]()")
        ])
        let textView = try textView(in: mounted.view)
        XCTAssertTrue(mounted.window.makeFirstResponder(textView))
        textView.setSelectedRange(NSRange(location: ("![bike](" as NSString).length, length: 0))

        try withPasteboardString(imageURL) {
            textView.paste(nil)
        }

        XCTAssertEqual(mounted.view.document.blocks.count, 1)
        XCTAssertEqual(
            mounted.view.document.blocks[0].kind,
            .image(BlockInputImage(source: imageURL, altText: "bike"))
        )
        XCTAssertEqual(mounted.view.document.blocks[0].text, "")
    }

    func testPastingURLInsideUnclosedMarkdownImageSyntaxInsertsPlainURL() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let imageURL = "https://af.codes/images/portfolio/streettriple.jpg"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "![bike](")
        ])
        let textView = try textView(in: mounted.view)
        XCTAssertTrue(mounted.window.makeFirstResponder(textView))
        textView.setSelectedRange(NSRange(location: ("![bike](" as NSString).length, length: 0))

        try withPasteboardString(imageURL) {
            textView.paste(nil)
        }

        XCTAssertEqual(mounted.view.document.blocks.count, 1)
        XCTAssertEqual(mounted.view.document.blocks[0].kind, .paragraph)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "![bike](\(imageURL)")
    }

    func testURLPasteMutationInsidePendingMarkdownImageDestinationCreatesImageBlock() {
        let blockID = BlockInputBlockID(rawValue: "block")
        let imageURL = "https://af.codes/images/portfolio/streettriple.jpg"
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "![bike]()")
        ])))
        let imageDestinationRange = NSRange(location: ("![bike](" as NSString).length, length: 0)
        view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: imageDestinationRange.location)), notify: false)

        XCTAssertTrue(view.pasteURLString(imageURL, blockID: blockID, selectedRange: imageDestinationRange))
        XCTAssertEqual(view.document.blocks.count, 1)
        XCTAssertEqual(
            view.document.blocks[0].kind,
            .image(BlockInputImage(source: imageURL, altText: "bike"))
        )
        XCTAssertEqual(view.document.blocks[0].text, "")
    }

    func testPastingFileURLAtCollapsedCursorCreatesLinkAndPlacesCaretAfterLink() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open ")
        ])
        let textView = try textView(in: mounted.view)
        XCTAssertTrue(mounted.window.makeFirstResponder(textView))
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        try withPasteboardFileURL(URL(fileURLWithPath: "/tmp/demo.md")) {
            textView.paste(nil)
        }

        assertPastedLinkText("Open [file:///tmp/demo.md](file:///tmp/demo.md)", blockID: "block", in: mounted.view, textView: textView)
    }

    func testPastingURLInsideExistingLinkUpdatesDestinationAndPlacesCaretAfterLink() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open [docs](https://old.example)")
        ])
        let textView = try textView(in: mounted.view)
        XCTAssertTrue(mounted.window.makeFirstResponder(textView))
        textView.setSelectedRange(NSRange(location: 7, length: 0))

        try withPasteboardString("https://new.example") {
            textView.paste(nil)
        }

        assertPastedLinkText("Open [docs](https://new.example)", blockID: "block", in: mounted.view, textView: textView)
    }

    func testPastingURLOverSelectionInsideExistingLinkUpdatesDestinationAndPlacesCaretAfterLink() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open [docs](https://old.example)")
        ])
        let textView = try textView(in: mounted.view)
        XCTAssertTrue(mounted.window.makeFirstResponder(textView))
        textView.setSelectedRange(NSRange(location: 7, length: 2))

        try withPasteboardString("https://new.example") {
            textView.paste(nil)
        }

        assertPastedLinkText("Open [docs](https://new.example)", blockID: "block", in: mounted.view, textView: textView)
    }

    func testPastingURLIntoUnsupportedBlockFallsBackToNativePaste() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let prefix = "let url = "
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, kind: .code(language: "swift"), text: prefix)
        ])
        let textView = try textView(in: mounted.view)
        XCTAssertTrue(mounted.window.makeFirstResponder(textView))
        textView.setSelectedRange(NSRange(location: (prefix as NSString).length, length: 0))

        try withPasteboardString("https://example.com") {
            textView.paste(nil)
        }

        let expectedText = "let url = https://example.com"
        XCTAssertEqual(mounted.view.document.blocks[0].text, expectedText)
        assertCaret(in: mounted.view, textView: textView, blockID: blockID, utf16Offset: (expectedText as NSString).length)
    }

    func testPastingUnsupportedURLFallsBackToNativePaste() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Open docs")
        ])
        let textView = try textView(in: mounted.view)
        XCTAssertTrue(mounted.window.makeFirstResponder(textView))
        textView.setSelectedRange(NSRange(location: 5, length: 4))

        try withPasteboardString("mailto:user@example.com") {
            textView.paste(nil)
        }

        let expectedText = "Open mailto:user@example.com"
        XCTAssertEqual(mounted.view.document.blocks[0].text, expectedText)
        assertCaret(in: mounted.view, textView: textView, blockID: blockID, utf16Offset: (expectedText as NSString).length)
    }

    func testPastingURLUndoRedoRestoresSelections() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Open docs")
        ])
        let initialTextView = try textView(in: mounted.view)
        XCTAssertTrue(mounted.window.makeFirstResponder(initialTextView))
        initialTextView.setSelectedRange(NSRange(location: 5, length: 4))

        try withPasteboardString("https://example.com") {
            initialTextView.paste(nil)
        }

        XCTAssertNotNil(mounted.view.undoStructuralEdit())
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Open docs")
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(blockID: blockID, range: NSRange(location: 5, length: 4))))
        XCTAssertEqual(try textView(in: mounted.view).selectedRange(), NSRange(location: 5, length: 4))

        XCTAssertNotNil(mounted.view.redoStructuralEdit())
        assertPastedLinkText(
            "Open [docs](https://example.com)",
            blockID: blockID,
            in: mounted.view,
            textView: try textView(in: mounted.view)
        )
    }

    func testPastingURLPublishesGranularStoreMutation() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Open docs")
        ]))
        var mutations: [BlockInputDocumentChange] = []
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            documentStore: store,
            onDocumentMutation: { mutations.append($0) }
        ))
        let textView = try textView(in: mounted.view)
        XCTAssertTrue(mounted.window.makeFirstResponder(textView))
        textView.setSelectedRange(NSRange(location: 5, length: 4))
        store.resetCounts()
        mutations.removeAll()

        try withPasteboardString("https://example.com") {
            textView.paste(nil)
        }

        let expectedText = "Open [docs](https://example.com)"
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replaceBlockIDs, [blockID])
        XCTAssertEqual(store.document.blocks[0].text, expectedText)
        XCTAssertEqual(mutations, [.replaceBlock(store.document.blocks[0])])
        assertCaret(in: mounted.view, textView: textView, blockID: blockID, utf16Offset: (expectedText as NSString).length)
    }

    private func assertPastedLinkText(
        _ expectedText: String,
        blockID: BlockInputBlockID,
        in view: BlockInputView,
        textView: BlockInputTextView
    ) {
        XCTAssertEqual(view.document.blocks[0].text, expectedText)
        assertCaret(in: view, textView: textView, blockID: blockID, utf16Offset: (expectedText as NSString).length)
    }

    private func assertCaret(
        in view: BlockInputView,
        textView: BlockInputTextView,
        blockID: BlockInputBlockID,
        utf16Offset: Int
    ) {
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(
            blockID: blockID,
            utf16Offset: utf16Offset
        )))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: utf16Offset, length: 0))
    }

    private func textView(in view: BlockInputView) throws -> BlockInputTextView {
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        return try XCTUnwrap(item.testingTextView)
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

    private func withPasteboardFileURL(_ url: URL, body: () throws -> Void) throws {
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }
        try body()
    }
}
