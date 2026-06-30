import AppKit

extension BlockInputTextView {
    /// Paints each file chip's leading accessory into the `.kern`-reserved gap on the chip's leading `[` character.
    ///
    /// Mirrors `drawLinkOpenIcons` but at the chip's leading edge and policy-free: the accessory lives under
    /// `.blockInputChipLeadingAccessory` on the hidden `[`, whose `.kern` widens its advance so the label shifts right.
    /// Core only computes the gap rect and calls the host accessory's `draw` closure — it never knows what is painted.
    func drawChipLeadingAccessories(in dirtyRect: NSRect) {
        guard blockItem?.supportsInlineMarkdownLinkRendering(for: self) == true,
              let textStorage,
              let layoutManager,
              let textContainer else {
            return
        }
        layoutManager.ensureLayout(for: textContainer)
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.enumerateAttribute(.blockInputChipLeadingAccessory, in: fullRange) { value, range, _ in
            guard let attachment = value as? BlockInputChipAccessoryAttachment, range.length == 1,
                  let drawRect = chipLeadingAccessoryDrawRect(forCharacterRange: range, reservedWidth: attachment.accessory.reservedWidth),
                  drawRect.intersects(dirtyRect) else {
                return
            }
            attachment.accessory.draw(drawRect)
        }
        textStorage.enumerateAttribute(.blockInputChipTrailingAccessory, in: fullRange) { value, range, _ in
            guard let attachment = value as? BlockInputChipAccessoryAttachment, range.length == 1,
                  let drawTrailing = attachment.accessory.drawTrailing,
                  let drawRect = chipLeadingAccessoryDrawRect(forCharacterRange: range, reservedWidth: attachment.accessory.trailingReservedWidth),
                  drawRect.intersects(dirtyRect) else {
                return
            }
            drawTrailing(drawRect)
        }
    }

    /// The accessory's painted rectangle (view coordinates) for the leading `[` character `range`.
    ///
    /// The kern-widened `[` glyph box starts at the chip's leading edge; the accessory occupies the reserved width there.
    /// Vertical centering uses the LINE FRAGMENT rect so it aligns with the text line box.
    func chipLeadingAccessoryDrawRect(
        forCharacterRange range: NSRange,
        reservedWidth: CGFloat
    ) -> NSRect? {
        guard range.length == 1,
              reservedWidth > 0,
              let layoutManager,
              let textContainer else {
            return nil
        }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphRange.length > 0 else {
            return nil
        }
        let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let lineFragmentRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        let origin = textContainerOrigin
        return NSRect(
            x: glyphRect.minX + origin.x,
            y: lineFragmentRect.minY + origin.y,
            width: reservedWidth,
            height: lineFragmentRect.height
        )
    }
}
