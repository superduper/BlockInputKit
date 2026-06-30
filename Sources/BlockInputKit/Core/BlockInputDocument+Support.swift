extension BlockInputDocument {
    func detachedStorage() -> Self {
        // Keep editor-owned snapshots from sharing copy-on-write array storage
        // with large host stores; per-block edits should not copy every block.
        BlockInputDocument(blocks: blocks.map { $0 })
    }
}

public extension BlockInputBlock {
    /// Creates a new empty paragraph block.
    static func emptyParagraph() -> Self {
        BlockInputBlock(kind: .paragraph)
    }
}

struct BlockInputMoveResult: Equatable, Sendable {
    var selection: BlockInputSelection
    var changedBlocks: [BlockInputBlock]
    var finalIndex: Int
}
