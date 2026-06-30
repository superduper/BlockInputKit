import AppKit

extension BlockInputTextView {
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        guard blockItem?.insertionPointStyle == .block else {
            super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
            return
        }
        guard flag else {
            // Let AppKit erase the cursor area; setNeedsDisplay triggered by the blink timer redraws the glyph.
            super.drawInsertionPoint(in: rect, color: color, turnedOn: false)
            return
        }
        drawBlockCursor(defaultRect: rect, color: color)
    }

    private func drawBlockCursor(defaultRect rect: NSRect, color: NSColor) {
        let location = selectedRange().location
        guard let layoutManager, let textContainer else {
            var fallback = rect
            fallback.size.width = max(rect.height * 0.55, 8)
            color.setFill()
            fallback.fill()
            return
        }

        let blockRect = blockCursorRect(for: location, defaultRect: rect, layoutManager: layoutManager, textContainer: textContainer)
        color.setFill()
        blockRect.fill()

        guard let textStorage, location < textStorage.length else { return }
        redrawGlyphOverBlock(at: location, blockRect: blockRect, layoutManager: layoutManager)
    }

    private func blockCursorRect(
        for location: Int,
        defaultRect rect: NSRect,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> NSRect {
        guard let textStorage, location < textStorage.length else {
            return fallbackBlockRect(rect)
        }
        let charRange = NSRange(location: location, length: 1)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return fallbackBlockRect(rect) }
        let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let width = max(glyphRect.width, 2)
        return NSRect(x: glyphRect.minX + textContainerOrigin.x, y: rect.minY, width: width, height: rect.height)
    }

    private func fallbackBlockRect(_ rect: NSRect) -> NSRect {
        var result = rect
        result.size.width = max(rect.height * 0.55, 8)
        return result
    }

    // Draws the glyph at `location` on top of the already-filled block rect using a contrasting color.
    // Uses NSLayoutManager temporary attributes so no text storage mutation occurs.
    private func redrawGlyphOverBlock(at location: Int, blockRect: NSRect, layoutManager: NSLayoutManager) {
        let charRange = NSRange(location: location, length: 1)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        blockRect.clip()
        layoutManager.addTemporaryAttribute(.foregroundColor, value: NSColor.textBackgroundColor, forCharacterRange: charRange)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: textContainerOrigin)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: charRange)
        NSGraphicsContext.restoreGraphicsState()
    }
}
