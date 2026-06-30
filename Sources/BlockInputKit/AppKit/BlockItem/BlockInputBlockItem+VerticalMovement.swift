import AppKit

extension BlockInputBlockItem {
    func utf16Offset(
        closestToTextContainerX preferredTextContainerX: CGFloat?,
        linePosition: TextLinePosition
    ) -> Int {
        let textLength = (textView.string as NSString).length
        guard let preferredTextContainerX,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let line = textLineFragments().line(at: linePosition) else {
            return linePosition == .first ? 0 : textLength
        }
        var fraction: CGFloat = 0
        let characterIndex = layoutManager.characterIndex(
            for: NSPoint(x: preferredTextContainerX, y: line.usedRect.midY),
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        let roundedCharacterIndex = characterIndex + (fraction > 0.5 ? 1 : 0)
        return min(max(roundedCharacterIndex, line.insertionRange.location), NSMaxRange(line.insertionRange))
    }

    func lineBoundaryUTF16Offset(
        containingUTF16Offset offset: Int,
        direction: BlockInputLineBoundarySelectionDirection
    ) -> Int {
        let text = textView.string as NSString
        let clampedOffset = min(max(offset, 0), text.length)
        guard textView.window != nil else {
            return text.sourceLineBoundaryOffset(containingUTF16Offset: clampedOffset, direction: direction)
        }
        if let line = textLineFragments().line(containingInsertionOffset: clampedOffset, textLength: text.length) {
            switch direction {
            case .beginning:
                return line.insertionRange.location
            case .end:
                return NSMaxRange(line.insertionRange)
            }
        }
        return text.sourceLineBoundaryOffset(containingUTF16Offset: clampedOffset, direction: direction)
    }

    func canMoveVerticallyOutOfBlock(_ direction: BlockInputVerticalMovementDirection) -> Bool {
        let selectedRange = textView.selectedRange()
        guard selectedRange.length == 0 else {
            return false
        }
        let lines = textLineFragments()
        guard let lineIndex = lineIndex(containingUTF16Offset: selectedRange.location, lines: lines) else {
            let textLength = (textView.string as NSString).length
            switch direction {
            case .upward:
                return selectedRange.location == 0
            case .downward:
                return selectedRange.location >= textLength
            }
        }
        switch direction {
        case .upward:
            return lineIndex == 0
        case .downward:
            return lineIndex == lines.count - 1
        }
    }

    func shouldMoveVerticallyOutOfFocusedTableCell(_ direction: BlockInputVerticalMovementDirection) -> Bool {
        guard direction == .upward,
              let activeCellView = tableView.activeCellView,
              activeCellView.position.row == .header,
              activeCellView.position.column == 0 else {
            return false
        }
        let selectedRange = activeCellView.textView.selectedRange()
        return selectedRange.location == 0 && selectedRange.length == 0
    }

    func currentCaretTextContainerX() -> CGFloat? {
        selectionExtentTextContainerX(.downward)
    }

    func selectionExtentTextContainerX(_ direction: BlockInputVerticalMovementDirection) -> CGFloat? {
        let selectedRange = textView.selectedRange()
        let offset = direction == .upward ? selectedRange.location : NSMaxRange(selectedRange)
        return textContainerX(forUTF16Offset: offset)
    }

    func textContainerX(forUTF16Offset offset: Int) -> CGFloat? {
        guard let window = textView.window else {
            return nil
        }
        // AppKit reports caret rects in screen coordinates; convert back into text-container coordinates.
        let caretRect = textView.firstRect(forCharacterRange: NSRange(location: offset, length: 0), actualRange: nil)
        guard caretRect != .zero, !caretRect.isNull, !caretRect.isInfinite else {
            return nil
        }
        let windowPoint = window.convertPoint(fromScreen: caretRect.origin)
        let localPoint = textView.convert(windowPoint, from: nil)
        return localPoint.x - textView.textContainerOrigin.x
    }

    func utf16Offset(atWindowLocation windowLocation: NSPoint) -> Int {
        if !tableView.isHidden,
           let offset = tableView.sourceOffset(atWindowLocation: windowLocation) {
            return offset
        }
        let textLength = (textView.string as NSString).length
        let localLocation = textView.convert(windowLocation, from: nil)
        let offset = textView.characterIndexForInsertion(at: localLocation)
        return min(max(offset, 0), textLength)
    }

    /// Returns a window-coordinate caret anchor for popovers that originate at a collapsed text offset.
    func anchorWindowRect(forUTF16Offset offset: Int) -> NSRect {
        if !tableView.isHidden,
           let tableAnchor = tableView.anchorWindowRect(forSourceRange: NSRange(location: offset, length: 0)) {
            return tableAnchor
        }
        let clampedOffset = min(max(offset, 0), (textView.string as NSString).length)
        guard let window = textView.window else {
            return .zero
        }
        let rect = textView.firstRect(forCharacterRange: NSRange(location: clampedOffset, length: 0), actualRange: nil)
        guard rect != .zero, !rect.isNull, !rect.isInfinite else {
            return textView.convert(textView.bounds, to: nil)
        }
        let origin = window.convertPoint(fromScreen: rect.origin)
        return NSRect(origin: origin, size: rect.size)
    }

    /// Returns a window-coordinate anchor over visible glyphs, falling back to a caret anchor when layout has no glyphs.
    func anchorWindowRect(forUTF16Range range: NSRange) -> NSRect {
        if !tableView.isHidden,
           let tableAnchor = tableView.anchorWindowRect(forSourceRange: range) {
            return tableAnchor
        }
        guard range.length > 0,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return anchorWindowRect(forUTF16Offset: range.location)
        }
        let characterRange = textView.string.linkAnchorClampedRange(range)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
            .clamped(toGlyphCount: layoutManager.numberOfGlyphs)
        guard glyphRange.length > 0 else {
            return anchorWindowRect(forUTF16Offset: range.location)
        }
        layoutManager.ensureLayout(for: textContainer)
        let localRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            .offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
        return textView.convert(localRect, to: nil)
    }

