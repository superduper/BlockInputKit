import AppKit

extension BlockInputTextView {
    override func layout() {
        super.layout()
        updateInlineHintView()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInlineHintView()
    }

    func configureInlineHintView() {
        inlineHintView.isHidden = true
        inlineHintView.autoresizingMask = []
        addSubview(inlineHintView)
    }

    func clearInlineHint() {
        inlineHint = nil
    }

    func updateInlineHintView() {
        guard let hint = inlineHint,
              !hint.text.isEmpty,
              !string.isEmpty,
              let frame = inlineHintDrawingRect() else {
            inlineHintView.isHidden = true
            return
        }
        let caretOffset = min(max(selectedRange().location, 0), (string as NSString).length)
        inlineHintView.text = hint.text
        inlineHintView.font = inlineHintFont(caretOffset: caretOffset)
        inlineHintView.color = .placeholderTextColor
        inlineHintView.frame = frame.integral
        inlineHintView.isHidden = false
    }

    func inlineHintDrawingRect() -> NSRect? {
        guard selectedRange().length == 0 else {
            return nil
        }
        let textLength = (string as NSString).length
        guard textLength > 0,
              let layoutManager,
              let textContainer else {
            return nil
        }
        let caretOffset = min(max(selectedRange().location, 0), textLength)
        let hintFont = inlineHintFont(caretOffset: caretOffset)
        if let caretRect = inlineHintCaretRect(caretOffset: caretOffset, hintFont: hintFont) {
            return inlineHintDrawingRect(fromCaretRect: caretRect)
        }
        layoutManager.ensureLayout(for: textContainer)
        guard let lineRect = inlineHintLineRect(caretOffset: caretOffset, layoutManager: layoutManager) else {
            return nil
        }
        let origin = textContainerOrigin
        let hintX = origin.x + inlineHintTextContainerX(
            caretOffset: caretOffset,
            lineRect: lineRect,
            layoutManager: layoutManager
        )
        let hintY = origin.y + lineRect.minY
        let width = max(0, bounds.maxX - hintX - textContainerInset.width)
        let height = max(lineRect.height, hintFont.boundingRectForFont.height)
        guard width > 1, height > 1 else {
            return nil
        }
        return NSRect(x: hintX, y: hintY, width: width, height: height)
    }

    private func inlineHintCaretRect(caretOffset: Int, hintFont: NSFont) -> NSRect? {
        guard let window else {
            return nil
        }
        let rect = firstRect(forCharacterRange: NSRange(location: caretOffset, length: 0), actualRange: nil)
        guard rect != .zero, !rect.isNull, !rect.isInfinite else {
            return nil
        }
        let windowPoint = window.convertPoint(fromScreen: NSPoint(x: rect.minX, y: rect.maxY))
        let localPoint = convert(windowPoint, from: nil)
        return NSRect(
            x: localPoint.x,
            y: localPoint.y,
            width: rect.width,
            height: max(rect.height, hintFont.boundingRectForFont.height)
        )
    }

    private func inlineHintDrawingRect(fromCaretRect caretRect: NSRect) -> NSRect? {
        let hintX = caretRect.maxX
        let width = max(0, bounds.maxX - hintX - textContainerInset.width)
        guard width > 1, caretRect.height > 1 else {
            return nil
        }
        return NSRect(x: hintX, y: caretRect.minY, width: width, height: caretRect.height)
    }

    private func inlineHintFont(caretOffset: Int) -> NSFont {
        if let textStorage,
           let visibleFont = nearestVisibleFont(caretOffset: caretOffset, textStorage: textStorage) {
            return visibleFont
        }
        if let typingFont = typingAttributes[.font] as? NSFont,
           typingFont.pointSize >= 4 {
            return typingFont
        }
        if let font,
           font.pointSize >= 4 {
            return font
        }
        return .preferredFont(forTextStyle: .body)
    }

    private func nearestVisibleFont(caretOffset: Int, textStorage: NSTextStorage) -> NSFont? {
        guard textStorage.length > 0 else {
            return nil
        }
        let startLocation = min(max(caretOffset - 1, 0), textStorage.length - 1)
        for location in stride(from: startLocation, through: 0, by: -1) {
            if textStorage.attribute(.blockInputHiddenDelimiter, at: location, effectiveRange: nil) as? Bool == true {
                continue
            }
            if textStorage.attribute(.blockInputInlineChip, at: location, effectiveRange: nil) as? Bool == true {
                continue
            }
            guard let font = textStorage.attribute(.font, at: location, effectiveRange: nil) as? NSFont,
                  font.pointSize >= 4 else {
                continue
            }
            return font
        }
        return nil
    }

    private func inlineHintLineRect(caretOffset: Int, layoutManager: NSLayoutManager) -> NSRect? {
        let textLength = (string as NSString).length
        let characterIndex = min(max(caretOffset < textLength ? caretOffset : caretOffset - 1, 0), textLength - 1)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
        return layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
    }

    private func inlineHintTextContainerX(
        caretOffset: Int,
        lineRect: NSRect,
        layoutManager: NSLayoutManager
    ) -> CGFloat {
        if caretOffset <= 0 {
            return lineRect.minX
        }
        let textLength = (string as NSString).length
        if caretOffset >= textLength {
            return lineRect.maxX
        }
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: caretOffset)
        return max(lineRect.minX, layoutManager.location(forGlyphAt: glyphIndex).x)
    }
}
