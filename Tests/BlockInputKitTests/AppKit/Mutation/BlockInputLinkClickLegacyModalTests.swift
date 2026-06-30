import AppKit
import XCTest
@testable import BlockInputKit

/// Legacy link interaction model: with `linkHoverEditAffordance` off, a plain click shows the link-edit modal and
/// cmd-click opens (byte-for-byte the pre-wikilink behavior). The shipped default (a single click places the caret;
/// opening is via double-click / the trailing open icon / command-click / hover Edit) is covered in
/// `BlockInputLinkClickTests`.
@MainActor
final class BlockInputLinkClickLegacyModalTests: XCTestCase {
    func testPlainClickOpensModalWhenHoverAffordanceDisabled() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: "Open [docs](https://example.com)")
            ]),
            linkHoverEditAffordance: false
        ))
        var openedURL: URL?
        mounted.view.linkURLOpener = {
            openedURL = $0
            return true
        }
        let textView = try textView(in: mounted.view)
        let location = try windowLocation(forUTF16Offset: 7, in: textView)

        XCTAssertTrue(mounted.view.handleLinkClick(
            blockID: "block",
            selectedRange: NSRange(location: 7, length: 0),
            event: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber)
        ))
        XCTAssertNotNil(mounted.view.linkModalView)

        mounted.view.dismissLinkModal(restoreFocus: false)
        XCTAssertTrue(mounted.view.handleLinkClick(
            blockID: "block",
            selectedRange: NSRange(location: 7, length: 0),
            event: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber, modifierFlags: .command)
        ))
        XCTAssertEqual(openedURL?.absoluteString, "https://example.com")
    }

    func testPlainClickAngleBracketFileURLOpensModalLikeRegularLinks() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: "Open [file](<file:///tmp/demo.md>)")
            ]),
            linkHoverEditAffordance: false
        ))
        var openedURL: URL?
        mounted.view.linkURLOpener = {
            openedURL = $0
            return true
        }
        let textView = try textView(in: mounted.view)
        let location = try windowLocation(forUTF16Offset: 7, in: textView)

        XCTAssertTrue(mounted.view.handleLinkClick(
            blockID: "block",
            selectedRange: NSRange(location: 7, length: 0),
            event: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber)
        ))

        XCTAssertNil(openedURL)
        let modal = try XCTUnwrap(mounted.view.linkModalView)
        XCTAssertEqual(modal.textField.stringValue, "file")
        XCTAssertEqual(modal.urlField.stringValue, "file:///tmp/demo.md")
    }

    func testSlashCommandChipFallsBackToModalWithoutHandlerWhenHoverAffordanceDisabled() throws {
        let text = "Run [/table](host-app://commands/table)"
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: text)
            ]),
            linkHoverEditAffordance: false
        ))
        var openedURL: URL?
        mounted.view.linkURLOpener = {
            openedURL = $0
            return true
        }
        let textView = try textView(in: mounted.view)
        let location = try windowLocation(forUTF16Offset: contentLocation("/table", in: text), in: textView)

        XCTAssertTrue(mounted.view.handleLinkClick(
            blockID: "block",
            selectedRange: NSRange(location: contentLocation("/table", in: text), length: 0),
            event: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber)
        ))
        XCTAssertNotNil(mounted.view.linkModalView)

        mounted.view.dismissLinkModal(restoreFocus: false)
        XCTAssertTrue(mounted.view.handleLinkClick(
            blockID: "block",
            selectedRange: NSRange(location: contentLocation("/table", in: text), length: 0),
            event: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber, modifierFlags: .command)
        ))
        XCTAssertEqual(openedURL?.absoluteString, "host-app://commands/table")
    }

    private func textView(in view: BlockInputView) throws -> BlockInputTextView {
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        return try XCTUnwrap(item.testingTextView)
    }

    private func contentLocation(_ content: String, in text: String) -> Int {
        (text as NSString).range(of: content).location
    }
}