    private func lineIndex(containingUTF16Offset offset: Int, lines: [TextLineFragment]) -> Int? {
        let textLength = (textView.string as NSString).length
        let clampedOffset = min(max(offset, 0), textLength)
        guard !lines.isEmpty else {
            return nil
        }
        // At the start of an internal line, let NSTextView handle normal in-block vertical movement.
        if let index = lines.firstIndex(where: { $0.characterRange.location == clampedOffset }) {
            return index
        }
        for (index, line) in lines.enumerated() {
            let isFinalTextOffset = index == lines.count - 1 && clampedOffset == textLength
            if line.containsInterior(utf16Offset: clampedOffset) || isFinalTextOffset {
                return index
            }
        }
        return clampedOffset == textLength ? lines.indices.last : nil
    }

    private func textLineFragments() -> [TextLineFragment] {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return []
        }
        let text = textView.string as NSString
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        guard glyphRange.length > 0 else {
            let emptyRange = NSRange(location: 0, length: 0)
            return [TextLineFragment(characterRange: emptyRange, insertionRange: emptyRange, usedRect: .zero)]
        }

        var fragments: [TextLineFragment] = []
        var glyphIndex = glyphRange.location
        while glyphIndex < NSMaxRange(glyphRange) {
            var lineGlyphRange = NSRange()
            let usedRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: &lineGlyphRange)
            let characterRange = layoutManager.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
            fragments.append(TextLineFragment(
                characterRange: characterRange,
                insertionRange: characterRange.insertionRange(in: text),
                usedRect: usedRect
            ))
            glyphIndex = NSMaxRange(lineGlyphRange)
        }
        if text.hasTrailingLineEnding {
            // NSLayoutManager folds a terminal newline into the previous glyph line. Add the visual blank line
            // explicitly so Up/Down movement stays inside the block until the caret reaches a true boundary.
            let emptyFinalLineRange = NSRange(location: text.length, length: 0)
            fragments.append(TextLineFragment(
                characterRange: emptyFinalLineRange,
                insertionRange: emptyFinalLineRange,
                usedRect: layoutManager.extraLineFragmentUsedRect.fallbackExtraLineFragmentUsedRect(
                    after: fragments,
                    in: textContainer
                )
            ))
        }
        return fragments
    }
}

