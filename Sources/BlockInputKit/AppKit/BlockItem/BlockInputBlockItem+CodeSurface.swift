import AppKit

extension BlockInputBlockItem {
    func applyCodeBlockAttributes(for block: BlockInputBlock, textStorage: NSTextStorage) {
        guard case let .code(language) = block.kind else {
            return
        }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let highlighted = BlockInputSyntaxHighlighter.highlighted(
            textStorage.string,
            language: language,
            colorScheme: BlockInputSyntaxColorScheme(appearance: textView.effectiveAppearance),
            font: Self.font(for: block.kind, style: style),
            baseForegroundColor: foregroundColor(for: block.kind)
        )
        highlighted.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            textStorage.addAttributes(attributes, range: range)
        }
        // An explicit code foreground color is a global override, including syntax-highlighted token ranges.
        if let foregroundColor = style.codeBlock.foregroundColor {
            textStorage.addAttribute(.foregroundColor, value: foregroundColor, range: fullRange)
        }
        applyReadOnlyCodeForegroundIfNeeded(textStorage: textStorage, range: fullRange)
    }

    func configureCodeBackground(for block: BlockInputBlock, suppressed: Bool = false) {
        guard case .code = block.kind, !suppressed else {
            codeBackgroundView.isHidden = true
            codeBackgroundView.alphaValue = 0
            renderedCodeColorScheme = nil
            return
        }
        codeBackgroundView.isHidden = false
        codeBackgroundView.alphaValue = BlockInputReadOnlyStyle.alpha(
            isEditable: isEditable,
            readOnly: BlockInputReadOnlyStyle.codeBackgroundAlpha
        )
        codeBackgroundView.layer?.backgroundColor = codeBackgroundColor(for: effectiveCodeColorScheme).cgColor
        codeBackgroundView.layer?.borderColor = Self.codeBorderColor(for: effectiveCodeColorScheme).cgColor
        codeBackgroundView.layer?.cornerRadius = style.codeBlock.cornerRadius ?? 6
        renderedCodeColorScheme = effectiveCodeColorScheme
        updateCodeBackgroundFrame()
    }

    func refreshCodeAppearanceIfNeeded() {
        guard let renderedBlock,
              case .code = renderedBlock.kind,
              !isRenderedContentBlock,
              renderedCodeColorScheme != effectiveCodeColorScheme else {
            return
        }
        configureCodeBackground(for: renderedBlock)
        applyTextAttributes(for: renderedBlock)
    }

    func updateCodeBackgroundFrame() {
        guard !codeBackgroundView.isHidden else {
            return
        }
        let verticalInset = Self.scaledVerticalInset(2, blockVerticalInsetMultiplier: blockVerticalInsetMultiplier)
        let minX = min(scrollView.frame.minX + Self.textContainerContentLeading, view.bounds.maxX)
        let maxX = max(minX, scrollView.frame.maxX - Self.textContainerContentLeading)
        let availableWidth = max(0, maxX - minX)
        codeBackgroundView.frame = NSRect(
            x: minX,
            y: max(0, scrollView.frame.minY + verticalInset),
            width: Self.codeSurfaceWidth(
                for: textView.string,
                font: textView.font ?? Self.font(for: renderedBlock?.kind ?? .code(language: nil), style: style),
                availableWidth: availableWidth
            ),
            height: max(0, scrollView.frame.height - verticalInset * 2)
        ).integral
    }

    static func codeSurfaceWidth(for text: String, font: NSFont, availableWidth: CGFloat) -> CGFloat {
        let naturalWidth = widestCodeLineWidth(in: text, font: font) + codeTextHorizontalPadding * 2
        let minimumWidth = max(ceil(font.pointSize * 12), 144)
        return min(max(naturalWidth, minimumWidth), max(availableWidth, 0))
    }

    private func applyReadOnlyCodeForegroundIfNeeded(textStorage: NSTextStorage, range: NSRange) {
        guard !isEditable else {
            return
        }
        BlockInputReadOnlyStyle.applyDisabledForeground(to: textStorage, range: range)
    }

    private static func widestCodeLineWidth(in text: String, font: NSFont) -> CGFloat {
        let code = text.isEmpty ? " " : text
        return code
            .components(separatedBy: .newlines)
            .map { line in
                let measuredLine = line.isEmpty ? " " : line
                return ceil((measuredLine as NSString).size(withAttributes: [.font: font]).width)
            }
            .max() ?? 0
    }

    private var effectiveCodeColorScheme: BlockInputSyntaxColorScheme {
        BlockInputSyntaxColorScheme(appearance: view.effectiveAppearance)
    }

    private func codeBackgroundColor(for colorScheme: BlockInputSyntaxColorScheme) -> NSColor {
        if let backgroundColor = style.codeBlock.backgroundColor {
            return backgroundColor
        }
        switch colorScheme {
        case .dark:
            return NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1)
        case .light:
            return NSColor(srgbRed: 0.96, green: 0.97, blue: 0.98, alpha: 1)
        }
    }

    private static func codeBorderColor(for colorScheme: BlockInputSyntaxColorScheme) -> NSColor {
        switch colorScheme {
        case .dark:
            return NSColor(srgbRed: 0.23, green: 0.25, blue: 0.28, alpha: 1)
        case .light:
            return NSColor(srgbRed: 0.84, green: 0.86, blue: 0.89, alpha: 1)
        }
    }
}
