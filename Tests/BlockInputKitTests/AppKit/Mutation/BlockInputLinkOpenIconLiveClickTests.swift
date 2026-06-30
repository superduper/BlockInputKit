import AppKit
import XCTest
@testable import BlockInputKit

/// LIVE mouse-path coverage for the inline link "open" icon: real `mouseDown` + tracked `mouseUp` activation on the
/// painted icon rect (regular link opens URL, wikilink routes to the handler) without placing the caret, plus the
/// pointing-hand cursor coverage over the icon. Split from `BlockInputLinkOpenIconTests` to keep files under the limit.
@MainActor
final class BlockInputLinkOpenIconLiveClickTests: XCTestCase {
    // MARK: - (c3) LIVE mouse-down/up tracking on the painted icon activates the link without placing the caret

    func testLiveMouseDownThenTrackedMouseUpOnRegularLinkIconOpensURLWithoutPlacingCaret() throws {
        let text = "Open [docs](https://example.com) end"
        let mounted = makeMountedBlockInputView(blocks: [BlockInputBlock(id: "block", text: text)])
        var openedURLs: [URL] = []
        mounted.view.linkURLOpener = {
            openedURLs.append($0)
            return true
        }
        let textView = try textView(in: mounted.view)
        // Seed a caret well away from the link so a successful click can be shown NOT to move it.
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        let iconCharacterIndex = (text as NSString).range(of: "](").location
        let paintedRect = try paintedIconWindowRect(in: textView, iconCharacterIndex: iconCharacterIndex)
        let center = NSPoint(x: paintedRect.midX, y: paintedRect.midY)

        // Drive the REAL live mouse path: mouseDown captures the link/icon hit, the tracked mouse-up routes the click.
        textView.mouseDown(with: try mouseDownEvent(location: center, windowNumber: mounted.window.windowNumber))
        XCTAssertEqual(textView.blockSelectionClickLinkRange?.style, .link)
        XCTAssertTrue(textView.completeTrackedMouseUp(with: try mouseUpEvent(
            location: center,
            windowNumber: mounted.window.windowNumber
        )))

        XCTAssertEqual(openedURLs.map(\.absoluteString), ["https://example.com"])
        // The icon click routes WITHOUT placing the caret: selection stays collapsed and is not a link-text selection.
        XCTAssertEqual(textView.selectedRange().length, 0)
        XCTAssertNil(mounted.view.linkModalView)
    }

