import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputLinkClickTests: XCTestCase {
    func testCommandClickRelativeFileChipResolvesAgainstFileBaseURL() throws {
        let baseURL = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: "Open [README](assets/README.md)")
            ]),
            fileBaseURL: baseURL
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
            event: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber, modifierFlags: .command)
        ))

        XCTAssertEqual(openedURL, baseURL.appendingPathComponent("assets/README.md"))
    }

    func testSingleClickOnBodyPlacesCaretWhileDoubleClickAndCommandClickOpen() throws {
        // Interaction model (linkHoverEditAffordance default ON): a single click on the link BODY only places the caret
        // (returns false, no open, no modal). A double-click on the body opens; cmd-click also opens.
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open [docs](https://example.com)")
        ])
        var openedURLs: [URL] = []
        mounted.view.linkURLOpener = {
            openedURLs.append($0)
            return true
        }
        let textView = try textView(in: mounted.view)
        let location = try windowLocation(forUTF16Offset: 7, in: textView)

        // Single click on the body: no open, no modal (the caller's caret placement proceeds).
        XCTAssertFalse(mounted.view.handleLinkClick(
            blockID: "block",
            selectedRange: NSRange(location: 7, length: 0),
            event: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber)
        ))
        XCTAssertTrue(openedURLs.isEmpty)
        XCTAssertNil(mounted.view.linkModalView)

        // Double click on the body opens.
        XCTAssertTrue(mounted.view.handleLinkClick(
            blockID: "block",
            selectedRange: NSRange(location: 7, length: 0),
            event: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber, clickCount: 2)
        ))
        XCTAssertNil(mounted.view.linkModalView)

        // Command click opens.
        XCTAssertTrue(mounted.view.handleLinkClick(
            blockID: "block",
            selectedRange: NSRange(location: 7, length: 0),
            event: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber, modifierFlags: .command)
        ))
        XCTAssertEqual(openedURLs.map(\.absoluteString), ["https://example.com", "https://example.com"])
    }

    func testSingleClickOnBodyThroughTrackedMouseUpPlacesCaretWithoutOpening() throws {
        // Routing intent: a single plain click completed through the tracked mouse-up monitor path reaches the link's
        // click decision but, landing on the BODY (not the open icon), only places the caret — it does NOT open.
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open [docs](https://example.com)")
        ])
        var openedURLs: [URL] = []
        mounted.view.linkURLOpener = {
            openedURLs.append($0)
            return true
        }
        let textView = try textView(in: mounted.view)
        let location = try windowLocation(forUTF16Offset: 7, in: textView)

        textView.mouseDown(with: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber))
        _ = textView.completeTrackedMouseUp(with: try mouseUpEvent(
            location: location,
            windowNumber: mounted.window.windowNumber
        ))

        XCTAssertTrue(openedURLs.isEmpty)
        XCTAssertNil(mounted.view.linkModalView)
        // The caret is placed inside the link label rather than the link opening.
        XCTAssertEqual(textView.selectedRange().length, 0)
    }

    func testSingleClickOnBodyDoesNotOpenWhenMouseUpLandsOnNeighboringLinkOffsetWithoutDragEvent() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open [docs](https://example.com)")
        ])
        var openedURLs: [URL] = []
        mounted.view.linkURLOpener = {
            openedURLs.append($0)
            return true
        }
        let textView = try textView(in: mounted.view)
        let mouseDownLocation = try windowLocation(forUTF16Offset: 7, in: textView)
        let mouseUpLocation = try windowLocation(forUTF16Offset: 8, in: textView)

        textView.mouseDown(with: try mouseDownEvent(location: mouseDownLocation, windowNumber: mounted.window.windowNumber))
        _ = textView.completeTrackedMouseUp(with: try mouseUpEvent(
            location: mouseUpLocation,
            windowNumber: mounted.window.windowNumber
        ))

        XCTAssertTrue(openedURLs.isEmpty)
        XCTAssertNil(mounted.view.linkModalView)
    }

    func testPlainClickDoesNotOpenModalWhenUnreportedMouseMoveCrossesMultipleOffsets() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open [docs](https://example.com)")
        ])
        let textView = try textView(in: mounted.view)
        let mouseDownLocation = try windowLocation(forUTF16Offset: 5, in: textView)
        let mouseUpLocation = try windowLocation(forUTF16Offset: 9, in: textView)

        textView.mouseDown(with: try mouseDownEvent(location: mouseDownLocation, windowNumber: mounted.window.windowNumber))
        XCTAssertTrue(textView.completeTrackedMouseUp(with: try mouseUpEvent(
            location: mouseUpLocation,
            windowNumber: mounted.window.windowNumber
        )))

        XCTAssertNil(mounted.view.linkModalView)
        XCTAssertGreaterThan(textView.selectedRange().length, 1)
    }

    func testCommandClickThroughTextViewMouseDownOpensURL() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open [docs](https://example.com)")
        ])
        var openedURL: URL?
        mounted.view.linkURLOpener = {
            openedURL = $0
            return true
        }
        let textView = try textView(in: mounted.view)
        let location = try windowLocation(forUTF16Offset: 7, in: textView)

        textView.mouseDown(with: try mouseDownEvent(
            location: location,
            windowNumber: mounted.window.windowNumber,
            modifierFlags: .command
        ))

        XCTAssertEqual(openedURL?.absoluteString, "https://example.com")
    }

    func testCommandClickFileLinkThroughTextViewMouseDownAndMouseUpOpensURLOnce() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open [file](file:///tmp/demo.md)")
        ])
        var openedURLs: [URL] = []
        mounted.view.linkURLOpener = {
            openedURLs.append($0)
            return true
        }
        let textView = try textView(in: mounted.view)
        let location = try windowLocation(forUTF16Offset: 7, in: textView)

        textView.mouseDown(with: try mouseDownEvent(
            location: location,
            windowNumber: mounted.window.windowNumber,
            modifierFlags: .command
        ))
        textView.mouseUp(with: try mouseUpEvent(
            location: location,
            windowNumber: mounted.window.windowNumber,
            modifierFlags: .command
        ))

        XCTAssertEqual(openedURLs.map(\.absoluteString), ["file:///tmp/demo.md"])
        XCTAssertNil(mounted.view.linkModalView)
    }

    func testCommandClickOpensSupportedLinkSchemes() throws {
        let urls = [
            "http://example.com",
            "https://example.com",
            "file:///tmp/demo.md"
        ]

        for urlString in urls {
            let mounted = makeMountedBlockInputView(blocks: [
                BlockInputBlock(id: "block", text: "Open [docs](\(urlString))")
            ])
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
                event: try mouseDownEvent(
                    location: location,
                    windowNumber: mounted.window.windowNumber,
                    modifierFlags: .command
                )
            ))
            XCTAssertEqual(openedURL?.absoluteString, urlString)
        }
    }

    func testAngleBracketFileURLBehavesLikeRegularLinkOnDoubleClick() throws {
        // A `<file://>` URL is classified as a regular plain link (not a file chip). Under the shipped model a single
        // click on its body only places the caret; a double-click opens it (like any other regular link).
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open [file](<file:///tmp/demo.md>)")
        ])
        var openedURL: URL?
        mounted.view.linkURLOpener = {
            openedURL = $0
            return true
        }
        let textView = try textView(in: mounted.view)
        let location = try windowLocation(forUTF16Offset: 7, in: textView)

        // Single click on the body does not open.
        XCTAssertFalse(mounted.view.handleLinkClick(
            blockID: "block",
            selectedRange: NSRange(location: 7, length: 0),
            event: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber)
        ))
        XCTAssertNil(openedURL)

        // Double click opens.
        XCTAssertTrue(mounted.view.handleLinkClick(
            blockID: "block",
            selectedRange: NSRange(location: 7, length: 0),
            event: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber, clickCount: 2)
        ))

        XCTAssertEqual(openedURL?.absoluteString, "file:///tmp/demo.md")
        XCTAssertNil(mounted.view.linkModalView)
    }

    func testFileLinkFullSourceResolvesForChipClickButRegularLinkDoesNot() throws {
        let fileText = "Open [file](file:///tmp/demo.md) now"
        let regularText = "Open [docs](https://example.com) now"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: fileText)
        ])
        let fileOpeningBracket = (fileText as NSString).range(of: "[").location
        let filePostBoundary = NSMaxRange((fileText as NSString).range(of: "[file](file:///tmp/demo.md)"))
        let regularOpeningBracket = (regularText as NSString).range(of: "[").location

        XCTAssertNotNil(mounted.view.linkRange(
            in: fileText,
            containing: NSRange(location: fileOpeningBracket, length: 0)
        ))
        XCTAssertNil(mounted.view.linkRange(
            in: fileText,
            containing: NSRange(location: filePostBoundary, length: 0)
        ))
        XCTAssertNil(mounted.view.linkRange(
            in: regularText,
            containing: NSRange(location: regularOpeningBracket, length: 0)
        ))
    }

    func testDraggingFromLinkTextDoesNotOpenModalOnMouseUp() throws {
        // Geometry intent: dragging across the link's visible glyphs selects text and never opens a modal. The
        // precomputed window points assume the always-collapsed layout, which stays stable across the drag.
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: "Open [docs](https://example.com)")
            ])
        ))
        let textView = try textView(in: mounted.view)
        let startLocation = try windowLocation(forUTF16Offset: 7, in: textView)
        let endLocation = try windowLocation(forUTF16Offset: 9, in: textView)

        textView.mouseDown(with: try mouseDownEvent(location: startLocation, windowNumber: mounted.window.windowNumber))
        textView.mouseDragged(with: try mouseDraggedEvent(location: endLocation, windowNumber: mounted.window.windowNumber))
        XCTAssertTrue(textView.completeTrackedMouseUp(with: try mouseUpEvent(
            location: endLocation,
            windowNumber: mounted.window.windowNumber
        )))

        XCTAssertNil(mounted.view.linkModalView)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 7, length: 2))
    }

    // MARK: - Legacy (linkHoverEditAffordance OFF) double-click still shows the modal, not navigation

    func testDoubleClickOnRegularLinkShowsModalWhenAffordanceOff() throws {
        // The default (affordance ON) path navigates on a double-click. The LEGACY path (affordance OFF) keeps the
        // pre-wikilink behavior where a click shows the link-edit modal and never auto-navigates on double-click.
        let text = "Open [docs](https://example.com) end"
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: text)
            ]),
            linkHoverEditAffordance: false
        ))
        var openedURLs: [URL] = []
        mounted.view.linkURLOpener = {
            openedURLs.append($0)
            return true
        }
        let textView = try textView(in: mounted.view)
        let location = try windowLocation(forUTF16Offset: 7, in: textView)

        // A double-click event no longer opens; with the affordance off the link modal is shown instead.
        XCTAssertTrue(mounted.view.handleLinkClick(
            blockID: "block",
            selectedRange: NSRange(location: 7, length: 0),
            event: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber, clickCount: 2)
        ))
        XCTAssertTrue(openedURLs.isEmpty)
        XCTAssertNotNil(mounted.view.linkModalView)
    }

    func testSingleClickPlacesCaretWithoutOpeningWhenAffordanceOff() throws {
        // Single click still places the caret (the modal fallback path) and does NOT open the URL when the hover
        // affordance is off.
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: "Open [docs](https://example.com) end")
            ]),
            linkHoverEditAffordance: false
        ))
        var openedURLs: [URL] = []
        mounted.view.linkURLOpener = {
            openedURLs.append($0)
            return true
        }
        let textView = try textView(in: mounted.view)
        let location = try windowLocation(forUTF16Offset: 7, in: textView)

        textView.mouseDown(with: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber, clickCount: 1))
        _ = textView.completeTrackedMouseUp(with: try mouseUpEvent(location: location, windowNumber: mounted.window.windowNumber))

        XCTAssertTrue(openedURLs.isEmpty)
    }

    // MARK: - Live double-click routing

    func testLiveDoubleClickOnLinkBodyOpensURL() throws {
        // Routing decision at the live `mouseDown` level: a `clickCount == 2` event over the link body routes to the
        // link-click path and opens, without driving a synthetic double-click through `super.mouseDown` (whose
        // event-tracking loop hangs headless). A single click over the same body does not open.
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open [docs](https://example.com)")
        ])
        var openedURLs: [URL] = []
        mounted.view.linkURLOpener = {
            openedURLs.append($0)
            return true
        }
        let textView = try textView(in: mounted.view)
        let location = try windowLocation(forUTF16Offset: 7, in: textView)

        // The text view classifies the gesture: a double-click over a link is routable as a link click.
        XCTAssertFalse(textView.shouldRequestDoubleClickLink(
            with: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber, clickCount: 1)
        ))
        XCTAssertTrue(textView.shouldRequestDoubleClickLink(
            with: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber, clickCount: 2)
        ))

        // Driving the double-click through the live mouseDown opens the link (and does not enter native multi-click).
        textView.mouseDown(with: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber, clickCount: 2))
        XCTAssertEqual(openedURLs.map(\.absoluteString), ["https://example.com"])
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
