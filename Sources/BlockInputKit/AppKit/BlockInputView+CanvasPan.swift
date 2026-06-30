import AppKit

extension BlockInputView {
    /// Routes a two-finger scroll event into canvas pan while pinch-zoomed. Returns true when consumed.
    ///
    /// The controller runs its own velocity-projected glide (so a small flick travels further than 1:1) and
    /// deliberately swallows the OS momentum-phase frames, so the two inertia sources don't compound.
    func routeScrollToCanvasPan(_ event: NSEvent) -> Bool {
        guard pinchZoomController.isZoomed else {
            return false
        }
        // Trackpad precise deltas are already in points; line-based mice are scaled up for a usable pan step.
        // A small extra boost makes the pan feel "giddier" while zoomed (responds eagerly to finger motion).
        let factor: CGFloat = (event.hasPreciseScrollingDeltas ? 1 : 10) * 1.5
        return pinchZoomController.pan(
            deltaX: event.scrollingDeltaX * factor,
            deltaY: event.scrollingDeltaY * factor,
            phase: event.phase,
            momentumPhase: event.momentumPhase
        )
    }
}
