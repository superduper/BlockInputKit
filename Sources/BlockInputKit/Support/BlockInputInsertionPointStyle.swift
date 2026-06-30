/// Shape of the text insertion point in `BlockInputView` text blocks.
public enum BlockInputInsertionPointStyle: Equatable, Sendable {
    /// Thin vertical bar (default NSTextView behavior).
    case bar
    /// Solid block covering the width of the glyph at the cursor position (vim normal-mode style).
    case block
}
