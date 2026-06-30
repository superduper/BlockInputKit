import AppKit

extension BlockInputTextView {
    /// Character range used to hit-test and draw the pointing-hand cursor for a link.
    ///
    /// This is the link's visible `contentRange`, extended by the single trailing hidden chrome character when that
    /// character carries the inline "open" icon, so clicking (or hovering) the icon glyph activates the link.
    func linkHitCharacterRange(for linkRange: BlockInputInlineMarkdownRange) -> NSRange {
        let text = string as NSString
        let location = min(max(linkRange.contentRange.location, 0), text.length)
        let length = min(max(linkRange.contentRange.length, 0), max(text.length - location, 0))
        let contentRange = NSRange(location: location, length: length)
        guard contentRange.length > 0 else {
            return contentRange
        }
        let iconIndex = NSMaxRange(contentRange)
        guard linkRange.inlineChipKind(in: string) == nil,
              iconIndex < text.length,
              textStorage?.attribute(.blockInputLinkOpenIcon, at: iconIndex, effectiveRange: nil) is BlockInputLinkOpenAttachment else {
            return contentRange
        }
        return NSRange(location: contentRange.location, length: contentRange.length + 1)
    }

    /// Paints the inline link "open" icon into the `.kern`-reserved gap on each link's trailing hidden chrome character.
    ///
    /// The icon descriptor lives under `.blockInputLinkOpenIcon` on a single already-hidden character; the matching
    /// `.kern` widens that glyph's advance so the icon draws in the reserved space rather than overlapping later text.
    /// Drawing here (rather than inserting a U+FFFC attachment character) keeps the storage string equal to the source.
    func drawLinkOpenIcons(in dirtyRect: NSRect) {
        guard blockItem?.supportsInlineMarkdownLinkRendering(for: self) == true,
              let textStorage,
              let layoutManager,
              let textContainer else {
            return
        }
        layoutManager.ensureLayout(for: textContainer)
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.enumerateAttribute(.blockInputLinkOpenIcon, in: fullRange) { value, range, _ in
            guard let attachment = value as? BlockInputLinkOpenAttachment, range.length == 1,
                  let drawRect = linkOpenIconDrawRect(forIconCharacterRange: range, attachment: attachment),
                  drawRect.intersects(dirtyRect) else {
                return
            }
            drawLinkOpenIconImage(attachment.image, in: drawRect)
        }
    }

    /// The icon's painted rectangle (view coordinates) for the icon-bearing character `range`.
    ///
    /// This is the single source of truth shared by drawing (`drawLinkOpenIcons`) and hit-testing
    /// (`linkOpenIconRect(for:)` / `linkOpenIconWindowRect(for:)`) so the painted icon and its clickable/cursor area never drift.
    ///
    /// Geometry: the icon is anchored to the trailing edge of the VISIBLE label, not to a kern-widened glyph box. The
    /// icon-bearing character is the hidden chrome `]` that immediately follows the label, so its glyph's `minX` equals
    /// the label's trailing edge; the icon is placed just to the right of that edge with a small lead gap, and the
    /// matching `.kern` (icon width + gap) reserves the room so following text never overlaps. Vertical centering uses the
    /// LINE FRAGMENT rect — not a single glyph's `midY` — so the icon aligns with the text line box across the label.
    func linkOpenIconDrawRect(
        forIconCharacterRange range: NSRange,
        attachment: BlockInputLinkOpenAttachment
    ) -> NSRect? {
        guard range.length == 1,
              let layoutManager,
              let textContainer else {
            return nil
        }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphRange.length > 0 else {
            return nil
        }
        // The icon glyph's leading edge sits at the visible label's trailing edge; anchor the icon there.
        let iconGlyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let lineFragmentRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        let origin = textContainerOrigin
        let imageSize = attachment.image.size
        // Lead gap = reserved advance minus icon width, so draw + reserved kern gap stay consistent (icon hugs neither edge).
        let leadGap = max(attachment.advance - imageSize.width, 0)
        let labelTrailingX = iconGlyphRect.minX + origin.x
        return NSRect(
            x: labelTrailingX + leadGap,
            y: lineFragmentRect.midY + origin.y - imageSize.height / 2,
            width: imageSize.width,
            height: imageSize.height
        )
    }

    /// The painted open-icon rect in view coordinates for a link, if that link carries the inline open icon.
    ///
    /// Hit-test and cursor rects union this in so a click (or hover) on the painted icon resolves to the link even when
    /// the glyph bounding rect of the hidden chrome character does not cover the full kern-reserved icon gap.
    func linkOpenIconRect(for linkRange: BlockInputInlineMarkdownRange) -> NSRect? {
        let text = string as NSString
        let location = min(max(linkRange.contentRange.location, 0), text.length)
        let length = min(max(linkRange.contentRange.length, 0), max(text.length - location, 0))
        guard length > 0, linkRange.inlineChipKind(in: string) == nil else {
            return nil
        }
        let iconIndex = location + length
        guard iconIndex < text.length,
              let attachment = textStorage?.attribute(
                .blockInputLinkOpenIcon,
                at: iconIndex,
                effectiveRange: nil
              ) as? BlockInputLinkOpenAttachment else {
            return nil
        }
        return linkOpenIconDrawRect(
            forIconCharacterRange: NSRange(location: iconIndex, length: 1),
            attachment: attachment
        )
    }

    /// The painted open-icon rect in window coordinates for a link, if that link carries the inline open icon.
    func linkOpenIconWindowRect(for linkRange: BlockInputInlineMarkdownRange) -> NSRect? {
        linkOpenIconRect(for: linkRange).map { convert($0, to: nil) }
    }

    /// Whether a window-coordinate point falls inside any visible link's painted open icon.
    ///
    /// Used by the cursor path so the pointing hand shows over the icon even in editable views, where `NSTextView`'s
    /// dynamic I-beam would otherwise override the static cursor rects.
    func isPointInsideAnyLinkOpenIcon(_ windowPoint: NSPoint) -> Bool {
        guard supportsInlineMarkdownLinkRendering else {
            return false
        }
        let localPoint = convert(windowPoint, from: nil)
        return linkRangesForCurrentText().contains { linkRange in
            linkOpenIconRect(for: linkRange).map { $0.insetBy(dx: -1, dy: -1).contains(localPoint) } ?? false
        }
    }

    /// Draws the icon upright even though `NSTextView` uses a flipped coordinate space.
    ///
    /// `NSImage.draw(in:)` does not compensate for the view's flipped context, so the SF Symbol would render
    /// vertically mirrored (an `up.right` arrow appears to point down). Flipping the CTM around the draw rect
    /// before drawing keeps the icon upright.
    private func drawLinkOpenIconImage(_ image: NSImage, in drawRect: NSRect) {
        guard isFlipped, let context = NSGraphicsContext.current else {
            image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
            return
        }
        context.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: 0, yBy: drawRect.maxY + drawRect.minY)
        transform.scaleX(by: 1, yBy: -1)
        transform.concat()
        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
        context.restoreGraphicsState()
    }
}
