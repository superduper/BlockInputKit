import Foundation

/// A single search hit within a document block.
///
/// The `range` is a UTF-16 source range on the owning block's ``BlockInputBlock/text``,
/// so it can be turned into a `BlockInputTextRange` directly. For table blocks the range
/// is mapped from the matched cell's visible text back to the table's Markdown source.
public struct BlockInputSearchMatch: Equatable, Sendable {
    /// Identifier of the block that contains the match.
    public let blockID: BlockInputBlockID
    /// UTF-16 source range of the match on the block's `.text`.
    public let range: NSRange

    /// Creates a search match for a block and source range.
    public init(blockID: BlockInputBlockID, range: NSRange) {
        self.blockID = blockID
        self.range = range
    }
}

/// Options controlling how ``BlockInputSearch`` matches text.
public struct BlockInputSearchOptions: Equatable, Sendable {
    /// When `false` (the default), matching ignores case.
    public var caseSensitive: Bool

    /// Creates search options.
    public init(caseSensitive: Bool = false) {
        self.caseSensitive = caseSensitive
    }

    /// Default case-insensitive plain-substring matching.
    public static let `default` = BlockInputSearchOptions()
}

/// Pure, AppKit-free document search engine.
///
/// Performs plain-substring matching (case-insensitive by default) across all
/// searchable blocks in document order. Table blocks search each cell's visible
/// text and map matches back to source ranges on the table Markdown.
public enum BlockInputSearch {
    /// Returns all matches for `query` in document order.
    ///
    /// Empty or whitespace-only queries produce no matches. Within each block,
    /// matches are returned in ascending source-location order; across blocks they
    /// follow document block order.
    public static func matches(
        in document: BlockInputDocument,
        query: String,
        options: BlockInputSearchOptions = .default
    ) -> [BlockInputSearchMatch] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        return document.blocks.flatMap { block in
            matches(in: block, query: query, options: options)
        }
    }

    private static func matches(
        in block: BlockInputBlock,
        query: String,
        options: BlockInputSearchOptions
    ) -> [BlockInputSearchMatch] {
        switch block.kind {
        case .image, .horizontalRule:
            return []
        case .table:
            return tableMatches(in: block, query: query, options: options)
        case .paragraph, .heading, .quote,
             .bulletedListItem, .numberedListItem, .checklistItem:
            // Inline-Markdown blocks: search the document as the reader sees it. A link/image
            // `[title](url)` contributes only its visible `title`/alt text; its URL, brackets, and
            // parens are excluded, so a query never matches inside a destination or the syntax.
            let excluded = inlineLinkExclusionRanges(in: block.text)
            return ranges(of: query, in: block.text, options: options)
                .filter { match in !excluded.contains { NSIntersectionRange($0, match).length > 0 } }
                .map { BlockInputSearchMatch(blockID: block.id, range: $0) }
        case .code, .frontMatter, .rawMarkdown:
            // Raw/code blocks have no inline link rendering; search their literal text.
            return ranges(of: query, in: block.text, options: options).map {
                BlockInputSearchMatch(blockID: block.id, range: $0)
            }
        }
    }

    /// Ranges within an inline-Markdown block that should NOT be matched: each link/image's full
    /// source range minus its visible title/alt content range (i.e. the brackets, parens, and the
    /// URL/destination). A match overlapping any of these is rejected so search/replace only ever
    /// touches the human-readable title.
    private static func inlineLinkExclusionRanges(in text: String) -> [NSRange] {
        let nsText = text as NSString
        guard nsText.length > 0 else {
            return []
        }
        let lookup = BlockInputExcludedRangeLookup(textLength: nsText.length, ranges: [])
        return BlockInputInlineMarkdownParsing.linkRanges(in: nsText, excluding: lookup)
            .flatMap { link in subtract(link.contentRange, from: link.fullRange) }
    }

    /// Returns the portions of `outer` that are not covered by `inner` (0, 1, or 2 ranges).
    private static func subtract(_ inner: NSRange, from outer: NSRange) -> [NSRange] {
        guard NSIntersectionRange(inner, outer).length > 0 else {
            return [outer]
        }
        var pieces: [NSRange] = []
        if inner.location > outer.location {
            pieces.append(NSRange(location: outer.location, length: inner.location - outer.location))
        }
        let innerEnd = NSMaxRange(inner)
        let outerEnd = NSMaxRange(outer)
        if innerEnd < outerEnd {
            pieces.append(NSRange(location: innerEnd, length: outerEnd - innerEnd))
        }
        return pieces
    }

    private static func tableMatches(
        in block: BlockInputBlock,
        query: String,
        options: BlockInputSearchOptions
    ) -> [BlockInputSearchMatch] {
        // Fall back to searching the raw block text when reconstruction fails, so a
        // malformed table still yields hits instead of silently disappearing.
        guard let table = BlockInputTable(markdown: block.text) else {
            return ranges(of: query, in: block.text, options: options).map {
                BlockInputSearchMatch(blockID: block.id, range: $0)
            }
        }
        var matches: [BlockInputSearchMatch] = []
        for position in table.searchCellPositions {
            guard let cell = table.cell(at: position) else {
                continue
            }
            for localRange in ranges(of: query, in: cell.text, options: options) {
                guard let sourceRange = table.sourceRange(forLocalRange: localRange, in: position) else {
                    continue
                }
                matches.append(BlockInputSearchMatch(blockID: block.id, range: sourceRange))
            }
        }
        return matches.sorted { $0.range.location < $1.range.location }
    }

    private static func ranges(
        of query: String,
        in text: String,
        options: BlockInputSearchOptions
    ) -> [NSRange] {
        let haystack = text as NSString
        guard haystack.length > 0 else {
            return []
        }
        var compareOptions: NSString.CompareOptions = [.literal]
        if !options.caseSensitive {
            compareOptions.insert(.caseInsensitive)
        }
        var results: [NSRange] = []
        var searchStart = 0
        while searchStart < haystack.length {
            let searchRange = NSRange(location: searchStart, length: haystack.length - searchStart)
            let found = haystack.range(of: query, options: compareOptions, range: searchRange)
            guard found.location != NSNotFound, found.length > 0 else {
                break
            }
            results.append(found)
            searchStart = NSMaxRange(found)
        }
        return results
    }
}

private extension BlockInputTable {
    /// Cell positions in header-then-body order for searching visible cell text.
    var searchCellPositions: [CellPosition] {
        (0..<columnCount).map { CellPosition(row: .header, column: $0) } +
            bodyRows.indices.flatMap { rowIndex in
                (0..<columnCount).map { CellPosition(row: .body(rowIndex), column: $0) }
            }
    }
}
