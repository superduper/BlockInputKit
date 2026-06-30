import AppKit
@testable import BlockInputKit

/// In-core test stand-in for the (now plugin-owned) `[[ ]] |` wikilink markup.
///
/// Core has zero wikilink grammar, so the core test suites that exercise core's generic custom-markup
/// rendering/click/open-icon/modal plumbing register THIS provider (identifier `"wikilink"`) so the destination scheme
/// stays `wikilink:` and the click kind stays `.customMarkup("wikilink")`. It mimics the real
/// `BlockInputWikilinkScanner`: visible = alias for `[[t|a]]` else target for `[[t]]`; hidden chrome = (`[[t|` + `]]`)
/// or (`[[` + `]]`); payload `primary = target`, `secondary = alias` (nil for bare). A trailing-empty alias
/// (`[[t|]]`) is treated as bare. Spans never cross a newline and skip excluded (inline-code) ranges.
struct WikilinkStandInMarkupProvider: BlockInputInlineMarkupProvider {
    let identifier = "wikilink"

    /// The exact look the built-in wikilink branch rendered, matching `BlockInputWikilinkScanner.style`.
    static var standInStyle: BlockInputInlineMarkupStyle {
        BlockInputInlineMarkupStyle(
            foregroundColor: .systemTeal,
            underlines: true,
            backgroundColor: NSColor.systemTeal.withAlphaComponent(0.12),
            showsOpenIcon: true
        )
    }

    var modalMode: BlockInputInlineMarkupModalMode? {
        BlockInputInlineMarkupModalMode(
            targetFieldLabel: "Target",
            finderTriggerID: "wikilink"
        ) { title, target in
            let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTarget.isEmpty else {
                return nil
            }
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedTitle.isEmpty || trimmedTitle == trimmedTarget {
                return "[[\(trimmedTarget)]]"
            }
            return "[[\(trimmedTarget)|\(trimmedTitle)]]"
        }
    }

    func spans(in text: String, excluding excludedRanges: [NSRange]) -> [BlockInputInlineMarkupSpan] {
        let nsText = text as NSString
        var spans: [BlockInputInlineMarkupSpan] = []
        var location = 0
        while location + 1 < nsText.length {
            guard nsText.character(at: location) == openingBracket,
                  nsText.character(at: location + 1) == openingBracket,
                  !intersects(NSRange(location: location, length: 2), excludedRanges) else {
                location += 1
                continue
            }
            let contentStart = location + 2
            guard let closing = closingLocation(in: nsText, from: contentStart, excluding: excludedRanges),
                  closing > contentStart else {
                location += 2
                continue
            }
            let innerRange = NSRange(location: contentStart, length: closing - contentStart)
            spans.append(span(in: nsText, openingLocation: location, innerRange: innerRange, closingLocation: closing))
            location = closing + 2
        }
        return spans
    }

    private func span(
        in text: NSString,
        openingLocation: Int,
        innerRange: NSRange,
        closingLocation: Int
    ) -> BlockInputInlineMarkupSpan {
        let fullRange = NSRange(location: openingLocation, length: closingLocation + 2 - openingLocation)
        let closingRange = NSRange(location: closingLocation, length: 2)
        let pipeLocation = firstPipe(in: text, range: innerRange)
        if let pipeLocation {
            let aliasStart = pipeLocation + 1
            let aliasLength = NSMaxRange(innerRange) - aliasStart
            if aliasLength > 0 {
                let target = text.substring(with: NSRange(location: innerRange.location, length: pipeLocation - innerRange.location))
                let alias = text.substring(with: NSRange(location: aliasStart, length: aliasLength))
                let leadingHidden = NSRange(location: openingLocation, length: aliasStart - openingLocation)
                return BlockInputInlineMarkupSpan(
                    fullRange: fullRange,
                    contentRange: NSRange(location: aliasStart, length: aliasLength),
                    hiddenRanges: [leadingHidden, closingRange],
                    style: Self.standInStyle,
                    payload: BlockInputInlineMarkupPayload(primary: target, secondary: alias)
                )
            }
        }
        return BlockInputInlineMarkupSpan(
            fullRange: fullRange,
            contentRange: innerRange,
            hiddenRanges: [NSRange(location: openingLocation, length: 2), closingRange],
            style: Self.standInStyle,
            payload: BlockInputInlineMarkupPayload(primary: text.substring(with: innerRange), secondary: nil)
        )
    }

