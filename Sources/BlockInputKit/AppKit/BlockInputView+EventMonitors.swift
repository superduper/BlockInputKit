import AppKit

extension BlockInputView {
    nonisolated func removeNonisolatedEventMonitors() {
        if let selectionExpansionKeyMonitor {
            NSEvent.removeMonitor(selectionExpansionKeyMonitor)
        }
        if let linkModalMouseDownMonitor {
            NSEvent.removeMonitor(linkModalMouseDownMonitor)
        }
        if let completionPopupMouseDownMonitor {
            NSEvent.removeMonitor(completionPopupMouseDownMonitor)
        }
        if let modalCompletionPopupMouseDownMonitor {
            NSEvent.removeMonitor(modalCompletionPopupMouseDownMonitor)
        }
        if let selectionOverlayMouseDownMonitor {
            NSEvent.removeMonitor(selectionOverlayMouseDownMonitor)
        }
        // Anchored-accessory growth observer is a NotificationCenter (not NSEvent) observer.
        if let anchoredAccessoryFrameObserver {
            NotificationCenter.default.removeObserver(anchoredAccessoryFrameObserver)
        }
    }

    func installModalCompletionDismissalMonitor() {
        guard modalCompletionPopupMouseDownMonitor == nil else {
            return
        }
        modalCompletionPopupMouseDownMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseUp, .rightMouseUp, .otherMouseUp, .scrollWheel]
        ) { [weak self] event -> NSEvent? in
            self?.handleModalCompletionPopupMouseEvent(event) ?? event
        }
    }

    func removeModalCompletionDismissalMonitor() {
        if let modalCompletionPopupMouseDownMonitor {
            NSEvent.removeMonitor(modalCompletionPopupMouseDownMonitor)
            self.modalCompletionPopupMouseDownMonitor = nil
        }
        modalCompletionPopupConsumesNextMouseUp = false
    }

    private func handleModalCompletionPopupMouseEvent(_ event: NSEvent) -> NSEvent? {
        guard let popup = modalCompletionPopupView,
              eventBelongsToEditorWindow(event) else {
            return event
        }
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return handleModalCompletionPopupMouseDown(event, popup: popup)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return handleModalCompletionPopupMouseUp(event, popup: popup)
        case .scrollWheel:
            let locationInPopup = popup.convert(event.locationInWindow, from: nil)
            guard popup.bounds.contains(locationInPopup) else {
                return event
            }
            _ = popup.routeScrollWheel(at: locationInPopup, event: event)
            return nil
        default:
            return event
        }
    }

    private func handleModalCompletionPopupMouseDown(_ event: NSEvent, popup: BlockInputCompletionPopupView) -> NSEvent? {
        let locationInPopup = popup.convert(event.locationInWindow, from: nil)
        guard popup.bounds.contains(locationInPopup) else {
            // Outside the popup: close only the popup. The modal's own monitor decides the modal's fate.
            dismissModalCompletionPopup()
            return event
        }
        modalCompletionPopupConsumesNextMouseUp = true
        _ = popup.routeMouseDown(at: locationInPopup, event: event)
        return nil
    }

    private func handleModalCompletionPopupMouseUp(_ event: NSEvent, popup: BlockInputCompletionPopupView) -> NSEvent? {
        guard modalCompletionPopupConsumesNextMouseUp else {
            return event
        }
        modalCompletionPopupConsumesNextMouseUp = false
        guard event.type == .leftMouseUp else {
            return event
        }
        let locationInPopup = popup.convert(event.locationInWindow, from: nil)
        guard popup.bounds.contains(locationInPopup) else {
            return nil
        }
        _ = popup.routeMouseUp(at: locationInPopup, event: event)
        return nil
    }

    func installCompletionPopupDismissalMonitor() {
        guard completionPopupMouseDownMonitor == nil else {
            return
        }
        completionPopupMouseDownMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseUp, .rightMouseUp, .otherMouseUp, .scrollWheel]
        ) { [weak self] event -> NSEvent? in
            self?.handleCompletionPopupMouseEvent(event) ?? event
        }
    }

    func removeCompletionPopupDismissalMonitor() {
        if let completionPopupMouseDownMonitor {
            NSEvent.removeMonitor(completionPopupMouseDownMonitor)
            self.completionPopupMouseDownMonitor = nil
        }
        completionPopupConsumesNextMouseUp = false
    }

    func handleCompletionPopupMouseEvent(_ event: NSEvent) -> NSEvent? {
        guard let popup = completionPopupView,
              eventBelongsToEditorWindow(event) else {
            return event
        }
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return handleCompletionPopupMouseDown(event, popup: popup)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return handleCompletionPopupMouseUp(event, popup: popup)
        case .scrollWheel:
            return handleCompletionPopupScrollWheel(event, popup: popup)
        default:
            return event
        }
    }

    func handleCompletionPopupMouseDown(_ event: NSEvent) -> NSEvent? {
        guard let popup = completionPopupView,
              eventBelongsToEditorWindow(event) else {
            return event
        }
        return handleCompletionPopupMouseDown(event, popup: popup)
    }

    private func handleCompletionPopupMouseDown(_ event: NSEvent, popup: BlockInputCompletionPopupView) -> NSEvent? {
        for windowPoint in completionMouseEventWindowPoints(event) {
            let locationInPopup = popup.convert(windowPoint, from: nil)
            guard popup.bounds.contains(locationInPopup) else {
                continue
            }
            // Consume the down/up pair so accepting a row cannot retarget the same click into the block underneath.
            completionPopupConsumesNextMouseUp = true
            _ = popup.routeMouseDown(at: locationInPopup, event: event)
            return nil
        }
        dismissCompletionPopup()
        return event
    }

    private func handleCompletionPopupMouseUp(_ event: NSEvent, popup: BlockInputCompletionPopupView) -> NSEvent? {
        guard completionPopupConsumesNextMouseUp else {
            return event
        }
        completionPopupConsumesNextMouseUp = false
        guard event.type == .leftMouseUp else {
            return event
        }
        for windowPoint in completionMouseEventWindowPoints(event) {
            let locationInPopup = popup.convert(windowPoint, from: nil)
            guard popup.bounds.contains(locationInPopup) else {
                continue
            }
            _ = popup.routeMouseUp(at: locationInPopup, event: event)
            return nil
        }
        return nil
    }

    private func handleCompletionPopupScrollWheel(_ event: NSEvent, popup: BlockInputCompletionPopupView) -> NSEvent? {
        let locationInPopup = popup.convert(event.locationInWindow, from: nil)
        guard popup.bounds.contains(locationInPopup) else {
            return event
        }
        _ = popup.routeScrollWheel(at: locationInPopup, event: event)
        return nil
    }

    private func eventBelongsToEditorWindow(_ event: NSEvent) -> Bool {
        if let eventWindow = event.window {
            return eventWindow === window
        }
        return event.windowNumber == window?.windowNumber
    }

    private func completionMouseEventWindowPoints(_ event: NSEvent) -> [NSPoint] {
        guard let editorWindow = window,
              event.window === editorWindow || event.windowNumber == editorWindow.windowNumber else {
            return [event.locationInWindow]
        }
        let livePoint = editorWindow.mouseLocationOutsideOfEventStream
        guard livePoint != event.locationInWindow else {
            return [event.locationInWindow]
        }
        return [event.locationInWindow, livePoint]
    }
}
