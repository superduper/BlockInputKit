import AppKit

let inlineChipAdjacentWhitespaceKern: CGFloat = 5

extension BlockInputBlockItem {
    func applyInlineMarkdownAttributes(for block: BlockInputBlock, textStorage: NSTextStorage) {
        Self.applyInlineMarkdownAttributes(
            for: block,
            textStorage: textStorage,
            style: style,
            fileBaseURL: fileBaseURL,
            allowsAnchorLinks: allowsAnchorLinks,
            rawSlashCommandChips: rawSlashCommandChips,
            slashCommandAvailability: slashCommandAvailability,
            isDocumentStartBlock: isDocumentStartBlock,
            showsInlineLinkOpenIcon: showsInlineLinkOpenIcon,
            inlineMarkupProviders: inlineMarkupProviders,
            appearance: view.effectiveAppearance,
            chipAccessoryProvider: resolvedChipAccessoryProvider()
        )
    }

    /// Bridges the `@MainActor` host accessory resolver into the non-isolated inline pass. All inline-markdown attribute
    /// work runs on the main actor (it mutates `NSTextStorage` for a mounted row), so assuming isolation here is safe.
    private func resolvedChipAccessoryProvider() -> ((BlockInputChipContext) -> BlockInputChipAccessory?)? {
        guard let provider = inlineChipAccessoryProvider else {
            return nil
        }
        return { chipContext in MainActor.assumeIsolated { provider(chipContext) } }
    }

