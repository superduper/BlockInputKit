import Foundation

/// Inline-markup termination for mid-block Return splits.
///
/// When the caret splits a block inside an open inline-markdown span (e.g. `**bold|text**`), a naive
/// substring split leaves both halves with unbalanced delimiters: prefix `**bold` and suffix `text**`.
/// `BlockInputInlineMarkupSplitTermination` re-balances both halves by CLOSING every straddled span at
/// the end of the prefix and RE-OPENING it at the start of the suffix, preserving nesting order.
///
/// Caret rule: the new suffix block keeps the caret at the start of the *visible* content, i.e. AFTER any
/// reopened opening delimiters. This lets the user keep typing inside the still-open span. When no span
/// straddles the split, no delimiters are prepended and the caret stays at offset 0 (prior behavior).
enum BlockInputInlineMarkupSplitTermination {
    /// Prefix/suffix text plus the caret offset to use inside the suffix block.
    struct Result: Equatable {
        let prefix: String
        let suffix: String
        /// UTF-16 offset of the caret inside `suffix`, past any reopened opening delimiters.
        let suffixCaretOffset: Int
    }

    /// Balances the inline markup around a split.
    ///
    /// - Parameters:
    ///   - text: The full source text of the block being split.
    ///   - splitOffset: UTF-16 caret offset; the prefix is `text[0..<splitOffset]`.
    ///   - replacementLength: UTF-16 length of the selection consumed by the break; the suffix starts at
    ///     `splitOffset + replacementLength`.
    /// - Returns: The prefix/suffix text and the suffix caret offset. When nothing straddles, the prefix
    ///   and suffix are the plain substrings and the caret offset is 0.
    static func terminate(
        text: String,
        splitOffset: Int,
        replacementLength: Int
    ) -> Result {
        let textStorage = text as NSString
        let splitOffset = min(max(splitOffset, 0), textStorage.length)
        let replacementLength = min(max(replacementLength, 0), textStorage.length - splitOffset)
        let suffixStart = splitOffset + replacementLength
        let prefix = textStorage.substring(to: splitOffset)
        let suffix = textStorage.substring(from: suffixStart)

        let straddling = straddlingSpans(in: text, splitOffset: splitOffset)
        guard !straddling.isEmpty else {
            return Result(prefix: prefix, suffix: suffix, suffixCaretOffset: 0)
        }

        // Close innermost-first at the prefix end; reopen outermost-first at the suffix start so the
        // nesting order is preserved on both sides. `straddling` is sorted outermost -> innermost, so
        // closing delimiters are appended in reverse and opening delimiters prepended in order.
        let closing = straddling.reversed().map(\.closingDelimiter).joined()
        let opening = straddling.map(\.openingDelimiter).joined()
        return Result(
            prefix: prefix + closing,
            suffix: opening + suffix,
            suffixCaretOffset: (opening as NSString).length
        )
    }

    /// A rewrappable inline span and the delimiter strings used to close/reopen it.
    private struct RewrappableSpan {
        let contentRange: NSRange
        let openingDelimiter: String
        let closingDelimiter: String
    }

    /// Finds rewrappable inline spans whose CONTENT strictly straddles the split point, ordered
    /// outermost-first (earliest content start; ties — e.g. composed `***` bold+italic — broken so the
    /// shorter opening delimiter is treated as the outer span). A caret exactly on a delimiter boundary is
    /// not "strictly inside" the content and is intentionally excluded.
    private static func straddlingSpans(in text: String, splitOffset: Int) -> [RewrappableSpan] {
        rewrappableSpans(in: text)
            .filter { span in
                let content = span.contentRange
                return content.location < splitOffset && splitOffset < content.location + content.length
            }
            .sorted { lhs, rhs in
                if lhs.contentRange.location == rhs.contentRange.location {
                    return (lhs.openingDelimiter as NSString).length < (rhs.openingDelimiter as NSString).length
                }
                return lhs.contentRange.location < rhs.contentRange.location
            }
    }

    /// Rewrappable inline spans: bold/italic/underline/strikethrough markdown plus inline code.
    /// Links, custom markup, and raw slash commands are intentionally excluded — splitting a link and
    /// re-wrapping it would corrupt the destination, so those spans are left alone.
    private static func rewrappableSpans(in text: String) -> [RewrappableSpan] {
        let inlineCodeRanges = BlockInputCodeParsing.inlineCodeRanges(in: text)
        let textStorage = text as NSString
        let codeSpans = inlineCodeRanges.map { code -> RewrappableSpan in
            // Read the delimiter from the source rather than hardcoding a backtick; inline code is
            // single-backtick today, but this stays correct if that ever changes.
            let delimiter = code.delimiterRanges.first.map(textStorage.substring(with:)) ?? "`"
            return RewrappableSpan(contentRange: code.contentRange, openingDelimiter: delimiter, closingDelimiter: delimiter)
        }
        let markdownSpans = BlockInputInlineMarkdownParsing
            .inlineMarkdownRanges(in: text, excluding: inlineCodeRanges.map(\.fullRange))
            .compactMap { range -> RewrappableSpan? in
                guard let delimiters = emphasisDelimiters(for: range.style) else {
                    return nil
                }
                return RewrappableSpan(
                    contentRange: range.contentRange,
                    openingDelimiter: delimiters.opening,
                    closingDelimiter: delimiters.closing
                )
            }
        return markdownSpans + codeSpans
    }

    /// Opening/closing delimiter strings for an emphasis style, reusing `TextFormattingStyle` mappings.
    /// `***bold italic***` reports two separate `.bold`/`.italic` ranges that share the same delimiter
    /// run; each is closed/reopened with its own delimiter (`**` and `_`) so nesting is preserved.
    /// Returns `nil` for non-rewrappable styles (link/customMarkup/rawSlashCommand).
    private static func emphasisDelimiters(
        for style: BlockInputInlineMarkdownStyle
    ) -> (opening: String, closing: String)? {
        guard let shortcut = style.rewrappableShortcut else {
            return nil
        }
        let formatting = TextFormattingStyle(shortcut)
        return (formatting.openingDelimiter, formatting.closingDelimiter)
    }
}

private extension BlockInputInlineMarkdownStyle {
    /// Maps a visual emphasis style to its source-editing shortcut. Bold/italic/underline/strikethrough
    /// are safe to auto-close and reopen on a split; links, custom markup, and raw slash commands are
    /// not, so they map to `nil` and are never rewrapped.
    var rewrappableShortcut: BlockInputTextFormattingShortcut? {
        switch self {
        case .bold:
            return .bold
        case .italic:
            return .italic
        case .underline:
            return .underline
        case .strikethrough:
            return .strikethrough
        case .link, .customMarkup, .rawSlashCommand:
            return nil
        }
    }
}
