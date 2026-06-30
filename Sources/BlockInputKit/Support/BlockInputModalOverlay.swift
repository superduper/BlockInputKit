import AppKit

/// Host-provided placement for editor-owned link and image modals.
///
/// Return this from ``BlockInputConfiguration/modalOverlayProvider`` to choose both the destination parent view for a
/// modal and the frame it should occupy inside that parent.
public struct BlockInputModalOverlay {
    /// Parent view that should own the modal.
    public var container: NSView
    /// Modal frame in `container` coordinates.
    public var frame: NSRect

    /// Creates modal placement with an owning container and modal frame.
    public init(container: NSView, frame: NSRect) {
        self.container = container
        self.frame = frame
    }
}

/// Editor-owned modal type being presented.
public enum BlockInputModalKind: Equatable {
    /// The create/edit link modal.
    case link
    /// The insert image modal.
    case image
}

/// Layout values supplied when a host customizes link or image modal presentation.
public struct BlockInputModalOverlayContext {
    /// Editor requesting the modal.
    public var editorView: BlockInputView
    /// Modal type being presented.
    public var kind: BlockInputModalKind
    /// Default parent view chosen by the editor when the host does not override modal placement.
    public var defaultContainer: NSView
    /// Default modal frame in `defaultContainer` coordinates.
    public var defaultFrame: NSRect
    /// Measured modal size before host adjustment.
    public var modalSize: NSSize
    /// Source anchor in window coordinates.
    public var anchorWindowRect: NSRect

    /// Creates host overlay-placement context for a link or image modal request.
    public init(
        editorView: BlockInputView,
        kind: BlockInputModalKind,
        defaultContainer: NSView,
        defaultFrame: NSRect,
        modalSize: NSSize,
        anchorWindowRect: NSRect
    ) {
        self.editorView = editorView
        self.kind = kind
        self.defaultContainer = defaultContainer
        self.defaultFrame = defaultFrame
        self.modalSize = modalSize
        self.anchorWindowRect = anchorWindowRect
    }

    /// Converts the editor bounds into a candidate modal container.
    @MainActor
    public func editorFrame(in container: NSView) -> NSRect {
        container.convert(editorView.bounds, from: editorView)
    }

    /// Converts the modal anchor into a candidate modal container.
    @MainActor
    public func anchorRect(in container: NSView) -> NSRect {
        container.convert(anchorWindowRect, from: nil)
    }

    /// Returns a modal frame near the source anchor, clamped inside `container`.
    @MainActor
    public func modalFrame(
        in container: NSView,
        margin: CGFloat = 12,
        horizontalOffset: CGFloat = -12,
        verticalSpacing: CGFloat = 8
    ) -> NSRect {
        let anchor = anchorRect(in: container)
        let minX = container.bounds.minX + margin
        let maxX = container.bounds.maxX - modalSize.width - margin
        let originX = Self.clamped(anchor.minX + horizontalOffset, min: minX, max: maxX)
        let minY = container.bounds.minY + margin
        let maxY = container.bounds.maxY - modalSize.height - margin
        let preferredY = container.isFlipped
            ? anchor.maxY + verticalSpacing
            : anchor.minY - modalSize.height - verticalSpacing
        let preferredFits = container.isFlipped
            ? preferredY <= maxY
            : preferredY >= minY
        let fallbackY = container.isFlipped
            ? anchor.minY - modalSize.height - verticalSpacing
            : anchor.maxY + verticalSpacing
        let originY = Self.clamped(preferredFits ? preferredY : fallbackY, min: minY, max: maxY)
        return NSRect(origin: NSPoint(x: originX, y: originY), size: modalSize)
    }

    private static func clamped(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        guard maximum >= minimum else {
            return minimum
        }
        return Swift.min(Swift.max(value, minimum), maximum)
    }
}