private struct TextLineFragment {
    var characterRange: NSRange
    var insertionRange: NSRange
    var usedRect: NSRect

    func containsInterior(utf16Offset: Int) -> Bool {
        utf16Offset > characterRange.location && utf16Offset < NSMaxRange(characterRange)
    }
}

private extension NSRange {
    func insertionRange(in text: NSString) -> NSRange {
        var upperBound = min(NSMaxRange(self), text.length)
        while upperBound > location {
            let character = text.character(at: upperBound - 1)
            guard character == 10 || character == 13 else {
                break
            }
            upperBound -= 1
        }
        return NSRange(location: location, length: upperBound - location)
    }

    func clamped(toGlyphCount glyphCount: Int) -> NSRange {
        let location = min(max(location, 0), glyphCount)
        let length = min(max(length, 0), max(glyphCount - location, 0))
        return NSRange(location: location, length: length)
    }
}

private extension String {
    func linkAnchorClampedRange(_ range: NSRange) -> NSRange {
        let text = self as NSString
        let location = min(max(range.location, 0), text.length)
        let length = min(max(range.length, 0), max(text.length - location, 0))
        return NSRange(location: location, length: length)
    }
}

private extension NSString {
    var hasTrailingLineEnding: Bool {
        guard length > 0 else {
            return false
        }
        let lastCharacter = character(at: length - 1)
        return lastCharacter == 10 || lastCharacter == 13
    }
}

private extension NSRect {
    func fallbackExtraLineFragmentUsedRect(after fragments: [TextLineFragment], in textContainer: NSTextContainer) -> NSRect {
        guard isEmpty else {
            return self
        }
        if let last = fragments.last {
            return NSRect(
                x: last.usedRect.minX,
                y: last.usedRect.maxY,
                width: max(last.usedRect.width, 12),
                height: max(last.usedRect.height, 1)
            )
        }
        return NSRect(x: 0, y: 0, width: max(textContainer.size.width, 12), height: 1)
    }
}

private extension Array where Element == TextLineFragment {
    func line(at position: BlockInputBlockItem.TextLinePosition) -> TextLineFragment? {
        switch position {
        case .first:
            return first
        case .last:
            return last
        }
    }

    func line(containingInsertionOffset offset: Int, textLength: Int) -> TextLineFragment? {
        if let line = first(where: { $0.insertionRange.location == offset }) {
            return line
        }
        if let line = first(where: { $0.insertionRange.containsInsertionOffset(offset) }) {
            return line
        }
        if offset == textLength {
            return last
        }
        return nil
    }
}

private extension NSRange {
    func containsInsertionOffset(_ offset: Int) -> Bool {
        offset > location && offset <= NSMaxRange(self)
    }
}

private extension NSString {
    func sourceLineBoundaryOffset(
        containingUTF16Offset offset: Int,
        direction: BlockInputLineBoundarySelectionDirection
    ) -> Int {
        guard length > 0 else {
            return 0
        }
        let clampedOffset = min(max(offset, 0), length)
        var lineStart = 0
        var lineEnd = 0
        var contentsEnd = 0
        getLineStart(
            &lineStart,
            end: &lineEnd,
            contentsEnd: &contentsEnd,
            for: NSRange(location: clampedOffset, length: 0)
        )
        switch direction {
        case .beginning:
            return lineStart
        case .end:
            return contentsEnd
        }
    }
}