    func testLiveMouseDownThenTrackedMouseUpOnWikilinkIconRoutesToWikilinkHandler() throws {
        let text = "Open [[baz/Foo|Foo]] here"
        var captured: BlockInputInlineLinkClickContext?
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "block", text: text)]),
            inlineMarkupProviders: [WikilinkStandInMarkupProvider()],
            inlineLinkClickHandler: { context in
                captured = context
                return .hostHandled
            }
        ))
        let textView = try textView(in: mounted.view)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        let iconCharacterIndex = (text as NSString).range(of: "]]").location
        let paintedRect = try paintedIconWindowRect(in: textView, iconCharacterIndex: iconCharacterIndex)
        let center = NSPoint(x: paintedRect.midX, y: paintedRect.midY)

        textView.mouseDown(with: try mouseDownEvent(location: center, windowNumber: mounted.window.windowNumber))
        XCTAssertEqual(textView.blockSelectionClickLinkRange?.style.customMarkupIdentity?.identifier, "wikilink")
        XCTAssertTrue(textView.completeTrackedMouseUp(with: try mouseUpEvent(
            location: center,
            windowNumber: mounted.window.windowNumber
        )))

        let context = try XCTUnwrap(captured)
        XCTAssertEqual(context.kind, .customMarkup("wikilink"))
        XCTAssertEqual(context.alias, "Foo")
        XCTAssertEqual(context.destination.scheme, "wikilink")
        XCTAssertTrue(context.destination.absoluteString.contains("baz/Foo"))
        XCTAssertEqual(textView.selectedRange().length, 0)
    }

    func testIconDragJitterKeepsPendingLinkClickEvenWhenMouseDownPointDriftedPastTolerance() throws {
        // Live-path hardening: the open icon paints in a kern gap past the link's visible glyph, so the captured
        // mouse-down window point can sit farther than the movement tolerance from the icon a tracking drag reports.
        // The icon-rect geometry (not point proximity) must keep the pending link click so the click is not dropped.
        let text = "Open [docs](https://example.com) end"
        let mounted = makeMountedBlockInputView(blocks: [BlockInputBlock(id: "block", text: text)])
        var openedURLs: [URL] = []
        mounted.view.linkURLOpener = {
            openedURLs.append($0)
            return true
        }
        let textView = try textView(in: mounted.view)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        let iconCharacterIndex = (text as NSString).range(of: "](").location
        let paintedRect = try paintedIconWindowRect(in: textView, iconCharacterIndex: iconCharacterIndex)
        let center = NSPoint(x: paintedRect.midX, y: paintedRect.midY)

        textView.mouseDown(with: try mouseDownEvent(location: center, windowNumber: mounted.window.windowNumber))
        XCTAssertEqual(textView.blockSelectionClickLinkRange?.style, .link)
        // Force the stored mouse-down point far from the icon so the legacy proximity check alone would FAIL.
        textView.blockSelectionMouseDownWindowLocation = NSPoint(x: center.x - 100, y: center.y - 100)

        // A tracking drag reported on the icon must be treated as "stayed near the link" (so it does not promote to a
        // selection), and the completed mouse-up must still open the link without placing the caret.
        textView.mouseDragged(with: try mouseDraggedEvent(location: center, windowNumber: mounted.window.windowNumber))
        XCTAssertFalse(textView.isDraggingBlockSelection)
        XCTAssertNil(textView.blockSelectionLocalDragRange)

        XCTAssertTrue(textView.completeTrackedMouseUp(with: try mouseUpEvent(
            location: center,
            windowNumber: mounted.window.windowNumber
        )))
        XCTAssertEqual(openedURLs.map(\.absoluteString), ["https://example.com"])
        XCTAssertEqual(textView.selectedRange().length, 0)
    }

    // MARK: - (c4) the link's hand-cursor rects cover the painted open icon

    func testLinkHandCursorRectsIncludeTheOpenIconRect() throws {
        let text = "Open [docs](https://example.com) end"
        let mounted = makeMountedBlockInputView(blocks: [BlockInputBlock(id: "block", text: text)])
        let textView = try textView(in: mounted.view)

        // Resolve the link via the shared hit-test, then ask for its shared painted icon rect (view coords).
        let labelLocation = try windowLocation(forUTF16Offset: (text as NSString).range(of: "docs").location, in: textView)
        let linkRange = try XCTUnwrap(textView.linkHitResult(atWindowLocation: labelLocation)).range
        let iconRect = try XCTUnwrap(textView.linkOpenIconRect(for: linkRange))

        // `addLinkCursorRects` (driven by `resetCursorRects`) builds these. The shared painted icon rect must be added
        // explicitly so the pointing-hand cursor is guaranteed over the icon gap, not only the visible label.
        let cursorRects = textView.linkCursorRectsForTesting()
        XCTAssertTrue(
            cursorRects.contains { $0.contains(iconRect) },
            "hand-cursor rects \(cursorRects) should cover the open-icon rect \(iconRect)"
        )
        // The exact shared icon rect is one of the cursor rects (the explicit `linkOpenIconRect(for:)` append), so the
        // hand cursor stays guaranteed over the icon even if a font/kern change shrinks the chrome glyph's bounding rect.
        XCTAssertTrue(
            cursorRects.contains { $0.equalTo(iconRect) },
            "hand-cursor rects \(cursorRects) should include the exact open-icon rect \(iconRect)"
        )
    }

    // MARK: - (c5) REAL-LAYOUT adjacency + cursor/hit coverage of the painted icon rect

    /// Mounts and lays out the view, then asserts the painted icon rect (a) touches the visible label's trailing edge
    /// (adjacent, not gapped far past it), (b) sits within the line fragment vertically, and (c) is contained in BOTH the
    /// link's hand-cursor rects AND its hit rects — so the hand cursor and click cover exactly the painted icon — and a
    /// live click at the icon-rect center opens the link.
    func testPaintedIconRectIsAdjacentToLabelAndCoveredByCursorAndHitRects() throws {
        let text = "Open [docs](https://example.com) end"
        let mounted = makeMountedBlockInputView(blocks: [BlockInputBlock(id: "block", text: text)])
        var openedURLs: [URL] = []
        mounted.view.linkURLOpener = {
            openedURLs.append($0)
            return true
        }
        let textView = try textView(in: mounted.view)
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)

        // Resolve the link via the shared hit-test on the label, then the shared painted icon rect (view coords).
        let labelRange = (text as NSString).range(of: "docs")
        let labelLocation = try windowLocation(forUTF16Offset: labelRange.location, in: textView)
        let linkRange = try XCTUnwrap(textView.linkHitResult(atWindowLocation: labelLocation)).range
        let iconRect = try XCTUnwrap(textView.linkOpenIconRect(for: linkRange))
        XCTAssertFalse(iconRect.isEmpty)

        // (a) Adjacency: the icon starts at the label's trailing edge plus only the small lead gap (icon width + 3 kern).
        let labelGlyphRange = layoutManager.glyphRange(forCharacterRange: labelRange, actualCharacterRange: nil)
        let labelBounds = layoutManager.boundingRect(forGlyphRange: labelGlyphRange, in: textContainer)
        let labelMaxX = labelBounds.maxX + textView.textContainerOrigin.x
        XCTAssertGreaterThanOrEqual(iconRect.minX, labelMaxX)
        XCTAssertLessThanOrEqual(iconRect.minX - labelMaxX, 6, "icon must hug the label, not float far past it")

        // (b) Vertical: the icon sits within the label's line fragment.
        var lineRange = NSRange()
        let fragment = layoutManager.lineFragmentUsedRect(forGlyphAt: labelGlyphRange.location, effectiveRange: &lineRange)
        let fragmentInView = fragment.offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
        XCTAssertGreaterThanOrEqual(iconRect.minY, fragmentInView.minY - 0.5)
        XCTAssertLessThanOrEqual(iconRect.maxY, fragmentInView.maxY + 0.5)

        // (c) Cursor coverage: the icon rect is one of the hand-cursor rects (exact append) and is fully contained.
        let cursorRects = textView.linkCursorRectsForTesting()
        XCTAssertTrue(cursorRects.contains { $0.contains(iconRect) }, "cursor rects \(cursorRects) must cover icon \(iconRect)")

        // (c) Hit coverage: clicking the icon center resolves to the link, and the icon rect is inside the hit rects.
        let iconWindowRect = try XCTUnwrap(textView.linkOpenIconWindowRect(for: linkRange))
        let center = NSPoint(x: iconWindowRect.midX, y: iconWindowRect.midY)
        let hit = try XCTUnwrap(textView.linkHitResult(atWindowLocation: center))
        XCTAssertEqual(hit.range.style, .link)
        XCTAssertTrue(
            hit.windowRects.contains { $0.contains(iconWindowRect) },
            "hit rects \(hit.windowRects) must cover icon window rect \(iconWindowRect)"
        )

        // Live click at the icon center opens the link (reusing the live mouse-down/up tracking path).
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.mouseDown(with: try mouseDownEvent(location: center, windowNumber: mounted.window.windowNumber))
        XCTAssertEqual(textView.blockSelectionClickLinkRange?.style, .link)
        XCTAssertTrue(textView.completeTrackedMouseUp(with: try mouseUpEvent(
            location: center,
            windowNumber: mounted.window.windowNumber
        )))
        XCTAssertEqual(openedURLs.map(\.absoluteString), ["https://example.com"])
        XCTAssertEqual(textView.selectedRange().length, 0)
    }

    // MARK: - Helpers

    private func paintedIconWindowRect(in textView: BlockInputTextView, iconCharacterIndex: Int) throws -> NSRect {
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        let storage = try XCTUnwrap(textView.textStorage)
        layoutManager.ensureLayout(for: textContainer)
        let attachment = try XCTUnwrap(
            storage.attribute(.blockInputLinkOpenIcon, at: iconCharacterIndex, effectiveRange: nil) as? BlockInputLinkOpenAttachment
        )
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: iconCharacterIndex, length: 1),
            actualCharacterRange: nil
        )
        let iconGlyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let lineFragmentRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        let origin = textView.textContainerOrigin
        let imageSize = attachment.image.size
        let leadGap = max(attachment.advance - imageSize.width, 0)
        let drawRect = NSRect(
            x: iconGlyphRect.minX + origin.x + leadGap,
            y: lineFragmentRect.midY + origin.y - imageSize.height / 2,
            width: imageSize.width,
            height: imageSize.height
        )
        return textView.convert(drawRect, to: nil)
    }

    private func textView(in view: BlockInputView) throws -> BlockInputTextView {
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        return try XCTUnwrap(item.testingTextView)
    }
}
