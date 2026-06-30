import AppKit

extension BlockInputView {
    /// Shows, refreshes, or dismisses the host-supplied selection overlay for the current selection.
    ///
    /// Off entirely when no provider is configured. Shown only for a non-empty selection anchor (a `.text` range with
    /// length, or a `.mixed` selection with a non-empty edge range); any other selection dismisses it.
    func updateSelectionOverlayForCurrentSelection() {
        guard selectionOverlayProvider != nil else {
            dismissSelectionOverlay()
            return
        }
        guard let anchorRange = selectionOverlayAnchorRange(for: selection),
              let selection else {
            dismissSelectionOverlay()
            return
        }
        presentSelectionOverlay(blockID: anchorRange.blockID, range: anchorRange.range, selection: selection)
    }

    /// Re-anchors a visible selection overlay after scroll or resize; no-op when nothing is shown.
    func refreshSelectionOverlayPresentation() {
        guard selectionOverlayView != nil else {
            return
        }
        updateSelectionOverlayForCurrentSelection()
    }

    /// Repositions the visible overlay against the live selection geometry without rebuilding it.
    func repositionSelectionOverlayOnScrollOrResize() {
        refreshSelectionOverlayPresentation()
    }

    func dismissSelectionOverlay() {
        selectionOverlayView?.removeFromSuperview()
        selectionOverlayView = nil
        removeSelectionOverlayDismissalMonitor()
    }

    private func presentSelectionOverlay(blockID: BlockInputBlockID, range: NSRange, selection: BlockInputSelection) {
        guard let provider = selectionOverlayProvider,
              let item = mountedSelectionOverlayItem(for: blockID) else {
            dismissSelectionOverlay()
            return
        }
        let container = selectionOverlayContainer()
        let anchorWindowRect = item.anchorWindowRect(forUTF16Range: range)
        guard anchorWindowRect != .zero else {
            dismissSelectionOverlay()
            return
        }
        let anchorRect = container.convert(anchorWindowRect, from: nil)
        let context = BlockInputSelectionOverlayContext(
            editorView: self,
            container: container,
            anchorRect: anchorRect,
            selection: selection
        )
        guard let overlay = provider(context) else {
            dismissSelectionOverlay()
            return
        }
        mountSelectionOverlay(overlay, context: context, container: container)
    }

    private func mountSelectionOverlay(
        _ overlay: NSView,
        context: BlockInputSelectionOverlayContext,
        container: NSView
    ) {
        if selectionOverlayView !== overlay {
            selectionOverlayView?.removeFromSuperview()
        }
        selectionOverlayView = overlay
        overlay.appearance = effectiveAppearance
        if overlay.superview !== container {
            overlay.removeFromSuperview()
            container.addSubview(overlay, positioned: .above, relativeTo: nil)
        }
        overlay.frame = context.overlayFrame(for: overlay.fittingSize)
        overlay.layoutSubtreeIfNeeded()

        // Click-outside dismissal is handled by the global mouse-down monitor below, matching the completion popup.
        installSelectionOverlayDismissalMonitor()
    }

    /// Returns the mounted block item for `blockID` without scrolling or reconfiguring it.
    private func mountedSelectionOverlayItem(for blockID: BlockInputBlockID) -> BlockInputBlockItem? {
        collectionView.visibleItems()
            .compactMap { $0 as? BlockInputBlockItem }
            .first { $0.representedBlockID == blockID }
    }

    private func selectionOverlayContainer() -> NSView {
        if let contentView = window?.contentView,
           contentView !== self {
            return contentView
        }
        return superview ?? self
    }

    /// Resolves the non-empty selection anchor (block + range) used to position the overlay, or nil when none applies.
    private func selectionOverlayAnchorRange(
        for selection: BlockInputSelection?
    ) -> (blockID: BlockInputBlockID, range: NSRange)? {
        switch selection {
        case let .text(textRange) where textRange.range.length > 0:
            return (textRange.blockID, textRange.range)
        case let .mixed(mixedSelection):
            if let leading = mixedSelection.leadingTextRange, leading.range.length > 0 {
                return (leading.blockID, leading.range)
            }
            if let trailing = mixedSelection.trailingTextRange, trailing.range.length > 0 {
                return (trailing.blockID, trailing.range)
            }
            return nil
        default:
            return nil
        }
    }
}

extension BlockInputView {
    private func installSelectionOverlayDismissalMonitor() {
        guard selectionOverlayMouseDownMonitor == nil else {
            return
        }
        selectionOverlayMouseDownMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { [weak self] event -> NSEvent? in
            self?.handleSelectionOverlayMonitorEvent(event) ?? event
        }
    }

    private func removeSelectionOverlayDismissalMonitor() {
        if let selectionOverlayMouseDownMonitor {
            NSEvent.removeMonitor(selectionOverlayMouseDownMonitor)
            self.selectionOverlayMouseDownMonitor = nil
        }
    }

    private func handleSelectionOverlayMonitorEvent(_ event: NSEvent) -> NSEvent? {
        guard let overlay = selectionOverlayView,
              selectionOverlayEventBelongsToEditorWindow(event) else {
            return event
        }
        switch event.type {
        case .keyDown:
            // Esc dismisses the overlay and is otherwise passed through.
            if event.keyCode == 53 {
                dismissSelectionOverlay()
            }
            return event
        default:
            let locationInOverlay = overlay.convert(event.locationInWindow, from: nil)
            if overlay.bounds.contains(locationInOverlay) {
                return event
            }
            dismissSelectionOverlay()
            return event
        }
    }

    private func selectionOverlayEventBelongsToEditorWindow(_ event: NSEvent) -> Bool {
        if let eventWindow = event.window {
            return eventWindow === window
        }
        return event.windowNumber == window?.windowNumber
    }
}
