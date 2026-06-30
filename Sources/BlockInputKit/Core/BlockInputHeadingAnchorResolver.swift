import Foundation

/// Maps GitHub-style heading slugs to block IDs for a document, deduplicating repeated slugs in
/// document order (`setup`, `setup-1`, `setup-2`). Built on demand from the current blocks.
public struct BlockInputHeadingAnchorResolver {
    private let slugToBlock: [String: BlockInputBlockID]

    public init(blocks: [BlockInputBlock]) {
        var map: [String: BlockInputBlockID] = [:]
        var counts: [String: Int] = [:]
        for block in blocks {
            guard case .heading = block.kind else { continue }
            let base = BlockInputHeadingSlug.make(block.text)
            guard !base.isEmpty else { continue }
            let count = counts[base, default: 0]
            counts[base] = count + 1
            let slug = count == 0 ? base : "\(base)-\(count)"
            if map[slug] == nil { map[slug] = block.id }
        }
        slugToBlock = map
    }

    public func resolve(_ slug: String) -> BlockInputBlockID? { slugToBlock[slug] }
}
