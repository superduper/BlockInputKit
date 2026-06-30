import AppKit

extension BlockInputBlockItem {
    func applySelectionChrome(_ chrome: BlockInputBlockSelectionChrome) {
        blockSelectionChrome = chrome
        updateImageSelectionBorder()
        selectionBackgroundView.isHidden = !chrome.showsContentBackground
        selectionBackgroundView.fillColor = chrome.contentBackgroundColor(style: style)
        selectionBackgroundView.cornerRadius = selectionChromeCornerRadius(for: chrome)
        updateSelectionChromeFrame()
    }

    func updateSelectionChromeFrame() {
        guard blockSelectionChrome.showsContentBackground else {
            selectionBackgroundView.isHidden = true
            selectionBackgroundView.segmentRects = []
            return
        }
        guard !usesImageSelectionBorder, !usesRenderedContentSelectionBorder else {
            selectionBackgroundView.isHidden = true
            selectionBackgroundView.segmentRects = []
            return
        }
        selectionBackgroundView.isHidden = false
        guard !view.bounds.isEmpty else {
            return
        }
        let layout = selectedContentBackgroundLayout()
        let frame = layout.usesIntegralFrame ? layout.frame.integral : layout.frame
        selectionBackgroundView.frame = frame
        selectionBackgroundView.segmentRects = layout.segmentFrames.map {
            $0.offsetBy(dx: -frame.minX, dy: -frame.minY).integral
        }
    }

    @discardableResult
    func applyTemporarySelectionHighlight(_ range: NSRange) -> Bool {
        clearTemporarySelectionHighlight()
        let clampedRange = textView.string.blockInputClampedRange(range)
        guard clampedRange.length > 0 else {
            return false
        }
        textView.selectedTextAttributes = BlockInputBlockSelectionChrome.suppressedNativeSelectedTextAttributes
        // Partial selections use editor-owned line-fragment chrome; the temporary text attribute only keeps unfocused
        // endpoint text readable instead of letting AppKit draw inactive gray selection.
        textView.layoutManager?.addTemporaryAttribute(
            .foregroundColor,
            value: NSColor.selectedTextColor,
            forCharacterRange: clampedRange
        )
        temporarySelectionHighlightRange = clampedRange
        return true
    }

    func clearTemporarySelectionHighlight() {
        guard let range = temporarySelectionHighlightRange else {
            restoreNativeSelectionDisplay()
            return
        }
        textView.layoutManager?.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
        restoreNativeSelectionDisplay()
        temporarySelectionHighlightRange = nil
    }

    func suppressNativeSelectionBackground() {
        textView.selectedTextAttributes = BlockInputBlockSelectionChrome.suppressedNativeSelectedTextAttributes
        textView.needsDisplay = true
    }

    func suppressNativeSelectionDisplayForPartialChrome() {
        // Keep the text view selectable so AppKit continues to own caret and text-command mechanics.
        // Gray overlay suppression comes from collapsed ranges plus clear selected-text backgrounds.
        suppressNativeSelectionBackground()
    }

    func restoreNativeSelectionDisplay() {
        textView.selectedTextAttributes = BlockInputBlockSelectionChrome.nativeSelectedTextAttributes
        let usesTableSurface = renderedBlock?.kind == .table && !tableView.isHidden
        textView.isSelectable = renderedBlock?.kind != .horizontalRule && !usesTableSurface
        textView.needsDisplay = true
    }

    func setFocusedTextSelectionHighlightRange(_ range: NSRange) {
        guard applyTemporarySelectionHighlight(range) else {
            applySelectionChrome(.none)
            return
        }
        applySelectionChrome(.partial)
        suppressNativeSelectionBackground()
    }

    private func selectedContentBackgroundLayout() -> BlockInputSelectionBackgroundLayout {
        if blockSelectionChrome == .partial {
            return selectedPartialTextBackgroundLayout()
        }
        let frame = selectedWholeContentBackgroundFrame()
        return BlockInputSelectionBackgroundLayout(
            frame: frame.rect,
            segmentFrames: [frame.rect],
            usesIntegralFrame: frame.usesIntegralFrame
        )
    }

