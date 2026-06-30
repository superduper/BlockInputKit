import AppKit

extension BlockInputBlockItem {
    /// Returns the on-screen rect of a UTF-16 match range, converted into `coordinateView`'s space.
    ///
    /// Text blocks resolve the rect from the layout manager (the `boundingRect(forGlyphRange:in:)`
    /// pattern). Table blocks store match ranges as markdown source ranges that do not map onto the
    /// item's primary text view, so they fall back to the item's whole frame — good enough for the
    /// dim scrim to leave the table row bright without precise per-cell geometry.
    func findMatchRect(forUTF16Range range: NSRange, in coordinateView: NSView) -> NSRect? {
        if !tableView.isHidden {
            return tableFallbackRect(in: coordinateView)
        }
        guard range.length > 0,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return nil
        }
        let clampedRange = textView.string.blockInputClampedRange(range)
        guard clampedRange.length > 0 else {
            return nil
        }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: clampedRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else {
            return nil
        }
        layoutManager.ensureLayout(for: textContainer)
        let localRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            .offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
        return textView.convert(localRect, to: coordinateView)
    }

    private func tableFallbackRect(in coordinateView: NSView) -> NSRect? {
        guard view.superview != nil else {
            return nil
        }
        return view.convert(view.bounds, to: coordinateView)
    }
}
