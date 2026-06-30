import AppKit

/// Public facade over the built-in lite code highlighter, so downstream targets (e.g. a host's plain-text
/// code editor) can syntax-highlight a snippet without reaching into the editor's internals.
@MainActor
public enum BlockInputCodeHighlighting {
    /// Returns a syntax-highlighted attributed string for `source` in the given language, themed for the
    /// supplied appearance. Unknown languages return the plain text in the base color. Regex-based and
    /// dependency-free; bounded for large inputs.
    public static func highlighted(
        _ source: String,
        language: String?,
        appearance: NSAppearance,
        font: NSFont? = nil,
        baseForegroundColor: NSColor? = nil
    ) -> NSAttributedString {
        BlockInputSyntaxHighlighter.highlighted(
            source,
            language: language,
            colorScheme: BlockInputSyntaxColorScheme(appearance: appearance),
            font: font,
            baseForegroundColor: baseForegroundColor
        )
    }
}
