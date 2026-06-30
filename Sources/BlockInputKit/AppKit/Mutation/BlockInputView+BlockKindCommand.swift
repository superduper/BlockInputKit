import AppKit

extension BlockInputView {
    /// Returns `.on` when the active block already matches the requested kind, `.off` when the
    /// command can convert the active block, and `.unavailable` otherwise.
    func blockKindCommandState(_ kind: BlockInputBlockKind) -> BlockInputEditorCommandState {
        guard let blockID = currentSelectionOwnerBlockID(),
              let block = block(withID: blockID),
              kind.isBlockKindCommandTarget,
              block.kind.acceptsBlockKindCommand else {
            return .unavailable
        }
        return block.kind.matchesBlockKindCommand(kind) ? .on : .off
    }

    func canPerformBlockKindCommand(_ command: BlockInputEditorCommand) -> Bool? {
        guard case let .setBlockKind(kind) = command else {
            return nil
        }
        return blockKindCommandState(kind) != .unavailable
    }

    func performBlockKindCommand(_ command: BlockInputEditorCommand) -> Bool? {
        guard case let .setBlockKind(kind) = command else {
            return nil
        }
        return applyBlockKindCommand(kind)
    }

    /// Converts the active/owner block to the requested kind using the granular replace-plus-undo
    /// pattern. Returns `false` when there is no eligible target block or it already matches.
    ///
    /// Scope (v1): applies to the single active/owner block resolved from the current selection,
    /// even when a multi-block selection is active.
    private func applyBlockKindCommand(_ kind: BlockInputBlockKind) -> Bool {
        guard isEditable,
              kind.isBlockKindCommandTarget,
              let blockID = currentSelectionOwnerBlockID(),
              let index = index(of: blockID),
              let beforeBlock = block(at: index),
              beforeBlock.kind.acceptsBlockKindCommand,
              !beforeBlock.kind.matchesBlockKindCommand(kind) else {
            return false
        }
        let beforeSelection = selection
        var afterBlock = beforeBlock
        afterBlock.kind = kind
        let afterSelection = blockKindCommandSelection(
            before: beforeSelection,
            block: afterBlock
        )

        syncDocumentStore(.replaceBlock(afterBlock))
        _ = replaceCachedBlock(afterBlock, at: index)
        applySelection(afterSelection, notify: true)
        undoController?.registerBlockReplacementStructuralEdit(
            actionName: "Format Block",
            beforeBlock: beforeBlock,
            afterBlock: afterBlock,
            selectionBefore: beforeSelection,
            selectionAfter: afterSelection
        )
        if !reconfigureVisibleReplacement(afterBlock, at: index),
           !shouldDeferGranularCountLayout {
            collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
            collectionView.layoutSubtreeIfNeeded()
            restoreMountedSelection()
        }
        // applySelection positioned any selection overlay against the pre-reload geometry; re-anchor it
        // now that the row reflects the new kind (e.g. a heading's larger line height).
        refreshSelectionOverlayPresentation()
        publishDocumentChange()
        return true
    }

    /// Clamps the prior selection into the converted block, falling back to a caret at the block
    /// start when the previous selection did not target this block.
    private func blockKindCommandSelection(
        before selection: BlockInputSelection?,
        block: BlockInputBlock
    ) -> BlockInputSelection {
        let length = block.utf16Length
        switch selection {
        case let .cursor(cursor) where cursor.blockID == block.id:
            return .cursor(BlockInputCursor(blockID: block.id, utf16Offset: min(cursor.utf16Offset, length)))
        case let .text(textRange) where textRange.blockID == block.id:
            let location = min(textRange.range.location, length)
            let maxLength = max(0, length - location)
            let clampedRange = NSRange(location: location, length: min(textRange.range.length, maxLength))
            return .text(BlockInputTextRange(blockID: block.id, range: clampedRange))
        default:
            return .cursor(BlockInputCursor(blockID: block.id, utf16Offset: 0))
        }
    }
}

private extension BlockInputBlockKind {
    /// Block kinds whose text content can be re-tagged with a different kind in place.
    var acceptsBlockKindCommand: Bool {
        switch self {
        case .paragraph, .heading, .code, .quote, .bulletedListItem, .numberedListItem, .checklistItem:
            return true
        case .horizontalRule, .frontMatter, .table, .image, .rawMarkdown:
            return false
        }
    }

    /// Kinds that are valid conversion targets for ``BlockInputEditorCommand/setBlockKind(_:)``.
    var isBlockKindCommandTarget: Bool {
        acceptsBlockKindCommand
    }

    /// Compares kinds for toggle state, respecting heading level while ignoring numbered-list
    /// start values and checklist checked state.
    func matchesBlockKindCommand(_ other: BlockInputBlockKind) -> Bool {
        switch (self, other) {
        case let (.heading(lhsLevel), .heading(rhsLevel)):
            return lhsLevel == rhsLevel
        case (.numberedListItem, .numberedListItem):
            return true
        case (.checklistItem, .checklistItem):
            return true
        case (.code, .code):
            return true
        default:
            return self == other
        }
    }
}
