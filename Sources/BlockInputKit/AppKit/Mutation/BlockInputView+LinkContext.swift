import AppKit

extension BlockInputView {
    /// Builds an edit context from the captured visual hit before falling back to raw event/insertion geometry.
    func clickedLinkContext(
        blockID: BlockInputBlockID,
        block: BlockInputBlock,
        item: BlockInputBlockItem?,
        clickedLinkRange: BlockInputInlineMarkdownRange?,
        event: NSEvent?
    ) -> BlockInputLinkContext? {
        if let clickedLinkRange {
            return linkEditContext(
                blockID: blockID,
                block: block,
                item: item,
                linkRange: clickedLinkRange,
                sourceRange: NSRange(location: clickedLinkRange.contentRange.location, length: 0)
            )
        }
        guard let event,
              let clickedChipRange = item?.inlineChipRange(atWindowLocation: event.locationInWindow) else {
            return nil
        }
        return linkEditContext(
            blockID: blockID,
            block: block,
            item: item,
            linkRange: clickedChipRange,
            sourceRange: NSRange(location: clickedChipRange.contentRange.location, length: 0)
        )
    }

    func linkEditContext(
        blockID: BlockInputBlockID,
        block: BlockInputBlock,
        item: BlockInputBlockItem?,
        linkRange: BlockInputInlineMarkdownRange,
        sourceRange: NSRange
    ) -> BlockInputLinkContext {
        BlockInputLinkContext(
            blockID: blockID,
            mode: .edit(linkRange),
            sourceRange: sourceRange,
            sourceText: block.text,
            anchorWindowRect: item?.anchorWindowRect(forUTF16Range: linkRange.contentRange) ?? .zero
        )
    }
}
