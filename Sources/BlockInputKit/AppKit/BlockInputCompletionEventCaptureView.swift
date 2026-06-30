import AppKit

/// Transparent event shield installed above the popup container while completions are open.
///
/// The shield only hit-tests inside the popup's frame, so clicks outside still reach the editor and can dismiss the
/// popup through the local event monitor. Keeping this separate from `BlockInputCompletionPopupView` lets overlay
/// placement rehost the popup into host-provided containers without changing event routing.
@MainActor
final class BlockInputCompletionEventCaptureView: NSView {
    private weak var popup: BlockInputCompletionPopupView?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point), let popup else {
            return nil
        }
        let popupPoint = popup.convert(point, from: self)
        return popup.bounds.contains(popupPoint) ? self : nil
    }

    func configure(popup: BlockInputCompletionPopupView) {
        self.popup = popup
    }

    override func mouseMoved(with event: NSEvent) {
        guard let popup,
              let popupPoint = popupPoint(for: event, in: popup) else {
            return
        }
        _ = popup.routeMouseMoved(at: popupPoint, event: event)
    }

    override func mouseDown(with event: NSEvent) {
        routeMouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        routeMouseDown(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        routeMouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard let popup,
              let popupPoint = popupPoint(for: event, in: popup) else {
            return
        }
        _ = popup.routeMouseUp(at: popupPoint, event: event)
    }

    override func rightMouseUp(with event: NSEvent) {}

    override func otherMouseUp(with event: NSEvent) {}

    override func scrollWheel(with event: NSEvent) {
        guard let popup else {
            return
        }
        let popupPoint = popupPointForWheelEvent(event, in: popup)
        _ = popup.routeScrollWheel(at: popupPoint, event: event)
    }

    private func routeMouseDown(with event: NSEvent) {
        guard let popup,
              let popupPoint = popupPoint(for: event, in: popup) else {
            return
        }
        _ = popup.routeMouseDown(at: popupPoint, event: event)
    }

    private func popupPoint(for event: NSEvent, in popup: BlockInputCompletionPopupView) -> NSPoint? {
        let localPoint = convert(event.locationInWindow, from: nil)
        let popupPoint = popup.convert(localPoint, from: self)
        guard popup.bounds.contains(popupPoint) else {
            return nil
        }
        return popupPoint
    }

    private func popupPointForWheelEvent(_ event: NSEvent, in popup: BlockInputCompletionPopupView) -> NSPoint {
        if let popupPoint = popupPoint(for: event, in: popup) {
            return popupPoint
        }
        return popup.convert(NSPoint(x: bounds.midX, y: bounds.midY), from: self)
    }
}
