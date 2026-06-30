import AppKit

extension BlockInputView {
    /// Focuses the editor like a single text field, preserving valid current selections.
    public func focusEditor() {
        refreshDocumentFromStore()
        if tableKeyboardRowSelection != nil {
            if !isBecomingFirstResponder, window?.firstResponder !== self {
                window?.makeFirstResponder(self)
            }
            publishFocusChange(true)
            return
        }
        if let selection, containsValidSelection(selection) {
            restoreVisibleSelection()
            if isEditorFirstResponder {
                publishFocusChange(true)
            }
            return
        }
        let cursor = pendingFocus ?? cursorForRestoredFocus()
        focus(blockID: cursor.blockID, utf16Offset: cursor.utf16Offset)
    }

    var isEditorFirstResponder: Bool {
        guard let firstResponder = window?.firstResponder else {
            return false
        }
        if firstResponder === self {
            return true
        }
        var candidateView = firstResponder as? NSView
        while let view = candidateView {
            if view === self {
                return true
            }
            candidateView = view.superview
        }
        return false
    }

    var activeBlockID: BlockInputBlockID? {
        let candidateID: BlockInputBlockID?
        switch selection {
        case let .cursor(cursor):
            candidateID = cursor.blockID
        case let .text(range):
            candidateID = range.blockID
        case let .blocks(ids):
            // Store-backed documents can change under an existing multi-block selection.
            // Keep commands anchored to the last interaction point when possible.
            if let lastFocusedBlockID,
               ids.contains(lastFocusedBlockID),
               index(of: lastFocusedBlockID) != nil {
                return lastFocusedBlockID
            }
            if let validBlockID = ids.first(where: { index(of: $0) != nil }) {
                return validBlockID
            }
            candidateID = nil
        case let .mixed(selection):
            candidateID = selection.leadingTextRange?.blockID
                ?? selection.trailingTextRange?.blockID
                ?? selection.blockIDs.first
        case nil:
            candidateID = lastFocusedBlockID
        }
        if let candidateID, index(of: candidateID) != nil {
            return candidateID
        }
        return block(at: 0)?.id
    }

    func cursorForRestoredFocus() -> BlockInputCursor {
        if let cursor = pendingFocus, index(of: cursor.blockID) != nil {
            return cursor
        }
        if selection != nil,
           let blockID = activeBlockID,
           let block = block(withID: blockID) {
            return BlockInputCursor(blockID: blockID, utf16Offset: block.cursorUTF16Length)
        }
        if let lastFocusedBlockID, let block = block(withID: lastFocusedBlockID) {
            return BlockInputCursor(blockID: lastFocusedBlockID, utf16Offset: block.cursorUTF16Length)
        }
        let firstBlock = block(at: 0) ?? document.blocks[0]
        return BlockInputCursor(blockID: firstBlock.id, utf16Offset: 0)
    }

    @discardableResult
    func resignEditorFocus() -> Bool {
        guard isEditorFirstResponder else {
            return true
        }
        window?.endEditing(for: nil)
        let didResign = window?.makeFirstResponder(nil) ?? false
        let isResigned = !isEditorFirstResponder
        if didResign || isResigned {
            publishFocusLossIfNeeded()
        }
        return didResign || isResigned
    }

    func publishFocusChange(_ isFocused: Bool) {
        guard publishedFocusState != isFocused else {
            return
        }
        publishedFocusState = isFocused
        onFocusChange?(isFocused)
        if !isFocused {
            dismissSelectionOverlay()
        }
    }

