import AppKit

/// Re-entry key for a registered async rewriter: one outstanding rewrite per `(identifier, blockID)` at a time.
struct BlockInputInlineMarkupRewriteKey: Hashable {
    let identifier: String
    let blockID: BlockInputBlockID
}

extension BlockInputView {
    /// Requests every registered async source rewriter for a mounted block, off the render hot path.
    ///
    /// Called when a block is (re)configured for display, never during attribute application or measurement. Each
    /// rewriter runs at most once at a time per `(identifier, blockID)` via `inlineMarkupRewritesInFlight`, and the
    /// awaited result is applied only when it differs from the still-current block text — both guard against re-entry
    /// and infinite loops (a rewriter that returns the same/unchanged text is a no-op).
    func requestInlineMarkupRewritesIfNeeded(for block: BlockInputBlock) {
        guard !inlineMarkupRewriters.isEmpty,
              BlockInputBlockItem.supportsInlineMarkdownStyling(block.kind) else {
            return
        }
        for rewriter in inlineMarkupRewriters {
            let key = BlockInputInlineMarkupRewriteKey(identifier: rewriter.identifier, blockID: block.id)
            guard !inlineMarkupRewritesInFlight.contains(key) else {
                continue
            }
            runInlineMarkupRewrite(rewriter, key: key, blockID: block.id, sourceText: block.text)
        }
    }

    private func runInlineMarkupRewrite(
        _ rewriter: any BlockInputInlineMarkupRewriter,
        key: BlockInputInlineMarkupRewriteKey,
        blockID: BlockInputBlockID,
        sourceText: String
    ) {
        inlineMarkupRewritesInFlight.insert(key)
        Task { @MainActor [weak self] in
            let rewritten = await rewriter.rewrittenSource(for: sourceText, blockID: blockID)
            guard let self else { return }
            self.inlineMarkupRewritesInFlight.remove(key)
            guard let rewritten, rewritten != sourceText else {
                return
            }
            self.applyInlineMarkupRewrite(
                blockID: blockID,
                sourceText: sourceText,
                rewrittenText: rewritten,
                actionName: rewriter.rewriteActionName
            )
        }
    }

    /// Applies a rewriter result as one granular, undoable mutation, re-validating that the block text is still the text
    /// the rewriter ran against so a source that drifted in flight is left untouched.
    private func applyInlineMarkupRewrite(
        blockID: BlockInputBlockID,
        sourceText: String,
        rewrittenText: String,
        actionName: String
    ) {
        guard let index = index(of: blockID),
              var block = block(at: index),
              block.text == sourceText,
              rewrittenText != sourceText else {
            return
        }
        let beforeBlock = block
        let beforeSelection = selection
        block.text = rewrittenText
        let afterSelection = clampedRewriteSelection(beforeSelection, toBlock: block)
        _ = applyGranularBlockReplacement(block, at: index, selection: afterSelection)
        undoController?.registerBlockReplacementStructuralEdit(
            actionName: actionName,
            beforeBlock: beforeBlock,
            afterBlock: block,
            selectionBefore: beforeSelection,
            selectionAfter: afterSelection
        )
    }

    private func clampedRewriteSelection(
        _ selection: BlockInputSelection?,
        toBlock block: BlockInputBlock
    ) -> BlockInputSelection? {
        guard case let .cursor(cursor)? = selection, cursor.blockID == block.id else {
            return selection
        }
        let length = (block.text as NSString).length
        return .cursor(BlockInputCursor(blockID: block.id, utf16Offset: min(cursor.utf16Offset, length)))
    }
}
