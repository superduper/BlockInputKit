import Foundation

/// Editor presentation mode for image content.
public enum BlockInputImagePresentation: Equatable, Sendable {
    /// Render `BlockInputImage` values as inline standalone image blocks.
    case inlineBlocks
    /// Insert new images as textual Markdown links and show editor-owned thumbnails in a preview strip.
    ///
    /// Prebuilt `.image` blocks remain image blocks. Pair this with
    /// `BlockInputMarkdownImageParsingMode.preserveSourceText` when loading
    /// Markdown that should keep image syntax editable as text.
    case textLinksWithPreviewStrip
}
