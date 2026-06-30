import AppKit

extension BlockInputView {
    /// Re-applies match background highlights to every visible/configured block item.
    /// Bounded to visible items so large documents stay cheap (AppKit perf rule).
    func applyFindHighlights() {
        for item in collectionView.visibleItems().compactMap({ $0 as? BlockInputBlockItem }) {
            applyFindHighlight(to: item)
        }
    }

    /// Removes match highlights from every visible block item.
    func clearFindHighlights() {
        for item in collectionView.visibleItems().compactMap({ $0 as? BlockInputBlockItem }) {
            item.clearFindMatchHighlights()
        }
    }

    /// Applies the find highlight for a single item, used both during a full pass and when a
    /// block is (re)configured/scrolled into view. The active match gets a stronger color.
    func applyFindHighlight(to item: BlockInputBlockItem) {
        guard findController.hasMatches, let blockID = item.representedBlockID else {
            item.clearFindMatchHighlights()
            return
        }
        let activeRange = findController.activeMatch.flatMap { match -> NSRange? in
            match.blockID == blockID ? match.range : nil
        }
        let inactiveRanges = findController.matches.compactMap { match -> NSRange? in
            guard match.blockID == blockID else {
                return nil
            }
            if let activeRange, NSEqualRanges(match.range, activeRange) {
                return nil
            }
            return match.range
        }
        item.applyFindMatchHighlights(
            inactiveRanges: inactiveRanges,
            activeRange: activeRange,
            inactiveColor: BlockInputView.inactiveFindHighlightColor,
            activeColor: BlockInputView.activeFindHighlightColor
        )
    }

    /// Background drawn behind non-active matches.
    static let inactiveFindHighlightColor = NSColor.systemYellow.withAlphaComponent(0.35)
    /// Stronger background drawn behind the active match.
    static let activeFindHighlightColor = NSColor.systemOrange.withAlphaComponent(0.65)
}