    private var usesImageSelectionBorder: Bool {
        blockSelectionChrome.showsContentBackground
            && renderedBlock?.kind.isImage == true
            && !imageBlockView.isHidden
    }

    private var usesRenderedContentSelectionBorder: Bool {
        blockSelectionChrome.showsContentBackground
            && isRenderedContentBlock
            && !renderedContentView.isHidden
    }

    private func updateImageSelectionBorder() {
        let imageBorderColor = usesImageSelectionBorder
            ? blockSelectionChrome.contentBackgroundColor(style: style)
            : nil
        imageBlockView.setSelectionBorderColor(imageBorderColor)
        let renderedBorderColor = usesRenderedContentSelectionBorder
            ? blockSelectionChrome.contentBackgroundColor(style: style)
            : nil
        renderedContentView.setSelectionBorderColor(renderedBorderColor)
    }

    private func selectionChromeCornerRadius(for chrome: BlockInputBlockSelectionChrome) -> CGFloat {
        guard chrome.showsContentBackground,
              let renderedBlock else {
            return chrome.cornerRadius
        }
        if renderedBlock.kind == .table,
           !tableView.isHidden {
            return BlockInputTableView.cornerRadius
        }
        if renderedBlock.kind.isImage,
           !imageBlockView.isHidden {
            return style.imageBlock.cornerRadius ?? 6
        }
        if isRenderedContentBlock, !renderedContentView.isHidden {
            return style.imageBlock.cornerRadius ?? 6
        }
        return chrome.cornerRadius
    }

    private func selectedWholeContentBackgroundFrame() -> BlockInputWholeSelectionFrame {
        if case .code = renderedBlock?.kind,
           !codeBackgroundView.isHidden {
            return BlockInputWholeSelectionFrame(rect: codeBackgroundView.frame.integral)
        }
        if renderedBlock?.kind == .table,
           !tableView.isHidden {
            return BlockInputWholeSelectionFrame(rect: tableView.convert(tableView.visibleTableFrame, to: view).integral)
        }
        if renderedBlock?.kind.isImage == true,
           !imageBlockView.isHidden {
            return BlockInputWholeSelectionFrame(rect: imageBlockView.frame.integral)
        }
        if isRenderedContentBlock, !renderedContentView.isHidden {
            return BlockInputWholeSelectionFrame(rect: renderedContentView.frame.integral)
        }
        let leadingPadding: CGFloat = 0
        let trailingPadding: CGFloat = 6
        let verticalInset = Self.scaledVerticalInset(2, blockVerticalInsetMultiplier: blockVerticalInsetMultiplier)
        let bounds = selectedContentBounds()
        let chipVerticalFrame = selectedSingleLineInlineChipVerticalFrame()
        let xPosition = max(0, bounds.minX - leadingPadding)
        let maxWidth = max(0, view.bounds.maxX - xPosition - trailingPadding)
        let width = min(max(bounds.width + leadingPadding + trailingPadding, 24), maxWidth)
        return BlockInputWholeSelectionFrame(
            rect: NSRect(
                x: xPosition,
                y: chipVerticalFrame?.minY ?? verticalInset,
                width: width,
                height: chipVerticalFrame?.height ?? max(0, view.bounds.height - verticalInset * 2)
            ),
            usesIntegralFrame: chipVerticalFrame == nil
        )
    }

