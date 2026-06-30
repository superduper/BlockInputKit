import AppKit

extension BlockInputTextView {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let linkHoverTrackingArea {
            removeTrackingArea(linkHoverTrackingArea)
        }
        guard blockItem?.linkHoverEditAffordanceEnabled == true else {
            self.linkHoverTrackingArea = nil
            return
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
        linkHoverTrackingArea = trackingArea
    }

    override func mouseExited(with event: NSEvent) {
        blockItem?.scheduleLinkHoverDismissal()
        super.mouseExited(with: event)
    }

    /// Hit-tests the inline link under the pointer and asks the editor to show or dismiss the hover Edit popover.
    func updateLinkHoverAffordance(at windowLocation: NSPoint) {
        guard blockItem?.linkHoverEditAffordanceEnabled == true else {
            return
        }
        guard let hit = linkHoverHitResult(atWindowLocation: windowLocation) else {
            blockItem?.scheduleLinkHoverDismissal()
            return
        }
        blockItem?.showLinkHoverEditAffordance(localLinkRange: hit.range, windowRects: hit.windowRects)
    }
}
