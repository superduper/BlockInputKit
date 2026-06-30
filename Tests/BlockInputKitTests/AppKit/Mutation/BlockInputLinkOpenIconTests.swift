import AppKit
import XCTest
@testable import BlockInputKit

/// The inline link "open" icon is a PRESENTATION-ONLY `NSTextAttachment` set on a single already-hidden trailing chrome
/// character of a link (the `]` closing `[label]`, or the first `]` of a wikilink's `]]`). It flows with the text and
/// never mutates the source: the rendered storage string still equals the source markdown (no U+FFFC inserted), the
/// paragraph still lays out on one line, and clicking the icon glyph activates the link through the normal click path.
@MainActor
final class BlockInputLinkOpenIconTests: XCTestCase {
    // MARK: - (a) attachment on a single trailing hidden chrome character; source unchanged

    func testRegularLinkGetsOpenIconOnTrailingBracketWithoutChangingSource() throws {
        let text = "Open [docs](https://example.com) end"
        let storage = styledStorage(for: text, showsInlineLinkOpenIcon: true)

        // Source is byte-for-byte unchanged: same length, same content, no U+FFFC object-replacement character.
        XCTAssertEqual(storage.string, text)
        XCTAssertEqual(storage.length, (text as NSString).length)
        XCTAssertFalse(storage.string.contains("\u{FFFC}"))

        // Exactly one open-icon attachment, on the single `]` that closes `[docs]`.
        let attachmentRanges = openIconAttachmentRanges(in: storage)
        XCTAssertEqual(attachmentRanges.count, 1)
        let iconRange = try XCTUnwrap(attachmentRanges.first)
        XCTAssertEqual(iconRange.length, 1)
        XCTAssertEqual((text as NSString).substring(with: iconRange), "]")
        // That same character is hidden chrome (so it is real markdown, not a new glyph).
        XCTAssertEqual(storage.attribute(.blockInputHiddenDelimiter, at: iconRange.location, effectiveRange: nil) as? Bool, true)
    }

    func testWikilinkGetsOpenIconOnTrailingBracketWithoutChangingSource() throws {
        let text = "Open [[baz/Foo|Foo]] here"
        let storage = styledStorage(for: text, showsInlineLinkOpenIcon: true, inlineMarkupProviders: [WikilinkStandInMarkupProvider()])

        XCTAssertEqual(storage.string, text)
        XCTAssertEqual(storage.length, (text as NSString).length)
        XCTAssertFalse(storage.string.contains("\u{FFFC}"))

        let attachmentRanges = openIconAttachmentRanges(in: storage)
        XCTAssertEqual(attachmentRanges.count, 1)
        let iconRange = try XCTUnwrap(attachmentRanges.first)
        XCTAssertEqual(iconRange.length, 1)
        // The icon sits on the first `]` of the trailing `]]`, right after the visible alias.
        XCTAssertEqual((text as NSString).substring(with: iconRange), "]")
        let aliasRange = (text as NSString).range(of: "Foo]")
        XCTAssertEqual(iconRange.location, NSMaxRange(aliasRange) - 1)
        XCTAssertEqual(storage.attribute(.blockInputHiddenDelimiter, at: iconRange.location, effectiveRange: nil) as? Bool, true)
    }

    // MARK: - (b) the decorated line still lays out on one line

