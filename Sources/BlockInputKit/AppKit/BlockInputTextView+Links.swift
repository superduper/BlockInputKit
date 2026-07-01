import AppKit

/// Visual hit-test result for an inline Markdown link.
///
/// The window-space geometry is captured at mouse-down so mouse-up handling can survive tiny pointer drift, focus
/// changes, and AppKit's occasional remapping of insertion offsets near hidden Markdown source.
struct BlockInputLinkHitResult {
    let range: BlockInputInlineMarkdownRange
    let windowRects: [NSRect]
    let windowLocation: NSPoint
}

extension BlockInputTextView {
    override func draw(_ dirtyRect: NSRect) {
        drawInlineChipBackgrounds(in: dirtyRect)
        super.draw(dirtyRect)
        drawLinkOpenIcons(in: dirtyRect)
        drawChipLeadingAccessories(in: dirtyRect)
    }

    /// Hit-tests any hoverable link or chip (plain links, file/slash chips) at a window location.
    ///
    /// Unlike `linkHitResult`, this also matches chip ranges so the hover Edit popover can anchor to every inline link
    /// kind uniformly. Returns the range plus its visual rects in window coordinates.
    func linkHoverHitResult(atWindowLocation windowLocation: NSPoint) -> BlockInputLinkHitResult? {
        guard supportsInlineMarkdownLinkRendering,
              let layoutManager,
              let textContainer else {
            return nil
        }
        let location = convert(windowLocation, from: nil)
        layoutManager.ensureLayout(for: textContainer)
        for hoverRange in hoverableLinkRangesForCurrentText() {
            let isChip = hoverRange.inlineChipKind(in: string) != nil
            // For chips, use the visual range (incl. leading/trailing accessory gaps) so the whole chip background is
            // hoverable, not just the label glyphs. Plain links keep their label range.
            let characterRange = isChip
                ? chipVisualCharacterRange(for: hoverRange)
                : string.linkCursorClampedRange(hoverRange.contentRange)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
                .clamped(toGlyphCount: layoutManager.numberOfGlyphs)
            guard glyphRange.length > 0 else {
                continue
            }
            let rects = isChip
                ? inlineChipBackgroundRects(glyphRange: glyphRange, layoutManager: layoutManager, textContainer: textContainer)
                : linkCursorRects(glyphRange: glyphRange, layoutManager: layoutManager, textContainer: textContainer)
            if rects.contains(where: { $0.contains(location) }) {
                return BlockInputLinkHitResult(
                    range: hoverRange,
                    windowRects: rects.map { convert($0, to: nil) },
                    windowLocation: windowLocation
                )
            }
        }
        return nil
    }

    private func hoverableLinkRangesForCurrentText() -> [BlockInputInlineMarkdownRange] {
        inlineMarkdownRangesForCurrentText().filter { range in
            (range.style.isLinkLikeStyle || range.inlineChipKind(in: string) != nil)
                && range.contentRange.length > 0
        }
    }

    func inlineChipRange(atWindowLocation windowLocation: NSPoint) -> BlockInputInlineMarkdownRange? {
        guard supportsInlineMarkdownLinkRendering,
              let layoutManager,
              let textContainer else {
            return nil
        }
        layoutManager.ensureLayout(for: textContainer)
        return inlineChipHitResult(
            atWindowLocation: windowLocation,
            layoutManager: layoutManager,
            textContainer: textContainer
        )?.range
    }

    func linkHitResult(for event: NSEvent) -> BlockInputLinkHitResult? {
        for windowLocation in linkEventWindowLocations(event) {
            if let hit = linkHitResult(atWindowLocation: windowLocation) {
                return hit
            }
        }
        return nil
    }

    func linkHitResult(atWindowLocation windowLocation: NSPoint) -> BlockInputLinkHitResult? {
        guard supportsInlineMarkdownLinkRendering,
              let layoutManager,
              let textContainer else {
            return nil
        }
        let location = convert(windowLocation, from: nil)
        layoutManager.ensureLayout(for: textContainer)
        if let chipHit = inlineChipHitResult(
            atWindowLocation: windowLocation,
            layoutManager: layoutManager,
            textContainer: textContainer
        ) {
            return chipHit
        }
        if let regularHit = regularLinkHitResult(
            atWindowLocation: windowLocation,
            layoutManager: layoutManager,
            textContainer: textContainer
        ) {
            return regularHit
        }
        let offset = characterIndexForInsertion(at: location)
        for linkRange in linkRangesForCurrentText() where linkRange.inlineChipKind(in: string) == nil {
            let characterRange = linkHitCharacterRange(for: linkRange)
            let iconRect = linkOpenIconRect(for: linkRange)
            let isInsideIcon = iconRect?.contains(location) == true
            guard characterRange.containsOrTouches(offset) || isInsideIcon else {
                continue
            }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
                .clamped(toGlyphCount: layoutManager.numberOfGlyphs)
            guard glyphRange.length > 0 else {
                continue
            }
            var cursorRects = linkCursorRects(
                glyphRange: glyphRange,
                layoutManager: layoutManager,
                textContainer: textContainer
            )
            if let iconRect {
                cursorRects.append(iconRect)
            }
            return BlockInputLinkHitResult(
                range: linkRange,
                windowRects: cursorRects.map { convert($0, to: nil) },
                windowLocation: windowLocation
            )
        }
        return nil
    }

