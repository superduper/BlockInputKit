import AppKit

extension BlockInputView {
    func dispatchKeyboardShortcut(
        event: NSEvent,
        focusSource: BlockInputKeyboardShortcutFocusSource? = nil
    ) -> BlockInputKeyboardShortcutDispatchResult {
        guard !isSkippingKeyboardShortcutDispatch(for: event),
              let shortcut = BlockInputKeyboardShortcut(event: event) else {
            return .notRegistered
        }
        return dispatchKeyboardShortcut(
            shortcut,
            focusSource: focusSource ?? keyboardShortcutFocusSourceForCurrentSelection(),
            isRepeat: event.isARepeat,
            selectionOverride: nil,
            activeBlockOverride: nil
        )
    }

    func dispatchKeyboardShortcut(
        selector: Selector,
        focusSource: BlockInputKeyboardShortcutFocusSource? = nil
    ) -> BlockInputKeyboardShortcutDispatchResult {
        guard !isSkippingKeyboardShortcutDispatchForCurrentEvent(),
              let shortcut = BlockInputKeyboardShortcut(selector: selector) else {
            return .notRegistered
        }
        let isRepeat = NSApp.currentEvent?.type == .keyDown ? NSApp.currentEvent?.isARepeat == true : false
        return dispatchKeyboardShortcut(
            shortcut,
            focusSource: focusSource ?? keyboardShortcutFocusSourceForCurrentSelection(),
            isRepeat: isRepeat,
            selectionOverride: nil,
            activeBlockOverride: nil
        )
    }

    func dispatchKeyboardShortcut(
        _ shortcut: BlockInputKeyboardShortcut,
        focusSource: BlockInputKeyboardShortcutFocusSource,
        isRepeat: Bool,
        selectionOverride: BlockInputSelection?,
        activeBlockOverride: BlockInputBlock?,
        performDefault: ((BlockInputKeyboardShortcut) -> Bool)? = nil
    ) -> BlockInputKeyboardShortcutDispatchResult {
        let allowsActiveCompletion = completionSession == nil ||
            (shortcut == .returnKey && shouldPassthroughCompletionReturn())
        guard !isPerformingDefaultKeyboardShortcut,
              allowsActiveCompletion,
              let handler = keyboardShortcuts[shortcut] else {
            return .notRegistered
        }
        let resolvedSelection = selectionOverride ?? selection
        let activeBlock = activeBlockOverride ?? activeKeyboardShortcutBlock(selection: resolvedSelection)
        let context = BlockInputKeyboardShortcutContext(
            shortcut: shortcut,
            selection: resolvedSelection,
            activeBlock: activeBlock,
            focusSource: focusSource,
            isRepeat: isRepeat
        )
        switch handler(context) {
        case .handled:
            return .handled
        case .ignored:
            return .ignored
        case .performDefault(let defaultShortcut):
            return performDefaultKeyboardShortcut(defaultShortcut, performDefault: performDefault) ? .handled : .ignored
        }
    }

    func performDefaultKeyboardShortcut(
        _ shortcut: BlockInputKeyboardShortcut,
        performDefault: ((BlockInputKeyboardShortcut) -> Bool)? = nil
    ) -> Bool {
        guard !isPerformingDefaultKeyboardShortcut else {
            return false
        }
        isPerformingDefaultKeyboardShortcut = true
        defer { isPerformingDefaultKeyboardShortcut = false }
        if let performDefault {
            return performDefault(shortcut)
        }
        if let direction = shortcut.lineBoundarySelectionDirection {
            return adjustSelectionToLineBoundary(direction)
        }
        guard shortcut == .returnKey else {
            return false
        }
        guard insertBlockBelowCurrentBlock() != nil else {
            return false
        }
        restoreVisibleSelection()
        return true
    }

    func keyboardShortcutSelection(blockID: BlockInputBlockID, selectedRange: NSRange) -> BlockInputSelection {
        if selectedRange.length == 0 {
            return .cursor(BlockInputCursor(blockID: blockID, utf16Offset: selectedRange.location))
        }
        return .text(BlockInputTextRange(blockID: blockID, range: selectedRange))
    }

    func performKeyboardShortcutContinuationAfterIgnoredEvent<T>(_ event: NSEvent, _ continuation: () -> T) -> T {
        let eventID = ObjectIdentifier(event)
        isIgnoringShortcutDispatch = true
        ignoredKeyboardShortcutEventIDs.insert(eventID)
        defer {
            ignoredKeyboardShortcutEventIDs.remove(eventID)
            isIgnoringShortcutDispatch = false
        }
        return continuation()
    }

