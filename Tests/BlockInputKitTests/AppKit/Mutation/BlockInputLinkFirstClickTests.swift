import AppKit
import XCTest
@testable import BlockInputKit

/// First-click / event-forwarding reliability. The observable proof that a forwarded mouse-down reached the link
/// click path is, under the shipped interaction model (`linkHoverEditAffordance` default ON), the link OPENING via
/// `linkURLOpener`. These tests keep the forwarding intent and assert the open instead of the legacy modal.
@MainActor
final class BlockInputLinkFirstClickTests: XCTestCase {
    private final class OpenedURLBox {
        var value: URL?
    }

    private func installOpener(on view: BlockInputView) -> OpenedURLBox {
        let box = OpenedURLBox()
        view.linkURLOpener = {
            box.value = $0
            return true
        }
        return box
    }

    func testTextViewAcceptsFirstMouseForImmediateLinkClicks() throws {
        let text = "Open [docs](https://example.com)"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let textView = try textView(in: mounted.view)
        let location = try windowLocation(forUTF16Offset: contentLocation("docs", in: text), in: textView)
        let event = try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber)

        XCTAssertTrue(textView.acceptsFirstMouse(for: event))
    }

    func testBlockContainersAcceptFirstMouseForImmediateLinkClicks() throws {
        let text = "Open [docs](https://example.com)"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let location = try windowLocation(forUTF16Offset: contentLocation("docs", in: text), in: textView)
        let event = try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber)

        XCTAssertTrue(item.view.acceptsFirstMouse(for: event))
        XCTAssertTrue(item.scrollView.acceptsFirstMouse(for: event))
        XCTAssertTrue(item.scrollView.contentView.acceptsFirstMouse(for: event))
        XCTAssertTrue(mounted.view.collectionView.acceptsFirstMouse(for: event))
    }

    func testReadOnlyTextViewDoesNotBroadenFirstMouseAwayFromLinks() throws {
        let text = "Open [docs](https://example.com)"
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: text)
            ]),
            isEditable: false
        ))
        let textView = try textView(in: mounted.view)
        let location = try windowLocation(forUTF16Offset: 0, in: textView)
        let event = try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber)

        XCTAssertFalse(textView.acceptsFirstMouse(for: event))
    }

    func testReadOnlyBlockContainersDoNotBroadenFirstMouseAwayFromLinks() throws {
        let text = "Open [docs](https://example.com)"
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: text)
            ]),
            isEditable: false
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let location = try windowLocation(forUTF16Offset: 0, in: textView)
        let event = try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber)

        XCTAssertFalse(item.view.acceptsFirstMouse(for: event))
        XCTAssertFalse(item.scrollView.acceptsFirstMouse(for: event))
        XCTAssertFalse(item.scrollView.contentView.acceptsFirstMouse(for: event))
        XCTAssertFalse(mounted.view.collectionView.acceptsFirstMouse(for: event))
    }

    func testClipViewMouseDownOnLinkForwardsToTextViewLinkClickPath() throws {
        let text = "Open [docs](https://example.com)"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let openedURL = installOpener(on: mounted.view)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let location = try iconCenter(in: textView, text: text)

        item.scrollView.contentView.mouseDown(with: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber))

        XCTAssertTrue(textView.completeTrackedMouseUp(with: try mouseUpEvent(
            location: location,
            windowNumber: mounted.window.windowNumber
        )))
        XCTAssertEqual(openedURL.value?.absoluteString, "https://example.com")
    }

    func testRootViewMouseDownOnLinkForwardsToTextViewLinkClickPath() throws {
        let text = "Open [docs](https://example.com)"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let openedURL = installOpener(on: mounted.view)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let location = try iconCenter(in: textView, text: text)

        item.view.mouseDown(with: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber))

        XCTAssertTrue(textView.completeTrackedMouseUp(with: try mouseUpEvent(
            location: location,
            windowNumber: mounted.window.windowNumber
        )))
        XCTAssertEqual(openedURL.value?.absoluteString, "https://example.com")
    }

    func testScrollViewMouseDownOnLinkForwardsToTextViewLinkClickPath() throws {
        let text = "Open [docs](https://example.com)"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let openedURL = installOpener(on: mounted.view)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let location = try iconCenter(in: textView, text: text)

        item.scrollView.mouseDown(with: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber))

        XCTAssertTrue(textView.completeTrackedMouseUp(with: try mouseUpEvent(
            location: location,
            windowNumber: mounted.window.windowNumber
        )))
        XCTAssertEqual(openedURL.value?.absoluteString, "https://example.com")
    }

    func testCollectionViewMouseDownOnLinkForwardsToTextViewLinkClickPath() throws {
        let text = "Open [docs](https://example.com)"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let openedURL = installOpener(on: mounted.view)
        let textView = try textView(in: mounted.view)
        let location = try iconCenter(in: textView, text: text)

        mounted.view.collectionView.mouseDown(with: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber))

        XCTAssertTrue(textView.completeTrackedMouseUp(with: try mouseUpEvent(
            location: location,
            windowNumber: mounted.window.windowNumber
        )))
        XCTAssertEqual(openedURL.value?.absoluteString, "https://example.com")
    }

    func testPlainClickRegularLinkDoesNotPublishCursorSelectionBeforeMouseUp() throws {
        let text = "Open [docs](https://example.com)"
        var publishedSelections: [BlockInputSelection?] = []
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: text)
            ]),
            onSelectionChange: { publishedSelections.append($0) }
        ))
        let openedURL = installOpener(on: mounted.view)
        let textView = try textView(in: mounted.view)
        let location = try iconCenter(in: textView, text: text)

        textView.mouseDown(with: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber))

        XCTAssertTrue(publishedSelections.isEmpty)
        XCTAssertTrue(textView.completeTrackedMouseUp(with: try mouseUpEvent(
            location: location,
            windowNumber: mounted.window.windowNumber
        )))
        XCTAssertEqual(openedURL.value?.absoluteString, "https://example.com")
    }

    func testPendingLinkClickDragJitterDoesNotPublishCursorSelectionBeforeMouseUp() throws {
        let text = "Open [docs](https://example.com)"
        var publishedSelections: [BlockInputSelection?] = []
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: text)
            ]),
            onSelectionChange: { publishedSelections.append($0) }
        ))
        let openedURL = installOpener(on: mounted.view)
        let textView = try textView(in: mounted.view)
        let location = try iconCenter(in: textView, text: text)

        textView.mouseDown(with: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber))
        textView.mouseDragged(with: try mouseDraggedEvent(
            location: NSPoint(x: location.x + 1, y: location.y),
            windowNumber: mounted.window.windowNumber
        ))

        XCTAssertTrue(publishedSelections.isEmpty)
        XCTAssertTrue(textView.completeTrackedMouseUp(with: try mouseUpEvent(
            location: location,
            windowNumber: mounted.window.windowNumber
        )))
        XCTAssertEqual(openedURL.value?.absoluteString, "https://example.com")
    }

    /// Window-space center of the link's painted open-icon rect: a single click here opens under the shipped model.
    private func iconCenter(in textView: BlockInputTextView, text: String) throws -> NSPoint {
        let labelLocation = try windowLocation(forUTF16Offset: contentLocation("docs", in: text), in: textView)
        let linkRange = try XCTUnwrap(textView.linkHitResult(atWindowLocation: labelLocation)).range
        let iconRect = try XCTUnwrap(textView.linkOpenIconWindowRect(for: linkRange))
        return NSPoint(x: iconRect.midX, y: iconRect.midY)
    }

    private func textView(in view: BlockInputView) throws -> BlockInputTextView {
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        return try XCTUnwrap(item.testingTextView)
    }

    private func contentLocation(_ content: String, in text: String) -> Int {
        (text as NSString).range(of: content).location
    }
}
