import Foundation

/// Markdown image handling used while importing Markdown into a `BlockInputDocument`.
public enum BlockInputMarkdownImageParsingMode: Equatable, Sendable {
    /// Parse Markdown and HTML image syntax into standalone image blocks.
    case imageBlocks
    /// Preserve Markdown and HTML image syntax in the surrounding source text.
    case preserveSourceText
}
