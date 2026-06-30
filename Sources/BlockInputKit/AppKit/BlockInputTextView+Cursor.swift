import AppKit

extension BlockInputTextView {
    override func cursorUpdate(with event: NSEvent) {
        if applyLinkOpenIconCursor(for: event) || applyReadOnlyCursor(for: event) {
            return
        }
        super.cursorUpdate(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateLinkHoverAffordance(at: event.locationInWindow)
        if applyLinkOpenIconCursor(for: event) || applyReadOnlyCursor(for: event) {
            return
        }
        super.mouseMoved(with: event)
    }

    /// Shows the pointing-hand cursor over a link's open icon even in an editable view, where the I-beam would otherwise
    /// win. The icon is a click target, not text, so it should always read as actionable.
    @discardableResult
    func applyLinkOpenIconCursor(for event: NSEvent) -> Bool {
        guard isPointInsideAnyLinkOpenIcon(event.locationInWindow) else {
            return false
        }
        NSCursor.pointingHand.set()
        return true
    }

    @discardableResult
    func applyReadOnlyCursor(for event: NSEvent) -> Bool {
        guard let cursor = readOnlyCursor(for: event) else {
            return false
        }
        cursor.set()
        return true
    }

    func readOnlyCursor(for event: NSEvent) -> NSCursor? {
        guard blockItem?.isEditable == false else {
            return nil
        }
        if linkHitResult(for: event) != nil {
            return .pointingHand
        }
        guard let cursor = blockItem?.disabledCursorForReadOnly else {
            return nil
        }
        return cursor
    }
}
