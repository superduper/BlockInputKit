import AppKit

private let blockInputLinkClickMovementTolerance: CGFloat = 8

/// Custom plain-drag selection tracking for `BlockInputTextView`.
///
/// The real AppKit event stream does not guarantee that a drag ending inside one text view calls `mouseUp(with:)` on that
/// text view; the release can arrive through the local event monitor instead. Keep drag-range updates and completion in
/// this companion so both paths commit the same final text range and custom selection chrome.
extension BlockInputTextView {
    /// Only plain single-click drags enter custom selection tracking.
    ///
    /// Modified clicks and multi-clicks are standard `NSTextView` selection gestures and must remain native.
    func shouldTrackBlockSelectionDrag(for event: NSEvent) -> Bool {
        guard blockItem?.isTableCellTextView(self) != true else {
            return false
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.clickCount == 1
            && !modifiers.contains(.command)
            && !modifiers.contains(.option)
            && !modifiers.contains(.control)
            && !modifiers.contains(.shift)
    }

    func blockSelectionDragAnchorOffset(for event: NSEvent) -> Int {
        let location = convert(event.locationInWindow, from: nil)
        let offset = characterIndexForInsertion(at: location)
        return min(max(offset, 0), (string as NSString).length)
    }

    func blockSelectionDragRange(for event: NSEvent) -> NSRange {
        let anchor = blockSelectionDragAnchorOffset ?? blockSelectionDragAnchorOffset(for: event)
        let current = blockSelectionDragAnchorOffset(for: event)
        return NSRange(location: min(anchor, current), length: abs(current - anchor))
    }

    func collapseNativeSelectionForTrackedDrag(to offset: Int) {
        let textLength = (string as NSString).length
        setSelectedRange(NSRange(location: min(max(offset, 0), textLength), length: 0))
    }

    /// Renders a same-block drag with the editor-owned blue chrome while keeping AppKit's native selection collapsed.
    ///
    /// Cross-block drags promote into `BlockInputView` selection, but a drag can spend many events inside the first
    /// text view. This keeps that initial partial range visually identical to mixed selection endpoints.
    func updateTrackedLocalTextSelection(_ range: NSRange) {
        collapseNativeSelectionForTrackedDrag(to: NSMaxRange(range))
        if range.length > 0 {
            blockItem?.setFocusedTextSelectionHighlightRange(range)
        } else {
            blockItem?.setBlockSelection(false)
        }
    }

    func installBlockSelectionDragMonitor() {
        removeBlockSelectionDragMonitor()
        blockSelectionDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self else {
                return event
            }
            if event.type == .leftMouseDragged,
               let blockItem {
                if shouldKeepPendingLinkClick(for: event) {
                    return nil
                }
                let localDragRange = blockSelectionDragRange(for: event)
                blockSelectionDragSelectedRange = localDragRange
                blockSelectionLocalDragRange = localDragRange
                isDraggingBlockSelection = blockItem.updateBlockSelectionDrag(
                    with: event,
                    selectedRange: localDragRange
                )
                if isDraggingBlockSelection {
                    return nil
                }
                updateTrackedLocalTextSelection(localDragRange)
            }
            if event.type == .leftMouseUp {
                // Mouse-up can be observed here without a matching `mouseUp(with:)` override call. Commit the local range
                // from the monitor too so single-block drag selection persists after release.
                _ = completeTrackedMouseUp(with: event)
                return nil
            }
            return event
        }
    }

