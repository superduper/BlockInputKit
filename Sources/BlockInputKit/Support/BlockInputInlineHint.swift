import Foundation

/// Visual-only hint text drawn inline with the active block editor.
public struct BlockInputInlineHint: Equatable, Sendable {
    /// Hint text to draw after the active caret.
    public var text: String

    /// Creates an inline hint.
    public init(text: String) {
        self.text = text
    }
}

/// Context supplied when the editor asks the host for an inline hint.
public struct BlockInputInlineHintContext {
    /// Editor requesting the hint.
    public var editorView: BlockInputView
    /// Block that owns the active collapsed selection.
    public var block: BlockInputBlock
    /// Loaded document index for `block`.
    public var blockIndex: Int
    /// Active collapsed cursor.
    public var cursor: BlockInputCursor
    /// AppKit selected range for the focused text view.
    public var selectedRange: NSRange
    /// Whether `block` is the first loaded block in the document.
    public var isDocumentStartBlock: Bool
    /// Whether the active cursor is at UTF-16 offset zero in the first loaded block.
    public var isAtDocumentStart: Bool

    /// Creates inline hint context for a focused block.
    public init(
        editorView: BlockInputView,
        block: BlockInputBlock,
        blockIndex: Int,
        cursor: BlockInputCursor,
        selectedRange: NSRange,
        isDocumentStartBlock: Bool,
        isAtDocumentStart: Bool
    ) {
        self.editorView = editorView
        self.block = block
        self.blockIndex = blockIndex
        self.cursor = cursor
        self.selectedRange = selectedRange
        self.isDocumentStartBlock = isDocumentStartBlock
        self.isAtDocumentStart = isAtDocumentStart
    }
}

/// Host hook that can provide visual-only inline hints for the active editor line.
public typealias BlockInputInlineHintProvider = @MainActor (BlockInputInlineHintContext) -> BlockInputInlineHint?
