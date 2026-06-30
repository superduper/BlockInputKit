import AppKit
import XCTest
@testable import BlockInputKit

/// Geometry / drag-jitter tolerance for link clicks. Under the shipped interaction model (`linkHoverEditAffordance`
/// default ON) a single click on the link BODY only places the caret; a single click on the trailing OPEN ICON opens
/// the link. These tests exercise the drift/jitter tolerance on the OPEN path by clicking the painted icon rect: a
/// successful icon click OPENS via `linkURLOpener` even when the tracked mouse-up drifts within tolerance.
@MainActor
final class BlockInputLinkClickJitterTests: XCTestCase {
    func testIconClickUsesMouseDownHitWhenMouseUpHasNoClickCount() throws {
        let text = "Open [docs](https://example.com)"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let openedURL = installOpener(on: mounted.view)
        let textView = try textView(in: mounted.view)
        let location = try iconCenter(in: textView, text: text)

        textView.mouseDown(with: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber))
        XCTAssertTrue(textView.completeTrackedMouseUp(with: try mouseUpEvent(
            location: location,
            windowNumber: mounted.window.windowNumber,
            clickCount: 0
        )))

        XCTAssertEqual(openedURL.value?.absoluteString, "https://example.com")
        XCTAssertNil(mounted.view.linkModalView)
    }

    func testIconClickAllowsTrackedDragJitterInsideMouseDownHit() throws {
        let text = "Open [docs](https://example.com)"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let openedURL = installOpener(on: mounted.view)
        let textView = try textView(in: mounted.view)
        let location = try iconCenter(in: textView, text: text)

        textView.mouseDown(with: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber))
        XCTAssertTrue(textView.completeTrackedMouseUp(with: try mouseUpEvent(
            location: NSPoint(x: location.x + 2, y: location.y),
            windowNumber: mounted.window.windowNumber
        )))

        XCTAssertEqual(openedURL.value?.absoluteString, "https://example.com")
        XCTAssertNil(mounted.view.linkModalView)
    }

    func testIconClickAllowsTinyTrackedDragJitterWithinTolerance() throws {
        let text = "Open [docs](https://example.com)"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let openedURL = installOpener(on: mounted.view)
        let textView = try textView(in: mounted.view)
        let location = try iconCenter(in: textView, text: text)
        let mouseUpLocation = NSPoint(x: location.x + 1, y: location.y)

        textView.mouseDown(with: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber))
        textView.mouseDragged(with: try mouseDraggedEvent(location: mouseUpLocation, windowNumber: mounted.window.windowNumber))
        XCTAssertTrue(textView.completeTrackedMouseUp(with: try mouseUpEvent(
            location: mouseUpLocation,
            windowNumber: mounted.window.windowNumber
        )))

        XCTAssertEqual(openedURL.value?.absoluteString, "https://example.com")
        XCTAssertNil(mounted.view.linkModalView)
    }

    func testSingleClickOnLabelBodyPlacesCaretWithoutOpening() throws {
        // The flip side of the icon-open path: a single tracked click on the visible LABEL only places the caret.
        let text = "Open [docs](https://example.com)"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let openedURL = installOpener(on: mounted.view)
        let textView = try textView(in: mounted.view)
        let location = try windowLocation(forUTF16Offset: contentLocation("docs", in: text), in: textView)

        textView.mouseDown(with: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber))
        _ = textView.completeTrackedMouseUp(with: try mouseUpEvent(
            location: location,
            windowNumber: mounted.window.windowNumber
        ))

        XCTAssertNil(openedURL.value)
        XCTAssertNil(mounted.view.linkModalView)
    }

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

    /// Window-space center of the link's painted open-icon rect (the shared single source of truth).
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
