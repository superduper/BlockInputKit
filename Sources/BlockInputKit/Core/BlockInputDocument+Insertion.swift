import Foundation

public extension BlockInputDocument {
    /// Inserts blocks at a clamped document index and focuses the first inserted block.
    ///
    /// Empty insertions are ignored so callers can forward parsed content without
    /// separately special-casing no-op results. Inserting at index `0` keeps
    /// existing leading frontmatter pinned before the inserted blocks.
    @discardableResult
    mutating func insertBlocks(
        _ insertedBlocks: [BlockInputBlock],
        at index: Int
    ) -> BlockInputSelection? {
        guard let firstBlock = insertedBlocks.first else {
            return nil
        }
        let insertionIndex = Self.insertionIndexPreservingLeadingFrontMatter(index, in: blocks)
        blocks.insert(contentsOf: insertedBlocks, at: insertionIndex)
        return .cursor(BlockInputCursor(blockID: firstBlock.id, utf16Offset: 0))
    }

    /// Returns a clamped insertion index that keeps existing frontmatter document-leading.
    ///
    /// Custom stores that mutate their own block arrays should use this helper
    /// before applying granular insertion mutations. It makes index `0` mean
    /// "after leading frontmatter" when the existing document starts with
    /// frontmatter, preventing store implementations from drifting away from the
    /// model's canonical frontmatter placement.
    static func insertionIndexPreservingLeadingFrontMatter(
        _ index: Int,
        in blocks: [BlockInputBlock]
    ) -> Int {
        let clampedIndex = min(max(index, 0), blocks.count)
        guard clampedIndex == 0,
              blocks.first?.kind == .frontMatter else {
            return clampedIndex
        }
        return 1
    }
}
