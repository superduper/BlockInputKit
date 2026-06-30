import AppKit

extension BlockInputView {
    /// Whether the active-match emphasis overlay is currently installed.
    var isFindActiveMatchOverlayInstalled: Bool {
        findActiveMatchView != nil
    }

    /// Installs the active-match emphasis overlay as a direct child of the editor view, added *above*
    /// the dim scrim so it sits over the brightened match, but below the find bar. It is NOT a child
    /// of `editorChromeView` (which is hidden when no chrome surface is configured).
    /// `hitTest -> nil` keeps the editor interactive.
    func installFindActiveMatchOverlay() {
        guard findEnabled, findActiveMatchView == nil else {
            return
        }
        let overlay = BlockInputFindActiveMatchView(frame: .zero)
        if let scrim = findScrimView {
            addSubview(overlay, positioned: .above, relativeTo: scrim)
        } else if let bar = findBarView {
            addSubview(overlay, positioned: .below, relativeTo: bar)
        } else {
            addSubview(overlay, positioned: .above, relativeTo: editorChromeView)
        }
        findActiveMatchView = overlay
    }

    /// Repositions the overlay onto the active match's rect. When `animated` is true (the user landed
    /// on a match) it also fires the pulse; scroll-driven repositioning passes `false`. Hides the
    /// overlay when there is no active match or its block is not currently visible.
    func updateFindActiveMatchOverlay(animated: Bool) {
        guard let overlay = findActiveMatchView else {
            return
        }
        guard let rect = activeFindMatchRect(in: overlay.superview ?? editorChromeView) else {
            overlay.isHidden = true
            return
        }
        overlay.isHidden = false
        overlay.frame = rect
        if animated {
            overlay.pulse()
        }
    }

    /// Removes the active-match emphasis overlay.
    func removeFindActiveMatchOverlay() {
        findActiveMatchView?.removeFromSuperview()
        findActiveMatchView = nil
    }

    /// Rect of the currently active match in `coordinateView`'s space, or `nil` when there is no
    /// active match or its block is not visible. Only the single active match is measured (bounded).
    private func activeFindMatchRect(in coordinateView: NSView) -> NSRect? {
        guard let activeMatch = findController.activeMatch,
              let item = collectionView.visibleItems()
                  .compactMap({ $0 as? BlockInputBlockItem })
                  .first(where: { $0.representedBlockID == activeMatch.blockID }) else {
            return nil
        }
        return item.findMatchRect(forUTF16Range: activeMatch.range, in: coordinateView)
    }
}

extension BlockInputView {
    /// Active-match emphasis overlay, when installed. Test-only accessor.
    var findActiveMatchOverlayForTesting: BlockInputFindActiveMatchView? {
        findActiveMatchView
    }
}
