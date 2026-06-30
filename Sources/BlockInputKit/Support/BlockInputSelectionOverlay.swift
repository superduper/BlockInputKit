import AppKit

/// Host-supplied, selection-anchored overlay seam.
///
/// The editor positions an arbitrary host-owned `NSView` above the current non-empty text selection. Core knows nothing
/// about the view's contents or purpose: the host owns the view, its subviews, and its intrinsic size, while the editor
/// only anchors it (centered horizontally over the selection, above by default, flipping below near the top, clamped
/// inside the container). This mirrors the completion-popup and modal hosting seams but carries no view-kind vocabulary.
public struct BlockInputSelectionOverlayContext {
    /// Editor presenting the overlay.
    public var editorView: BlockInputView
    /// Container view that will own the overlay; frames returned here are in this view's coordinate space.
    public var container: NSView
    /// Selection anchor rect in `container` coordinates (the glyph rect of the active selection).
    public var anchorRect: NSRect
    /// Current editor selection driving the overlay.
    public var selection: BlockInputSelection

    /// Creates a selection-overlay placement context.
    public init(
        editorView: BlockInputView,
        container: NSView,
        anchorRect: NSRect,
        selection: BlockInputSelection
    ) {
        self.editorView = editorView
        self.container = container
        self.anchorRect = anchorRect
        self.selection = selection
    }

    /// Returns an overlay frame centered horizontally over the selection, placed above it with a below-flip near the
    /// top, clamped inside `container`. Hosts can call this for default placement or compute their own frame.
    @MainActor
    public func overlayFrame(
        for size: NSSize,
        margin: CGFloat = 8,
        verticalSpacing: CGFloat = 8
    ) -> NSRect {
        let minX = container.bounds.minX + margin
        let maxX = container.bounds.maxX - size.width - margin
        let centeredX = anchorRect.midX - size.width / 2
        let originX = Self.clamped(centeredX, min: minX, max: maxX)
        let minY = container.bounds.minY + margin
        let maxY = container.bounds.maxY - size.height - margin
        let preferredY = container.isFlipped
            ? anchorRect.minY - size.height - verticalSpacing
            : anchorRect.maxY + verticalSpacing
        let preferredFits = container.isFlipped
            ? preferredY >= minY
            : preferredY <= maxY
        let fallbackY = container.isFlipped
            ? anchorRect.maxY + verticalSpacing
            : anchorRect.minY - size.height - verticalSpacing
        let originY = Self.clamped(preferredFits ? preferredY : fallbackY, min: minY, max: maxY)
        return NSRect(origin: NSPoint(x: originX, y: originY), size: size)
    }

    private static func clamped(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        guard maximum >= minimum else {
            return minimum
        }
        return Swift.min(Swift.max(value, minimum), maximum)
    }
}

/// Host closure that supplies the view to anchor above the current text selection, or nil to show nothing.
///
/// The closure is invoked while a non-empty text selection is active. Return a host-owned `NSView` to host (the editor
/// sizes the frame via ``BlockInputSelectionOverlayContext/overlayFrame(for:margin:verticalSpacing:)`` using the view's
/// `fittingSize`, then anchors it), or nil to suppress the overlay for this selection.
public typealias BlockInputSelectionOverlayProvider =
    @MainActor (BlockInputSelectionOverlayContext) -> NSView?
