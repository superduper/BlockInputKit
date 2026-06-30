import Foundation

/// Per-style inline Markdown range groups merged into source order by the scanner.
struct BlockInputInlineMarkdownRangeGroups {
    /// Host-registered custom markup spans (e.g. the wikilink plugin's `[[...]]`), claimed before the built-in passes.
    let customMarkups: [BlockInputInlineMarkdownRange]
    let links: [BlockInputInlineMarkdownRange]
    let composedAsterisks: [BlockInputInlineMarkdownRange]
    let bold: [BlockInputInlineMarkdownRange]
    let strikethrough: [BlockInputInlineMarkdownRange]
    let underlineTags: [BlockInputInlineMarkdownRange]
    let insertTags: [BlockInputInlineMarkdownRange]
    let italicAsterisks: [BlockInputInlineMarkdownRange]
    let italicUnderscores: [BlockInputInlineMarkdownRange]

    var delimiterRanges: [NSRange] {
        nonRawGroups.flatMap { ranges in
            ranges.flatMap { $0.delimiterRanges }
        }
    }

    func including(rawSlashRanges: [BlockInputInlineMarkdownRange]) -> [[BlockInputInlineMarkdownRange]] {
        [
            customMarkups,
            links,
            rawSlashRanges,
            composedAsterisks,
            bold,
            strikethrough,
            underlineTags,
            insertTags,
            italicAsterisks,
            italicUnderscores
        ]
    }

    private var nonRawGroups: [[BlockInputInlineMarkdownRange]] {
        [
            customMarkups,
            links,
            composedAsterisks,
            bold,
            strikethrough,
            underlineTags,
            insertTags,
            italicAsterisks,
            italicUnderscores
        ]
    }
}