    private func firstPipe(in text: NSString, range: NSRange) -> Int? {
        var location = range.location
        let upperBound = NSMaxRange(range)
        while location < upperBound {
            if text.character(at: location) == pipe {
                return location
            }
            location += 1
        }
        return nil
    }

    private func closingLocation(in text: NSString, from startLocation: Int, excluding excludedRanges: [NSRange]) -> Int? {
        var location = startLocation
        while location + 1 < text.length {
            let character = text.character(at: location)
            if character == lineFeed || character == carriageReturn {
                return nil
            }
            if character == closingBracket,
               text.character(at: location + 1) == closingBracket,
               !intersects(NSRange(location: location, length: 2), excludedRanges) {
                return location
            }
            location += 1
        }
        return nil
    }

    private func intersects(_ range: NSRange, _ ranges: [NSRange]) -> Bool {
        ranges.contains { NSIntersectionRange($0, range).length > 0 }
    }

    private let openingBracket: unichar = 0x5B
    private let closingBracket: unichar = 0x5D
    private let pipe: unichar = 0x7C
    private let lineFeed: unichar = 0x0A
    private let carriageReturn: unichar = 0x0D
}

extension WikilinkStandInMarkupProvider {
    /// Convenience for tests: the first scanned `[[...]]` markup range in `text` (registering this stand-in provider),
    /// or `nil` when there is no balanced wikilink.
    static func wikilinkRange(in text: String) -> BlockInputInlineMarkdownRange? {
        BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: text,
            excluding: BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange),
            inlineMarkupProviders: [WikilinkStandInMarkupProvider()]
        )
        .first { if case .customMarkup = $0.style { return true } else { return false } }
    }
}

/// In-core test stand-in for the (now plugin-owned) `BlockInputWikilinkTitleRewriter`.
///
/// Core has zero wikilink grammar, so the core test suites that exercise core's generic `inlineMarkupRewriters` rewrite
/// seam register THIS rewriter (identifier `"wikilink"`). It mirrors the plugin rewriter: it finds the first complete
/// bare `[[slug]]` (no `|alias`) outside inline code, resolves its title via the host closure, sanitizes the title, and
/// rewrites every still-bare matching `[[slug]]` to `[[slug|title]]`. Returning the original text (or `nil`) signals
/// "no change".
struct WikilinkStandInTitleRewriter: BlockInputInlineMarkupRewriter {
    let identifier = "wikilink"
    let rewriteActionName = "Resolve Wikilink Title"

    let resolver: @MainActor (String) async -> String?

    @MainActor
    func rewrittenSource(for text: String, blockID: BlockInputBlockID) async -> String? {
        guard let slug = Self.firstBareSlug(in: text) else {
            return nil
        }
        guard let title = await resolver(slug)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return nil
        }
        return Self.rewriting(text, matchingSlug: slug, title: title)
    }

    private static func firstBareSlug(in text: String) -> String? {
        for span in bareSpans(in: text) where !span.slug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return span.slug
        }
        return nil
    }

    private static func rewriting(_ text: String, matchingSlug slug: String, title: String) -> String {
        let bareRanges = bareSpans(in: text).filter { $0.slug == slug }.map(\.fullRange)
        guard !bareRanges.isEmpty else {
            return text
        }
        let safeSlug = sanitized(slug)
        let safeTitle = sanitized(title)
        guard !safeSlug.isEmpty, !safeTitle.isEmpty, safeTitle != safeSlug else {
            return text
        }
        let replacement = "[[\(safeSlug)|\(safeTitle)]]"
        let mutableText = NSMutableString(string: text)
        for range in bareRanges.sorted(by: { $0.location > $1.location }) {
            let clamped = NSIntersectionRange(range, NSRange(location: 0, length: mutableText.length))
            guard clamped.length == range.length else {
                continue
            }
            mutableText.replaceCharacters(in: clamped, with: replacement)
        }
        return mutableText as String
    }

    private static func sanitized(_ value: String) -> String {
        value.filter { !structuralCharacters.contains($0) }
    }

    private static func bareSpans(in text: String) -> [(fullRange: NSRange, slug: String)] {
        WikilinkStandInMarkupProvider()
            .spans(in: text, excluding: BlockInputInlineMarkupExclusions.inlineCodeRanges(in: text))
            .filter { $0.payload.secondary == nil }
            .map { (fullRange: $0.fullRange, slug: $0.payload.primary) }
    }

    private static let structuralCharacters: Set<Character> = ["[", "]", "|", "\n", "\r"]
}
