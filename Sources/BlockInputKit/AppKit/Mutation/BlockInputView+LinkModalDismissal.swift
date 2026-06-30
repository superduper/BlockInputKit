import AppKit

extension BlockInputView {
    /// Link target resolved before outside modal dismissal can consume the mouse-down that should retarget the modal.
    struct LinkClickTarget {
        let blockID: BlockInputBlockID
        let item: BlockInputBlockItem
        let hit: BlockInputLinkHitResult
    }

    func dismissLinkModalIfSelectionMovedOutside(_ newSelection: BlockInputSelection?) {
        guard linkModalRetargetMouseDownWindowLocation == nil else {
            return
        }
        guard let context = linkModalContext,
              !context.contains(selection: newSelection) else {
            return
        }
        dismissLinkModal(restoreFocus: false)
    }

    func dismissLinkModalIfFocusMovedOutside() {
        guard linkModalRetargetMouseDownWindowLocation == nil else {
            return
        }
        guard let modal = linkModalView else {
            return
        }
        guard let firstResponder = window?.firstResponder else {
            dismissLinkModal(restoreFocus: false)
            return
        }
        guard !modal.containsResponder(firstResponder) else {
            return
        }
        dismissLinkModal(restoreFocus: false)
    }

    /// Closes the editor-owned link modal when a mouse interaction would move focus outside it.
    @discardableResult
    func dismissLinkModalIfMouseDownMovedFocusOutside(_ event: NSEvent) -> Bool {
        guard let modal = linkModalView,
              event.windowNumber == window?.windowNumber else {
            return false
        }
        // A click inside the modal's note-finder popup must not dismiss the modal; the popup's own monitor handles it.
        guard !modalCompletionPopupContains(windowPoint: event.locationInWindow) else {
            return false
        }
        let locationInModal = modal.convert(event.locationInWindow, from: nil)
        guard !modal.bounds.contains(locationInModal) else {
            return false
        }
        if event.type == .leftMouseDown,
           let target = linkClickTarget(for: event) {
            linkModalRetargetMouseDownWindowLocation = event.locationInWindow
            if handleLinkClick(
                blockID: target.blockID,
                selectedRange: NSRange(location: target.hit.range.contentRange.location, length: 0),
                clickedLinkRange: target.hit.range,
                event: event
            ) {
                return true
            }
            linkModalRetargetMouseDownWindowLocation = nil
        }
        dismissLinkModal(restoreFocus: false)
        return false
    }

    func finishPendingLinkModalRetargetIfNeeded() {
        guard linkModalRetargetMouseDownWindowLocation != nil else {
            return
        }
        linkModalRetargetMouseDownWindowLocation = nil
        dismissLinkModalIfFocusMovedOutside()
        dismissLinkModalIfSelectionMovedOutside(selection)
    }

    func linkClickTarget(for event: NSEvent) -> LinkClickTarget? {
        let collectionLocation = collectionView.convert(event.locationInWindow, from: nil)
        guard let indexPath = collectionView.indexPathForItem(at: collectionLocation),
              let item = collectionView.item(at: indexPath) as? BlockInputBlockItem,
              let blockID = item.representedBlockID,
              let hit = item.textView.linkHitResult(for: event) else {
            return nil
        }
        return LinkClickTarget(blockID: blockID, item: item, hit: hit)
    }

    func installLinkModalDismissalMonitors() {
        removeLinkModalDismissalMonitors()
        linkModalMouseDownMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            switch event.type {
            case .leftMouseUp:
                DispatchQueue.main.async { [weak self] in
                    self?.finishPendingLinkModalRetargetIfNeeded()
                }
            default:
                if self?.dismissLinkModalIfMouseDownMovedFocusOutside(event) == true {
                    return nil
                }
            }
            return event
        }
        if let window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(blockInputLinkModalWindowDidResignKey(_:)),
                name: NSWindow.didResignKeyNotification,
                object: window
            )
        }
    }

    func removeLinkModalDismissalMonitors() {
        if let linkModalMouseDownMonitor {
            NSEvent.removeMonitor(linkModalMouseDownMonitor)
            self.linkModalMouseDownMonitor = nil
        }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
    }

    @objc(blockInputLinkModalWindowDidResignKey:)
    func blockInputLinkModalWindowDidResignKey(_ notification: Notification) {
        dismissLinkModal(restoreFocus: false)
    }
}
