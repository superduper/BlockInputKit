import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputLinkReviewTests: XCTestCase {
    func testPastingURLObjectAtCollapsedCursorCreatesLink() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open ")
        ])
        let textView = try textView(in: mounted.view)
        XCTAssertTrue(mounted.window.makeFirstResponder(textView))
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        try withPasteboardURL(try XCTUnwrap(URL(string: "https://example.com/object"))) {
            textView.paste(nil)
        }

        let expectedText = "Open [https://example.com/object](https://example.com/object)"
        XCTAssertEqual(mounted.view.document.blocks[0].text, expectedText)
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(
            blockID: "block",
            utf16Offset: (expectedText as NSString).length
        )))
    }

    func testLinkModalDismissesWhenMouseDownMovesFocusOutsideModal() throws {
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

        mounted.view.dismissLinkModalIfMouseDownMovedFocusOutside(try mouseDownEvent(
            location: mounted.view.convert(NSPoint(x: modal.frame.maxX + 8, y: modal.frame.midY), to: nil),
            windowNumber: mounted.window.windowNumber
        ))

        XCTAssertNil(mounted.view.linkModalView)
        XCTAssertEqual(mounted.view.document.blocks[0].text, originalText)
    }

    func testLinkModalStaysOpenWhenMouseDownRemainsInsideModal() throws {
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

        mounted.view.dismissLinkModalIfMouseDownMovedFocusOutside(try mouseDownEvent(
            location: mounted.view.convert(NSPoint(x: modal.frame.midX, y: modal.frame.midY), to: nil),
            windowNumber: mounted.window.windowNumber
        ))

        XCTAssertIdentical(mounted.view.linkModalView, modal)
    }

    func testLinkModalDismissesWhenFocusMovesOutsideModal() throws {
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
        XCTAssertNotNil(mounted.view.linkModalView)

        let focusSink = FocusSinkView()
        mounted.view.addSubview(focusSink)
        XCTAssertTrue(mounted.window.makeFirstResponder(focusSink))
        mounted.view.dismissLinkModalIfFocusMovedOutside()

        XCTAssertNil(mounted.view.linkModalView)
    }

    func testLinkModalDismissesWhenFocusClears() throws {
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
        XCTAssertNotNil(mounted.view.linkModalView)

        XCTAssertTrue(mounted.window.makeFirstResponder(nil))
        mounted.view.dismissLinkModalIfFocusMovedOutside()

        XCTAssertNil(mounted.view.linkModalView)
    }

    func testLinkModalTextFieldsKeepOptionArrowWordNavigation() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open [docs](https://example.com)")
        ])
        let context = try XCTUnwrap(mounted.view.linkContext(
            blockID: "block",
            selectedRange: NSRange(location: 7, length: 0),
            event: nil,
            prefersClickedOffset: false
        ))
        mounted.view.focus(blockID: "block", utf16Offset: 7)
        let originalSelection = mounted.view.selection

        mounted.view.showLinkModal(context: context)
        let modal = try XCTUnwrap(mounted.view.linkModalView)

        for field in [modal.textField, modal.urlField] {
            XCTAssertTrue(mounted.window.makeFirstResponder(field))
            XCTAssertFalse(modal.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.moveWordLeft(_:))))
            XCTAssertFalse(modal.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.moveWordRight(_:))))
            XCTAssertFalse(mounted.view.performKeyEquivalent(with: try optionLeftEvent()))
            XCTAssertFalse(mounted.view.performKeyEquivalent(with: try optionRightEvent()))
            XCTAssertIdentical(mounted.view.linkModalView, modal)
            XCTAssertEqual(mounted.view.selection, originalSelection)
        }
    }

    private func textView(in view: BlockInputView) throws -> BlockInputTextView {
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        return try XCTUnwrap(item.testingTextView)
    }

    private func withPasteboardURL(_ url: URL, body: () throws -> Void) throws {
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

private final class FocusSinkView: NSView {
    override var acceptsFirstResponder: Bool { true }
}
