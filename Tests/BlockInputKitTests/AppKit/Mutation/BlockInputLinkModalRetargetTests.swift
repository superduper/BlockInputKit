import AppKit
import XCTest
@testable import BlockInputKit

/// Modal retargeting / dismissal behavior, which only exists in the legacy modal interaction model
/// (`linkHoverEditAffordance` off). Links always render collapsed, so the layout the tests precompute the second
/// link's window point against stays stable across the first click.
@MainActor
final class BlockInputLinkModalRetargetTests: XCTestCase {
    private func mountLegacy(blocks: [BlockInputBlock]) -> (view: BlockInputView, window: NSWindow) {
        makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: blocks),
            linkHoverEditAffordance: false
        ))
    }

    func testOutsideMouseDownOnAnotherRegularLinkRetargetsExistingModalOnSameClick() throws {
        let text = "Open [one](https://one.example) then continue to [two](https://two.example)"
        let mounted = mountLegacy(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let textView = try textView(in: mounted.view)
        let firstLocation = try windowLocation(forUTF16Offset: contentLocation("one", in: text), in: textView)
        let secondLocation = try windowLocation(forUTF16Offset: contentLocation("two", in: text), in: textView)

        try plainClick(textView, at: firstLocation, in: mounted)
        let firstModal = try XCTUnwrap(mounted.view.linkModalView)
        let firstFrame = firstModal.frame
        XCTAssertEqual(firstModal.textField.stringValue, "one")

        let mouseDown = try mouseDownEvent(location: secondLocation, windowNumber: mounted.window.windowNumber)
        XCTAssertTrue(mounted.view.dismissLinkModalIfMouseDownMovedFocusOutside(mouseDown))

        let updatedModal = try XCTUnwrap(mounted.view.linkModalView)
        XCTAssertIdentical(updatedModal, firstModal)
        XCTAssertEqual(updatedModal.textField.stringValue, "two")
        XCTAssertEqual(updatedModal.urlField.stringValue, "https://two.example")
        XCTAssertNotEqual(updatedModal.frame.origin.x, firstFrame.origin.x, accuracy: 0.5)
    }

    func testFocusCheckDoesNotDismissModalDuringPendingRegularLinkRetarget() throws {
        let text = "Open [one](https://one.example) then [two](https://two.example)"
        let mounted = mountLegacy(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let textView = try textView(in: mounted.view)
        let firstLocation = try windowLocation(forUTF16Offset: contentLocation("one", in: text), in: textView)
        let secondLocation = try windowLocation(forUTF16Offset: contentLocation("two", in: text), in: textView)

        try plainClick(textView, at: firstLocation, in: mounted)
        let modal = try XCTUnwrap(mounted.view.linkModalView)
        let mouseDown = try mouseDownEvent(location: secondLocation, windowNumber: mounted.window.windowNumber)

        XCTAssertTrue(mounted.view.dismissLinkModalIfMouseDownMovedFocusOutside(mouseDown))
        mounted.view.dismissLinkModalIfFocusMovedOutside()

        XCTAssertIdentical(mounted.view.linkModalView, modal)
        XCTAssertEqual(modal.textField.stringValue, "two")
        XCTAssertEqual(modal.urlField.stringValue, "https://two.example")
    }

    func testOutsideMouseDownOnLinkRetargetsModalInsteadOfDismissing() throws {
        let text = "Open [one](https://one.example) then [two](https://two.example)"
        let mounted = mountLegacy(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let textView = try textView(in: mounted.view)
        let firstLocation = try windowLocation(forUTF16Offset: contentLocation("one", in: text), in: textView)
        let secondLocation = try windowLocation(forUTF16Offset: contentLocation("two", in: text), in: textView)

        try plainClick(textView, at: firstLocation, in: mounted)
        let modal = try XCTUnwrap(mounted.view.linkModalView)

        XCTAssertTrue(mounted.view.dismissLinkModalIfMouseDownMovedFocusOutside(try mouseDownEvent(
            location: secondLocation,
            windowNumber: mounted.window.windowNumber
        )))

        XCTAssertIdentical(mounted.view.linkModalView, modal)
        XCTAssertEqual(modal.textField.stringValue, "two")
        XCTAssertEqual(modal.urlField.stringValue, "https://two.example")
    }

    func testCommandClickFileChipWhileModalIsOpenDismissesModalThroughClickHandler() throws {
        let text = "Open [one](https://one.example) then [file](file:///tmp/demo.md)"
        let mounted = mountLegacy(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        var openedURLs: [URL] = []
        mounted.view.linkURLOpener = {
            openedURLs.append($0)
            return true
        }
        let textView = try textView(in: mounted.view)
        let firstLocation = try windowLocation(forUTF16Offset: contentLocation("one", in: text), in: textView)
        let chipLocation = try trailingChipPaddingLocation(content: "file", in: text, textView: textView)

        try plainClick(textView, at: firstLocation, in: mounted)
        XCTAssertNotNil(mounted.view.linkModalView)

        let mouseDown = try mouseDownEvent(
            location: chipLocation,
            windowNumber: mounted.window.windowNumber,
            modifierFlags: .command
        )
        XCTAssertTrue(mounted.view.dismissLinkModalIfMouseDownMovedFocusOutside(mouseDown))

        XCTAssertEqual(openedURLs.map(\.absoluteString), ["file:///tmp/demo.md"])
        XCTAssertNil(mounted.view.linkModalView)
    }

    func testCommandClickSlashCommandChipWhileModalIsOpenDismissesModalThroughHostHandler() throws {
        let text = "Open [one](https://one.example) then [/table](host-app://commands/table)"
        var contexts: [BlockInputSlashCommandChipClickContext] = []
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: text)
            ]),
            slashCommandChipClickHandler: { context in
                contexts.append(context)
                return .hostHandled
            },
            linkHoverEditAffordance: false
        ))
        let textView = try textView(in: mounted.view)
        let firstLocation = try windowLocation(forUTF16Offset: contentLocation("one", in: text), in: textView)
        let chipLocation = try trailingChipPaddingLocation(content: "/table", in: text, textView: textView)

        try plainClick(textView, at: firstLocation, in: mounted)
        XCTAssertNotNil(mounted.view.linkModalView)

        let mouseDown = try mouseDownEvent(
            location: chipLocation,
            windowNumber: mounted.window.windowNumber,
            modifierFlags: .command
        )
        XCTAssertTrue(mounted.view.dismissLinkModalIfMouseDownMovedFocusOutside(mouseDown))

        XCTAssertEqual(contexts.map(\.label), ["/table"])
        XCTAssertEqual(contexts.map(\.clickKind), [.commandClick])
        XCTAssertNil(mounted.view.linkModalView)
    }

    private func textView(in view: BlockInputView) throws -> BlockInputTextView {
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        return try XCTUnwrap(item.testingTextView)
    }

    private func contentLocation(_ content: String, in text: String) -> Int {
        (text as NSString).range(of: content).location
    }

    private func trailingChipPaddingLocation(
        content: String,
        in text: String,
        textView: BlockInputTextView
    ) throws -> NSPoint {
        let contentRange = (text as NSString).range(of: content)
        let item = try XCTUnwrap(textView.blockItem)
        let contentRect = item.anchorWindowRect(forUTF16Range: contentRange)
        XCTAssertFalse(contentRect.isEmpty)
        return NSPoint(x: contentRect.maxX + 1, y: contentRect.midY)
    }

    private func plainClick(
        _ textView: BlockInputTextView,
        at location: NSPoint,
        in mounted: (view: BlockInputView, window: NSWindow)
    ) throws {
        let mouseDown = try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber)
        if mounted.view.dismissLinkModalIfMouseDownMovedFocusOutside(mouseDown) {
            return
        }
        textView.mouseDown(with: mouseDown)
        XCTAssertTrue(textView.completeTrackedMouseUp(with: try mouseUpEvent(
            location: location,
            windowNumber: mounted.window.windowNumber
        )))
    }
}