    private func selectedSingleLineInlineChipVerticalFrame() -> NSRect? {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return nil
        }
        let text = textView.string as NSString
        layoutManager.ensureLayout(for: textContainer)
        guard textLineSelectionFragments(
            layoutManager: layoutManager,
            textContainer: textContainer,
            text: text
        ).count == 1 else {
            return nil
        }
        let chipRects = textView.inlineChipBackgroundRects()
        guard let firstRect = chipRects.first else {
            return nil
        }
        let chipBounds = chipRects.dropFirst().reduce(firstRect) { $0.union($1) }
        let itemChipBounds = textView.convert(chipBounds, to: view)
        return NSRect(
            x: 0,
            y: itemChipBounds.minY,
            width: max(itemChipBounds.width, 1),
            height: max(itemChipBounds.height, 1)
        )
    }

    private func selectedContentBounds() -> NSRect {
        if renderedBlock?.kind == .horizontalRule {
            let minX = min(horizontalRuleView.frame.minX, standardTextSelectionLeadingX())
            return NSRect(
                x: minX,
                y: 0,
                width: max(1, horizontalRuleView.frame.maxX - minX),
                height: view.bounds.height
            )
        }
        if renderedBlock?.kind == .frontMatter, !frontMatterDividerView.isHidden {
            let minX = min(textGlyphLeadingX(), frontMatterDividerView.frame.minX)
            let maxX = max(textGlyphTrailingX(), frontMatterDividerView.frame.maxX)
            return NSRect(x: minX, y: 0, width: max(1, maxX - minX), height: view.bounds.height)
        }
        if renderedBlock?.kind == .table, !tableView.isHidden {
            let tableFrame = tableView.convert(tableView.visibleTableFrame, to: view)
            return NSRect(x: tableFrame.minX, y: 0, width: max(1, tableFrame.width), height: view.bounds.height)
        }
        if renderedBlock?.kind.isImage == true,
           !imageBlockView.isHidden {
            return imageBlockView.frame
        }
        if isRenderedContentBlock, !renderedContentView.isHidden {
            return renderedContentView.frame
        }
        let textBounds = renderedTextBoundsForSelectionChrome()
        var minX = min(textBounds?.minX ?? textGlyphLeadingX(), standardTextSelectionLeadingX())
        var maxX = textBounds?.maxX ?? textGlyphTrailingX()
        if !kindLabel.markerLines.isEmpty {
            minX = min(minX, kindLabel.frame.minX)
            maxX = max(maxX, kindLabel.frame.maxX)
        }
        if !checklistButton.isHidden {
            minX = min(minX, checklistButton.frame.minX)
            maxX = max(maxX, checklistButton.frame.maxX)
        }
        if !quoteBarView.isHidden {
            minX = min(minX, quoteBarView.frame.minX)
            maxX = max(maxX, quoteBarView.frame.maxX)
        }
        return NSRect(x: minX, y: 0, width: max(1, maxX - minX), height: view.bounds.height)
    }

    private func selectedPartialTextBackgroundLayout() -> BlockInputSelectionBackgroundLayout {
        let segmentFrames = selectedPartialTextBackgroundRects()
        guard let firstFrame = segmentFrames.first else {
            let fallbackFrame = singleLinePartialBackgroundFrame(
                for: NSRect(x: textGlyphLeadingX(), y: 0, width: 24, height: view.bounds.height)
            )
            return BlockInputSelectionBackgroundLayout(frame: fallbackFrame, segmentFrames: [fallbackFrame])
        }
        let frame = segmentFrames.dropFirst().reduce(firstFrame) { $0.union($1) }
        return BlockInputSelectionBackgroundLayout(frame: frame, segmentFrames: segmentFrames)
    }

    private func selectedPartialTextBackgroundRects() -> [NSRect] {
        guard let range = temporarySelectionHighlightRange,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            let leadingX = textGlyphLeadingX()
            return [singleLinePartialBackgroundFrame(for: NSRect(x: leadingX, y: 0, width: 24, height: view.bounds.height))]
        }
        layoutManager.ensureLayout(for: textContainer)
        let text = textView.string as NSString
        let clampedRange = textView.string.blockInputClampedRange(range)
        guard clampedRange.length > 0 else {
            return []
        }
        let lineFragments = textLineSelectionFragments(
            layoutManager: layoutManager,
            textContainer: textContainer,
            text: text
        )
        let lineFrames = lineFragments.compactMap {
            selectedPartialTextBackgroundFrame(
                for: clampedRange,
                line: $0,
                layoutManager: layoutManager
            )
        }
        let frames = lineFrames.mergingSelectionChromeFrames(
            selectedLogicalListLineStartBackgroundFrames(for: clampedRange, layoutManager: layoutManager)
        )
        return frames
    }

    private func selectedPartialTextBackgroundFrame(
        for range: NSRange,
        line: BlockInputTextSelectionLineFragment,
        layoutManager: NSLayoutManager
    ) -> NSRect? {
        let selectedCharacterStart = max(range.location, line.characterRange.location)
        let selectedCharacterEnd = min(NSMaxRange(range), NSMaxRange(line.characterRange))
        guard selectedCharacterStart < selectedCharacterEnd else {
            return nil
        }
        let lineStart = line.insertionRange.location
        let lineEnd = NSMaxRange(line.insertionRange)
        let lineContentStart = line.insertionRange.selectionChromeContentStart(in: textView.string as NSString)
        let selectionStart = min(max(selectedCharacterStart, lineStart), lineEnd)
        let selectionEnd = min(max(selectedCharacterEnd, lineStart), lineEnd)
        let startX = textContainerX(forSelectionOffset: selectionStart, in: line, layoutManager: layoutManager)
        let endX = selectionEnd > selectionStart
            ? textContainerX(forSelectionOffset: selectionEnd, in: line, layoutManager: layoutManager)
            : max(line.usedRect.maxX, line.usedRect.minX + 12)
        let textOrigin = textView.textContainerOrigin
        let startViewX = textView.convert(NSPoint(x: textOrigin.x + startX, y: textOrigin.y), to: view).x
        let endViewX = textView.convert(NSPoint(x: textOrigin.x + endX, y: textOrigin.y), to: view).x
        var minX = min(startViewX, endViewX)
        var maxX = max(startViewX, endViewX)
        if line.index == 0, selectionStart == 0 {
            let leadingBounds = selectedLeadingChromeBounds()
            minX = min(minX, standardTextSelectionLeadingX(), leadingBounds?.minX ?? minX)
            maxX = max(maxX, leadingBounds?.maxX ?? maxX)
        }
        if selectionStart <= lineContentStart,
           selectionEnd > lineContentStart,
           let markerBounds = selectedMarkerLineBounds(forLineAt: line.index) {
            // NSLayoutManager may fold the previous newline into the next line fragment. For Shift+Right across a
            // nested list line break, include the marker only once the first visible character is selected.
            minX = min(minX, markerBounds.minX)
            maxX = max(maxX, markerBounds.maxX)
        }
        let lineViewRect = textView.convert(NSRect(
            x: textOrigin.x + line.lineRect.minX,
            y: textOrigin.y + line.usedRect.minY,
            width: max(line.lineRect.width, 1),
            height: max(line.usedRect.height, 1)
        ), to: view)
        let frame = NSRect(
            x: minX,
            y: max(0, lineViewRect.minY),
            width: max(maxX - minX, 1),
            height: max(lineViewRect.height, 1)
        )
        guard case .code = renderedBlock?.kind else {
            return frame
        }
        let clippedFrame = frame.intersection(visibleTextViewportInItemCoordinates)
        return clippedFrame.isNull || clippedFrame.isEmpty ? nil : clippedFrame
    }

    private func singleLinePartialBackgroundFrame(for bounds: NSRect) -> NSRect {
        let verticalInset = Self.scaledVerticalInset(2, blockVerticalInsetMultiplier: blockVerticalInsetMultiplier)
        return NSRect(
            x: bounds.minX,
            y: verticalInset,
            width: max(bounds.width, 1),
            height: max(0, view.bounds.height - verticalInset * 2)
        )
    }

    private func textLineSelectionFragments(
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        text: NSString
    ) -> [BlockInputTextSelectionLineFragment] {
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        guard glyphRange.length > 0 else {
            let emptyRange = NSRange(location: 0, length: 0)
            return [BlockInputTextSelectionLineFragment(
                index: 0,
                characterRange: emptyRange,
                insertionRange: emptyRange,
                lineRect: .zero,
                usedRect: .zero
            )]
        }

        var fragments: [BlockInputTextSelectionLineFragment] = []
        var glyphIndex = glyphRange.location
        while glyphIndex < NSMaxRange(glyphRange) {
            var lineGlyphRange = NSRange()
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineGlyphRange)
            let usedRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let characterRange = layoutManager.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
            fragments.append(BlockInputTextSelectionLineFragment(
                index: fragments.count,
                characterRange: characterRange,
                insertionRange: characterRange.selectionChromeInsertionRange(in: text),
                lineRect: lineRect,
                usedRect: usedRect
            ))
            glyphIndex = NSMaxRange(lineGlyphRange)
        }
        if let trailingLineEndingRange = text.trailingLineEndingRange {
            // NSLayoutManager folds a terminal newline into the previous line's character range. Add the extra line
            // fragment explicitly so selecting code that ends with a blank line paints that blank line too.
            let lineRect = layoutManager.extraLineFragmentRect.fallbackExtraLineFragmentRect(after: fragments, in: textContainer)
            let usedRect = layoutManager.extraLineFragmentUsedRect.fallbackExtraLineFragmentUsedRect(in: lineRect)
            fragments.append(BlockInputTextSelectionLineFragment(
                index: fragments.count,
                characterRange: trailingLineEndingRange,
                insertionRange: NSRange(location: text.length, length: 0),
                lineRect: lineRect,
                usedRect: usedRect
            ))
        }
        return fragments
    }

    private func textContainerX(
        forSelectionOffset offset: Int,
        in line: BlockInputTextSelectionLineFragment,
        layoutManager: NSLayoutManager
    ) -> CGFloat {
        if offset <= line.insertionRange.location {
            return line.usedRect.minX
        }
        if offset >= NSMaxRange(line.insertionRange) {
            return line.usedRect.maxX
        }
        if let textContainerX = textContainerX(forUTF16Offset: offset) {
            return textContainerX
        }
        return layoutTextContainerX(forUTF16Offset: offset, in: line, layoutManager: layoutManager) ?? line.usedRect.maxX
    }

    private func layoutTextContainerX(
        forUTF16Offset offset: Int,
        in line: BlockInputTextSelectionLineFragment,
        layoutManager: NSLayoutManager
    ) -> CGFloat? {
        let textLength = (textView.string as NSString).length
        guard offset > line.insertionRange.location,
              offset < NSMaxRange(line.insertionRange),
              offset < textLength else {
            return nil
        }
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: offset)
        return layoutManager.location(forGlyphAt: glyphIndex).x
    }

    private func selectedLeadingChromeBounds() -> NSRect? {
        // Multi-line list marker views span every nested marker. Partial text selection on line 0 should include only
        // that line's marker, or Shift+Right from the previous block paints far past the first selected character.
        let markerBounds = !kindLabel.markerLines.isEmpty ? selectedMarkerLineBounds(forLineAt: 0) : nil
        let bounds = [
            markerBounds,
            !checklistButton.isHidden ? checklistButton.frame : nil,
            !quoteBarView.isHidden ? quoteBarView.frame : nil
        ].compactMap { $0 }
        guard let first = bounds.first else {
            return nil
        }
        return bounds.dropFirst().reduce(first) { $0.union($1) }
    }

    private func textGlyphLeadingX() -> CGFloat {
        scrollView.frame.minX + textView.textContainerInset.width
    }

    private func standardTextSelectionLeadingX() -> CGFloat {
        Self.horizontalChromeWidth(
            allowsReordering: allowsReordering,
            editorHorizontalInset: editorHorizontalInset
        ) + Self.standardTextContainerInset.width
    }

    private func textGlyphTrailingX() -> CGFloat {
        textGlyphLeadingX() + max(ceil(measuredTextWidth()), 24)
    }

    private func measuredTextWidth() -> CGFloat {
        let text = textView.string.isEmpty ? " " : textView.string
        let font = textView.font ?? Self.font(for: renderedBlock?.kind ?? .paragraph, style: style)
        return text
            .components(separatedBy: .newlines)
            .map { line in
                let measuredLine = line.isEmpty ? " " : line
                return (measuredLine as NSString).size(withAttributes: [.font: font]).width
            }
            .max() ?? 24
    }
}

private struct BlockInputSelectionBackgroundLayout {
    var frame: NSRect
    var segmentFrames: [NSRect]
    var usesIntegralFrame: Bool = true
}

private struct BlockInputWholeSelectionFrame {
    var rect: NSRect
    var usesIntegralFrame: Bool = true
}
