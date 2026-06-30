import AppKit

extension BlockInputBlockItem {
    func renderedTextBoundsForSelectionChrome() -> NSRect? {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return nil
        }
        layoutManager.ensureLayout(for: textContainer)
        let text = textView.string as NSString
        let textOrigin = textView.textContainerOrigin
        var bounds: NSRect?
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        var glyphIndex = glyphRange.location
        var lastLineRect: NSRect?
        while glyphIndex < NSMaxRange(glyphRange) {
            var lineGlyphRange = NSRange()
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineGlyphRange)
            let usedRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            bounds = unionSelectionChromeTextBounds(
                bounds,
                lineRect: lineRect,
                usedRect: usedRect,
                textOrigin: textOrigin
            )
            lastLineRect = lineRect
            glyphIndex = NSMaxRange(lineGlyphRange)
        }
        if text.hasTerminalLineEnding {
            let lineRect = layoutManager.extraLineFragmentRect.fallbackSelectionChromeLineRect(after: lastLineRect, in: textContainer)
            let usedRect = layoutManager.extraLineFragmentUsedRect.fallbackSelectionChromeUsedRect(in: lineRect)
            bounds = unionSelectionChromeTextBounds(
                bounds,
                lineRect: lineRect,
                usedRect: usedRect,
                textOrigin: textOrigin
            )
        }
        return bounds ?? selectionChromeTextFrame(lineRect: .zero, usedRect: .zero, textOrigin: textOrigin)
    }

    private func unionSelectionChromeTextBounds(
        _ bounds: NSRect?,
        lineRect: NSRect,
        usedRect: NSRect,
        textOrigin: NSPoint
    ) -> NSRect {
        let frame = selectionChromeTextFrame(lineRect: lineRect, usedRect: usedRect, textOrigin: textOrigin)
        return bounds.map { $0.union(frame) } ?? frame
    }

    private func selectionChromeTextFrame(
        lineRect: NSRect,
        usedRect: NSRect,
        textOrigin: NSPoint
    ) -> NSRect {
        textView.convert(NSRect(
            x: textOrigin.x + usedRect.minX,
            y: textOrigin.y + lineRect.minY,
            width: max(usedRect.width, 12),
            height: max(lineRect.height, 1)
        ), to: view)
    }
}

private extension NSRect {
    func fallbackSelectionChromeLineRect(after lineRect: NSRect?, in textContainer: NSTextContainer) -> NSRect {
        guard isEmpty else {
            return self
        }
        if let lineRect {
            return NSRect(
                x: lineRect.minX,
                y: lineRect.maxY,
                width: max(lineRect.width, 1),
                height: max(lineRect.height, 1)
            )
        }
        return NSRect(x: 0, y: 0, width: max(textContainer.size.width, 1), height: 1)
    }

    func fallbackSelectionChromeUsedRect(in lineRect: NSRect) -> NSRect {
        guard !isEmpty else {
            return NSRect(x: lineRect.minX, y: lineRect.minY, width: 12, height: max(lineRect.height, 1))
        }
        return self
    }
}

private extension NSString {
    var hasTerminalLineEnding: Bool {
        guard length > 0 else {
            return false
        }
        let lastCharacter = character(at: length - 1)
        return lastCharacter == 10 || lastCharacter == 13
    }
}
