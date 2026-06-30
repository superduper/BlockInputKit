import AppKit

extension BlockInputView {
    /// Replaces the current active match with `replacement` as one undoable granular block edit,
    /// then recomputes matches for the same query so the active match anchors at/after the edit.
    ///
    /// Returns `false` when find is disabled, the editor is read-only, or there is no active match.
    /// The match `range` is a UTF-16 source range on the block's `.text`, so a raw
    /// `replacingCharacters` is valid for table blocks too (search ranges never touch pipes); the
    /// granular replacement reconfigures the row, re-rendering the table.
    @discardableResult
    public func replaceCurrentMatch(with replacement: String) -> Bool {
        guard findEnabled, isEditable,
              let match = findController.activeMatch,
              let beforeBlock = block(withID: match.blockID),
              let index = index(of: match.blockID) else {
            return false
        }
        var afterBlock = beforeBlock
        afterBlock.text = (beforeBlock.text as NSString).replacingCharacters(in: match.range, with: replacement)
        guard afterBlock != beforeBlock else {
            return false
        }
        let selectionBefore = selection
        _ = applyGranularBlockReplacement(afterBlock, at: index, selection: nil)
        undoController?.registerBlockReplacementStructuralEdit(
            actionName: "Replace",
            beforeBlock: beforeBlock,
            afterBlock: afterBlock,
            selectionBefore: selectionBefore,
            selectionAfter: selection
        )
        recomputeFindMatchesAfterReplace()
        return true
    }

    /// Replaces every match for the current query in one undoable edit, then recomputes matches.
    ///
    /// Replacements within each block are applied in descending source-location order so earlier
    /// offsets stay valid while building one `afterBlock` per affected block. A single affected
    /// block uses the single-block granular path; multiple blocks use the batch path with one
    /// multi-block undo entry, so a single undo reverts everything. Returns `false` when find is
    /// disabled, the editor is read-only, or there is nothing to replace.
    @discardableResult
    public func replaceAllMatches(with replacement: String) -> Bool {
        guard findEnabled, isEditable else {
            return false
        }
        refreshDocumentFromStore()
        let matches = BlockInputSearch.matches(in: document, query: findController.query)
        guard !matches.isEmpty else {
            return false
        }
        let edits = replaceAllBlockEdits(for: matches, replacement: replacement)
        guard !edits.isEmpty else {
            return false
        }
        applyReplaceAllEdits(edits)
        recomputeFindMatchesAfterReplace()
        return true
    }

    /// Recomputes matches for the current query and refreshes highlight/scrim/active overlay so the
    /// find UI reflects the post-replace document. Preserves the find field's first responder.
    private func recomputeFindMatchesAfterReplace() {
        updateFindQuery(findController.query)
    }

    /// Builds one before/after block pair per affected block by applying each block's replacements
    /// in descending source-location order.
    private func replaceAllBlockEdits(
        for matches: [BlockInputSearchMatch],
        replacement: String
    ) -> [(before: BlockInputBlock, after: BlockInputBlock)] {
        var rangesByBlock: [BlockInputBlockID: [NSRange]] = [:]
        var order: [BlockInputBlockID] = []
        for match in matches {
            if rangesByBlock[match.blockID] == nil {
                order.append(match.blockID)
            }
            rangesByBlock[match.blockID, default: []].append(match.range)
        }
        return order.compactMap { blockID in
            guard let beforeBlock = block(withID: blockID) else {
                return nil
            }
            var text = beforeBlock.text as NSString
            let descendingRanges = (rangesByBlock[blockID] ?? []).sorted { $0.location > $1.location }
            for range in descendingRanges {
                text = text.replacingCharacters(in: range, with: replacement) as NSString
            }
            var afterBlock = beforeBlock
            afterBlock.text = text as String
            return beforeBlock != afterBlock ? (beforeBlock, afterBlock) : nil
        }
    }

    /// Applies the collected block edits as one undoable mutation (single- or multi-block path).
    private func applyReplaceAllEdits(_ edits: [(before: BlockInputBlock, after: BlockInputBlock)]) {
        let selectionBefore = selection
        let afterBlocks = edits.map(\.after)
        if edits.count == 1, let edit = edits.first, let index = index(of: edit.after.id) {
            _ = applyGranularBlockReplacement(edit.after, at: index, selection: nil)
            undoController?.registerBlockReplacementStructuralEdit(
                actionName: "Replace All",
                beforeBlock: edit.before,
                afterBlock: edit.after,
                selectionBefore: selectionBefore,
                selectionAfter: selection
            )
            return
        }
        _ = applyGranularBlockReplacements(afterBlocks, selection: nil)
        undoController?.registerMultiBlockReplacementStructuralEdit(BlockInputMultiBlockReplacementEdit(
            actionName: "Replace All",
            beforeBlocks: edits.map(\.before),
            afterBlocks: afterBlocks,
            selectionBefore: selectionBefore,
            selectionAfter: selection
        ))
    }
}
