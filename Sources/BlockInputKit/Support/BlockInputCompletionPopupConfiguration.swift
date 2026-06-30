import AppKit

/// Host-provided popup placement inside an overlay surface.
///
/// Return this from `BlockInputCompletionPopupConfiguration.overlayProvider` to choose both the destination parent
/// view for the popup and the frame it should occupy inside that parent.
public struct BlockInputCompletionPopupOverlay {
    /// Parent view that should own the popup.
    public var container: NSView
    /// Popup frame in `container` coordinates.
    public var frame: NSRect

    /// Creates overlay placement with an owning container and popup frame.
    public init(container: NSView, frame: NSRect) {
        self.container = container
        self.frame = frame
    }
}

/// Layout values supplied when a host customizes overlay popup presentation.
public struct BlockInputCompletionPopupOverlayContext {
    /// Editor requesting the popup.
    public var editorView: BlockInputView
    /// Default parent view chosen by the editor when the host does not override popup placement.
    public var defaultContainer: NSView
    /// Default popup frame in `defaultContainer` coordinates.
    public var defaultFrame: NSRect
    /// Measured popup size before host adjustment.
    public var popupSize: NSSize

    /// Creates host overlay-placement context for a completion popup request.
    public init(
        editorView: BlockInputView,
        defaultContainer: NSView,
        defaultFrame: NSRect,
        popupSize: NSSize
    ) {
        self.editorView = editorView
        self.defaultContainer = defaultContainer
        self.defaultFrame = defaultFrame
        self.popupSize = popupSize
    }

    /// Converts the editor bounds into a candidate popup container.
    @MainActor
    public func editorFrame(in container: NSView) -> NSRect {
        container.convert(editorView.bounds, from: editorView)
    }
}

/// Visual styling for the built-in completion popup.
public struct BlockInputCompletionPopupStyle: @unchecked Sendable {
    /// Current built-in popup style.
    public static var `default`: BlockInputCompletionPopupStyle {
        BlockInputCompletionPopupStyle()
    }

    /// Appearance-aware default popup fill.
    public static var defaultBackgroundColor: NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .darkAqua:
                return NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.17, alpha: 1)
            default:
                return NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.97, alpha: 1)
            }
        }
    }

    /// Appearance-aware default popup border color.
    public static var defaultBorderColor: NSColor {
        NSColor.separatorColor.withAlphaComponent(0.24)
    }

    /// Default highlight fill for the selected completion row.
    public static var defaultHighlightedRowBackgroundColor: NSColor {
        NSColor.controlAccentColor.withAlphaComponent(0.13)
    }

    /// Popup fill color.
    public var backgroundColor: NSColor
    /// Popup border color. When nil, no border is drawn.
    public var borderColor: NSColor?
    /// Highlight fill for the selected completion row.
    public var highlightedRowBackgroundColor: NSColor
    /// Highlight corner radius for the selected completion row. When nil, the popup corner radius is used.
    public var highlightedRowCornerRadius: CGFloat? {
        didSet {
            highlightedRowCornerRadius = highlightedRowCornerRadius.map(Self.validNonNegative)
        }
    }
    /// Popup corner radius. Negative values are clamped to zero.
    public var cornerRadius: CGFloat {
        didSet {
            cornerRadius = Self.validNonNegative(cornerRadius)
        }
    }
    /// Popup border width. Negative values are clamped to zero.
    public var borderWidth: CGFloat {
        didSet {
            borderWidth = Self.validNonNegative(borderWidth)
        }
    }

    /// Creates completion popup styling overrides.
    public init(
        backgroundColor: NSColor = BlockInputCompletionPopupStyle.defaultBackgroundColor,
        borderColor: NSColor? = BlockInputCompletionPopupStyle.defaultBorderColor,
        highlightedRowBackgroundColor: NSColor = BlockInputCompletionPopupStyle.defaultHighlightedRowBackgroundColor,
        highlightedRowCornerRadius: CGFloat? = nil,
        cornerRadius: CGFloat = 10,
        borderWidth: CGFloat = 1
    ) {
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.highlightedRowBackgroundColor = highlightedRowBackgroundColor
        self.highlightedRowCornerRadius = highlightedRowCornerRadius.map(Self.validNonNegative)
        self.cornerRadius = Self.validNonNegative(cornerRadius)
        self.borderWidth = Self.validNonNegative(borderWidth)
    }

    var resolvedHighlightedRowCornerRadius: CGFloat {
        highlightedRowCornerRadius ?? cornerRadius
    }

    private static func validNonNegative(_ value: CGFloat) -> CGFloat {
        max(0, value)
    }
}

/// Built-in completion popup behavior and host integration points.
public struct BlockInputCompletionPopupConfiguration {
    /// Where the editor-owned completion popup should be shown.
    public var placement: BlockInputCompletionPopupPlacement
    /// Visual styling for the built-in popup.
    public var style: BlockInputCompletionPopupStyle
    /// Optional host override for overlay popup presentation.
    ///
    /// Return both the parent view and popup frame in that parent's coordinate space. Keeping the container and frame
    /// together lets hosts rehost the popup into another surface while aligning it to that surface. When nil, the
    /// editor falls back to the window content view, then its superview, then itself, and anchors the popup above the
    /// editor.
    public var overlayProvider: (@MainActor (BlockInputCompletionPopupOverlayContext) -> BlockInputCompletionPopupOverlay?)?

    /// Creates built-in completion popup behavior.
    public init(
        placement: BlockInputCompletionPopupPlacement = .caret,
        style: BlockInputCompletionPopupStyle = .default,
        overlayProvider: (@MainActor (BlockInputCompletionPopupOverlayContext) -> BlockInputCompletionPopupOverlay?)? = nil
    ) {
        self.placement = placement
        self.style = style
        self.overlayProvider = overlayProvider
    }
}