    static func applyInlineMarkdownAttributes(
        for block: BlockInputBlock,
        textStorage: NSTextStorage,
        style: BlockInputStyle,
        fileBaseURL: URL? = nil,
        allowsAnchorLinks: Bool = false,
        rawSlashCommandChips: Bool = false,
        slashCommandAvailability: BlockInputSlashCommandAvailability = .documentStart,
        isDocumentStartBlock: Bool = false,
        showsInlineLinkOpenIcon: Bool = false,
        inlineMarkupProviders: [any BlockInputInlineMarkupProvider] = [],
        appearance: NSAppearance = NSApp?.effectiveAppearance ?? .init(named: .aqua) ?? NSAppearance(),
        chipAccessoryProvider: ((BlockInputChipContext) -> BlockInputChipAccessory?)? = nil
    ) {
        guard Self.supportsInlineMarkdownStyling(block.kind) else {
            return
        }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let inlineCodeRanges = BlockInputCodeParsing.inlineCodeRanges(in: textStorage.string).map(\.fullRange)
        let markdownRanges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: textStorage.string,
            excluding: inlineCodeRanges,
            fileBaseURL: fileBaseURL,
            allowsAnchorLinks: allowsAnchorLinks,
            rawSlashCommandChips: rawSlashCommandChips,
            slashCommandAvailability: slashCommandAvailability,
            isDocumentStartBlock: isDocumentStartBlock,
            inlineMarkupProviders: inlineMarkupProviders
        )
        let context = BlockInputInlineMarkdownPassContext(
            textStorage: textStorage,
            style: style,
            baseFont: Self.font(for: block.kind, style: style),
            fullRange: fullRange,
            inlineCodeRanges: inlineCodeRanges,
            openIcon: BlockInputLinkOpenIconContext(shows: showsInlineLinkOpenIcon, appearance: appearance),
            chipAccessoryProvider: chipAccessoryProvider
        )
        for markdownRange in markdownRanges {
            Self.applyInlineMarkdownRangeAttributes(for: markdownRange, context: context)
        }
    }

    private static func applyInlineMarkdownRangeAttributes(
        for markdownRange: BlockInputInlineMarkdownRange,
        context: BlockInputInlineMarkdownPassContext
    ) {
        let textStorage = context.textStorage
        if let descriptor = markdownRange.style.customMarkupDescriptor {
            applyCustomMarkupAttributes(
                for: markdownRange,
                descriptor: descriptor,
                fullRange: context.fullRange,
                textStorage: textStorage,
                baseFont: context.baseFont
            )
            applyLinkOpenIconIfNeeded(for: markdownRange, context: context)
            return
        }
        let inlineChipStyle = markdownRange
            .inlineChipKind(in: textStorage.string)
            .map { context.style.inlineChipStyle(for: $0) }
        applyInlineMarkdownContentAttributes(
            for: markdownRange,
            excluding: context.inlineCodeRanges,
            fullRange: context.fullRange,
            textStorage: textStorage,
            baseFont: context.baseFont,
            inlineChipStyle: inlineChipStyle
        )
        for delimiterRange in markdownRange.delimiterRanges {
            let clampedDelimiterRange = NSIntersectionRange(delimiterRange, context.fullRange)
            guard clampedDelimiterRange.length > 0 else {
                continue
            }
            textStorage.addAttributes(
                [
                    .font: inlineMarkdownDelimiterFont(for: context.baseFont),
                    .foregroundColor: NSColor.clear,
                    .blockInputHiddenDelimiter: true
                ],
                range: clampedDelimiterRange
            )
        }
        if markdownRange.style == .link {
            applyLinkOpenIconIfNeeded(for: markdownRange, context: context)
        }
        if inlineChipStyle != nil {
            applyChipLeadingAccessoryIfNeeded(for: markdownRange, context: context)
            applyInlineChipAdjacentWhitespaceSpacers(for: markdownRange, in: textStorage)
        }
    }

    /// Decorates a file chip's leading `[` chrome character with a host-supplied leading accessory (icon, pill tag, …).
    ///
    /// Mirrors `applyLinkOpenIconIfNeeded` but at the chip's leading edge: the accessory is stored under
    /// `.blockInputChipLeadingAccessory` and a matching `.kern` reserves `reservedWidth` so the label shifts right and
    /// the host draws into the gap. When the accessory hides the extension, the label's extension characters are marked
    /// hidden (null-glyphed) like delimiters. Only file chips are decorated; the source string and its length never change.
    private static func applyChipLeadingAccessoryIfNeeded(
        for markdownRange: BlockInputInlineMarkdownRange,
        context: BlockInputInlineMarkdownPassContext
    ) {
        let textStorage = context.textStorage
        guard let provider = context.chipAccessoryProvider,
              markdownRange.inlineChipKind(in: textStorage.string) == .fileLink,
              let destination = markdownRange.linkDestination,
              markdownRange.contentRange.location > 0 else {
            return
        }
        let label = markdownRange.linkLabel(in: textStorage.string)
        guard let accessory = provider(BlockInputChipContext(destination: destination, label: label)) else {
            return
        }
        let attachment = BlockInputChipAccessoryAttachment(accessory: accessory)
        // Leading accessory rides the chip's opening `[` (the char before the visible label).
        if accessory.reservedWidth > 0 {
            let index = markdownRange.contentRange.location - 1
            applyChipAccessoryKern(
                at: index, attribute: .blockInputChipLeadingAccessory, attachment: attachment,
                kern: accessory.reservedWidth, markdownRange: markdownRange, context: context)
        }
        // Trailing accessory rides the chip's closing `]` (the first delimiter char after the visible label). Only
        // reserve when there is something to paint, so a width without a draw closure can't leave an empty gap.
        if accessory.trailingReservedWidth > 0, accessory.drawTrailing != nil {
            applyChipAccessoryKern(
                at: NSMaxRange(markdownRange.contentRange), attribute: .blockInputChipTrailingAccessory, attachment: attachment,
                kern: accessory.trailingReservedWidth, markdownRange: markdownRange, context: context)
        }
        if accessory.hidesLabelExtension,
           let extensionRange = chipHiddenExtensionRange(in: textStorage.string, contentRange: markdownRange.contentRange) {
            hideLabelExtension(in: extensionRange, context: context)
        }
    }

    /// Marks a chip's hidden-delimiter char `index` with an accessory attachment + reserved `.kern`, when that index is a
    /// real delimiter inside the block. Shared by the leading `[` and trailing `]` accessory reservations.
    private static func applyChipAccessoryKern(
        at index: Int,
        attribute: NSAttributedString.Key,
        attachment: BlockInputChipAccessoryAttachment,
        kern: CGFloat,
        markdownRange: BlockInputInlineMarkdownRange,
        context: BlockInputInlineMarkdownPassContext
    ) {
        let range = NSRange(location: index, length: 1)
        guard index >= 0,
              NSIntersectionRange(range, context.fullRange).length == 1,
              markdownRange.delimiterRanges.contains(where: { NSLocationInRange(index, $0) }) else {
            return
        }
        context.textStorage.addAttributes([attribute: attachment, .kern: kern], range: range)
    }

    /// Null-glyphs `extensionRange` so the file extension renders hidden while staying in the source.
    private static func hideLabelExtension(
        in extensionRange: NSRange,
        context: BlockInputInlineMarkdownPassContext
    ) {
        let clamped = NSIntersectionRange(extensionRange, context.fullRange)
        guard clamped.length > 0 else {
            return
        }
        context.textStorage.addAttributes(
            [.foregroundColor: NSColor.clear, .blockInputHiddenDelimiter: true],
            range: clamped
        )
    }

    /// Decorates the single trailing hidden-chrome character of a regular link or custom markup with a presentation-only
    /// "open" icon.
    ///
    /// The decorated character is the one at `NSMaxRange(contentRange)` — the `]` that closes `[label]` for a regular
    /// link, or the first hidden chrome character a custom markup hides after its visible content. It is already in
    /// `delimiterRanges` (hidden chrome marked
    /// `.blockInputHiddenDelimiter`), so the source string and its length are unchanged: no U+FFFC is inserted, only the
    /// rendering of an existing real character is repurposed. The icon descriptor is stored under the custom
    /// `.blockInputLinkOpenIcon` attribute and a matching `.kern` reserves the icon's advance; `BlockInputDelimiterGlyphs`
    /// keeps that one glyph (skips `.null`) so the reserved gap survives, and `BlockInputTextView` paints the icon into
    /// it. Inline chips (file/slash chips) are excluded: they have no separate trailing chrome to decorate.
    private static func applyLinkOpenIconIfNeeded(
        for markdownRange: BlockInputInlineMarkdownRange,
        context: BlockInputInlineMarkdownPassContext
    ) {
        let textStorage = context.textStorage
        guard context.openIcon.shows,
              markdownRange.style.showsCustomMarkupOpenIcon,
              markdownRange.contentRange.length > 0,
              markdownRange.inlineChipKind(in: textStorage.string) == nil else {
            return
        }
        let iconCharacterIndex = NSMaxRange(markdownRange.contentRange)
        let iconRange = NSRange(location: iconCharacterIndex, length: 1)
        // Only decorate when that index is a real hidden chrome character (the trailing `]`/`]]`), so we never alter
        // a visible character or run past the source.
        guard NSIntersectionRange(iconRange, context.fullRange).length == 1,
              markdownRange.delimiterRanges.contains(where: { NSLocationInRange(iconCharacterIndex, $0) }),
              let attachment = BlockInputLinkOpenAttachment.make(font: context.baseFont, appearance: context.openIcon.appearance) else {
            return
        }
        textStorage.addAttributes(
            [
                .blockInputLinkOpenIcon: attachment,
                .kern: attachment.advance
            ],
            range: iconRange
        )
        applyLinkOpenIconDecoration(for: markdownRange.style, iconRange: iconRange, in: textStorage)
    }

    /// Extends the link's underline (and the wikilink's faint background) across the kern-reserved icon gap so the painted
    /// open icon reads as part of the link rather than sitting in undecorated space.
    ///
    /// The decoration is applied to the icon-bearing hidden chrome character, whose glyph box (widened by the icon `.kern`)
    /// spans the gap the icon paints into. The chrome character keeps its clear foreground, so an explicit `.underlineColor`
    /// is set (the default underline color follows the clear foreground and would be invisible).
    private static func applyLinkOpenIconDecoration(
        for style: BlockInputInlineMarkdownStyle,
        iconRange: NSRange,
        in textStorage: NSTextStorage
    ) {
        switch style {
        case .link:
            textStorage.addAttributes(
                [
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: NSColor.linkColor
                ],
                range: iconRange
            )
        case let .customMarkup(identity):
            applyCustomMarkupOpenIconDecoration(for: identity.style, iconRange: iconRange, in: textStorage)
        default:
            break
        }
    }

    private static func applyInlineMarkdownContentAttributes(
        for markdownRange: BlockInputInlineMarkdownRange,
        excluding inlineCodeRanges: [NSRange],
        fullRange: NSRange,
        textStorage: NSTextStorage,
        baseFont: NSFont,
        inlineChipStyle: BlockInputInlineChipStyle?
    ) {
        for contentRange in markdownRange.contentRange.subtractingSorted(inlineCodeRanges) {
            let clampedContentRange = NSIntersectionRange(contentRange, fullRange)
            guard clampedContentRange.length > 0 else {
                continue
            }
            if let inlineChipStyle {
                Self.applyInlineChip(to: clampedContentRange, in: textStorage, baseFont: baseFont, style: inlineChipStyle)
            } else {
                Self.apply(markdownRange.style, to: clampedContentRange, in: textStorage, baseFont: baseFont)
            }
            if let destination = markdownRange.linkDestination {
                textStorage.addAttribute(.link, value: destination, range: clampedContentRange)
                textStorage.addAttribute(.toolTip, value: destination.absoluteString, range: clampedContentRange)
            }
        }
    }

    func inlineMarkdownStylesForCurrentSelection(in block: BlockInputBlock) -> Set<BlockInputInlineMarkdownStyle> {
        let selectedRange = textView.selectedRange()
        guard Self.supportsInlineMarkdownStyling(block.kind),
              !currentSelectionIntersectsStyledContent(inlineCodeContentRanges(for: block)) else {
            return []
        }
        let inlineCodeRanges = BlockInputCodeParsing.inlineCodeRanges(in: textView.string).map(\.fullRange)
        let markdownRanges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: textView.string,
            excluding: inlineCodeRanges,
            fileBaseURL: fileBaseURL,
            allowsAnchorLinks: allowsAnchorLinks,
            inlineMarkupProviders: inlineMarkupProviders
        )
        return Set(markdownRanges.compactMap { markdownRange in
            selectedRange.intersectsStyledContent(markdownRange.contentRange) ? markdownRange.style : nil
        })
    }

    func currentSelectionIntersectsStyledContent(_ ranges: [NSRange]) -> Bool {
        let selectedRange = textView.selectedRange()
        return ranges.contains { selectedRange.intersectsStyledContent($0) }
    }

    static func supportsInlineMarkdownStyling(_ kind: BlockInputBlockKind) -> Bool {
        switch kind {
        case .paragraph, .heading, .quote, .bulletedListItem, .numberedListItem, .checklistItem:
            return true
        case .code, .horizontalRule, .frontMatter, .table, .image, .rawMarkdown:
            return false
        }
    }

    private static func apply(
        _ style: BlockInputInlineMarkdownStyle,
        to range: NSRange,
        in textStorage: NSTextStorage,
        baseFont: NSFont
    ) {
        switch style {
        case .bold:
            applyFontTrait(.boldFontMask, to: range, in: textStorage, baseFont: baseFont)
        case .italic:
            applyFontTrait(.italicFontMask, to: range, in: textStorage, baseFont: baseFont)
        case .underline:
            textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .strikethrough:
            textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .link:
            textStorage.addAttributes(
                [
                    .foregroundColor: NSColor.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ],
                range: range
            )
        case .customMarkup:
            // Custom markups are styled over their whole range in the dedicated branch, never here.
            break
        case .rawSlashCommand:
            applyInlineChip(to: range, in: textStorage, baseFont: baseFont, style: .init())
        }
    }

    private static func applyInlineChip(
        to range: NSRange,
        in textStorage: NSTextStorage,
        baseFont: NSFont,
        style: BlockInputInlineChipStyle
    ) {
        let chipFont = inlineChipFont(for: baseFont)
        textStorage.addAttributes(
            [
                .font: chipFont,
                .foregroundColor: style.foregroundColor,
                .baselineOffset: inlineChipBaselineOffset(baseFont: baseFont, chipFont: chipFont),
                .blockInputInlineChip: true
            ],
            range: range
        )
    }

    static func inlineChipFont(for baseFont: NSFont) -> NSFont {
        .monospacedSystemFont(ofSize: max(baseFont.pointSize * 0.94, 1), weight: .regular)
    }

    static func inlineChipBaselineOffset(baseFont: NSFont, chipFont: NSFont) -> CGFloat {
        max(0, ceil(baseFont.ascender - chipFont.ascender))
    }

    private static func applyInlineChipAdjacentWhitespaceSpacers(
        for markdownRange: BlockInputInlineMarkdownRange,
        in textStorage: NSTextStorage
    ) {
        let text = textStorage.string as NSString
        [
            markdownRange.fullRange.location - 1,
            NSMaxRange(markdownRange.fullRange)
        ].forEach { location in
            guard location >= 0,
                  location < text.length,
                  Self.isInlineChipAdjacentSpacerCharacter(text.character(at: location)) else {
                return
            }
            textStorage.addAttribute(
                .kern,
                value: inlineChipAdjacentWhitespaceKern,
                range: NSRange(location: location, length: 1)
            )
        }
    }

    static func isInlineChipAdjacentSpacerCharacter(_ character: unichar) -> Bool {
        guard let scalar = UnicodeScalar(Int(character)) else {
            return false
        }
        return CharacterSet.whitespaces.contains(scalar)
    }

    private static func applyFontTrait(
        _ trait: NSFontTraitMask,
        to range: NSRange,
        in textStorage: NSTextStorage,
        baseFont: NSFont
    ) {
        var fontUpdates: [(NSFont, NSRange)] = []
        textStorage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = (value as? NSFont) ?? baseFont
            fontUpdates.append((NSFontManager.shared.convert(font, toHaveTrait: trait), subrange))
        }
        for (font, subrange) in fontUpdates {
            textStorage.addAttribute(.font, value: font, range: subrange)
        }
    }

    static func applyingInlineMarkdownStyles(
        _ styles: Set<BlockInputInlineMarkdownStyle>,
        to attributes: [NSAttributedString.Key: Any],
        baseFont: NSFont
    ) -> [NSAttributedString.Key: Any] {
        var attributes = attributes
        for style in styles.sortedByAttributeOrder {
            // Host custom markups use the descriptor-driven typing attributes, mirroring rendering.
            if let descriptor = style.customMarkupDescriptor {
                if let foregroundColor = descriptor.foregroundColor {
                    attributes[.foregroundColor] = foregroundColor
                }
                if descriptor.underlines {
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                continue
            }
            switch style {
            case .bold:
                attributes[.font] = NSFontManager.shared.convert((attributes[.font] as? NSFont) ?? baseFont, toHaveTrait: .boldFontMask)
            case .italic:
                attributes[.font] = NSFontManager.shared.convert((attributes[.font] as? NSFont) ?? baseFont, toHaveTrait: .italicFontMask)
            case .underline:
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            case .strikethrough:
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            case .link:
                attributes[.foregroundColor] = NSColor.linkColor
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            case .customMarkup, .rawSlashCommand:
                break
            }
        }
        return attributes
    }

    static func inlineMarkdownDelimiterFont(for font: NSFont) -> NSFont {
        .systemFont(ofSize: max(font.pointSize * 0.1, 1), weight: .regular)
    }
}

