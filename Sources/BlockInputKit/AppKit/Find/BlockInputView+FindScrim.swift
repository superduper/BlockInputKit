import AppKit

extension BlockInputView {
    /// Whether the dim find scrim is currently installed.
    var isFindScrimInstalled: Bool {
        findScrimView != nil
    }

    /// Installs the dim overlay as a full-bleed direct child of the editor view, positioned BELOW the
    /// find bar so the bar stays undimmed and on top. It is NOT a child of `editorChromeView`, which
    /// is hidden when the host configures no editor chrome surface (which would hide the scrim too).
    /// `hitTest -> nil` on the scrim keeps the editor interactive.
    func installFindScrim() {
        guard findEnabled, findScrimView == nil else {
            return
        }
        let scrim = BlockInputFindScrimView(frame: bounds)
        scrim.autoresizingMask = [.width, .height]
        if let bar = findBarView {
            addSubview(scrim, positioned: .below, relativeTo: bar)
        } else {
            addSubview(scrim, positioned: .above, relativeTo: editorChromeView)
        }
        findScrimView = scrim
    }

    /// Recomputes the punch-through holes from the rects of the currently visible matches and pushes
    /// them onto the scrim. Bounded to visible items only so large documents stay cheap.
    func updateFindScrim() {
        guard let scrim = findScrimView else {
            return
        }
        guard findController.hasMatches else {
            scrim.holeRects = []
            return
        }
        var holes: [NSRect] = []
        for item in collectionView.visibleItems().compactMap({ $0 as? BlockInputBlockItem }) {
            guard let blockID = item.representedBlockID else {
                continue
            }
            for match in findController.matches where match.blockID == blockID {
                if let rect = item.findMatchRect(forUTF16Range: match.range, in: scrim) {
                    holes.append(rect)
                }
            }
        }
        scrim.holeRects = holes
    }

    /// Removes the dim overlay.
    func removeFindScrim() {
        findScrimView?.removeFromSuperview()
        findScrimView = nil
    }

    /// Removes the dim overlay and the active-match emphasis on genuine user interaction (a click
    /// into a block), keeping the match highlights and find state so the user can keep navigating.
    func dismissFindDimForUserInteraction() {
        guard isFindScrimInstalled || isFindActiveMatchOverlayInstalled else {
            return
        }
        removeFindScrim()
        removeFindActiveMatchOverlay()
    }
}

extension BlockInputView {
    /// Dim find scrim view, when installed. Test-only accessor.
    var findScrimViewForTesting: BlockInputFindScrimView? {
        findScrimView
    }

    /// Whether the find controller currently has matches. Test-only accessor.
    var findControllerHasMatchesForTesting: Bool {
        findController.hasMatches
    }
}
