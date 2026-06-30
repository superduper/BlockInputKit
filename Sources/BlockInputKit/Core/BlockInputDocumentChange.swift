import Foundation

/// Granular document mutation emitted immediately after editor-backed store changes.
public enum BlockInputDocumentChange: Equatable, Sendable {
    /// The full document was replaced.
    case replaceDocument(BlockInputDocument)
    /// One block was replaced in place.
    case replaceBlock(BlockInputBlock)
    /// Blocks were inserted at a document index.
    case insertBlocks([BlockInputBlock], index: Int)
    /// Blocks were deleted by stable ID.
    case deleteBlocks([BlockInputBlockID])
    /// One block was moved to a final document index.
    case moveBlock(BlockInputBlockID, index: Int)
    /// Numbered-list markers changed without replacing block content.
    case numberedListMarkersChanged(BlockInputNumberedListMarkerTransaction)
}
