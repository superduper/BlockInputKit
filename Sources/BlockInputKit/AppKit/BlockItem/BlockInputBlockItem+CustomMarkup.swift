import AppKit

extension BlockInputBlockItem {
    /// Generic renderer for host custom markups (e.g. the wikilink plugin): styles the VISIBLE content with the
    /// descriptor's foreground/underline(+color)/background, then hides each chrome range via the proven
    /// `.blockInputHiddenDelimiter` null-glyph mechanism. Only REAL stored characters are styled or hidden — no glyph
    /// rewriting, attachments, or text substitution.
    static func applyCustomMarkupAttributes(
        for markdownRange: BlockInputInlineMarkdownRange,
        descriptor: BlockInputInlineMarkupStyle,
        fullRange: NSRange,
        textStorage: NSTextStorage,
        baseFont: NSFont
    ) {
        let clampedContentRange = NSIntersectionRange(markdownRange.contentRange, fullRange)
        guard clampedContentRange.length > 0 else {
            return
        }
        var contentAttributes: [NSAttributedString.Key: Any] = [:]
        if let foregroundColor = descriptor.foregroundColor {
            contentAttributes[.foregroundColor] = foregroundColor
        }
        if descriptor.underlines {
            contentAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            if let underlineColor = descriptor.underlineColor {
                contentAttributes[.underlineColor] = underlineColor
            }
        }
        if let backgroundColor = descriptor.backgroundColor {
            contentAttributes[.backgroundColor] = backgroundColor
        }
        if !contentAttributes.isEmpty {
            textStorage.addAttributes(contentAttributes, range: clampedContentRange)
        }
        hideCustomMarkupDelimiters(markdownRange.delimiterRanges, fullRange: fullRange, textStorage: textStorage, baseFont: baseFont)
    }

    private static func hideCustomMarkupDelimiters(
        _ delimiterRanges: [NSRange],
        fullRange: NSRange,
        textStorage: NSTextStorage,
        baseFont: NSFont
    ) {
        let delimiterFont = inlineMarkdownDelimiterFont(for: baseFont)
        for delimiterRange in delimiterRanges {
            let clampedDelimiterRange = NSIntersectionRange(delimiterRange, fullRange)
            guard clampedDelimiterRange.length > 0 else {
                continue
            }
            textStorage.addAttributes(
                [
                    .font: delimiterFont,
                    .foregroundColor: NSColor.clear,
                    .blockInputHiddenDelimiter: true
                ],
                range: clampedDelimiterRange
            )
        }
    }

    /// Extends a custom markup's underline and faint background across the kern-reserved open-icon gap using the
    /// descriptor's colors, so the painted icon reads as part of the styled span.
    static func applyCustomMarkupOpenIconDecoration(
        for descriptor: BlockInputInlineMarkupStyle,
        iconRange: NSRange,
        in textStorage: NSTextStorage
    ) {
        var attributes: [NSAttributedString.Key: Any] = [:]
        if descriptor.underlines {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attributes[.underlineColor] = descriptor.underlineColor ?? descriptor.foregroundColor ?? NSColor.labelColor
        }
        if let backgroundColor = descriptor.backgroundColor {
            attributes[.backgroundColor] = backgroundColor
        }
        guard !attributes.isEmpty else {
            return
        }
        textStorage.addAttributes(attributes, range: iconRange)
    }
}

extension BlockInputInlineMarkdownStyle {
    /// The style descriptor to render this style through the generic custom-markup renderer, or `nil` for styles that
    /// keep their own built-in rendering (only `.customMarkup` opts in).
    var customMarkupDescriptor: BlockInputInlineMarkupStyle? {
        if case let .customMarkup(identity) = self {
            return identity.style
        }
        return nil
    }

    /// Whether the open icon should attach for this style. Built-in links always attach (gated only by the editor's
    /// `showsInlineLinkOpenButton`); a custom markup attaches only when its descriptor opts in.
    var showsCustomMarkupOpenIcon: Bool {
        if case let .customMarkup(identity) = self {
            return identity.style.showsOpenIcon
        }
        return true
    }

    /// The custom-markup identity when this style is `.customMarkup`, otherwise `nil`.
    var customMarkupIdentity: BlockInputInlineMarkupIdentity? {
        if case let .customMarkup(identity) = self {
            return identity
        }
        return nil
    }

    /// Whether this style is a link-like, hit-tested span (regular link or any custom markup), so click and hover
    /// routing treat both uniformly.
    var isLinkLikeStyle: Bool {
        switch self {
        case .link, .customMarkup:
            return true
        case .bold, .italic, .underline, .strikethrough, .rawSlashCommand:
            return false
        }
    }
}
