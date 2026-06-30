import AppKit

extension BlockInputBlockItem {
    static func height(
        for block: BlockInputBlock,
        textWidth: CGFloat,
        style: BlockInputStyle = .default,
        fileBaseURL: URL? = nil,
        blockVerticalInsetMultiplier: CGFloat = 1,
        inlineMarkupProviders: [any BlockInputInlineMarkupProvider] = [],
        chipAccessoryProvider: ((BlockInputChipContext) -> BlockInputChipAccessory?)? = nil,
        contentRenderers: BlockInputBlockContentRendererRegistry = BlockInputBlockContentRendererRegistry(),
        resolvedContentDimensions: BlockInputImageDimensions? = nil
    ) -> CGFloat {
        let text = block.text.isEmpty ? " " : block.text
        let availableTextWidth = max(textWidth - perLineContentIndent(for: block), 120)
        let font = font(for: block.kind, style: style)
        let metrics = verticalMetrics(for: block, blockVerticalInsetMultiplier: blockVerticalInsetMultiplier)
        let frontMatterReserve = frontMatterHeightReserve(for: block, blockVerticalInsetMultiplier: blockVerticalInsetMultiplier)
        if block.kind == .table,
           let table = BlockInputTable(markdown: block.text) {
            return tableBlockHeight(
                table, availableTextWidth: availableTextWidth, style: style,
                metrics: metrics, blockVerticalInsetMultiplier: blockVerticalInsetMultiplier
            )
        }
        if let visualHeight = visualSurfaceHeight(
            for: block,
            availableTextWidth: availableTextWidth,
            style: style,
            blockVerticalInsetMultiplier: blockVerticalInsetMultiplier,
            contentRenderers: contentRenderers,
            resolvedContentDimensions: resolvedContentDimensions
        ) {
            return visualHeight
        }
        if case .code = block.kind {
            return codeBlockHeight(text: text, availableTextWidth: availableTextWidth, font: font, metrics: metrics)
        }
        // Parse inline code + markdown once; hidden-delimiter ranges and chip metrics both derive from it.
        let inlineCodeRanges = inlineCodeRangesForHeight(for: block, text: text)
        let markdownRanges = supportsInlineMarkdownStyling(block.kind)
            ? BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
                in: text, excluding: inlineCodeRanges.map(\.fullRange),
                fileBaseURL: fileBaseURL, inlineMarkupProviders: inlineMarkupProviders)
            : []
        return textBlockHeight(BlockInputTextHeightContext(
            text: text,
            availableTextWidth: availableTextWidth,
            font: font,
            metrics: metrics,
            hiddenDelimiterRanges: hiddenInlineDelimiterRanges(
                for: block, inlineCodeRanges: inlineCodeRanges, markdownRanges: markdownRanges),
            inlineCodeRanges: inlineCodeRanges,
            frontMatterReserve: frontMatterReserve,
            style: style,
            chipMetrics: chipHeightMetrics(
                for: block, text: text, font: font, markdownRanges: markdownRanges, provider: chipAccessoryProvider)
        ))
    }

    private static func tableBlockHeight(
        _ table: BlockInputTable,
        availableTextWidth: CGFloat,
        style: BlockInputStyle,
        metrics: BlockInputBlockItemVerticalMetrics,
        blockVerticalInsetMultiplier: CGFloat
    ) -> CGFloat {
        max(
            metrics.minimumHeight,
            BlockInputTableView.height(
                for: table,
                width: availableTextWidth,
                style: style,
                blockVerticalInsetMultiplier: blockVerticalInsetMultiplier
            )
                + (scaledTableExternalVerticalInset(for: blockVerticalInsetMultiplier) * 2)
        )
    }

    private static func frontMatterHeightReserve(for block: BlockInputBlock, blockVerticalInsetMultiplier: CGFloat) -> CGFloat {
        guard block.kind == .frontMatter else {
            return 0
        }
        return (scaledFrontMatterDividerVerticalInset(for: blockVerticalInsetMultiplier) * 2) + frontMatterDividerHeight
    }

    /// Height for blocks rendered as a standalone visual surface (image blocks and rendered content
    /// blocks such as Mermaid diagrams), or nil when the block uses a text/code surface instead.
    private static func visualSurfaceHeight(
        for block: BlockInputBlock,
        availableTextWidth: CGFloat,
        style: BlockInputStyle,
        blockVerticalInsetMultiplier: CGFloat,
        contentRenderers: BlockInputBlockContentRendererRegistry,
        resolvedContentDimensions: BlockInputImageDimensions?
    ) -> CGFloat? {
        let defaultAspectRatio = style.imageBlock.placeholderAspectRatio ?? 16.0 / 9.0
        if case let .image(image) = block.kind {
            return imageHeight(
                for: image,
                textWidth: availableTextWidth,
                defaultAspectRatio: defaultAspectRatio,
                blockVerticalInsetMultiplier: blockVerticalInsetMultiplier,
                zoomScale: Self.baseFontScale(for: style)
            )
        }
        if rendersInlineContent(block, contentRenderers: contentRenderers) {
            return renderedContentHeight(
                resolvedDimensions: resolvedContentDimensions,
                textWidth: availableTextWidth,
                defaultAspectRatio: defaultAspectRatio,
                blockVerticalInsetMultiplier: blockVerticalInsetMultiplier
            )
        }
        return nil
    }

    /// Whether the block has registered renderable content (e.g. a Mermaid diagram) that replaces its
    /// default text/code surface with a rendered diagram surface.
    static func rendersInlineContent(
        _ block: BlockInputBlock,
        contentRenderers: BlockInputBlockContentRendererRegistry
    ) -> Bool {
        guard let identifier = block.renderedContentIdentifier else {
            return false
        }
        return contentRenderers.canRender(contentIdentifier: identifier)
    }

    /// Height for a renderable content block (e.g. a Mermaid diagram).
    ///
    /// Before the async render resolves, `resolvedDimensions` is nil and the block is measured at the
    /// placeholder aspect ratio against the column width, matching the image-block fallback. Once the
    /// renderer reports dimensions, they drive the real scale-to-fit height.
    static func renderedContentHeight(
        resolvedDimensions: BlockInputImageDimensions?,
        textWidth: CGFloat,
        defaultAspectRatio: CGFloat,
        blockVerticalInsetMultiplier: CGFloat = 1
    ) -> CGFloat {
        let contentHeight = renderedContentDisplaySize(
            resolvedDimensions: resolvedDimensions,
            textWidth: textWidth,
            defaultAspectRatio: defaultAspectRatio
        ).height
        return max(44, ceil(contentHeight)) + (scaledImageExternalVerticalInset(for: blockVerticalInsetMultiplier) * 2)
    }

    static func renderedContentDisplaySize(
        resolvedDimensions: BlockInputImageDimensions?,
        textWidth: CGFloat,
        defaultAspectRatio: CGFloat
    ) -> NSSize {
        let availableWidth = max(textWidth, 120)
        let aspectRatio = max(defaultAspectRatio, 0.01)
        let sourceWidth: CGFloat
        let sourceHeight: CGFloat
        if let resolvedDimensions {
            sourceWidth = CGFloat(resolvedDimensions.width)
            sourceHeight = CGFloat(resolvedDimensions.height)
        } else {
            sourceWidth = availableWidth
            sourceHeight = availableWidth / aspectRatio
        }
        return constrainedRenderedContentDisplaySize(
            width: sourceWidth,
            height: sourceHeight,
            availableWidth: availableWidth
        )
    }

    private static func constrainedRenderedContentDisplaySize(
        width: CGFloat,
        height: CGFloat,
        availableWidth: CGFloat
    ) -> NSSize {
        let safeWidth = max(width, minimumImageDisplayDimension)
        let safeHeight = max(height, minimumImageDisplayDimension)
        let scale = min(availableWidth / safeWidth, 1)
        return NSSize(width: ceil(safeWidth * scale), height: ceil(safeHeight * scale))
    }

    private static func codeBlockHeight(
        text: String,
        availableTextWidth: CGFloat,
        font: NSFont,
        metrics: BlockInputBlockItemVerticalMetrics
    ) -> CGFloat {
        let codeWidth = max(unwrappedTextWidth(for: text, font: font), availableTextWidth)
        let horizontalScrollerReserve = codeWidth > availableTextWidth ? codeHorizontalScrollerReserve : 0
        return max(
            metrics.minimumHeight,
            textKitHeight(for: text, width: codeWidth, font: font)
                + metrics.topContentInset
                + metrics.bottomContentInset
                + horizontalScrollerReserve
                + 2
        )
    }

    private static func textBlockHeight(_ context: BlockInputTextHeightContext) -> CGFloat {
        if context.inlineCodeRanges.isEmpty,
           isShortSingleLine(context.text, likelyFitting: context.availableTextWidth, font: context.font) {
            return max(
                context.metrics.minimumHeight + context.frontMatterReserve,
                singleLineTextHeight(font: context.font)
                    + context.metrics.topContentInset
                    + context.metrics.bottomContentInset
                    + context.frontMatterReserve
                    + 2
            )
        }
        let boundingRect = (context.text as NSString).boundingRect(
            with: NSSize(width: context.availableTextWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: context.font]
        )
        let textKitHeight = textKitHeight(
            for: context.text,
            width: context.availableTextWidth,
            font: context.font,
            hiddenDelimiterRanges: context.hiddenDelimiterRanges,
            inlineCodeRanges: context.inlineCodeRanges,
            style: context.style,
            chipMetrics: context.chipMetrics
        )
        // The plain `boundingRect` ignores chip fonts and leading-icon kern, so once a chip is present the TextKit pass
        // (which applies them) is authoritative; otherwise keep the existing max with the bounding rect.
        let measuredTextHeight = context.hiddenDelimiterRanges.isEmpty && context.chipMetrics.chipContentRanges.isEmpty
            ? max(ceil(boundingRect.height), textKitHeight)
            : textKitHeight
        return max(
            context.metrics.minimumHeight + context.frontMatterReserve,
            measuredTextHeight
                + context.metrics.topContentInset
                + context.metrics.bottomContentInset
                + context.frontMatterReserve
                + chipWrapSlack(for: context)
                + 2
        )
    }

    /// Tiny slack reserved on chip-bearing blocks to absorb sub-pixel TextKit wrap-boundary rounding between the
    /// standalone height pass and the live text view. The measurement now mirrors the render pass's chip font, baseline
    /// offset, accessory kern, adjacent-whitespace kern, and hidden extension, so only a 1pt rounding guard remains.
    private static func chipWrapSlack(for context: BlockInputTextHeightContext) -> CGFloat {
        context.chipMetrics.chipContentRanges.isEmpty ? 0 : 1
    }

    private static func isShortSingleLine(_ text: String, likelyFitting width: CGFloat, font: NSFont) -> Bool {
        guard text.rangeOfCharacter(from: .newlines) == nil else {
            return false
        }
        guard text.utf16.count <= 24 else {
            return false
        }
        let conservativeCharacterWidth = max(font.pointSize * 0.75, 1)
        return CGFloat(text.utf16.count) * conservativeCharacterWidth <= width
    }

    private static func singleLineTextHeight(font: NSFont) -> CGFloat {
        let boundingRect = (" " as NSString).boundingRect(
            with: NSSize(width: 120, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return ceil(boundingRect.height)
    }

    private static func textKitHeight(
        for text: String,
        width: CGFloat,
        font: NSFont,
        hiddenDelimiterRanges: [NSRange] = [],
        inlineCodeRanges: [BlockInputInlineCodeRange] = [],
        style: BlockInputStyle = .default,
        chipMetrics: BlockInputChipHeightMetrics = BlockInputChipHeightMetrics()
    ) -> CGFloat {
        let textStorage = NSTextStorage(string: text, attributes: [.font: font])
        let layoutManager = NSLayoutManager()
        let delimiterGlyphs = hiddenDelimiterRanges.isEmpty ? nil : BlockInputDelimiterGlyphs()
        layoutManager.delegate = delimiterGlyphs
        let textContainer = NSTextContainer(size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textContainer.widthTracksTextView = false
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        let fullRange = NSRange(location: 0, length: textStorage.length)
        applyInlineCodeHeightAttributes(
            inlineCodeRanges,
            font: font,
            style: style,
            textStorage: textStorage,
            fullRange: fullRange
        )
        for delimiterRange in hiddenDelimiterRanges {
            let clampedDelimiterRange = NSIntersectionRange(delimiterRange, fullRange)
            guard clampedDelimiterRange.length > 0 else {
                continue
            }
            textStorage.addAttribute(.blockInputHiddenDelimiter, value: true, range: clampedDelimiterRange)
        }
        applyChipHeightAttributes(chipMetrics, font: font, textStorage: textStorage, fullRange: fullRange)
        return withExtendedLifetime(delimiterGlyphs) {
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            return ceil(max(usedRect.maxY, singleLineTextHeight(font: font)))
        }
    }

    /// Applies the render pass's chip-affecting attributes (chip font, leading-icon kern, adjacent-whitespace kern) to
    /// the measurement storage so standalone height layout wraps exactly like the live text view.
    private static func applyChipHeightAttributes(
        _ chipMetrics: BlockInputChipHeightMetrics,
        font: NSFont,
        textStorage: NSTextStorage,
        fullRange: NSRange
    ) {
        let chipFont = inlineChipFont(for: font)
        let baselineOffset = inlineChipBaselineOffset(baseFont: font, chipFont: chipFont)
        for range in chipMetrics.chipContentRanges {
            let clamped = NSIntersectionRange(range, fullRange)
            if clamped.length > 0 {
                // Match the render pass exactly: chip font AND baseline offset, so measured line height matches render.
                textStorage.addAttributes([.font: chipFont, .baselineOffset: baselineOffset], range: clamped)
            }
        }
        for kern in chipMetrics.accessoryKerns {
            let clamped = NSIntersectionRange(kern.range, fullRange)
            if clamped.length > 0 {
                // The Bool marker keeps the delimiter glyph (the glyph delegate skips null-glyphing accessory chars).
                textStorage.addAttributes([.kern: kern.advance, .blockInputChipLeadingAccessory: true], range: clamped)
            }
        }
        for range in chipMetrics.adjacentSpacerRanges {
            let clamped = NSIntersectionRange(range, fullRange)
            if clamped.length > 0 {
                textStorage.addAttribute(.kern, value: inlineChipAdjacentWhitespaceKern, range: clamped)
            }
        }
        for range in chipMetrics.hiddenLabelRanges {
            let clamped = NSIntersectionRange(range, fullRange)
            if clamped.length > 0 {
                textStorage.addAttribute(.blockInputHiddenDelimiter, value: true, range: clamped)
            }
        }
    }

    private static func inlineCodeRangesForHeight(for block: BlockInputBlock, text: String) -> [BlockInputInlineCodeRange] {
        guard supportsInlineCodeStyling(block.kind) else {
            return []
        }
        return BlockInputCodeParsing.inlineCodeRanges(in: text)
    }

    private static func applyInlineCodeHeightAttributes(
        _ inlineCodeRanges: [BlockInputInlineCodeRange],
        font: NSFont,
        style: BlockInputStyle,
        textStorage: NSTextStorage,
        fullRange: NSRange
    ) {
        guard !inlineCodeRanges.isEmpty else {
            return
        }
        let inlineFont = inlineCodeFont(for: font, style: style)
        let delimiterFont = inlineCodeDelimiterFont(for: font)
        for inlineCodeRange in inlineCodeRanges {
            let contentRange = NSIntersectionRange(inlineCodeRange.contentRange, fullRange)
            if contentRange.length > 0 {
                textStorage.addAttribute(.font, value: inlineFont, range: contentRange)
            }
            for delimiterRange in inlineCodeRange.delimiterRanges {
                let clampedDelimiterRange = NSIntersectionRange(delimiterRange, fullRange)
                guard clampedDelimiterRange.length > 0 else {
                    continue
                }
                textStorage.addAttribute(.font, value: delimiterFont, range: clampedDelimiterRange)
            }
        }
    }

    /// Hidden-delimiter ranges derived from already-parsed inline ranges (no re-parse). Empty for non-text kinds.
    private static func hiddenInlineDelimiterRanges(
        for block: BlockInputBlock,
        inlineCodeRanges: [BlockInputInlineCodeRange],
        markdownRanges: [BlockInputInlineMarkdownRange]
    ) -> [NSRange] {
        switch block.kind {
        case .paragraph, .heading, .quote, .bulletedListItem, .numberedListItem, .checklistItem:
            return (inlineCodeRanges.flatMap(\.delimiterRanges) + markdownRanges.flatMap(\.delimiterRanges))
                .sorted { $0.location < $1.location }
        case .code, .horizontalRule, .frontMatter, .table, .image, .rawMarkdown:
            return []
        }
    }

    /// Chip-related attributes that affect text wrapping, so height measurement matches the render pass.
    ///
    /// `chipContentRanges` get the monospaced chip font (the label renders smaller/wider than base text), and
    /// `accessoryKerns` reserve the file-chip leading/trailing accessory advances. Both shift where chips wrap.
    private static func chipHeightMetrics(
        for block: BlockInputBlock,
        text: String,
        font: NSFont,
        markdownRanges: [BlockInputInlineMarkdownRange],
        provider: ((BlockInputChipContext) -> BlockInputChipAccessory?)?
    ) -> BlockInputChipHeightMetrics {
        guard supportsInlineMarkdownStyling(block.kind) else {
            return BlockInputChipHeightMetrics()
        }
        var metrics = BlockInputChipHeightMetrics()
        for markdownRange in markdownRanges {
            guard let chipKind = markdownRange.inlineChipKind(in: text) else {
                continue
            }
            // The render pass draws every chip label in the smaller monospaced chip font, which changes wrapping;
            // measure with the same font so the row reserves the right number of lines.
            metrics.chipContentRanges.append(markdownRange.contentRange)
            metrics.adjacentSpacerRanges.append(contentsOf: chipAdjacentSpacerRanges(for: markdownRange, in: text))
            guard chipKind == .fileLink,
                  let provider,
                  markdownRange.contentRange.location > 0,
                  let destination = markdownRange.linkDestination,
                  let accessory = provider(BlockInputChipContext(destination: destination, label: markdownRange.linkLabel(in: text))) else {
                continue
            }
            if accessory.reservedWidth > 0 {
                metrics.accessoryKerns.append(
                    (NSRange(location: markdownRange.contentRange.location - 1, length: 1), accessory.reservedWidth)
                )
            }
            // Mirror the render-pass guard: only reserve trailing width when there is a draw closure to paint it.
            if accessory.trailingReservedWidth > 0, accessory.drawTrailing != nil {
                metrics.accessoryKerns.append(
                    (NSRange(location: NSMaxRange(markdownRange.contentRange), length: 1), accessory.trailingReservedWidth)
                )
            }
            if accessory.hidesLabelExtension,
               let hiddenRange = chipHiddenExtensionRange(in: text, contentRange: markdownRange.contentRange) {
                metrics.hiddenLabelRanges.append(hiddenRange)
            }
        }
        return metrics
    }

    /// Whitespace characters flanking a chip that the render pass widens with `.kern`; included so measurement wraps
    /// at the same point.
    private static func chipAdjacentSpacerRanges(for markdownRange: BlockInputInlineMarkdownRange, in text: String) -> [NSRange] {
        let nsText = text as NSString
        return [markdownRange.fullRange.location - 1, NSMaxRange(markdownRange.fullRange)].compactMap { location in
            guard location >= 0, location < nsText.length,
                  isInlineChipAdjacentSpacerCharacter(nsText.character(at: location)) else {
                return nil
            }
            return NSRange(location: location, length: 1)
        }
    }

    private static func unwrappedTextWidth(for text: String, font: NSFont) -> CGFloat {
        text.components(separatedBy: .newlines)
            .map { line in
                let measuredLine = line.isEmpty ? " " : line
                return ceil((measuredLine as NSString).size(withAttributes: [.font: font]).width)
            }
            .max() ?? 120
    }
}

private struct BlockInputChipHeightMetrics {
    /// Chip label ranges that render in the monospaced chip font.
    var chipContentRanges: [NSRange] = []
    /// File-chip leading-icon `.kern` advances, keyed by the chip's leading `[` range.
    var accessoryKerns: [(range: NSRange, advance: CGFloat)] = []
    /// Single-character whitespace ranges flanking chips that render with extra `.kern` spacing.
    var adjacentSpacerRanges: [NSRange] = []
    /// Label ranges hidden by an accessory (e.g. a hidden file extension); null-glyphed so measurement matches render.
    var hiddenLabelRanges: [NSRange] = []
}

private struct BlockInputTextHeightContext {
    var text: String
    var availableTextWidth: CGFloat
    var font: NSFont
    var metrics: BlockInputBlockItemVerticalMetrics
    var hiddenDelimiterRanges: [NSRange]
    var inlineCodeRanges: [BlockInputInlineCodeRange]
    var frontMatterReserve: CGFloat
    var style: BlockInputStyle
    /// Chip font ranges + leading-icon kerns that the render pass applies; measuring with them keeps wrapping in sync.
    var chipMetrics = BlockInputChipHeightMetrics()
}
