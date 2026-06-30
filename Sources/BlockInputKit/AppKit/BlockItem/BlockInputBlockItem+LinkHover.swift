import AppKit

extension BlockInputBlockItem {
    /// Whether the editor wants the hover Edit affordance for this item's links.
    var linkHoverEditAffordanceEnabled: Bool {
        isEditable && delegate?.blockItemLinkHoverEditAffordanceEnabled(self) == true
    }

    /// Maps a hovered text-view link range into source space and asks the editor to show the hover Edit popover.
    func showLinkHoverEditAffordance(localLinkRange: BlockInputInlineMarkdownRange, windowRects: [NSRect]) {
        guard let blockID,
              linkHoverEditAffordanceEnabled else {
            return
        }
        let sourceLinkRange = sourceInlineMarkdownRange(for: textView, localRange: localLinkRange) ?? localLinkRange
        delegate?.blockItem(
            self,
            blockID: blockID,
            didHoverLink: sourceLinkRange,
            windowRects: windowRects
        )
    }

    /// Asks the editor to schedule a graced dismissal of the hover Edit popover.
    func scheduleLinkHoverDismissal() {
        delegate?.blockItemDidRequestDismissLinkHoverAffordance(self)
    }
}