    func linkEventWindowLocations(_ event: NSEvent) -> [NSPoint] {
        guard let window,
              event.window === window || event.windowNumber == window.windowNumber else {
            return [event.locationInWindow]
        }
        let livePoint = window.mouseLocationOutsideOfEventStream
        guard livePoint != event.locationInWindow else {
            return [event.locationInWindow]
        }
        return [event.locationInWindow, livePoint]
    }

    private func regularLinkHitResult(
        atWindowLocation windowLocation: NSPoint,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> BlockInputLinkHitResult? {
        let location = convert(windowLocation, from: nil)
        for linkRange in linkRangesForCurrentText() where linkRange.inlineChipKind(in: string) == nil {
            let characterRange = linkHitCharacterRange(for: linkRange)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
                .clamped(toGlyphCount: layoutManager.numberOfGlyphs)
            guard glyphRange.length > 0 else {
                continue
            }
            var cursorRects = linkCursorRects(
                glyphRange: glyphRange,
                layoutManager: layoutManager,
                textContainer: textContainer
            )
            if let iconRect = linkOpenIconRect(for: linkRange) {
                cursorRects.append(iconRect)
            }
            if cursorRects.contains(where: { $0.contains(location) }) {
                return BlockInputLinkHitResult(
                    range: linkRange,
                    windowRects: cursorRects.map { convert($0, to: nil) },
                    windowLocation: windowLocation
                )
            }
        }
        return nil
    }

    private func inlineChipHitResult(
        atWindowLocation windowLocation: NSPoint,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> BlockInputLinkHitResult? {
        let location = convert(windowLocation, from: nil)
        for linkRange in linkRangesForCurrentText() where linkRange.inlineChipKind(in: string) != nil {
            let characterRange = string.linkCursorClampedRange(linkRange.contentRange)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
                .clamped(toGlyphCount: layoutManager.numberOfGlyphs)
            guard glyphRange.length > 0 else {
                continue
            }
            let backgroundRects = inlineChipBackgroundRects(
                glyphRange: glyphRange,
                layoutManager: layoutManager,
                textContainer: textContainer
            )
            if backgroundRects.contains(where: { $0.contains(location) }) {
                return BlockInputLinkHitResult(
                    range: linkRange,
                    windowRects: backgroundRects.map { convert($0, to: nil) },
                    windowLocation: windowLocation
                )
            }
        }
        return nil
    }

    /// Adds pointing-hand cursor rects over visible links; chips use their padded visual rects.
    ///
    /// `resetCursorRects` (the AppKit cursor-rect rebuild entry point, overridden on `BlockInputTextView`) calls this, so
    /// the hand cursor — including the open-icon rect — is rebuilt whenever AppKit invalidates the view's cursor rects.
    func addLinkCursorRects() {
        for cursorRect in linkCursorRectsForCurrentText() {
            addCursorRect(cursorRect, cursor: .pointingHand)
        }
    }

    /// The pointing-hand cursor rects (view coordinates) for every visible link and chip, including each link's painted
    /// open-icon rect via the shared `linkOpenIconRect(for:)`. Used by `addLinkCursorRects` and exposed for tests so the
    /// icon's hand-cursor coverage can be asserted directly.
    func linkCursorRectsForCurrentText() -> [NSRect] {
        guard supportsInlineMarkdownLinkRendering,
              let layoutManager,
              let textContainer else {
            return []
        }
        let textLength = (string as NSString).length
        guard textLength > 0 else {
            return []
        }
        layoutManager.ensureLayout(for: textContainer)
        var rects: [NSRect] = []
        for linkRange in linkRangesForCurrentText() where linkRange.contentRange.length > 0 {
            let characterRange = linkHitCharacterRange(for: linkRange)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
                .clamped(toGlyphCount: layoutManager.numberOfGlyphs)
            guard glyphRange.length > 0 else {
                continue
            }
            if linkRange.inlineChipKind(in: string) != nil {
                rects.append(contentsOf: inlineChipBackgroundRects(
                    glyphRange: glyphRange,
                    layoutManager: layoutManager,
                    textContainer: textContainer
                ))
            } else {
                rects.append(contentsOf: linkCursorRects(
                    glyphRange: glyphRange,
                    layoutManager: layoutManager,
                    textContainer: textContainer
                ))
                if let iconRect = linkOpenIconRect(for: linkRange) {
                    rects.append(iconRect)
                }
            }
        }
        return rects
    }

    func linkCursorRectsForTesting() -> [NSRect] {
        linkCursorRectsForCurrentText()
    }

    func drawInlineChipBackgrounds(in dirtyRect: NSRect) {
        guard supportsInlineMarkdownLinkRendering,
              let layoutManager,
              let textContainer else {
            return
        }
        layoutManager.ensureLayout(for: textContainer)
        for chipRange in inlineChipVisualRangesForCurrentText() {
            guard let chipStyle = inlineChipStyle(for: chipRange) else {
                continue
            }
            let characterRange = chipVisualCharacterRange(for: chipRange)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
                .clamped(toGlyphCount: layoutManager.numberOfGlyphs)
            guard glyphRange.length > 0 else {
                continue
            }
            for drawRect in inlineChipBackgroundRects(
                glyphRange: glyphRange,
                layoutManager: layoutManager,
                textContainer: textContainer
            ) where drawRect.intersects(dirtyRect) {
                drawInlineChipBackground(in: drawRect, style: chipStyle)
            }
        }
    }

    func inlineChipBackgroundRects() -> [NSRect] {
        guard supportsInlineMarkdownLinkRendering,
              let layoutManager,
              let textContainer else {
            return []
        }
        layoutManager.ensureLayout(for: textContainer)
        return inlineChipVisualRangesForCurrentText().flatMap { chipRange -> [NSRect] in
            let characterRange = chipVisualCharacterRange(for: chipRange)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
                .clamped(toGlyphCount: layoutManager.numberOfGlyphs)
            guard glyphRange.length > 0 else {
                return []
            }
            return inlineChipBackgroundRects(
                glyphRange: glyphRange,
                layoutManager: layoutManager,
                textContainer: textContainer
            )
        }
    }

    /// The chip's visible character range, extended to include the leading `[` and/or trailing `]` when they carry an
    /// accessory.
    ///
    /// Each accessory paints into the kern-reserved gap on its delimiter, so the chip background (and any chrome derived
    /// from this range) must span them; otherwise an accessory would sit just outside the chip fill.
    func chipVisualCharacterRange(for chipRange: BlockInputInlineMarkdownRange) -> NSRange {
        var range = string.linkCursorClampedRange(chipRange.contentRange)
        guard range.length > 0 else {
            return range
        }
        let leadingIndex = range.location - 1
        if leadingIndex >= 0, hasChipAccessory(.blockInputChipLeadingAccessory, at: leadingIndex) {
            range = NSRange(location: leadingIndex, length: range.length + 1)
        }
        let trailingIndex = NSMaxRange(range)
        if trailingIndex < (string as NSString).length, hasChipAccessory(.blockInputChipTrailingAccessory, at: trailingIndex) {
            range = NSRange(location: range.location, length: range.length + 1)
        }
        return range
    }

    private func hasChipAccessory(_ attribute: NSAttributedString.Key, at index: Int) -> Bool {
        textStorage?.attribute(attribute, at: index, effectiveRange: nil) is BlockInputChipAccessoryAttachment
    }

    func inlineChipBackgroundRectsForTesting() -> [NSRect] {
        inlineChipBackgroundRects()
    }

    private func linkCursorRects(
        glyphRange: NSRange,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> [NSRect] {
        var cursorRects: [NSRect] = []
        var glyphIndex = glyphRange.location
        while glyphIndex < NSMaxRange(glyphRange) {
            var lineGlyphRange = NSRange()
            let lineFragmentRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: &lineGlyphRange)
            let lineLinkGlyphRange = NSIntersectionRange(glyphRange, lineGlyphRange)
            if lineLinkGlyphRange.length > 0 {
                let labelRect = layoutManager.boundingRect(forGlyphRange: lineLinkGlyphRange, in: textContainer)
                let cursorRect = NSRect(
                    x: labelRect.minX + textContainerOrigin.x,
                    y: lineFragmentRect.minY + textContainerOrigin.y,
                    width: labelRect.width,
                    height: lineFragmentRect.height
                )
                .insetBy(dx: -1, dy: -1)
                cursorRects.append(cursorRect)
            }
            glyphIndex = max(glyphIndex + 1, NSMaxRange(lineGlyphRange))
        }
        return cursorRects
    }

    func linkRangesForCurrentText() -> [BlockInputInlineMarkdownRange] {
        inlineMarkdownRangesForCurrentText().filter { $0.style.isLinkLikeStyle }
    }

    private func inlineChipVisualRangesForCurrentText() -> [BlockInputInlineMarkdownRange] {
        inlineMarkdownRangesForCurrentText().filter { $0.inlineChipKind(in: string) != nil }
    }

    private func inlineChipStyle(for range: BlockInputInlineMarkdownRange) -> BlockInputInlineChipStyle? {
        guard let kind = range.inlineChipKind(in: string) else {
            return nil
        }
        return blockItem?.style.inlineChipStyle(for: kind)
    }

    private func inlineMarkdownRangesForCurrentText() -> [BlockInputInlineMarkdownRange] {
        BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: string,
            excluding: BlockInputCodeParsing.inlineCodeRanges(in: string).map(\.fullRange),
            fileBaseURL: blockItem?.fileBaseURL,
            allowsAnchorLinks: blockItem?.allowsAnchorLinks ?? false,
            rawSlashCommandChips: rendersRawSlashCommandChips,
            slashCommandAvailability: blockItem?.slashCommandAvailability ?? .documentStart,
            isDocumentStartBlock: blockItem?.isDocumentStartBlock == true,
            inlineMarkupProviders: blockItem?.inlineMarkupProviders ?? []
        )
    }

    var supportsInlineMarkdownLinkRendering: Bool {
        blockItem?.supportsInlineMarkdownLinkRendering(for: self) == true
    }

    private var rendersRawSlashCommandChips: Bool {
        guard blockItem?.isTableCellTextView(self) != true else {
            return false
        }
        return blockItem?.rawSlashCommandChips == true
    }

    private func inlineChipBackgroundRects(
        glyphRange: NSRange,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> [NSRect] {
        let drawingOffset = textContainerOrigin
        let baseLineHeight = inlineChipBaseLineHeight(layoutManager: layoutManager)
        var rects: [NSRect] = []
        var glyphIndex = glyphRange.location
        while glyphIndex < NSMaxRange(glyphRange) {
            var lineGlyphRange = NSRange()
            let lineFragmentUsedRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: &lineGlyphRange)
            let lineChipGlyphRange = NSIntersectionRange(glyphRange, lineGlyphRange)
            if lineChipGlyphRange.length > 0 {
                let labelRect = layoutManager.boundingRect(forGlyphRange: lineChipGlyphRange, in: textContainer)
                let verticalPadding: CGFloat = 2
                let visualHeight = max(baseLineHeight, labelRect.height) + (verticalPadding * 2)
                let visualY = lineFragmentUsedRect.midY - (visualHeight / 2)

                rects.append(NSRect(
                    x: labelRect.minX + drawingOffset.x - 2,
                    y: visualY + drawingOffset.y,
                    width: labelRect.width + 4,
                    height: visualHeight
                ))
            }
            glyphIndex = max(glyphIndex + 1, NSMaxRange(lineGlyphRange))
        }
        return rects
    }

    private func inlineChipBaseLineHeight(layoutManager: NSLayoutManager) -> CGFloat {
        let baseFont = blockItem?.renderedBlock.map {
            BlockInputBlockItem.font(for: $0.kind, style: blockItem?.style ?? .default)
        } ?? font
        guard let baseFont else {
            return 0
        }
        return ceil(max(layoutManager.defaultLineHeight(for: baseFont), baseFont.boundingRectForFont.height))
    }

    private func drawInlineChipBackground(in rect: NSRect, style: BlockInputInlineChipStyle) {
        if let fillColor = style.fillColor {
            fillColor.setFill()
            NSBezierPath(roundedRect: rect, xRadius: style.cornerRadius, yRadius: style.cornerRadius).fill()
        }
        if let strokeColor = style.strokeColor {
            strokeColor.setStroke()
            let stroke = NSBezierPath(
                roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                xRadius: style.cornerRadius,
                yRadius: style.cornerRadius
            )
            stroke.lineWidth = 1
            stroke.stroke()
        }
    }
}

private extension String {
    func linkCursorClampedRange(_ range: NSRange) -> NSRange {
        let text = self as NSString
        let location = min(max(range.location, 0), text.length)
        let length = min(max(range.length, 0), max(text.length - location, 0))
        return NSRange(location: location, length: length)
    }
}

private extension NSRange {
    func clamped(toGlyphCount glyphCount: Int) -> NSRange {
        let location = min(max(location, 0), glyphCount)
        let length = min(max(length, 0), max(glyphCount - location, 0))
        return NSRange(location: location, length: length)
    }
}
