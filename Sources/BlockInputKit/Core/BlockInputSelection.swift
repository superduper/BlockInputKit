import Foundation

/// Caret position inside a single block.
public struct BlockInputCursor: Equatable, Codable, Sendable {
    /// Block that owns the caret.
    public var blockID: BlockInputBlockID
    /// UTF-16 text offset compatible with AppKit text ranges.
    public var utf16Offset: Int

    /// Creates a cursor at a UTF-16 offset inside a block.
    public init(blockID: BlockInputBlockID, utf16Offset: Int) {
        self.blockID = blockID
        self.utf16Offset = max(0, utf16Offset)
    }
}

/// Text selection range inside a single block.
public struct BlockInputTextRange: Equatable, Codable, Sendable {
    /// Block that owns the selected text.
    public var blockID: BlockInputBlockID
    /// UTF-16 range compatible with AppKit text selections.
    public var range: NSRange

    /// Creates a text selection range inside a block.
    public init(blockID: BlockInputBlockID, range: NSRange) {
        self.blockID = blockID
        self.range = range
    }
}

/// Multi-block selection with optional partial text at document-order edges.
///
/// This represents a selection that crosses block boundaries as if the editor were one Markdown document. Fully selected
/// middle blocks live in `blockIDs`, while partial edge ranges keep the selected text at the start or end block.
public struct BlockInputMixedSelection: Equatable, Codable, Sendable {
    /// Fully selected blocks between any partial text edges.
    public var blockIDs: [BlockInputBlockID]
    /// Partial selection in the first selected text block, when present.
    public var leadingTextRange: BlockInputTextRange?
    /// Partial selection in the last selected text block, when present.
    public var trailingTextRange: BlockInputTextRange?

    /// Creates a mixed selection from whole blocks and optional partial edge ranges.
    public init(
        blockIDs: [BlockInputBlockID],
        leadingTextRange: BlockInputTextRange? = nil,
        trailingTextRange: BlockInputTextRange? = nil
    ) {
        self.blockIDs = blockIDs
        self.leadingTextRange = leadingTextRange
        self.trailingTextRange = trailingTextRange
    }
}

/// Current editor selection, including whole-block selection.
public enum BlockInputSelection: Equatable, Codable, Sendable {
    /// A collapsed caret inside one block.
    case cursor(BlockInputCursor)
    /// A non-empty AppKit text range inside one block.
    case text(BlockInputTextRange)
    /// Whole-block selection for one or more selected document blocks.
    case blocks([BlockInputBlockID])
    /// Multi-block selection with optional partial text at one or both edges.
    case mixed(BlockInputMixedSelection)
}