private extension Set where Element == BlockInputInlineMarkdownStyle {
    var sortedByAttributeOrder: [BlockInputInlineMarkdownStyle] {
        let fixedOrder: [BlockInputInlineMarkdownStyle] = [.bold, .italic, .underline, .strikethrough, .link, .rawSlashCommand]
        // Custom markups have associated identities and cannot be listed literally; append them after the fixed styles.
        let customMarkups = filter { style in
            if case .customMarkup = style { return true }
            return false
        }
        return fixedOrder.filter { contains($0) } + customMarkups
    }
}

/// Bundles whether the inline link "open" icon should be applied and the appearance used to tint it.
private struct BlockInputLinkOpenIconContext {
    let shows: Bool
    let appearance: NSAppearance
}

/// Loop-invariant inputs shared across every inline Markdown range processed in one attribute pass.
private struct BlockInputInlineMarkdownPassContext {
    let textStorage: NSTextStorage
    let style: BlockInputStyle
    let baseFont: NSFont
    let fullRange: NSRange
    let inlineCodeRanges: [NSRange]
    let openIcon: BlockInputLinkOpenIconContext
    /// Host-supplied leading file-chip accessory resolver.
    let chipAccessoryProvider: ((BlockInputChipContext) -> BlockInputChipAccessory?)?
}