    func publishFocusLossIfNeeded() {
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !isEditorFirstResponder else {
                return
            }
            publishFocusChange(false)
        }
    }

    func visibleItem(
        for blockID: BlockInputBlockID,
        refreshConfiguration: Bool = true
    ) -> BlockInputBlockItem? {
        guard let index = index(of: blockID),
              let block = block(at: index) else {
            return nil
        }
        let indexPath = IndexPath(item: index, section: 0)
        if indexPath.item >= collectionView.numberOfItems(inSection: indexPath.section) {
            collectionView.reloadData()
            collectionView.layoutSubtreeIfNeeded()
        }
        guard indexPath.item < collectionView.numberOfItems(inSection: indexPath.section) else {
            return nil
        }
        collectionView.scrollToItems(at: [indexPath], scrollPosition: .nearestVerticalEdge)
        collectionView.layoutSubtreeIfNeeded()
        guard let item = collectionView.item(at: indexPath) as? BlockInputBlockItem else {
            return nil
        }
        if refreshConfiguration {
            configureBlockItem(item, block: block, blockIndex: index)
        }
        return item
    }

    func focusVisibleItem(for cursor: BlockInputCursor) {
        let isImageCursor = block(withID: cursor.blockID)?.kind.isImage == true
        guard let item = isImageCursor
            ? visibleImageItem(for: cursor.blockID)
            : visibleItem(for: cursor.blockID) else {
            pendingFocus = cursor
            return
        }
        if isImageCursor {
            item.setImageCaretOffset(cursor.utf16Offset)
            if !isBecomingFirstResponder, window?.firstResponder !== self {
                window?.makeFirstResponder(self)
            }
            pendingFocus = nil
            return
        }
        item.focusText(atUTF16Offset: cursor.utf16Offset)
        pendingFocus = nil
    }

    private func visibleImageItem(for blockID: BlockInputBlockID) -> BlockInputBlockItem? {
        guard let index = activeStandaloneBlockIndex(for: blockID),
              block(at: index)?.kind.isImage == true else {
            return nil
        }
        let indexPath = IndexPath(item: index, section: 0)
        collectionView.scrollToItems(at: [indexPath], scrollPosition: .nearestVerticalEdge)
        collectionView.layoutSubtreeIfNeeded()
        return collectionView.item(at: indexPath) as? BlockInputBlockItem
    }

    func restoreVisibleBlockSelection(_ blockIDs: [BlockInputBlockID]) {
        if let firstBlockID = blockIDs.first {
            _ = visibleItem(for: firstBlockID, refreshConfiguration: false)
        }
        if !isBecomingFirstResponder, window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }
        updateVisibleBlockSelectionHighlights()
    }

    func restoreVisibleSelection() {
        if restoreVisibleSelectionPreservingFindBarFocusIfNeeded() {
            return
        }
        switch selection {
        case let .cursor(cursor):
            focusVisibleItem(for: cursor)
        case let .text(textRange):
            restoreVisibleTextSelection(textRange)
        case let .blocks(blockIDs):
            restoreVisibleBlockSelection(blockIDs)
        case let .mixed(selection):
            restoreVisibleBlockSelection(selectedBlockIDs(in: selection))
        case nil:
            break
        }
    }

    func moveCaretToDocumentBoundary(_ direction: BlockInputVerticalMovementDirection) -> Bool {
        refreshDocumentFromStore()
        let targetIndex = direction == .upward ? 0 : blockCount - 1
        guard let block = block(at: targetIndex) else {
            return false
        }
        if block.kind == .horizontalRule {
            applySelection(.blocks([block.id]), notify: true)
            scrollBlockToVisible(at: targetIndex, direction: direction)
            window?.makeFirstResponder(self)
            publishFocusChange(true)
            return true
        }
        focus(blockID: block.id, utf16Offset: direction == .upward ? 0 : block.cursorUTF16Length)
        return true
    }

    private func scrollBlockToVisible(at index: Int, direction: BlockInputVerticalMovementDirection) {
        let scrollPosition: NSCollectionView.ScrollPosition = direction == .upward ? .top : .bottom
        collectionView.scrollToItems(at: [IndexPath(item: index, section: 0)], scrollPosition: scrollPosition)
        collectionView.layoutSubtreeIfNeeded()
    }

    func restoreMountedSelection() {
        switch selection {
        case let .cursor(cursor):
            restoreMountedCursorSelection(cursor)
        case let .text(textRange):
            guard let item = mountedBlockItem(for: textRange.blockID) else {
                return
            }
            item.focusText(inUTF16Range: textRange.range)
        case let .blocks(blockIDs):
            if !blockIDs.isEmpty, !isBecomingFirstResponder, window?.firstResponder !== self {
                window?.makeFirstResponder(self)
            }
        case let .mixed(selection):
            if !selectedBlockIDs(in: selection).isEmpty, !isBecomingFirstResponder, window?.firstResponder !== self {
                window?.makeFirstResponder(self)
            }
            updateVisibleBlockSelectionHighlights()
        case nil:
            break
        }
    }

    private func restoreMountedCursorSelection(_ cursor: BlockInputCursor) {
        let item = block(withID: cursor.blockID)?.kind.isImage == true
            ? mountedImageItem(for: cursor.blockID)
            : mountedBlockItem(for: cursor.blockID)
        guard let item else {
            pendingFocus = cursor
            return
        }
        if block(withID: cursor.blockID)?.kind.isImage == true {
            item.setImageCaretOffset(cursor.utf16Offset)
            if !isBecomingFirstResponder, window?.firstResponder !== self {
                window?.makeFirstResponder(self)
            }
            pendingFocus = nil
            return
        }
        item.focusText(atUTF16Offset: cursor.utf16Offset)
        pendingFocus = nil
    }

    func restoreCursorSelectionIfNeeded(on item: BlockInputBlockItem, block: BlockInputBlock) {
        let cursor: BlockInputCursor?
        if pendingFocus?.blockID == block.id {
            cursor = pendingFocus
        } else if case let .cursor(selectionCursor) = selection,
                  selectionCursor.blockID == block.id {
            cursor = selectionCursor
        } else {
            cursor = nil
        }
        guard let cursor else {
            return
        }
        if block.kind.isImage {
            item.setImageCaretOffset(cursor.utf16Offset)
            if !isBecomingFirstResponder, window?.firstResponder !== self {
                window?.makeFirstResponder(self)
            }
            if pendingFocus == cursor {
                pendingFocus = nil
            }
            return
        }
        item.focusText(atUTF16Offset: cursor.utf16Offset)
        if pendingFocus == cursor {
            pendingFocus = nil
        }
    }

    private func mountedImageItem(for blockID: BlockInputBlockID) -> BlockInputBlockItem? {
        guard let index = activeStandaloneBlockIndex(for: blockID),
              block(at: index)?.kind.isImage == true else {
            return nil
        }
        return collectionView.item(at: IndexPath(item: index, section: 0)) as? BlockInputBlockItem
    }

    func mountedBlockItem(for blockID: BlockInputBlockID) -> BlockInputBlockItem? {
        guard let index = index(of: blockID),
              let block = block(at: index) else {
            return nil
        }
        let indexPath = IndexPath(item: index, section: 0)
        guard let item = collectionView.item(at: indexPath) as? BlockInputBlockItem else {
            return nil
        }
        configureBlockItem(item, block: block, blockIndex: index)
        return item
    }

    func reloadDataKeepingFocus() {
        focusRestoreGeneration += 1
        let generation = focusRestoreGeneration
        collectionView.reloadData()
        collectionView.collectionViewLayout?.invalidateLayout()
        updatePlaceholderVisibility()
        if selection != nil {
            // AppKit may recreate items either immediately or on the next pass;
            // restoring in both places keeps cursor/text selection stable.
            restoreVisibleSelection()
            DispatchQueue.main.async { [weak self] in
                guard let self, focusRestoreGeneration == generation else {
                    return
                }
                collectionView.layoutSubtreeIfNeeded()
                restoreVisibleSelection()
                updatePlaceholderVisibility()
                invalidatePreferredHeight()
            }
        }
        invalidatePreferredHeight()
    }

    func reloadDataWithoutRestoringFocus() {
        focusRestoreGeneration += 1
        collectionView.reloadData()
        collectionView.collectionViewLayout?.invalidateLayout()
        collectionView.layoutSubtreeIfNeeded()
        updatePlaceholderVisibility()
        invalidatePreferredHeight()
    }

    func clearStaleFocusState() {
        if let selection, !containsValidSelection(selection) {
            applySelection(nil, notify: true)
        }
        if let cursor = pendingFocus, !containsValidCursor(cursor) {
            pendingFocus = nil
        }
        if let lastFocusedBlockID, index(of: lastFocusedBlockID) == nil {
            self.lastFocusedBlockID = nil
        }
    }

    func applySelection(_ selection: BlockInputSelection?, notify: Bool) {
        let selection = normalizedTableSelection(selection)
        BlockInputSelectionDebug.emit("apply selection=\(String(describing: selection)) notify=\(notify)")
        dismissLinkModalIfSelectionMovedOutside(selection)
        self.selection = selection
        horizontalSelectionExpansion = nil
        tableKeyboardRowSelection = nil
        preferredNavigationX = nil
        switch selection {
        case let .cursor(cursor):
            lastFocusedBlockID = cursor.blockID
            pendingFocus = cursor
            if let selectedIndex = selectedHorizontalRuleIndex,
               block(at: selectedIndex)?.id == cursor.blockID,
               block(at: selectedIndex)?.kind.isSelectableStandaloneBlock == true {
                selectedHorizontalRuleIndex = selectedIndex
            } else {
                selectedHorizontalRuleIndex = nil
            }
            lastNativeTextSelectionExpansion = nil
            blockSelectionExpansion = nil
        case let .text(range):
            lastFocusedBlockID = range.blockID
            pendingFocus = nil
            selectedHorizontalRuleIndex = nil
            blockSelectionExpansion = nil
        case let .blocks(blockIDs):
            lastFocusedBlockID = blockIDs.first
            pendingFocus = nil
            lastNativeTextSelectionExpansion = nil
        case let .mixed(mixedSelection):
            lastFocusedBlockID = mixedSelection.leadingTextRange?.blockID
                ?? mixedSelection.trailingTextRange?.blockID
                ?? mixedSelection.blockIDs.first
            pendingFocus = nil
            selectedHorizontalRuleIndex = nil
            lastNativeTextSelectionExpansion = nil
        case nil:
            pendingFocus = nil
            selectedHorizontalRuleIndex = nil
            lastNativeTextSelectionExpansion = nil
            blockSelectionExpansion = nil
        }
        if notify {
            onSelectionChange?(selection)
        }
        updateVisibleBlockSelectionHighlights()
        updateInlineHintsForVisibleItems()
        updateSelectionOverlayForCurrentSelection()
    }

    func isBlockSelected(_ blockID: BlockInputBlockID) -> Bool {
        guard let blockIDs = selection?.wholeSelectedBlockIDs else {
            return false
        }
        return blockIDs.contains(blockID)
    }

    var selectedBlockCount: Int {
        selection?.wholeSelectedBlockIDs.count ?? 0
    }

    private func updateVisibleBlockSelectionHighlights() {
        let activeImageCursorIndex = activeImageCursorIndexForSelection()
        for item in collectionView.visibleItems().compactMap({ $0 as? BlockInputBlockItem }) {
            guard let blockID = item.representedBlockID else {
                item.setBlockSelection(false)
                item.setImageCaretOffset(nil)
                continue
            }
            item.setBlockSelection(isBlockSelected(blockID))
            if case let .cursor(cursor) = selection,
               cursor.blockID == blockID,
               activeImageCursorIndex == collectionView.indexPath(for: item)?.item {
                item.setImageCaretOffset(cursor.utf16Offset)
            } else {
                item.setImageCaretOffset(nil)
            }
            if let range = selection?.partialTextRange(for: blockID) {
                item.setSelectionHighlightRange(range.range)
            } else if let range = selection?.textRange(for: blockID) {
                item.setFocusedTextSelectionHighlightRange(range.range)
            } else if shouldCollapseNativeTextSelection(in: blockID) {
                // Editor-level selections use custom row chrome. Collapse any leftover AppKit range so an inactive
                // gray `NSTextView` selection cannot drift over the blue multi-selection background.
                item.collapseNativeSelectionIfNeeded()
            }
        }
    }

    private func activeImageCursorIndexForSelection() -> Int? {
        guard case let .cursor(cursor) = selection,
              block(withID: cursor.blockID)?.kind.isImage == true else {
            return nil
        }
        return activeStandaloneBlockIndex(for: cursor.blockID)
    }

    private func shouldCollapseNativeTextSelection(in blockID: BlockInputBlockID) -> Bool {
        switch selection {
        case .blocks, .mixed, nil:
            return true
        case let .cursor(cursor):
            return cursor.blockID != blockID
        case let .text(textRange):
            return textRange.blockID != blockID
        }
    }

    private func selectedBlockIDs(in selection: BlockInputMixedSelection) -> [BlockInputBlockID] {
        var blockIDs = selection.blockIDs
        if let blockID = selection.leadingTextRange?.blockID, !blockIDs.contains(blockID) {
            blockIDs.append(blockID)
        }
        if let blockID = selection.trailingTextRange?.blockID, !blockIDs.contains(blockID) {
            blockIDs.append(blockID)
        }
        return blockIDs.sorted { lhs, rhs in
            (index(of: lhs) ?? Int.max) < (index(of: rhs) ?? Int.max)
        }
    }

    func selectOnlyVisibleBlockItem(_ selectedItem: BlockInputBlockItem) {
        for item in collectionView.visibleItems().compactMap({ $0 as? BlockInputBlockItem }) {
            item.setBlockSelection(item === selectedItem)
        }
    }
}
