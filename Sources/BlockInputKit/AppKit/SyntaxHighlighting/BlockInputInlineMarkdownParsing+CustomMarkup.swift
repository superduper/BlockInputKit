import Foundation

extension BlockInputInlineMarkdownParsing {
    /// Runs every registered custom-markup provider in registration order, folding each provider's spans into
    /// `.customMarkup` ranges.
    ///
    /// The first provider sees only inline-code exclusions; each later provider also excludes every earlier provider's
    /// claimed spans, matching the wikilink-first precedence the built-in passes already rely on. Spans are dropped
    /// defensively when they cross a newline, fall outside their own `fullRange`, intersect an excluded range, or
    /// overlap a span already claimed in this pass, so the row-local UTF-16 contract holds even for a misbehaving
    /// provider. Returned ranges are sorted by `fullRange.location` so the downstream merge stays well-ordered.
    static func customMarkupRanges(
        in text: NSString,
        swiftText: String,
        excluding excludedRangeLookup: BlockInputExcludedRangeLookup,
        providers: [any BlockInputInlineMarkupProvider]
    ) -> [BlockInputInlineMarkdownRange] {
        guard !providers.isEmpty else {
            return []
        }
        var claimedRanges = excludedRangeLookup.coveredRanges
        var ranges: [BlockInputInlineMarkdownRange] = []
        for provider in providers {
            let providerExclusionLookup = BlockInputExcludedRangeLookup(textLength: text.length, ranges: claimedRanges)
            let spans = provider.spans(in: swiftText, excluding: claimedRanges)
            for span in spans {
                guard let range = customMarkupRange(
                    for: span,
                    provider: provider,
                    textLength: text.length,
                    text: text,
                    excluding: providerExclusionLookup
                ) else {
                    continue
                }
                ranges.append(range)
                claimedRanges.append(range.fullRange)
            }
        }
        return ranges.sorted { $0.fullRange.location < $1.fullRange.location }
    }

    /// Validates one provider span against the row-local UTF-16 contract and converts it to a `.customMarkup` range.
    private static func customMarkupRange(
        for span: BlockInputInlineMarkupSpan,
        provider: any BlockInputInlineMarkupProvider,
        textLength: Int,
        text: NSString,
        excluding excludedRangeLookup: BlockInputExcludedRangeLookup
    ) -> BlockInputInlineMarkdownRange? {
        let fullRange = span.fullRange
        guard isValidCustomMarkupRange(fullRange, in: textLength),
              isValidCustomMarkupRange(span.contentRange, in: textLength),
              NSIntersectionRange(span.contentRange, fullRange) == span.contentRange,
              span.contentRange.length > 0,
              !excludedRangeLookup.intersects(fullRange),
              !customMarkupRangeCrossesNewline(fullRange, in: text) else {
            return nil
        }
        for hiddenRange in span.hiddenRanges where NSIntersectionRange(hiddenRange, fullRange) != hiddenRange {
            return nil
        }
        let identity = BlockInputInlineMarkupIdentity(
            identifier: provider.identifier,
            style: span.style,
            payload: span.payload
        )
        return BlockInputInlineMarkdownRange(
            style: .customMarkup(identity),
            fullRange: fullRange,
            contentRange: span.contentRange,
            delimiterRanges: span.hiddenRanges
        )
    }

    private static func isValidCustomMarkupRange(_ range: NSRange, in textLength: Int) -> Bool {
        range.location >= 0 && range.length >= 0 && NSMaxRange(range) <= textLength
    }

    private static func customMarkupRangeCrossesNewline(_ range: NSRange, in text: NSString) -> Bool {
        var location = range.location
        let upperBound = NSMaxRange(range)
        while location < upperBound {
            let character = text.character(at: location)
            if character == 0x0A || character == 0x0D {
                return true
            }
            location += 1
        }
        return false
    }
}
