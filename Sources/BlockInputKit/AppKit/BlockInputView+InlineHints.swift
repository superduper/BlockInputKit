import AppKit

extension BlockInputView {
    func updateInlineHintsForVisibleItems() {
        for item in collectionView.visibleItems().compactMap({ $0 as? BlockInputBlockItem }) {
            guard let blockID = item.representedBlockID,
                  let block = block(withID: blockID) else {
                item.textView.clearInlineHint()
                continue
            }
            item.textView.inlineHint = inlineHint(for: item, block: block)
        }
    }

    func inlineHint(for item: BlockInputBlockItem, block: BlockInputBlock, blockIndex: Int? = nil) -> BlockInputInlineHint? {
        guard let inlineHintProvider,
              isEditable,
              BlockInputBlockItem.supportsInlineMarkdownStyling(block.kind),
              window?.firstResponder === item.textView,
              let context = inlineHintContext(for: item, block: block, blockIndex: blockIndex) else {
            return nil
        }
        let hint = inlineHintProvider(context)
        guard let text = hint?.text, !text.isEmpty else {
            return nil
        }
        return hint
    }

    private func inlineHintContext(
        for item: BlockInputBlockItem,
        block: BlockInputBlock,
        blockIndex: Int? = nil
    ) -> BlockInputInlineHintContext? {
        guard let blockIndex = blockIndex ?? collectionView.indexPath(for: item)?.item ?? index(of: block.id),
              case let .cursor(cursor) = selection,
              cursor.blockID == block.id,
              containsValidCursor(cursor) else {
            return nil
        }
        let selectedRange = item.currentSelectedRange
        guard selectedRange.length == 0,
              selectedRange.location == cursor.utf16Offset else {
            return nil
        }
        return BlockInputInlineHintContext(
            editorView: self,
            block: block,
            blockIndex: blockIndex,
            cursor: cursor,
            selectedRange: selectedRange,
            isDocumentStartBlock: blockIndex == 0,
            isAtDocumentStart: blockIndex == 0 && cursor.utf16Offset == 0
        )
    }
}
