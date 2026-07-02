import AppKit
import XCTest
@testable import BlockInputKit

/// Reliability/hit-geometry coverage for the legacy modal interaction model. These assertions are about *which*
/// link a click resolves to (modal field contents) and modal retargeting between links — behavior that only exists
/// when `linkHoverEditAffordance` is off. The tests mount with the affordance disabled so the geometry intent is
/// exercised against the modal path; the new plain-click-opens model is covered in `BlockInputLinkClickTests`.
@MainActor
final class BlockInputLinkClickReliabilityTests: XCTestCase {
    private func mountLegacy(blocks: [BlockInputBlock]) -> (view: BlockInputView, window: NSWindow) {
        // Legacy modal model: plain click shows the modal (linkHoverEditAffordance off). Links always render
        // collapsed, so the layout these tests precompute window points against stays stable across clicks.
        makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: blocks),
            linkHoverEditAffordance: false
        ))
    }

    func testPlainClickFileChipTrailingPaddingOpensModal() throws {
        let text = "Open [file](file:///tmp/demo.md) now"
        let mounted = mountLegacy(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let textView = try textView(in: mounted.view)
        let location = try trailingChipPaddingLocation(content: "file", in: text, textView: textView)

        try plainClick(textView, at: location, in: mounted)

        let modal = try XCTUnwrap(mounted.view.linkModalView)
        XCTAssertEqual(modal.textField.stringValue, "file")
        XCTAssertEqual(modal.urlField.stringValue, "file:///tmp/demo.md")
    }

    func testPlainClickFileChipTrailingPaddingStillWorksWithTransparentCustomChipStyle() throws {
        let text = "Open [file](file:///tmp/demo.md) now"
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: text)
            ]),
            style: BlockInputStyle(fileChip: BlockInputInlineChipStyle(
                fillColor: nil,
                strokeColor: nil,
                foregroundColor: .systemRed,
                cornerRadius: 0
            )),
            linkHoverEditAffordance: false
        ))
        let textView = try textView(in: mounted.view)
        let location = try trailingChipPaddingLocation(content: "file", in: text, textView: textView)

        try plainClick(textView, at: location, in: mounted)

        let modal = try XCTUnwrap(mounted.view.linkModalView)
        XCTAssertEqual(modal.textField.stringValue, "file")
        XCTAssertEqual(modal.urlField.stringValue, "file:///tmp/demo.md")
        XCTAssertEqual(mounted.view.document.markdown, text)
    }

    func testPlainClickSlashCommandChipTrailingPaddingRoutesHandler() throws {
        let text = "Run [/table](host-app://commands/table) now"
        var contexts: [BlockInputSlashCommandChipClickContext] = []
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: text)
            ]),
            slashCommandChipClickHandler: { context in
                contexts.append(context)
                return .hostHandled
            }
        ))
        let textView = try textView(in: mounted.view)
        let location = try trailingChipPaddingLocation(content: "/table", in: text, textView: textView)

        try plainClick(textView, at: location, in: mounted)

        XCTAssertEqual(contexts.map(\.label), ["/table"])
        XCTAssertNil(mounted.view.linkModalView)
    }

    func testClickingAnotherRegularLinkWhileModalIsOpenSwitchesModalOnSameClick() throws {
        let text = "Open [one](https://one.example) then [two](https://two.example)"
        let mounted = mountLegacy(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let textView = try textView(in: mounted.view)
        let firstLocation = try windowLocation(forUTF16Offset: contentLocation("one", in: text), in: textView)
        let secondLocation = try windowLocation(forUTF16Offset: contentLocation("two", in: text), in: textView)

        try plainClick(textView, at: firstLocation, in: mounted)
        XCTAssertEqual(mounted.view.linkModalView?.textField.stringValue, "one")

        try plainClick(textView, at: secondLocation, in: mounted)

        let modal = try XCTUnwrap(mounted.view.linkModalView)
        XCTAssertEqual(modal.textField.stringValue, "two")
        XCTAssertEqual(modal.urlField.stringValue, "https://two.example")
    }

    func testPlainClickRegularLinkInUnfocusedBlockOpensModalOnFirstClick() throws {
        let secondText = "Open [docs](https://example.com)"
        let mounted = mountLegacy(blocks: [
            BlockInputBlock(id: "first", text: "First block"),
            BlockInputBlock(id: "second", text: secondText)
        ])
        let firstTextView = try textView(in: mounted.view, at: 0)
        let secondTextView = try textView(in: mounted.view, at: 1)
        mounted.window.makeFirstResponder(firstTextView)
        firstTextView.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertEqual(mounted.window.firstResponder, firstTextView)
        let location = try windowLocation(forUTF16Offset: contentLocation("docs", in: secondText), in: secondTextView)

        try plainClick(secondTextView, at: location, in: mounted)

        let modal = try XCTUnwrap(mounted.view.linkModalView)
        XCTAssertEqual(modal.textField.stringValue, "docs")
        XCTAssertEqual(modal.urlField.stringValue, "https://example.com")
    }

    func testPlainClickRegularLinkInUnfocusedBlockUsesMouseDownHitWhenMouseUpOffsetRemaps() throws {
        let secondText = "Open [docs](https://example.com)"
        let mounted = mountLegacy(blocks: [
            BlockInputBlock(id: "first", text: "First block"),
            BlockInputBlock(id: "second", text: secondText)
        ])
        let firstTextView = try textView(in: mounted.view, at: 0)
        let secondTextView = try textView(in: mounted.view, at: 1)
        mounted.window.makeFirstResponder(firstTextView)
        firstTextView.setSelectedRange(NSRange(location: 0, length: 0))
        let location = try windowLocation(forUTF16Offset: contentLocation("docs", in: secondText), in: secondTextView)
        let mouseDown = try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber)

        secondTextView.mouseDown(with: mouseDown)
        secondTextView.blockSelectionDragAnchorOffset = 0
        XCTAssertTrue(secondTextView.completeTrackedMouseUp(with: try mouseUpEvent(
            location: location,
            windowNumber: mounted.window.windowNumber
        )))

        let modal = try XCTUnwrap(mounted.view.linkModalView)
        XCTAssertEqual(modal.textField.stringValue, "docs")
        XCTAssertEqual(modal.urlField.stringValue, "https://example.com")
    }

    func testPlainClickRegularLinkNearLineFragmentEdgeOpensModal() throws {
        // A 40pt inline-code sibling glyph on the same line makes the line fragment deterministically
        // taller than the link label's own glyph box, so `regularLinkLineEdgeLocation` can always pick
        // a point inside the fragment but vertically outside the link glyphs (the vertical-slop contract).
        let text = "Open [docs](https://example.com) and `x`"
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: text)
            ]),
            style: BlockInputStyle(inlineCode: BlockInputInlineCodeStyle(
                font: .monospacedSystemFont(ofSize: 40, weight: .regular)
            )),
            linkHoverEditAffordance: false
        ))
        let textView = try textView(in: mounted.view)
        let location = try regularLinkLineEdgeLocation(content: "docs", in: text, textView: textView)

        try plainClick(textView, at: location, in: mounted)

        let modal = try XCTUnwrap(mounted.view.linkModalView)
        XCTAssertEqual(modal.textField.stringValue, "docs")
        XCTAssertEqual(modal.urlField.stringValue, "https://example.com")
    }

    func testClickingFileChipWhileModalIsOpenSwitchesModalOnSameClick() throws {
        let text = "Open [one](https://one.example) then [file](file:///tmp/demo.md)"
        let mounted = mountLegacy(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let textView = try textView(in: mounted.view)
        let firstLocation = try windowLocation(forUTF16Offset: contentLocation("one", in: text), in: textView)
        let chipLocation = try trailingChipPaddingLocation(content: "file", in: text, textView: textView)

        try plainClick(textView, at: firstLocation, in: mounted)
        XCTAssertEqual(mounted.view.linkModalView?.textField.stringValue, "one")

        try plainClick(textView, at: chipLocation, in: mounted)

        let modal = try XCTUnwrap(mounted.view.linkModalView)
        XCTAssertEqual(modal.textField.stringValue, "file")
        XCTAssertEqual(modal.urlField.stringValue, "file:///tmp/demo.md")
    }

    func testPlainClickFileChipInUnfocusedBlockOpensModalOnFirstClick() throws {
        let secondText = "Open [file](file:///tmp/demo.md)"
        let mounted = mountLegacy(blocks: [
            BlockInputBlock(id: "first", text: "First block"),
            BlockInputBlock(id: "second", text: secondText)
        ])
        let firstTextView = try textView(in: mounted.view, at: 0)
        let secondTextView = try textView(in: mounted.view, at: 1)
        mounted.window.makeFirstResponder(firstTextView)
        firstTextView.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertEqual(mounted.window.firstResponder, firstTextView)
        let location = try trailingChipPaddingLocation(content: "file", in: secondText, textView: secondTextView)

        try plainClick(secondTextView, at: location, in: mounted)

        let modal = try XCTUnwrap(mounted.view.linkModalView)
        XCTAssertEqual(modal.textField.stringValue, "file")
        XCTAssertEqual(modal.urlField.stringValue, "file:///tmp/demo.md")
    }

    func testPlainClickFileChipInUnfocusedBlockUsesMouseDownHitWhenMouseUpOffsetRemaps() throws {
        let secondText = "Open [file](file:///tmp/demo.md)"
        let mounted = mountLegacy(blocks: [
            BlockInputBlock(id: "first", text: "First block"),
            BlockInputBlock(id: "second", text: secondText)
        ])
        let firstTextView = try textView(in: mounted.view, at: 0)
        let secondTextView = try textView(in: mounted.view, at: 1)
        mounted.window.makeFirstResponder(firstTextView)
        firstTextView.setSelectedRange(NSRange(location: 0, length: 0))
        let location = try trailingChipPaddingLocation(content: "file", in: secondText, textView: secondTextView)
        let mouseDown = try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber)

        secondTextView.mouseDown(with: mouseDown)
        secondTextView.blockSelectionDragAnchorOffset = 0
        XCTAssertTrue(secondTextView.completeTrackedMouseUp(with: try mouseUpEvent(
            location: location,
            windowNumber: mounted.window.windowNumber
        )))

        let modal = try XCTUnwrap(mounted.view.linkModalView)
        XCTAssertEqual(modal.textField.stringValue, "file")
        XCTAssertEqual(modal.urlField.stringValue, "file:///tmp/demo.md")
    }

    func testPlainClickSlashCommandChipInUnfocusedBlockOpensModalOnFirstClick() throws {
        let secondText = "Run [/table](host-app://commands/table)"
        var contexts: [BlockInputSlashCommandChipClickContext] = []
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "first", text: "First block"),
                BlockInputBlock(id: "second", text: secondText)
            ]),
            slashCommandChipClickHandler: { context in
                contexts.append(context)
                return .showLinkModal
            }
        ))
        let firstTextView = try textView(in: mounted.view, at: 0)
        let secondTextView = try textView(in: mounted.view, at: 1)
        mounted.window.makeFirstResponder(firstTextView)
        firstTextView.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertEqual(mounted.window.firstResponder, firstTextView)
        let location = try trailingChipPaddingLocation(content: "/table", in: secondText, textView: secondTextView)

        try plainClick(secondTextView, at: location, in: mounted)

        let modal = try XCTUnwrap(mounted.view.linkModalView)
        XCTAssertEqual(contexts.map(\.label), ["/table"])
        XCTAssertEqual(modal.textField.stringValue, "/table")
        XCTAssertEqual(modal.urlField.stringValue, "host-app://commands/table")
    }

    func testClickingSlashCommandChipWhileModalIsOpenSwitchesModalOnSameClick() throws {
        let text = "Open [one](https://one.example) then [/table](host-app://commands/table)"
        var contexts: [BlockInputSlashCommandChipClickContext] = []
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: text)
            ]),
            slashCommandChipClickHandler: { context in
                contexts.append(context)
                return .showLinkModal
            },
            linkHoverEditAffordance: false
        ))
        let textView = try textView(in: mounted.view)
        let firstLocation = try windowLocation(forUTF16Offset: contentLocation("one", in: text), in: textView)
        let chipLocation = try trailingChipPaddingLocation(content: "/table", in: text, textView: textView)

        try plainClick(textView, at: firstLocation, in: mounted)
        XCTAssertEqual(mounted.view.linkModalView?.textField.stringValue, "one")

        try plainClick(textView, at: chipLocation, in: mounted)

        let modal = try XCTUnwrap(mounted.view.linkModalView)
        XCTAssertEqual(contexts.map(\.label), ["/table"])
        XCTAssertEqual(modal.textField.stringValue, "/table")
        XCTAssertEqual(modal.urlField.stringValue, "host-app://commands/table")
    }

    func testCommandClickFileChipWhileModalIsOpenOpensURLOnSameClick() throws {
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
        XCTAssertEqual(mounted.view.linkModalView?.textField.stringValue, "one")

        let mouseDown = try mouseDownEvent(
            location: chipLocation,
            windowNumber: mounted.window.windowNumber,
            modifierFlags: .command
        )
        XCTAssertTrue(mounted.view.dismissLinkModalIfMouseDownMovedFocusOutside(mouseDown))

        XCTAssertEqual(openedURLs.map(\.absoluteString), ["file:///tmp/demo.md"])
        XCTAssertNil(mounted.view.linkModalView)
    }

    func testCommandClickSlashCommandChipWhileModalIsOpenRoutesHostActionOnSameClick() throws {
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
        XCTAssertEqual(mounted.view.linkModalView?.textField.stringValue, "one")

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
        try textView(in: view, at: 0)
    }

    private func textView(in view: BlockInputView, at index: Int) throws -> BlockInputTextView {
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: index))
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

    /// Returns a window point inside the link's line fragment but vertically above the link label's
    /// own glyph box. `boundingRect(forGlyphRange:)` always spans the full line-fragment height for a
    /// sub-line range, so the glyph box is derived from the link font's typographic bounds around the
    /// baseline instead. The caller's fixture must place a taller sibling glyph on the same line; the
    /// hard assertions below fail (never skip) if the vertical gap was not constructed.
    private func regularLinkLineEdgeLocation(
        content: String,
        in text: String,
        textView: BlockInputTextView
    ) throws -> NSPoint {
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        let textStorage = try XCTUnwrap(textView.textStorage)
        let contentRange = (text as NSString).range(of: content)
        XCTAssertNotEqual(contentRange.location, NSNotFound)
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: contentRange, actualCharacterRange: nil)
        XCTAssertGreaterThan(glyphRange.length, 0)
        var lineGlyphRange = NSRange()
        let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: &lineGlyphRange)
        let labelGlyphRange = NSIntersectionRange(glyphRange, lineGlyphRange)
        let labelRect = layoutManager.boundingRect(forGlyphRange: labelGlyphRange, in: textContainer)
        let linkFont = try XCTUnwrap(textStorage.attribute(.font, at: contentRange.location, effectiveRange: nil) as? NSFont)
        let fragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        let baselineY = fragmentRect.minY + layoutManager.location(forGlyphAt: glyphRange.location).y
        let labelGlyphRect = NSRect(
            x: labelRect.minX,
            y: baselineY - linkFont.ascender,
            width: labelRect.width,
            height: linkFont.ascender - linkFont.descender
        )
        XCTAssertGreaterThan(
            labelGlyphRect.minY - lineRect.minY,
            2.5,
            "Fixture must open a vertical gap between the line-fragment top and the link glyph box."
        )
        let labelScopedPoint = NSPoint(x: labelRect.midX, y: lineRect.minY + 1.5)
        XCTAssertFalse(labelGlyphRect.insetBy(dx: -1, dy: -1).contains(labelScopedPoint))
        XCTAssertTrue(lineRect.insetBy(dx: -1, dy: -1).contains(labelScopedPoint))
        return textView.convert(
            NSPoint(
                x: textView.textContainerOrigin.x + labelScopedPoint.x,
                y: textView.textContainerOrigin.y + labelScopedPoint.y
            ),
            to: nil
        )
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
