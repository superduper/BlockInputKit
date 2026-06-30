import AppKit

extension BlockInputTextView {
    /// When a whole chip is selected (e.g. after the first Backspace selected it), Left arrow drops the caret just
    /// before the closing `]` (end of the visible label) so the user can edit the label — erase `.md` etc. — without
    /// deleting the node; Right arrow collapses past the chip. Returns false when the selection is not exactly a chip.
    func collapseSelectedChip(_ direction: BlockInputHorizontalMovementDirection) -> Bool {
        let selected = selectedRange()
        guard selected.length > 0,
              supportsInlineLinkNavigation,
              let chip = inlineChipRange(matchingSelection: selected) else {
            return false
        }
        let caret: Int
        switch direction {
        case .leftward:
            // End of the visible label, before the closing delimiter — the natural place to edit the filename.
            caret = NSMaxRange(chip.contentRange)
        case .rightward:
            caret = NSMaxRange(chip.fullRange)
        }
        setSelectedRange(NSRange(location: caret, length: 0))
        scrollRangeToVisible(NSRange(location: caret, length: 0))
        blockItem?.updateSelectionDependentAttributesForCurrentSelection()
        return true
    }

    /// The inline chip whose `fullRange` exactly matches `selection`, or nil.
    private func inlineChipRange(matchingSelection selection: NSRange) -> BlockInputInlineMarkdownRange? {
        let inlineCodeRanges = BlockInputCodeParsing.inlineCodeRanges(in: string).map(\.fullRange)
        return BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: string, excluding: inlineCodeRanges, fileBaseURL: blockItem?.fileBaseURL,
            inlineMarkupProviders: blockItem?.inlineMarkupProviders ?? []
        )
        .first { NSEqualRanges($0.fullRange, selection) && $0.inlineChipKind(in: string) != nil }
    }
}
