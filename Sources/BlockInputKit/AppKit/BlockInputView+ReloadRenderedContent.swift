import AppKit

extension BlockInputView {
    /// Forces the rendered-content block to re-render even though its own source text is unchanged.
    /// Needed for content that is derived from OTHER blocks (e.g. a table of contents).
    public func reloadRenderedContent(for id: BlockInputBlockID) {
        guard let index = index(of: id) else { return }
        reloadRenderedContent(atItemIndexes: [index])
    }

    /// Refreshes every rendered-content block in the document.
    public func reloadRenderedContent() {
        let indexes = (0..<blockCount).compactMap { index -> Int? in
            guard let block = block(at: index), block.renderedContentIdentifier != nil else { return nil }
            return index
        }
        reloadRenderedContent(atItemIndexes: indexes)
    }

    private func reloadRenderedContent(atItemIndexes indexes: [Int]) {
        guard !indexes.isEmpty else { return }
        for index in indexes {
            let indexPath = IndexPath(item: index, section: 0)
            if let item = collectionView.item(at: indexPath) as? BlockInputBlockItem {
                item.invalidateRenderedContentCache()
            }
        }
        collectionView.reloadItems(at: Set(indexes.map { IndexPath(item: $0, section: 0) }))
    }
}
