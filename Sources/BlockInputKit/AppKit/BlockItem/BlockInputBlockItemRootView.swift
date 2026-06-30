import AppKit

/// Root view that owns row-level cursor rects and preserves first-click inline link routing.
final class BlockInputBlockItemRootView: NSView {
    weak var blockItem: BlockInputBlockItem?
    // Reordered rows can receive edge mouse events at the root view. Keep routing that drag sequence
    // to the image view so resize does not depend on which view AppKit chose for mouse-down.
    private weak var activeImageResizeView: BlockInputImageBlockView?

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateHorizontalMetrics()
    }

    override func layout() {
        updateHorizontalMetrics()
        super.layout()
    }

    private func updateHorizontalMetrics() {
        guard let renderedBlock = blockItem?.renderedBlock else {
            return
        }
        blockItem?.updateHorizontalConstraints(for: renderedBlock)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        guard let event else {
            return false
        }
        let point = convert(event.locationInWindow, from: nil)
        if blockItem?.imageResizeHitView(containing: point) != nil {
            return true
        }
        return blockItem?.usesEditableTextSurfaceCursor == true || blockItem?.textView.linkHitResult(for: event) != nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let imageResizeHitView = blockItem?.imageResizeHitView(containing: point) {
            activeImageResizeView = imageResizeHitView
            imageResizeHitView.mouseDown(with: event)
            return
        }
        if let offset = blockItem?.imageCaretOffset(containing: point) {
            blockItem?.requestImageCaret(at: offset)
            return
        }
        if blockItem?.textView.linkHitResult(for: event) != nil {
            blockItem?.textView.mouseDown(with: event)
            return
        }
        if blockItem?.routeEditableTextSurfaceMouseDown(event, atRootPoint: point) == true {
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if let activeImageResizeView {
            activeImageResizeView.mouseDragged(with: event)
            return
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if let activeImageResizeView {
            activeImageResizeView.mouseUp(with: event)
            self.activeImageResizeView = nil
            return
        }
        super.mouseUp(with: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let imageResizeHitView = blockItem?.imageResizeHitView(containing: point) {
            return imageResizeHitView
        }
        return super.hitTest(point)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        blockItem?.addEditableTextSurfaceCursorRectIfNeeded(to: self)
        blockItem?.addDisabledCursorRectIfNeeded(to: self)
        blockItem?.addImageResizeCursorRects(to: self)
        guard let blockItem,
              let cursor = blockItem.reorderHandleCursor else {
            return
        }
        addCursorRect(blockItem.reorderHandleCursorRect, cursor: cursor)
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let imageResizeCursor = blockItem?.imageResizeCursor(at: point) {
            imageResizeCursor.set()
            return
        }
        guard let blockItem,
              let cursor = blockItem.reorderHandleCursor,
              blockItem.containsReorderHandleHitTarget(point) else {
            if self.blockItem?.applyEditableTextSurfaceCursor(at: point) == true {
                return
            }
            super.cursorUpdate(with: event)
            return
        }
        cursor.set()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        menu.blockInputPrependingTextFormattingItems(blockItem?.textFormattingContextMenuItems(for: event) ?? [])
        menu.blockInputPrependingLinkItems(blockItem?.linkContextMenuItems(
            for: event,
            selectedRange: blockItem?.currentSelectedRange ?? NSRange(location: 0, length: 0)
        ) ?? [])
        return menu.items.isEmpty ? nil : menu
    }
}
