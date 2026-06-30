import AppKit

extension BlockInputView {
    struct InlineExit {
        var afterBlock: BlockInputBlock
        var insertedBlocks: [BlockInputBlock]
        var insertionOffset: Int
    }

    func inlineExitForGranularReturn(
        from block: BlockInputBlock,
        selection: ReturnSelection?
    ) -> InlineExit? {
        guard block.kind.acceptsInlineReturn,
              !block.isEmpty,
              (selection?.length ?? 0) == 0,
              let offset = selection?.offset,
              let removalRange = block.emptyInlineLineRemovalRangeForReturn(utf16Offset: offset) else {
            return nil
        }
        let textStorage = block.text as NSString
        let prefix = Self.removingOneTrailingLineEnding(textStorage.substring(to: removalRange.location))
        guard !prefix.isEmpty else {
            return nil
        }
        let suffix = textStorage.substring(from: NSMaxRange(removalRange))
        var afterBlock = block
        afterBlock.text = prefix
        // Empty inline exits are composite edits: trim the current block and insert the plain paragraph that receives focus.
        var insertedBlocks = [BlockInputBlock()]
        if !suffix.isEmpty {
            var continuationBlock = block
            continuationBlock.id = .unique()
            continuationBlock.kind = inlineExitContinuationKind(for: block.kind)
            continuationBlock.text = suffix
            insertedBlocks.append(continuationBlock)
        }
        return InlineExit(afterBlock: afterBlock, insertedBlocks: insertedBlocks, insertionOffset: 1)
    }

    func performGranularReturnInlineExit(
        actionName: String,
        beforeBlock: BlockInputBlock,
        inlineExit: InlineExit,
        replacementIndex: Int
    ) -> BlockInputSelection? {
        let afterBlock = inlineExit.afterBlock
        let insertedBlocks = inlineExit.insertedBlocks
        let insertionIndex = replacementIndex + inlineExit.insertionOffset
        guard let insertedBlock = insertedBlocks.first else {
            return nil
        }
        let resolvedInsertionIndex = frontMatterPreservingInsertionIndex(
            insertionIndex,
            afterReplacing: afterBlock,
            at: replacementIndex
        )
        let beforeSelection = selection
        if canSynchronizeCacheForGranularInsertion(insertedBlockCount: insertedBlocks.count) {
            guard replaceCachedBlock(afterBlock, at: replacementIndex),
                  document.insertBlocks(insertedBlocks, at: resolvedInsertionIndex) != nil else {
                return nil
            }
        } else {
            markDocumentCacheUnsynchronized()
        }
        let afterSelection = BlockInputSelection.cursor(BlockInputCursor(blockID: insertedBlock.id, utf16Offset: 0))
        syncDocumentStore(.replaceBlock(afterBlock))
        syncDocumentStore(.insertBlocks(insertedBlocks, insertionIndex: resolvedInsertionIndex))
        applySelection(afterSelection, notify: true)
        undoController?.registerBlockReplacementInsertionStructuralEdit(BlockInputReplaceInsertEdit(
            actionName: actionName,
            beforeBlock: beforeBlock,
            afterBlock: afterBlock,
            insertedBlocks: insertedBlocks,
            insertionIndex: resolvedInsertionIndex,
            selectionBefore: beforeSelection,
            selectionAfter: afterSelection
        ))
        reloadAfterGranularInlineExit(insertedBlocks: insertedBlocks, replacementIndex: replacementIndex, insertionIndex: resolvedInsertionIndex)
        publishDocumentChange()
        return afterSelection
    }

    private func reloadAfterGranularInlineExit(
        insertedBlocks: [BlockInputBlock],
        replacementIndex: Int,
        insertionIndex: Int
    ) {
        if shouldDeferGranularCountLayout {
            reloadVisibleBlock(at: replacementIndex)
            if insertedBlocks.count == 1 {
                insertVisibleBlock(at: insertionIndex)
            } else {
                reloadDataKeepingFocus()
            }
        } else {
            // The document count changed; reload-item plus insert-item is invalid here, so rebuild the visible layout once.
            reloadDataKeepingFocus()
        }
    }

    private static func removingOneTrailingLineEnding(_ text: String) -> String {
        if text.hasSuffix("\r\n") {
            return String(text.dropLast(2))
        }
        guard text.last == "\n" || text.last == "\r" else {
            return text
        }
        return String(text.dropLast())
    }

    private func inlineExitContinuationKind(for kind: BlockInputBlockKind) -> BlockInputBlockKind {
        // Frontmatter is only meaningful at index 0, so any trailing body text split after an inserted paragraph remains raw Markdown.
        kind == .frontMatter ? .rawMarkdown : kind
    }
}