    func testRegularLinkWithOpenIconLaysOutOnSingleLine() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open [docs](https://example.com) end")
        ])
        XCTAssertEqual(try usedLineCount(in: mounted, blockIndex: 0), 1)
    }

    func testWikilinkWithOpenIconLaysOutOnSingleLine() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "block", text: "Open [[baz/Foo|Foo]] here")]),
            inlineMarkupProviders: [WikilinkStandInMarkupProvider()]
        ))
        XCTAssertEqual(try usedLineCount(in: mounted, blockIndex: 0), 1)
    }

    // MARK: - (c) clicking the icon glyph activates the link

    func testClickingOpenIconOnRegularLinkOpensURL() throws {
        let text = "Open [docs](https://example.com) end"
        let mounted = makeMountedBlockInputView(blocks: [BlockInputBlock(id: "block", text: text)])
        var openedURLs: [URL] = []
        mounted.view.linkURLOpener = {
            openedURLs.append($0)
            return true
        }
        let textView = try textView(in: mounted.view)
        // The icon sits on the `]` that closes `[docs]`, right after the visible label.
        let iconCharacterIndex = (text as NSString).range(of: "](").location
        let iconLocation = try iconWindowLocation(in: textView, iconCharacterIndex: iconCharacterIndex)

        // The icon glyph is hit-tested as part of the link, so a plain click there routes through the link-click path.
        let hit = try XCTUnwrap(textView.linkHitResult(atWindowLocation: iconLocation))
        XCTAssertEqual(hit.range.style, .link)
        XCTAssertTrue(mounted.view.handleLinkClick(
            blockID: "block",
            selectedRange: hit.range.contentRange,
            clickedLinkRange: hit.range,
            event: try mouseDownEvent(location: iconLocation, windowNumber: mounted.window.windowNumber)
        ))

        XCTAssertEqual(openedURLs.map(\.absoluteString), ["https://example.com"])
    }

    func testClickingOpenIconOnWikilinkRoutesToWikilinkHandler() throws {
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
        // The icon sits on the first `]` of the trailing `]]`, i.e. right after the visible alias `Foo`.
        let iconCharacterIndex = (text as NSString).range(of: "]]").location
        let iconLocation = try iconWindowLocation(in: textView, iconCharacterIndex: iconCharacterIndex)

        let hit = try XCTUnwrap(textView.linkHitResult(atWindowLocation: iconLocation))
        XCTAssertEqual(hit.range.style.customMarkupIdentity?.identifier, "wikilink")
        XCTAssertTrue(mounted.view.handleLinkClick(
            blockID: "block",
            selectedRange: hit.range.contentRange,
            clickedLinkRange: hit.range,
            event: try mouseDownEvent(location: iconLocation, windowNumber: mounted.window.windowNumber)
        ))

        let context = try XCTUnwrap(captured)
        XCTAssertEqual(context.kind, .customMarkup("wikilink"))
        XCTAssertEqual(context.alias, "Foo")
        XCTAssertEqual(context.destination.scheme, "wikilink")
        XCTAssertTrue(context.destination.absoluteString.contains("baz/Foo"))
    }

    // MARK: - (c2) clicking the PAINTED icon rect (kern gap) resolves to the link and activates it

    func testClickingPaintedIconRectOnRegularLinkOpensURLWithoutPlacingCaret() throws {
        let text = "Open [docs](https://example.com) end"
        let mounted = makeMountedBlockInputView(blocks: [BlockInputBlock(id: "block", text: text)])
        var openedURLs: [URL] = []
        mounted.view.linkURLOpener = {
            openedURLs.append($0)
            return true
        }
        let textView = try textView(in: mounted.view)
        // Compute the painted icon rect the SAME way `drawLinkOpenIcons` does, then click its center.
        let iconCharacterIndex = (text as NSString).range(of: "](").location
        let paintedRect = try paintedIconWindowRect(in: textView, iconCharacterIndex: iconCharacterIndex)
        let center = NSPoint(x: paintedRect.midX, y: paintedRect.midY)

        let hit = try XCTUnwrap(textView.linkHitResult(atWindowLocation: center))
        XCTAssertEqual(hit.range.style, .link)
        XCTAssertTrue(mounted.view.handleLinkClick(
            blockID: "block",
            selectedRange: hit.range.contentRange,
            clickedLinkRange: hit.range,
            event: try mouseDownEvent(location: center, windowNumber: mounted.window.windowNumber)
        ))
        XCTAssertEqual(openedURLs.map(\.absoluteString), ["https://example.com"])

        // A mouse-down at the painted icon must NOT place the caret: the link hit captures the click, so `mouseDown`
        // leaves the selection collapsed (caret unmoved) rather than placing it at the icon glyph.
        textView.mouseDown(with: try mouseDownEvent(location: center, windowNumber: mounted.window.windowNumber))
        XCTAssertEqual(textView.selectedRange().length, 0)
        XCTAssertNotNil(textView.linkHitResult(atWindowLocation: center))
    }

    func testClickingPaintedIconRectOnWikilinkRoutesToWikilinkHandler() throws {
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
        let iconCharacterIndex = (text as NSString).range(of: "]]").location
        let paintedRect = try paintedIconWindowRect(in: textView, iconCharacterIndex: iconCharacterIndex)
        let center = NSPoint(x: paintedRect.midX, y: paintedRect.midY)

        let hit = try XCTUnwrap(textView.linkHitResult(atWindowLocation: center))
        XCTAssertEqual(hit.range.style.customMarkupIdentity?.identifier, "wikilink")
        XCTAssertTrue(mounted.view.handleLinkClick(
            blockID: "block",
            selectedRange: hit.range.contentRange,
            clickedLinkRange: hit.range,
            event: try mouseDownEvent(location: center, windowNumber: mounted.window.windowNumber)
        ))

        let context = try XCTUnwrap(captured)
        XCTAssertEqual(context.kind, .customMarkup("wikilink"))
        XCTAssertEqual(context.alias, "Foo")
        XCTAssertTrue(context.destination.absoluteString.contains("baz/Foo"))
    }

    func testPaintedIconRectIsNonEmptyAndSitsJustRightOfTheVisibleLabel() throws {
        let text = "Open [docs](https://example.com) end"
        let mounted = makeMountedBlockInputView(blocks: [BlockInputBlock(id: "block", text: text)])
        let textView = try textView(in: mounted.view)
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)

        // Find the link range via the shared hit-test (label center), then ask for the shared icon rect (view coords).
        let labelRange = (text as NSString).range(of: "docs")
        let labelLocation = try windowLocation(forUTF16Offset: labelRange.location, in: textView)
        let linkRange = try XCTUnwrap(textView.linkHitResult(atWindowLocation: labelLocation)).range
        let iconRect = try XCTUnwrap(textView.linkOpenIconRect(for: linkRange))
        XCTAssertFalse(iconRect.isEmpty)

        // The visible label's content rect: glyph bounding rect of "docs" in view coords.
        let labelGlyphRange = layoutManager.glyphRange(forCharacterRange: labelRange, actualCharacterRange: nil)
        let labelBounds = layoutManager.boundingRect(forGlyphRange: labelGlyphRange, in: textContainer)
        let origin = textView.textContainerOrigin
        let labelMaxX = labelBounds.maxX + origin.x
        // The icon sits to the right of the visible label.
        XCTAssertGreaterThan(iconRect.minX, labelMaxX)
        // The icon stays on the same line (vertically overlaps the label fragment).
        let labelMidY = labelBounds.midY + origin.y
        XCTAssertLessThanOrEqual(iconRect.minY, labelMidY)
        XCTAssertGreaterThanOrEqual(iconRect.maxY, labelMidY)
    }

    /// Asserts draw and hit-test share ONE icon-rect source of truth: the painted rect computed independently here
    /// (the same math `drawLinkOpenIcons` uses) equals the shared `linkOpenIconRect(for:)` used by hit-test and cursor.
    func testDrawAndHitTestShareSameIconRect() throws {
        let text = "Open [docs](https://example.com) end"
        let mounted = makeMountedBlockInputView(blocks: [BlockInputBlock(id: "block", text: text)])
        let textView = try textView(in: mounted.view)
        let iconCharacterIndex = (text as NSString).range(of: "](").location
        let paintedWindowRect = try paintedIconWindowRect(in: textView, iconCharacterIndex: iconCharacterIndex)

        let labelLocation = try windowLocation(forUTF16Offset: (text as NSString).range(of: "docs").location, in: textView)
        let linkRange = try XCTUnwrap(textView.linkHitResult(atWindowLocation: labelLocation)).range
        let sharedWindowRect = try XCTUnwrap(textView.linkOpenIconWindowRect(for: linkRange))
        XCTAssertEqual(sharedWindowRect.origin.x, paintedWindowRect.origin.x, accuracy: 0.5)
        XCTAssertEqual(sharedWindowRect.origin.y, paintedWindowRect.origin.y, accuracy: 0.5)
        XCTAssertEqual(sharedWindowRect.width, paintedWindowRect.width, accuracy: 0.5)
        XCTAssertEqual(sharedWindowRect.height, paintedWindowRect.height, accuracy: 0.5)
    }

    // MARK: - (d) flag off → no attachment

    func testFlagOffRendersNoOpenIconAttachment() throws {
        let text = "Open [docs](https://example.com) end"
        let storage = styledStorage(for: text, showsInlineLinkOpenIcon: false)

        XCTAssertEqual(storage.string, text)
        XCTAssertTrue(openIconAttachmentRanges(in: storage).isEmpty)
    }

    func testFlagOffOnMountedViewRendersNoOpenIconAttachment() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: "Open [docs](https://example.com) end")
            ]),
            showsInlineLinkOpenButton: false
        ))
        let textView = try textView(in: mounted.view)
        let storage = try XCTUnwrap(textView.textStorage)
        XCTAssertTrue(openIconAttachmentRanges(in: storage).isEmpty)
    }

    // MARK: - (e) visible label still editable; chrome still hidden

    func testVisibleLabelStaysEditableAndChromeStaysHidden() throws {
        let text = "Open [docs](https://example.com) end"
        let storage = styledStorage(for: text, showsInlineLinkOpenIcon: true)

        // The visible label is real, styled, editable source text (link color + underline), not collapsed.
        let labelRange = (text as NSString).range(of: "docs")
        let labelAttributes = storage.attributes(at: labelRange.location, effectiveRange: nil)
        XCTAssertNil(labelAttributes[.blockInputHiddenDelimiter])
        XCTAssertEqual(labelAttributes[.underlineStyle] as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertNotNil(labelAttributes[.link])

        // The destination chrome `(https://example.com)` stays hidden.
        let hidden = hiddenRanges(in: storage).map { (text as NSString).substring(with: $0) }.joined()
        XCTAssertTrue(hidden.contains("https://example.com"))
    }

    // MARK: - (f) decoration extends across the icon gap

    func testRegularLinkDecorationExtendsOntoIconCharacter() throws {
        let text = "Open [docs](https://example.com) end"
        let storage = styledStorage(for: text, showsInlineLinkOpenIcon: true)
        // The icon-bearing `]` carries the link underline (with an explicit color, since its glyph is clear) so the
        // underline visually reaches across the kern gap the icon paints into.
        let iconRange = (text as NSString).range(of: "](")
        let iconAttributes = storage.attributes(at: iconRange.location, effectiveRange: nil)
        XCTAssertEqual(iconAttributes[.underlineStyle] as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertEqual(iconAttributes[.underlineColor] as? NSColor, NSColor.linkColor)
    }

    func testWikilinkDecorationExtendsOntoIconCharacter() throws {
        let text = "Open [[baz/Foo|Foo]] here"
        let storage = styledStorage(for: text, showsInlineLinkOpenIcon: true, inlineMarkupProviders: [WikilinkStandInMarkupProvider()])
        // The icon-bearing first `]` of `]]` carries the wikilink underline AND faint background so the styling reaches
        // across the icon gap.
        let iconRange = (text as NSString).range(of: "]]")
        let iconAttributes = storage.attributes(at: iconRange.location, effectiveRange: nil)
        XCTAssertEqual(iconAttributes[.underlineStyle] as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertNotNil(iconAttributes[.underlineColor])
        XCTAssertNotNil(iconAttributes[.backgroundColor])
    }

    // MARK: - No icon for plain prose

    func testPlainTextWithoutLinksHasNoOpenIcon() throws {
        let text = "Just prose without any links"
        let storage = styledStorage(for: text, showsInlineLinkOpenIcon: true)
        XCTAssertTrue(openIconAttachmentRanges(in: storage).isEmpty)
    }

    // MARK: - Helpers

    private func styledStorage(
        for text: String,
        showsInlineLinkOpenIcon: Bool,
        inlineMarkupProviders: [any BlockInputInlineMarkupProvider] = []
    ) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        BlockInputBlockItem.applyInlineMarkdownAttributes(
            for: BlockInputBlock(id: "b", kind: .paragraph, text: text),
            textStorage: storage,
            style: .default,
            showsInlineLinkOpenIcon: showsInlineLinkOpenIcon,
            inlineMarkupProviders: inlineMarkupProviders
        )
        return storage
    }

    private func openIconAttachmentRanges(in storage: NSTextStorage) -> [NSRange] {
        var ranges: [NSRange] = []
        storage.enumerateAttribute(.blockInputLinkOpenIcon, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if value is BlockInputLinkOpenAttachment {
                ranges.append(range)
            }
        }
        return ranges
    }

    private func hiddenRanges(in storage: NSTextStorage) -> [NSRange] {
        var ranges: [NSRange] = []
        storage.enumerateAttribute(.blockInputHiddenDelimiter, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if value as? Bool == true {
                ranges.append(range)
            }
        }
        return ranges
    }

    /// Window-space center of the open-icon glyph drawn on the trailing chrome character at `iconCharacterIndex`.
    private func iconWindowLocation(in textView: BlockInputTextView, iconCharacterIndex: Int) throws -> NSPoint {
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: iconCharacterIndex, length: 1),
            actualCharacterRange: nil
        )
        let boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let origin = textView.textContainerOrigin
        let center = NSPoint(x: boundingRect.midX + origin.x, y: boundingRect.midY + origin.y)
        return textView.convert(center, to: nil)
    }

    /// Window-space painted icon rect, computed the SAME way `drawLinkOpenIcons` paints it (anchored to the visible
    /// label's trailing edge with a lead gap, centered on the LINE FRAGMENT), independent of the production helper.
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

    private func usedLineCount(in mounted: (view: BlockInputView, window: NSWindow), blockIndex: Int) throws -> Int {
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: blockIndex))
        let textView = try XCTUnwrap(item.testingTextView)
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        guard glyphRange.length > 0 else {
            return 0
        }
        var lineCount = 0
        var glyphIndex = glyphRange.location
        while glyphIndex < NSMaxRange(glyphRange) {
            var lineRange = NSRange()
            _ = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
            lineCount += 1
            glyphIndex = max(glyphIndex + 1, NSMaxRange(lineRange))
        }
        return lineCount
    }

    private func textView(in view: BlockInputView) throws -> BlockInputTextView {
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        return try XCTUnwrap(item.testingTextView)
    }
}
