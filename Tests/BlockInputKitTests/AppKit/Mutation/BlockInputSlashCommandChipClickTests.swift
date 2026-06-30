import AppKit
import XCTest
@testable import BlockInputKit

/// Slash-command chip click routing. Split from `BlockInputLinkClickTests` to keep that file under the line limit.
/// A chip click reaches the host `slashCommandChipClickHandler`/`inlineLinkClickHandler` before the link open-vs-caret
/// decision, so handler-decided clicks behave the same regardless of the new single-click-caret model; without a
/// handler a chip falls back to normal link behavior (single click places the caret, double/cmd-click open).
@MainActor
final class BlockInputSlashCommandChipClickTests: XCTestCase {
    func testSlashCommandChipClickHandlerCanOpenModalOpenURLOrConsumeClick() throws {
        let text = "Run [/table](host-app://commands/table)"
        var actions: [BlockInputSlashCommandChipClickAction] = [.showLinkModal, .openURL, .hostHandled]
        var contexts: [BlockInputSlashCommandChipClickContext] = []
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: text)
            ]),
            slashCommandChipClickHandler: { context in
                contexts.append(context)
                return actions.removeFirst()
            }
        ))
        var openedURLs: [URL] = []
        mounted.view.linkURLOpener = {
            openedURLs.append($0)
            return true
        }
        let textView = try textView(in: mounted.view)
        let location = try windowLocation(forUTF16Offset: contentLocation("/table", in: text), in: textView)

        XCTAssertTrue(mounted.view.handleLinkClick(
            blockID: "block",
            selectedRange: NSRange(location: contentLocation("/table", in: text), length: 0),
            event: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber)
        ))
        XCTAssertEqual(contexts.last?.label, "/table")
        XCTAssertEqual(contexts.last?.uri.absoluteString, "host-app://commands/table")
        XCTAssertEqual(contexts.last?.sourceRange, (text as NSString).range(of: "[/table](host-app://commands/table)"))
        XCTAssertEqual(contexts.last?.clickKind, .plainClick)
        XCTAssertNotNil(mounted.view.linkModalView)

        mounted.view.dismissLinkModal(restoreFocus: false)
        XCTAssertTrue(mounted.view.handleLinkClick(
            blockID: "block",
            selectedRange: NSRange(location: contentLocation("/table", in: text), length: 0),
            event: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber, modifierFlags: .command)
        ))
        XCTAssertEqual(openedURLs.map(\.absoluteString), ["host-app://commands/table"])
        XCTAssertEqual(contexts.last?.clickKind, .commandClick)

        XCTAssertTrue(mounted.view.handleLinkClick(
            blockID: "block",
            selectedRange: NSRange(location: contentLocation("/table", in: text), length: 0),
            event: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber)
        ))
        XCTAssertNil(mounted.view.linkModalView)
        XCTAssertEqual(openedURLs.map(\.absoluteString), ["host-app://commands/table"])
    }

    func testSlashCommandOpenURLActionConsumesClickWhenOpenerFails() throws {
        let text = "Run [/table](host-app://commands/table)"
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: text)
            ]),
            slashCommandChipClickHandler: { _ in .openURL }
        ))
        var openedURL: URL?
        mounted.view.linkURLOpener = {
            openedURL = $0
            return false
        }
        let textView = try textView(in: mounted.view)
        let location = try windowLocation(forUTF16Offset: contentLocation("/table", in: text), in: textView)

        XCTAssertTrue(mounted.view.handleLinkClick(
            blockID: "block",
            selectedRange: NSRange(location: contentLocation("/table", in: text), length: 0),
            event: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber)
        ))

        XCTAssertEqual(openedURL?.absoluteString, "host-app://commands/table")
        XCTAssertNil(mounted.view.linkModalView)
    }

    func testSlashCommandChipFallsBackToNormalLinkBehaviorWithoutHandler() throws {
        // Without a click handler, a slash-command chip falls back to normal link behavior. Under the shipped model a
        // single click on the body only places the caret; a double-click and a cmd-click open.
        let text = "Run [/table](host-app://commands/table)"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        var openedURLs: [URL] = []
        mounted.view.linkURLOpener = {
            openedURLs.append($0)
            return true
        }
        let textView = try textView(in: mounted.view)
        let location = try windowLocation(forUTF16Offset: contentLocation("/table", in: text), in: textView)

        // Single click on the chip body does not open.
        XCTAssertFalse(mounted.view.handleLinkClick(
            blockID: "block",
            selectedRange: NSRange(location: contentLocation("/table", in: text), length: 0),
            event: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber)
        ))
        XCTAssertTrue(openedURLs.isEmpty)
        XCTAssertNil(mounted.view.linkModalView)

        // Double click opens.
        XCTAssertTrue(mounted.view.handleLinkClick(
            blockID: "block",
            selectedRange: NSRange(location: contentLocation("/table", in: text), length: 0),
            event: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber, clickCount: 2)
        ))

        // Command click opens.
        XCTAssertTrue(mounted.view.handleLinkClick(
            blockID: "block",
            selectedRange: NSRange(location: contentLocation("/table", in: text), length: 0),
            event: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber, modifierFlags: .command)
        ))
        XCTAssertEqual(openedURLs.map(\.absoluteString), ["host-app://commands/table", "host-app://commands/table"])
    }

    func testRawSlashCommandChipDoesNotRouteAsLinkClick() throws {
        let text = "/table"
        var didRouteSlashCommand = false
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: text)
            ]),
            rawSlashCommandChips: true,
            slashCommandChipClickHandler: { _ in
                didRouteSlashCommand = true
                return .hostHandled
            }
        ))
        let textView = try textView(in: mounted.view)
        let location = try windowLocation(forUTF16Offset: 1, in: textView)

        XCTAssertFalse(mounted.view.handleLinkClick(
            blockID: "block",
            selectedRange: NSRange(location: 1, length: 0),
            event: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber)
        ))
        XCTAssertFalse(didRouteSlashCommand)
        XCTAssertNil(mounted.view.linkModalView)
    }

    private func textView(in view: BlockInputView) throws -> BlockInputTextView {
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        return try XCTUnwrap(item.testingTextView)
    }

    private func contentLocation(_ content: String, in text: String) -> Int {
        (text as NSString).range(of: content).location
    }
}
