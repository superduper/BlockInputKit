import AppKit

extension BlockInputView {
    /// Bridges the `@MainActor` accessory resolver into the non-isolated height pass; all measurement runs on main actor.
    var heightChipAccessoryProvider: ((BlockInputChipContext) -> BlockInputChipAccessory?)? {
        guard let provider = inlineChipAccessoryProvider else {
            return nil
        }
        return { chipContext in MainActor.assumeIsolated { provider(chipContext) } }
    }

    /// Resolved render dimensions for a block's content, looked up for synchronous height measurement.
    ///
    /// Populated when an async content render completes (see rendered-content reconciliation) so the
    /// next measurement pass produces the diagram's real scale-to-fit height instead of the placeholder.
    func resolvedContentDimensions(for blockID: BlockInputBlockID) -> BlockInputImageDimensions? {
        resolvedContentDimensionsByBlockID[blockID]
    }

    /// Drops resolved-dimension entries for blocks no longer in the document, so the cache can't grow
    /// unbounded across edits/document loads or hand stale dimensions to a recreated block ID.
    func pruneResolvedContentDimensions() {
        guard !resolvedContentDimensionsByBlockID.isEmpty else {
            return
        }
        let liveIDs = Set(document.blocks.map(\.id))
        resolvedContentDimensionsByBlockID = resolvedContentDimensionsByBlockID.filter { liveIDs.contains($0.key) }
    }

    func measuredBlockItemHeight(for block: BlockInputBlock, itemWidth: CGFloat) -> CGFloat {
        let textWidth = BlockInputBlockItem.measuredTextWidth(
            for: itemWidth,
            block: block,
            allowsReordering: allowsBlockReordering,
            editorHorizontalInset: editorHorizontalInset,
            style: style
        )
        return BlockInputBlockItem.height(
            for: block,
            textWidth: textWidth,
            style: style,
            fileBaseURL: fileBaseURL,
            allowsAnchorLinks: headingAnchorsEnabled || (inlineLinkClickHandler != nil),
            blockVerticalInsetMultiplier: blockVerticalInsetMultiplier,
            inlineMarkupProviders: inlineMarkupProviders,
            chipAccessoryProvider: heightChipAccessoryProvider,
            contentRenderers: blockContentRenderers,
            resolvedContentDimensions: resolvedContentDimensions(for: block.id)
        )
    }
}