    func performEditorKeyDownDefaults(_ event: NSEvent) {
        if event.isCancelOperation, cancelMultiBlockSelection() { return }
        if handleImageCaretKeyDown(event) { return }
        if handleEditorArrowKeyEvent(event) { return }
        if handleLineBoundarySelectionKeyEvent(event) { return }
        if handleWordSelectionAdjustmentShortcut(event) { return }
        if handleWordMovementShortcut(event) { return }
        if handlePlainVerticalMovement(event) { return }
        if let direction = event.verticalMovementDirection, moveSelectedBlockVertically(direction) { return }
        if handleEditorBackspaceOrDelete(event) { return }
        if let insertedText = event.blockInputInsertedText,
           replaceActiveSelection(with: insertedText) {
            return
        }
        super.keyDown(with: event)
    }

    func performEditorKeyEquivalentDefaults(_ event: NSEvent) -> Bool {
        if handleFindKeyEquivalent(event) { return true }
        if performKeyboardShortcutCommand(for: event) { return true }
        if event.plainVerticalMovementDirection == .upward, moveSelectedTableUpIfNeeded() { return true }
        if handleEditorArrowKeyEvent(event) { return true }
        if handleLineBoundarySelectionKeyEvent(event) { return true }
        if handleWordSelectionAdjustmentShortcut(event) { return true }
        if handleWordMovementShortcut(event) { return true }
        if window?.firstResponder is BlockInputTextView,
           event.blockInputWordMovementDirection != nil {
            return false
        }
        return super.performKeyEquivalent(with: event)
    }

    private func handlePlainVerticalMovement(_ event: NSEvent) -> Bool {
        guard let direction = event.plainVerticalMovementDirection else {
            return false
        }
        if collapseMultiBlockSelection(direction: direction) {
            return true
        }
        return direction == .upward && moveSelectedTableUpIfNeeded()
    }

    private func handleEditorBackspaceOrDelete(_ event: NSEvent) -> Bool {
        guard event.isBackspaceOrDelete else {
            return false
        }
        if selectedBlockCount == 1, deleteSelectedHorizontalRuleForBackspaceOrDelete() != nil {
            return true
        }
        return deleteSelectedBlocksForBackspaceOrDelete() != nil
    }

    private func isSkippingKeyboardShortcutDispatch(for event: NSEvent) -> Bool {
        ignoredKeyboardShortcutEventIDs.contains(ObjectIdentifier(event))
    }

    private func isSkippingKeyboardShortcutDispatchForCurrentEvent() -> Bool {
        if isIgnoringShortcutDispatch {
            return true
        }
        guard let event = NSApp.currentEvent,
              event.type == .keyDown else {
            return false
        }
        return isSkippingKeyboardShortcutDispatch(for: event)
    }

    func keyboardShortcutBlock(
        item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        focusSource: BlockInputKeyboardShortcutFocusSource
    ) -> BlockInputBlock? {
        guard var block = block(withID: blockID) else {
            return nil
        }
        if focusSource == .blockText {
            block.text = item.currentText
        }
        return block
    }

    private func keyboardShortcutFocusSourceForCurrentSelection() -> BlockInputKeyboardShortcutFocusSource {
        switch selection {
        case .blocks, .mixed:
            return .blockSelection
        case .cursor(let cursor):
            if block(withID: cursor.blockID)?.kind.isImage == true {
                return .imageCaret
            }
            return .editor
        case .text(let range):
            if block(withID: range.blockID)?.kind.isImage == true {
                return .imageCaret
            }
            return .editor
        case nil:
            return .editor
        }
    }

    private func activeKeyboardShortcutBlock(selection: BlockInputSelection?) -> BlockInputBlock? {
        guard let blockID = selection?.blockInputActiveBlockID else {
            return nil
        }
        return block(withID: blockID)
    }
}

private extension BlockInputSelection {
    var blockInputActiveBlockID: BlockInputBlockID? {
        switch self {
        case .cursor(let cursor):
            return cursor.blockID
        case .text(let range):
            return range.blockID
        case .blocks(let blockIDs):
            return blockIDs.first
        case .mixed(let mixed):
            return mixed.leadingTextRange?.blockID ?? mixed.blockIDs.first ?? mixed.trailingTextRange?.blockID
        }
    }
}