    func installBlockSelectionDragTimer() {
        removeBlockSelectionDragTimer()
        let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateBlockSelectionDragFromCurrentMouseLocation()
            }
        }
        blockSelectionDragTimer = timer
        RunLoop.current.add(timer, forMode: .eventTracking)
        RunLoop.current.add(timer, forMode: .common)
    }

    func updateBlockSelectionDragFromCurrentMouseLocation() {
        guard NSEvent.pressedMouseButtons & 1 == 1,
              let window,
              let blockItem else {
            finishBlockSelectionDrag()
            return
        }
        let windowLocation = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        guard let event = NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: windowLocation,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ) else {
            return
        }
        if shouldKeepPendingLinkClick(for: event) {
            return
        }
        let localDragRange = blockSelectionDragRange(for: event)
        blockSelectionDragSelectedRange = localDragRange
        blockSelectionLocalDragRange = localDragRange
        isDraggingBlockSelection = blockItem.updateBlockSelectionDrag(
            with: event,
            selectedRange: localDragRange
        )
        if !isDraggingBlockSelection {
            updateTrackedLocalTextSelection(localDragRange)
        }
    }

    func updateTrackedSelectionForCurrentMouseEvent(_ event: NSEvent) {
        guard let blockItem else {
            return
        }
        if shouldKeepPendingLinkClick(for: event) {
            return
        }
        let localDragRange = blockSelectionDragRange(for: event)
        blockSelectionDragSelectedRange = localDragRange
        blockSelectionLocalDragRange = localDragRange
        isDraggingBlockSelection = blockItem.updateBlockSelectionDrag(
            with: event,
            selectedRange: localDragRange
        )
        if !isDraggingBlockSelection {
            updateTrackedLocalTextSelection(localDragRange)
        }
    }

    /// Completes a tracked plain-click sequence, including link activation for mouse-up events delivered through the
    /// local drag monitor instead of `mouseUp(with:)`.
    @discardableResult
    func completeTrackedMouseUp(with event: NSEvent) -> Bool {
        guard hasTrackedMouseInteraction else {
            return false
        }
        let finalLocalRange = blockSelectionDragRange(for: event)
        if shouldRequestLinkClick(forFinalLocalRange: finalLocalRange, event: event),
           requestLinkClickIfNeeded(with: event) {
            finishBlockSelectionDrag()
            return true
        }
        updateTrackedSelectionForCurrentMouseEvent(event)
        return completeTrackedBlockSelectionMouseUp()
    }

    private func shouldRequestLinkClick(forFinalLocalRange range: NSRange, event: NSEvent) -> Bool {
        // A plain click can mouse down and mouse up on neighboring insertion offsets without a drag event, especially
        // near glyph boundaries. Treat that as a click so link activation does not feel intermittent.
        let mouseUpStayedNearMouseDownLink = mouseUpStayedNearMouseDownLink(event)
        if mouseUpStayedNearMouseDownLink {
            return !isDraggingBlockSelection
        }
        if blockSelectionLocalDragRange == nil {
            return !isDraggingBlockSelection
                && (blockSelectionDragSelectedRange?.length ?? 0) == 0
                && range.length <= 1
        }
        return !isDraggingBlockSelection
            && range.length == 0
            && (blockSelectionDragSelectedRange?.length ?? 0) == 0
            && (blockSelectionLocalDragRange?.length ?? 0) == 0
    }

    private func mouseUpStayedNearMouseDownLink(_ event: NSEvent) -> Bool {
        eventStayedNearMouseDownLink(event)
    }

    func shouldKeepPendingLinkClick(for event: NSEvent) -> Bool {
        blockSelectionClickLinkRange != nil &&
            event.type == .leftMouseDragged &&
            eventStayedNearMouseDownLink(event)
    }

    private func eventStayedNearMouseDownLink(_ event: NSEvent) -> Bool {
        guard let mouseDownLinkRange = blockSelectionClickLinkRange,
              let mouseDownLocation = blockSelectionMouseDownWindowLocation else {
            return false
        }
        // The painted open icon sits in a kern gap past the link's visible glyph, so a point on the icon can be farther
        // than the movement tolerance from the stored mouse-down location (which may be a slightly stale live point).
        // Treat a point anywhere over the same link's icon rect as "stayed near the link" so an icon click is never
        // reclassified as a drag/selection. Only the icon rect (not the label) is widened this way, so legitimate
        // text-selection drags across the link label still promote to a selection.
        let iconWindowRect = linkOpenIconWindowRect(for: mouseDownLinkRange)
        return linkEventWindowLocations(event).contains { windowLocation in
            if iconWindowRect?.contains(windowLocation) == true {
                return true
            }
            return hypot(
                windowLocation.x - mouseDownLocation.x,
                windowLocation.y - mouseDownLocation.y
            ) <= blockInputLinkClickMovementTolerance
        }
    }

    /// Commits an editor-tracked mouse drag, whether it ended via `mouseUp(with:)` or the local event monitor.
    ///
    /// For a same-block drag this restores the actual text selection after temporarily collapsing native selection during
    /// tracking. For a promoted block drag it only tears down tracking because `BlockInputView` already owns selection.
    @discardableResult
    func completeTrackedBlockSelectionMouseUp() -> Bool {
        guard hasTrackedMouseInteraction else {
            return false
        }
        let wasDraggingBlockSelection = isDraggingBlockSelection
        let finalTrackedRange = blockSelectionLocalDragRange
        finishBlockSelectionDrag()
        if wasDraggingBlockSelection {
            return true
        }
        if let finalTrackedRange, finalTrackedRange.length > 0 {
            setSelectedRange(finalTrackedRange)
            blockItem?.setFocusedTextSelectionHighlightRange(finalTrackedRange)
        } else {
            blockItem?.setBlockSelection(false)
        }
        return true
    }

    private var hasTrackedMouseInteraction: Bool {
        isDraggingBlockSelection
            || blockSelectionDragAnchorOffset != nil
            || blockSelectionDragSelectedRange != nil
            || blockSelectionLocalDragRange != nil
    }

    func cancelBlockSelectionDrag() {
        finishBlockSelectionDrag()
    }

    func finishBlockSelectionDrag() {
        let shouldCollapseNativeSelection = isDraggingBlockSelection
        let collapseOffset = blockSelectionDragAnchorOffset ?? blockSelectionDragSelectedRange?.location
        isDraggingBlockSelection = false
        blockSelectionDragSelectedRange = nil
        blockSelectionLocalDragRange = nil
        blockSelectionDragAnchorOffset = nil
        blockSelectionClickLinkRange = nil
        blockSelectionMouseDownWindowLocation = nil
        if shouldCollapseNativeSelection {
            blockItem?.collapseNativeSelectionIfNeeded(at: collapseOffset)
            blockItem?.suppressNativeSelectionDisplayForPartialChrome()
        }
        blockItem?.finishBlockSelectionDrag()
        removeBlockSelectionDragMonitor()
        removeBlockSelectionDragTimer()
        if shouldCollapseNativeSelection {
            DispatchQueue.main.async { [weak blockItem] in
                blockItem?.collapseNativeSelectionIfNeeded(at: collapseOffset)
                blockItem?.suppressNativeSelectionDisplayForPartialChrome()
            }
        }
    }

    func removeBlockSelectionDragMonitor() {
        if let blockSelectionDragMonitor {
            NSEvent.removeMonitor(blockSelectionDragMonitor)
            self.blockSelectionDragMonitor = nil
        }
    }

    func removeBlockSelectionDragTimer() {
        blockSelectionDragTimer?.invalidate()
        blockSelectionDragTimer = nil
    }
}
