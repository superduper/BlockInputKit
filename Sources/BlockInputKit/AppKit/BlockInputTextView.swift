import AppKit

/// Text view wrapper that forwards block-aware commands and cross-block drag selection to its owning block item.
class BlockInputTextView: NSTextView {
    weak var blockItem: BlockInputBlockItem?
    var isDraggingBlockSelection = false
    var blockSelectionDragMonitor: Any?
    var blockSelectionDragTimer: Timer?
    // Cross-block drags carry a logical range while native selection stays collapsed to avoid stale gray selection paint.
    var blockSelectionDragSelectedRange: NSRange?
    var blockSelectionLocalDragRange: NSRange?
    var blockSelectionDragAnchorOffset: Int?
    var blockSelectionClickLinkRange: BlockInputInlineMarkdownRange?
    var blockSelectionMouseDownWindowLocation: NSPoint?
    var isIgnoringShortcutDispatch = false
    var ignoredKeyboardShortcutEventIDs: Set<ObjectIdentifier> = []
    var linkHoverTrackingArea: NSTrackingArea?
    let fileDropCaretView = NSView()
    let inlineHintView = BlockInputInlineHintView()
    var inlineHint: BlockInputInlineHint? {
        didSet {
            updateInlineHintView()
        }
    }
    // Native modified-click and multi-click gestures can re-enter mouseDragged/mouseUp during AppKit tracking. Keep that
    // separate from the custom plain-drag state so native selection restoration cannot be consumed as a block drag.
    var isUsingNativeMouseSelection = false
    private var isForwardingVerticalScrollSequence = false
    private var verticalScrollSequenceToken = UUID()

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        guard let event else {
            return false
        }
        return blockItem?.isEditable == true || linkHitResult(for: event) != nil
    }

    override func mouseDown(with event: NSEvent) {
        _ = requestMouseDownCancelSelectionFromOwningBlock()
        if shouldRequestCommandClickLink(with: event),
           requestLinkClickIfNeeded(with: event) {
            return
        }
        // A double-click on a link opens/navigates. Route it before AppKit's native multi-click selection runs so the
        // open happens here; this also avoids driving a synthetic double-click through `super.mouseDown`, whose
        // event-tracking loop hangs headless tests.
        if shouldRequestDoubleClickLink(with: event),
           requestLinkClickIfNeeded(with: event) {
            return
        }
        guard shouldTrackBlockSelectionDrag(for: event) else {
            // Multi-click and modified-click selection are native NSTextView gestures; only plain single-click drags need
            // custom tracking.
            finishBlockSelectionDrag()
            isUsingNativeMouseSelection = true
            super.mouseDown(with: event)
            isUsingNativeMouseSelection = false
            return
        }
        blockItem?.beginBlockSelectionDrag()
        isDraggingBlockSelection = false
        let anchorOffset = blockSelectionDragAnchorOffset(for: event)
        let linkHit = linkHitResult(for: event)
        blockSelectionDragAnchorOffset = anchorOffset
        blockSelectionClickLinkRange = linkHit?.range
        blockSelectionMouseDownWindowLocation = linkHit?.windowLocation ?? event.locationInWindow
        blockSelectionDragSelectedRange = NSRange(location: anchorOffset, length: 0)
        blockSelectionLocalDragRange = nil
        installBlockSelectionDragMonitor()
        installBlockSelectionDragTimer()
        window?.makeFirstResponder(self)
        if linkHit == nil {
            setSelectedRange(NSRange(location: anchorOffset, length: 0))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if isUsingNativeMouseSelection {
            super.mouseDragged(with: event)
            return
        }
        if shouldKeepPendingLinkClick(for: event) {
            return
        }
        let localDragRange = blockSelectionDragRange(for: event)
        blockSelectionDragSelectedRange = localDragRange
        blockSelectionLocalDragRange = localDragRange
        isDraggingBlockSelection = blockItem?.updateBlockSelectionDrag(
            with: event,
            selectedRange: localDragRange
        ) == true
        if isDraggingBlockSelection {
            return
        }
        // Keep AppKit out of the native drag-selection path while block selection may be promoted. The visible selection
        // chrome is editor-owned, and allowing `NSTextView` to build a native range here can leave gray selection paint
        // over the custom blue endpoint background for the rest of the tracking cycle.
        updateTrackedLocalTextSelection(localDragRange)
    }

    override func mouseUp(with event: NSEvent) {
        if isUsingNativeMouseSelection {
            super.mouseUp(with: event)
            isUsingNativeMouseSelection = false
            return
        }
        if blockItem?.isTableCellTextView(self) == true,
           selectedRange().length == 0,
           requestLinkClickIfNeeded(with: event) {
            return
        }
        if completeTrackedMouseUp(with: event) {
            return
        }
        super.mouseUp(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        // While the canvas is pinch-zoomed, any two-finger scroll over a focused block must pan the canvas —
        // checked first, before the text view's own horizontal/vertical scroll routing, so quick swipes are
        // not swallowed by that logic (they otherwise reach this view but never the document scroll view).
        // Reach the editor through the document scroll view's existing back-reference, not a fresh superview
        // walk, so unzoomed scrolling pays nothing beyond the cheap `isCanvasZoomed` bool.
        if let owner = ownerForCanvasPan, owner.routeScrollToCanvasPan(event) {
            return
        }
        if shouldBreakVerticalSequenceForHorizontalScroll(event),
           forwardHorizontalScroll(event) {
            isForwardingVerticalScrollSequence = false
            verticalScrollSequenceToken = UUID()
            return
        }
        if isForwardingVerticalScrollSequence,
           let verticalAncestorScrollView {
            verticalAncestorScrollView.scrollWheel(with: event)
            schedulePhaseLessVerticalScrollSequenceResetIfNeeded(for: event)
            updateVerticalScrollSequenceState(after: event)
            return
        }
        if shouldForwardHorizontalScroll(event),
           forwardHorizontalScroll(event) {
            return
        }
        if shouldForwardVerticalScroll(event),
           let verticalAncestorScrollView {
            isForwardingVerticalScrollSequence = true
            schedulePhaseLessVerticalScrollSequenceResetIfNeeded(for: event)
            verticalAncestorScrollView.scrollWheel(with: event)
            updateVerticalScrollSequenceState(after: event)
            return
        }
        updateVerticalScrollSequenceState(after: event)
        super.scrollWheel(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.isArrowKey {
            BlockInputSelectionDebug.emit(
                "text equivalent key=\(event.debugKeyName) modifiers=\(event.debugModifierNames) range=\(selectedRange())"
            )
        }
        let focusSource: BlockInputKeyboardShortcutFocusSource =
            blockItem?.isTableCellTextView(self) == true ? .tableCell : .blockText
        switch dispatchKeyboardShortcut(event: event, focusSource: focusSource) {
        case .handled:
            return true
        case .ignored:
            return performKeyboardShortcutContinuationAfterIgnoredEvent(event) {
                performKeyEquivalentDefaults(with: event)
            }
        case .notRegistered:
            break
        }
        return performKeyEquivalentDefaults(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = systemMenuPreservingSelectedRange(for: event)
        menu.blockInputRemovingSystemFontItems()
        menu.blockInputRemovingSystemLinkItems()
        menu.blockInputPrependingTextFormattingItems(textFormattingMenuItems(for: event))
        menu.blockInputPrependingLinkItems(linkContextMenuItems(for: event))
        return menu.items.isEmpty ? nil : menu
    }

    override func paste(_ sender: Any?) {
        guard blockItem?.isEditable != false else {
            return
        }
        if blockItem?.requestPasteActiveSelection() == true {
            return
        }
        performPasteFromEditorCommand()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { fileDropOperation(sender, super.draggingEntered(sender)) }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { fileDropOperation(sender, super.draggingUpdated(sender)) }

    override func draggingExited(_ sender: NSDraggingInfo?) { hideFileDropCaret(); super.draggingExited(sender) }

    override func draggingEnded(_ sender: NSDraggingInfo) { hideFileDropCaret(); super.draggingEnded(sender) }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        prepareFileDropOperation(sender, super.prepareForDragOperation(sender))
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { performFileDropOperation(sender, super.performDragOperation(sender)) }

    override func resetCursorRects() {
        if blockItem?.isEditable == false {
            blockItem?.addDisabledCursorRectIfNeeded(to: self)
            addLinkCursorRects()
            return
        }
        super.resetCursorRects()
        blockItem?.addDisabledCursorRectIfNeeded(to: self)
        addLinkCursorRects()
    }

    override func selectAll(_ sender: Any?) {
        guard let blockItem else {
            super.selectAll(sender)
            return
        }
        blockItem.requestSelectAll()
    }

    override func copy(_ sender: Any?) {
        if blockItem?.requestCopyActiveSelection() == true {
            return
        }
        guard copySelectedPlainText(allowingEditorRoute: false) else {
            super.copy(sender)
            return
        }
    }

    override func cut(_ sender: Any?) {
        guard blockItem?.isEditable != false else {
            return
        }
        if blockItem?.requestCutActiveSelection() == true {
            return
        }
        performCutFromEditorCommand()
    }

    func performCutFromEditorCommand() {
        guard blockItem?.isEditable != false else {
            return
        }
        guard copySelectedPlainText(allowingEditorRoute: false) else {
            super.cut(nil)
            return
        }
        delete(nil)
    }

    override func doCommand(by selector: Selector) {
        BlockInputSelectionDebug.emit("text command selector=\(selector) range=\(selectedRange())")
        if blockItem?.isTableCellTextView(self) == true {
            switch dispatchKeyboardShortcut(selector: selector, focusSource: .tableCell) {
            case .handled:
                return
            case .ignored:
                performTableCellCommandDefaults(selector)
            case .notRegistered:
                performTableCellCommandDefaults(selector)
            }
            return
        }
        if blockItem?.requestCompletionCommand(selector) == true {
            BlockInputSelectionDebug.emit("text command consumed completion selector=\(selector)")
            return
        }
        switch dispatchKeyboardShortcut(selector: selector, focusSource: .blockText) {
        case .handled:
            return
        case .ignored:
            performNonTableCommandDefaults(selector)
            return
        case .notRegistered:
            break
        }
        performNonTableCommandDefaults(selector)
    }

    override func moveToBeginningOfDocument(_ sender: Any?) {
        if blockItem?.isTableCellTextView(self) != true,
           requestDocumentBoundaryFromOwningBlock(.upward) {
            return
        }
        super.moveToBeginningOfDocument(sender)
    }

    override func moveToEndOfDocument(_ sender: Any?) {
        if blockItem?.isTableCellTextView(self) != true,
           requestDocumentBoundaryFromOwningBlock(.downward) {
            return
        }
        super.moveToEndOfDocument(sender)
    }

    func handleBlockCommand(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(insertNewline(_:)):
            guard let blockItem else {
                return true
            }
            return blockItem.requestReturn()
        case #selector(deleteBackward(_:)), #selector(deleteForward(_:)):
            return handleDeleteCommand(selector)
        case #selector(selectAll(_:)):
            blockItem?.requestSelectAll()
            return true
        case #selector(insertTab(_:)):
            return blockItem?.requestIndent() == true
        case #selector(insertBacktab(_:)):
            return blockItem?.requestOutdent() == true
        case #selector(cancelOperation(_:)):
            return blockItem?.requestCancelSelection() == true
        default:
            return false
        }
    }

    private func handleDeleteCommand(_ selector: Selector) -> Bool {
        let deletionDirection: BlockInputLinkBoundaryDeletionDirection =
            selector == #selector(deleteBackward(_:)) ? .backward : .forward
        if blockItem?.requestLinkBoundaryDeletion(deletionDirection) == true {
            return true
        }
        if selectedRange().location == 0,
           selectedRange().length == 0,
           blockItem?.requestUnwrapBlock() == true {
            return true
        }
        if selectedRange().location == 0,
           selectedRange().length == 0,
           blockItem?.requestMergeWithPreviousBlock() == true {
            return true
        }
        return blockItem?.requestDeleteEmptyBlock() == true
    }

    func handleBoundaryCommand(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(moveUp(_:)):
            return blockItem?.requestCollapseSelection(.upward) == true
                || blockItem?.requestMoveVertically(.upward) == true
        case #selector(moveDown(_:)):
            return blockItem?.requestCollapseSelection(.downward) == true
                || blockItem?.requestMoveVertically(.downward) == true
        default:
            return false
        }
    }

    func handleSelectionExpansionCommand(_ selector: Selector) -> Bool {
        let direction: BlockInputVerticalMovementDirection
        switch selector {
        case #selector(moveUpAndModifySelection(_:)):
            direction = .upward
        case #selector(moveDownAndModifySelection(_:)):
            direction = .downward
        default:
            return false
        }
        _ = blockItem?.requestExpandSelection(direction)
        return true
    }

    func handleDocumentBoundaryCommand(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(moveToBeginningOfDocument(_:)):
            return requestDocumentBoundaryFromOwningBlock(.upward)
        case #selector(moveToEndOfDocument(_:)):
            return requestDocumentBoundaryFromOwningBlock(.downward)
        default:
            return false
        }
    }

    func handleDocumentBoundaryShortcut(_ event: NSEvent) -> Bool {
        guard let direction = event.blockInputDocumentBoundaryDirection else {
            return false
        }
        return requestDocumentBoundaryFromOwningBlock(direction)
    }

    func handleSelectionExpansionShortcut(_ event: NSEvent) -> Bool {
        if let direction = event.blockInputSelectionExpansionDirection {
            _ = requestSelectionExpansionFromOwningBlock(direction)
            return true
        }
        return false
    }

}

private extension BlockInputTextView {
    func shouldForwardVerticalScroll(_ event: NSEvent) -> Bool {
        guard !event.modifierFlags.contains(.shift) else {
            return false
        }
        let deltaY = abs(verticalScrollDelta(for: event))
        return deltaY > 0 && deltaY >= abs(horizontalRawScrollDelta(for: event))
    }

    func shouldForwardHorizontalScroll(_ event: NSEvent) -> Bool {
        abs(horizontalRawScrollDelta(for: event)) > abs(verticalScrollDelta(for: event)) ||
            shouldBreakVerticalSequenceForHorizontalScroll(event)
    }

    func forwardHorizontalScroll(_ event: NSEvent) -> Bool {
        guard let horizontalScrollView = enclosingScrollView,
              horizontalScrollView.hasHorizontalScroller else {
            return false
        }
        horizontalScrollView.scrollWheel(with: event)
        return true
    }

    func shouldBreakVerticalSequenceForHorizontalScroll(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.shift) &&
            (abs(verticalScrollDelta(for: event)) > 0 || abs(horizontalRawScrollDelta(for: event)) > 0)
    }

    func horizontalRawScrollDelta(for event: NSEvent) -> CGFloat {
        event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.deltaX
    }

    func verticalScrollDelta(for event: NSEvent) -> CGFloat {
        event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY
    }

    func updateVerticalScrollSequenceState(after event: NSEvent) {
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) ||
            event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
            isForwardingVerticalScrollSequence = false
            verticalScrollSequenceToken = UUID()
        }
    }

    func schedulePhaseLessVerticalScrollSequenceResetIfNeeded(for event: NSEvent) {
        guard event.phase == [], event.momentumPhase == [] else {
            return
        }
        let token = UUID()
        verticalScrollSequenceToken = token
        DispatchQueue.main.async { [weak self] in
            guard self?.verticalScrollSequenceToken == token else {
                return
            }
            self?.isForwardingVerticalScrollSequence = false
        }
    }

    var verticalAncestorScrollView: NSScrollView? {
        var candidate = superview
        while let view = candidate {
            if let scrollView = view as? NSScrollView,
               scrollView.hasVerticalScroller {
                return scrollView
            }
            candidate = view.superview
        }
        return nil
    }

    /// The editor that owns this text view, reached through the document scroll view's existing back-reference
    /// (rather than a second superview walk), and only while the canvas is zoomed so the unzoomed scroll path
    /// is untouched.
    private var ownerForCanvasPan: BlockInputView? {
        guard let owner = (verticalAncestorScrollView as? BlockInputDocumentScrollView)?.blockInputView,
              owner.pinchZoomController.isZoomed else {
            return nil
        }
        return owner
    }
}
