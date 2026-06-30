import AppKit

extension BlockInputBlockItem {
    var reorderHandleCursor: NSCursor? {
        handleView.activeCursor
    }

    var reorderHandleCursorRect: NSRect {
        guard handleView.isEnabled,
              !handleView.isHidden else {
            return .zero
        }
        let hitRect = handleView.frame.insetBy(dx: -Self.handleHitOutset, dy: -Self.handleHitOutset)
        return hitRect.intersection(view.bounds)
    }

    func containsReorderHandleHitTarget(_ point: NSPoint) -> Bool {
        reorderHandleCursor != nil && reorderHandleCursorRect.contains(point)
    }

    var usesEditableTextSurfaceCursor: Bool {
        guard isEditable,
              renderedBlock?.kind != .horizontalRule,
              !isImageBlock,
              tableView.isHidden else {
            return false
        }
        return true
    }

    func addEditableTextSurfaceCursorRectIfNeeded(to view: NSView) {
        guard usesEditableTextSurfaceCursor else {
            return
        }
        view.addCursorRect(view.bounds, cursor: .iBeam)
    }

    func applyEditableTextSurfaceCursor(at point: NSPoint?) -> Bool {
        guard usesEditableTextSurfaceCursor else {
            return false
        }
        if let point, containsReorderHandleHitTarget(point) {
            return false
        }
        NSCursor.iBeam.set()
        return true
    }

    @discardableResult
    func routeEditableTextSurfaceMouseDown(_ event: NSEvent, atRootPoint point: NSPoint? = nil) -> Bool {
        guard usesEditableTextSurfaceCursor else {
            return false
        }
        if let point, containsReorderHandleHitTarget(point) {
            return false
        }
        textView.mouseDown(with: event)
        return true
    }
}
