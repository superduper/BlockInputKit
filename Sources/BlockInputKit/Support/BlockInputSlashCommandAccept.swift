import Foundation

/// What the editor does when a slash-command suggestion is accepted. Content-agnostic: core never
/// learns what a command "means"; the host's `onSlashCommandAccepted` chooses one of these outcomes.
public enum BlockInputSlashCommandAcceptAction: Equatable, Sendable {
    /// Splice the suggestion's `insertionText` into the current block (the editor's default behavior).
    case insertText
    /// Remove the typed trigger token, then parse `markdown` into real blocks and insert them below
    /// the current block via `BlockInputView.insertMarkdown(_:below:)`.
    case replaceWithMarkdown(String)
    /// Consume the accept; insert nothing.
    case none
}

/// Context handed to `onSlashCommandAccepted` for an accepted slash-command suggestion.
public struct BlockInputSlashCommandAcceptContext: Sendable {
    /// The accepted suggestion (its `id` / `uri` / `title` / `insertionText` / `trigger`).
    public let suggestion: BlockInputCompletionSuggestion
    /// The block that owned the completion.
    public let blockID: BlockInputBlockID
    /// The source range the accept would replace (the typed trigger token, e.g. `/toc`).
    public let replacementRange: NSRange

    /// Creates accept-routing context for a slash-command suggestion.
    public init(
        suggestion: BlockInputCompletionSuggestion,
        blockID: BlockInputBlockID,
        replacementRange: NSRange
    ) {
        self.suggestion = suggestion
        self.blockID = blockID
        self.replacementRange = replacementRange
    }
}
