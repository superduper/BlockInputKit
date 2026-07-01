import AppKit

extension BlockInputBlockItem {
    /// Paints transient `.backgroundColor` (and optional strikethrough) over `ranges` without mutating
    /// the document text — modeled on the find-match highlight, using `NSLayoutManager` temporary
    /// attributes so it never collides with the selection or syntax styling and clears cleanly.
    func applyTransientHighlights(_ highlights: [BlockInputTransientHighlight]) {
        clearTransientHighlights()
        guard let layoutManager = textView.layoutManager else {
            return
        }
        for highlight in highlights {
            let clampedRange = textView.string.blockInputClampedRange(highlight.range)
            guard clampedRange.length > 0 else {
                continue
            }
            layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: highlight.backgroundColor,
                forCharacterRange: clampedRange
            )
            if highlight.strikethrough {
                layoutManager.addTemporaryAttribute(
                    .strikethroughStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    forCharacterRange: clampedRange
                )
                if let strikethroughColor = highlight.strikethroughColor {
                    layoutManager.addTemporaryAttribute(
                        .strikethroughColor,
                        value: strikethroughColor,
                        forCharacterRange: clampedRange
                    )
                }
            }
            transientHighlightRanges.append(clampedRange)
        }
    }

    /// Removes any transient highlights this item is currently painting.
    func clearTransientHighlights() {
        guard !transientHighlightRanges.isEmpty else {
            return
        }
        let layoutManager = textView.layoutManager
        for range in transientHighlightRanges {
            layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
            layoutManager?.removeTemporaryAttribute(.strikethroughStyle, forCharacterRange: range)
            layoutManager?.removeTemporaryAttribute(.strikethroughColor, forCharacterRange: range)
        }
        transientHighlightRanges = []
    }
}
