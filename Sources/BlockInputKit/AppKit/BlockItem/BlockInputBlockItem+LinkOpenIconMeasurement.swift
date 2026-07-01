import AppKit

/// Chip-related attributes the render pass applies that affect wrapping; measuring with them keeps the height pass in
/// sync with the live text view.
struct BlockInputChipHeightMetrics {
    /// Chip label ranges that render in the monospaced chip font.
    var chipContentRanges: [NSRange] = []
    /// File-chip leading-icon `.kern` advances, keyed by the chip's leading `[` range.
    var accessoryKerns: [(range: NSRange, advance: CGFloat)] = []
    /// Single-character whitespace ranges flanking chips that render with extra `.kern` spacing.
    var adjacentSpacerRanges: [NSRange] = []
    /// Label ranges hidden by an accessory (e.g. a hidden file extension); null-glyphed so measurement matches render.
    var hiddenLabelRanges: [NSRange] = []
}

/// Inputs for one text/heading/list block's height measurement, carrying every render-time width contributor
/// (hidden delimiters, chip metrics, link-open-icon kerns) so the standalone height pass wraps like the live view.
struct BlockInputTextHeightContext {
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
    /// Trailing link-open-icon `.kern` advances the render pass reserves per link (when the open icon is shown);
    /// measuring with them keeps wrapping in sync so a wrapping link paragraph reserves the right number of lines.
    var linkOpenIconKerns: [(range: NSRange, attachment: BlockInputLinkOpenAttachment)] = []
}

extension BlockInputBlockItem {
    /// The render pass reserves a trailing link-open-icon per link: `applyLinkOpenIconIfNeeded` marks the char at
    /// `NSMaxRange(contentRange)` (the hidden trailing `]`) with `.blockInputLinkOpenIcon` + a matching `.kern`, and
    /// `BlockInputDelimiterGlyphs` KEEPS that glyph (instead of null-glyphing it) so the reserved icon gap survives.
    ///
    /// Height measurement must apply the SAME attribute + kern (see `textKitHeight`), or a wrapping link paragraph
    /// reserves one line too few and its last line clips. This returns the per-link (range, attachment) pairs to apply,
    /// mirroring the render gate exactly.
    static func linkOpenIconKerns(
        for block: BlockInputBlock,
        text: String,
        font: NSFont,
        markdownRanges: [BlockInputInlineMarkdownRange]
    ) -> [(range: NSRange, attachment: BlockInputLinkOpenAttachment)] {
        let appearance = NSApp?.effectiveAppearance ?? NSAppearance(named: .aqua) ?? NSAppearance()
        guard supportsInlineMarkdownStyling(block.kind),
              let attachment = BlockInputLinkOpenAttachment.make(font: font, appearance: appearance) else {
            return []
        }
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        var kerns: [(range: NSRange, attachment: BlockInputLinkOpenAttachment)] = []
        for markdownRange in markdownRanges {
            guard markdownRange.style.showsCustomMarkupOpenIcon,
                  markdownRange.contentRange.length > 0,
                  markdownRange.inlineChipKind(in: text) == nil else {
                continue
            }
            let iconCharacterIndex = NSMaxRange(markdownRange.contentRange)
            let iconRange = NSRange(location: iconCharacterIndex, length: 1)
            guard NSIntersectionRange(iconRange, fullRange).length == 1,
                  markdownRange.delimiterRanges.contains(where: { NSLocationInRange(iconCharacterIndex, $0) }) else {
                continue
            }
            kerns.append((range: iconRange, attachment: attachment))
        }
        return kerns
    }
}
