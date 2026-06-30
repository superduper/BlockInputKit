import AppKit

extension BlockInputBlockItem {
    /// Paints temporary `.backgroundColor` attributes over the supplied match ranges. The
    /// active range, when present, gets `activeColor`; the rest get `inactiveColor`. Uses an
    /// independent attribute/range store so it never collides with the selection highlight.
    func applyFindMatchHighlights(
        inactiveRanges: [NSRange],
        activeRange: NSRange?,
        inactiveColor: NSColor,
        activeColor: NSColor
    ) {
        clearFindMatchHighlights()
        guard let layoutManager = textView.layoutManager else {
            return
        }
        for range in inactiveRanges {
            addFindHighlight(range, color: inactiveColor, layoutManager: layoutManager)
        }
        if let activeRange {
            addFindHighlight(activeRange, color: activeColor, layoutManager: layoutManager)
        }
    }

    /// Removes any temporary find background attributes this item is currently showing.
    func clearFindMatchHighlights() {
        guard !findHighlightRanges.isEmpty else {
            return
        }
        let layoutManager = textView.layoutManager
        for range in findHighlightRanges {
            layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
        }
        findHighlightRanges = []
    }

    private func addFindHighlight(_ range: NSRange, color: NSColor, layoutManager: NSLayoutManager) {
        let clampedRange = textView.string.blockInputClampedRange(range)
        guard clampedRange.length > 0 else {
            return
        }
        layoutManager.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: clampedRange)
        findHighlightRanges.append(clampedRange)
    }
}

extension BlockInputBlockItem {
    /// Match-highlight ranges this item is currently painting. Test-only accessor.
    var findHighlightRangesForTesting: [NSRange] {
        findHighlightRanges
    }
}
