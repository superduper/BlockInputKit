import AppKit

/// Visual styling used by AppKit block editor surfaces.
public struct BlockInputStyle: @unchecked Sendable {
    /// Current built-in visual style.
    public static var `default`: BlockInputStyle { BlockInputStyle() }

    /// Base text styling for paragraphs, lists, quotes, and scaled block typography.
    public var baseText: BlockInputTextStyle
    /// Background color used for editor-owned block and text selection chrome.
    public var selectionBackgroundColor: NSColor
    /// Styling for inline single-line code spans.
    public var inlineCode: BlockInputInlineCodeStyle
    /// Styling for fenced code block surfaces.
    public var codeBlock: BlockInputCodeBlockStyle
    /// Styling for image block surfaces.
    public var imageBlock: BlockInputImageBlockStyle
    /// Styling for the editor-owned image preview strip.
    public var imagePreviewStrip: BlockInputImagePreviewStripStyle
    /// Styling for editor-owned background surfaces.
    public var editorSurface: BlockInputEditorSurfaceStyle
    /// Styling for inline file-link chips.
    public var fileChip: BlockInputInlineChipStyle
    /// Styling for link-backed slash-command chips.
    public var slashCommandChip: BlockInputInlineChipStyle
    /// Styling for raw `/command` visual chips.
    public var rawSlashCommandChip: BlockInputInlineChipStyle

    /// Creates editor styling with optional overrides for built-in visual defaults.
    public init(
        baseText: BlockInputTextStyle = BlockInputTextStyle(),
        selectionBackgroundColor: NSColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.72),
        inlineCode: BlockInputInlineCodeStyle = BlockInputInlineCodeStyle(),
        codeBlock: BlockInputCodeBlockStyle = BlockInputCodeBlockStyle(),
        imageBlock: BlockInputImageBlockStyle = BlockInputImageBlockStyle(),
        imagePreviewStrip: BlockInputImagePreviewStripStyle = BlockInputImagePreviewStripStyle(),
        editorSurface: BlockInputEditorSurfaceStyle = BlockInputEditorSurfaceStyle(),
        fileChip: BlockInputInlineChipStyle = BlockInputInlineChipStyle(),
        slashCommandChip: BlockInputInlineChipStyle = BlockInputInlineChipStyle(),
        rawSlashCommandChip: BlockInputInlineChipStyle = BlockInputInlineChipStyle()
    ) {
        self.baseText = baseText
        self.selectionBackgroundColor = selectionBackgroundColor
        self.inlineCode = inlineCode
        self.codeBlock = codeBlock
        self.imageBlock = imageBlock
        self.imagePreviewStrip = imagePreviewStrip
        self.editorSurface = editorSurface
        self.fileChip = fileChip
        self.slashCommandChip = slashCommandChip
        self.rawSlashCommandChip = rawSlashCommandChip
    }
}

/// Visual styling for the textual-image preview strip.
public struct BlockInputImagePreviewStripStyle: @unchecked Sendable {
    /// Thumbnail display size. Width and height values are clamped to at least `1`.
    public var thumbnailSize: NSSize {
        didSet {
            thumbnailSize = Self.validSize(thumbnailSize)
        }
    }
    /// Padding around the thumbnail row inside the strip.
    public var contentInsets: NSEdgeInsets {
        didSet {
            contentInsets = Self.validInsets(contentInsets)
        }
    }
    /// Horizontal spacing between thumbnail tiles. Negative values are clamped to zero.
    public var interItemSpacing: CGFloat {
        didSet {
            interItemSpacing = Self.validNonNegative(interItemSpacing)
        }
    }
    /// Strip background color. When nil, the strip stays transparent.
    public var backgroundColor: NSColor?
    /// Thumbnail border color. When nil, no border is drawn.
    public var borderColor: NSColor?
    /// Thumbnail border width. Negative values are clamped to zero.
    public var borderWidth: CGFloat {
        didSet {
            borderWidth = Self.validNonNegative(borderWidth)
        }
    }
    /// Thumbnail corner radius. Negative values are clamped to zero.
    public var cornerRadius: CGFloat {
        didSet {
            cornerRadius = Self.validNonNegative(cornerRadius)
        }
    }
    /// Remove button styling shown over each thumbnail.
    public var removeButton: BlockInputImagePreviewRemoveButtonStyle

    /// Creates image preview strip styling overrides.
    public init(
        thumbnailSize: NSSize = NSSize(width: 76, height: 76),
        contentInsets: NSEdgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12),
        interItemSpacing: CGFloat = 12,
        backgroundColor: NSColor? = nil,
        borderColor: NSColor? = NSColor.separatorColor.withAlphaComponent(0.35),
        borderWidth: CGFloat = 1,
        cornerRadius: CGFloat = 12,
        removeButton: BlockInputImagePreviewRemoveButtonStyle = BlockInputImagePreviewRemoveButtonStyle()
    ) {
        self.thumbnailSize = Self.validSize(thumbnailSize)
        self.contentInsets = Self.validInsets(contentInsets)
        self.interItemSpacing = Self.validNonNegative(interItemSpacing)
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.borderWidth = Self.validNonNegative(borderWidth)
        self.cornerRadius = Self.validNonNegative(cornerRadius)
        self.removeButton = removeButton
    }

    var preferredHeight: CGFloat {
        contentInsets.top + thumbnailSize.height + contentInsets.bottom
    }

    private static func validSize(_ size: NSSize) -> NSSize {
        NSSize(width: max(1, size.width), height: max(1, size.height))
    }

    private static func validInsets(_ insets: NSEdgeInsets) -> NSEdgeInsets {
        NSEdgeInsets(
            top: validNonNegative(insets.top),
            left: validNonNegative(insets.left),
            bottom: validNonNegative(insets.bottom),
            right: validNonNegative(insets.right)
        )
    }

    private static func validNonNegative(_ value: CGFloat) -> CGFloat {
        value.isFinite ? max(0, value) : 0
    }
}

/// Visual styling for preview-strip remove buttons.
public struct BlockInputImagePreviewRemoveButtonStyle: @unchecked Sendable {
    /// Whether thumbnail remove buttons are shown.
    public var isVisible: Bool
    /// Remove button size. Width and height values are clamped to at least `1`.
    public var size: NSSize {
        didSet {
            size = Self.validSize(size)
        }
    }
    /// Distance from the thumbnail's top and trailing edges. Negative values are clamped to zero.
    public var edgeInset: CGFloat {
        didSet {
            edgeInset = Self.validNonNegative(edgeInset)
        }
    }
    /// Button fill color.
    public var backgroundColor: NSColor
    /// Button border color. When nil, no border is drawn.
    public var borderColor: NSColor?
    /// Button border width. Negative values are clamped to zero.
    public var borderWidth: CGFloat {
        didSet {
            borderWidth = Self.validNonNegative(borderWidth)
        }
    }
    /// Button corner radius. Negative values are clamped to zero.
    public var cornerRadius: CGFloat {
        didSet {
            cornerRadius = Self.validNonNegative(cornerRadius)
        }
    }
    /// Symbol foreground color.
    public var symbolColor: NSColor
    /// Symbol point size. Non-positive values use the built-in symbol size.
    public var symbolPointSize: CGFloat?
    /// Drop shadow color. When nil, no shadow is drawn.
    public var shadowColor: NSColor?
    /// Drop shadow opacity.
    public var shadowOpacity: Float {
        didSet {
            shadowOpacity = min(max(shadowOpacity, 0), 1)
        }
    }
    /// Drop shadow blur radius. Negative values are clamped to zero.
    public var shadowRadius: CGFloat {
        didSet {
            shadowRadius = Self.validNonNegative(shadowRadius)
        }
    }
    /// Drop shadow offset.
    public var shadowOffset: NSSize

    /// Creates preview-strip remove button styling overrides.
    public init(
        isVisible: Bool = true,
        size: NSSize = NSSize(width: 20, height: 20),
        edgeInset: CGFloat = 5,
        backgroundColor: NSColor = .controlBackgroundColor,
        borderColor: NSColor? = NSColor.separatorColor.withAlphaComponent(0.32),
        borderWidth: CGFloat = 1,
        cornerRadius: CGFloat = 10,
        symbolColor: NSColor = .labelColor,
        symbolPointSize: CGFloat? = 11,
        shadowColor: NSColor? = .black,
        shadowOpacity: Float = 0.18,
        shadowRadius: CGFloat = 3,
        shadowOffset: NSSize = NSSize(width: 0, height: -1)
    ) {
        self.isVisible = isVisible
        self.size = Self.validSize(size)
        self.edgeInset = Self.validNonNegative(edgeInset)
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.borderWidth = Self.validNonNegative(borderWidth)
        self.cornerRadius = Self.validNonNegative(cornerRadius)
        self.symbolColor = symbolColor
        self.symbolPointSize = symbolPointSize.flatMap { $0 > 0 ? $0 : nil }
        self.shadowColor = shadowColor
        self.shadowOpacity = min(max(shadowOpacity, 0), 1)
        self.shadowRadius = Self.validNonNegative(shadowRadius)
        self.shadowOffset = shadowOffset
    }

    private static func validSize(_ size: NSSize) -> NSSize {
        NSSize(width: max(1, size.width), height: max(1, size.height))
    }

    private static func validNonNegative(_ value: CGFloat) -> CGFloat {
        value.isFinite ? max(0, value) : 0
    }
}

/// Background styling for editor-owned AppKit surfaces.
///
/// Each color defaults to `NSColor.textBackgroundColor`. Set a color to nil when the host should draw that surface.
public struct BlockInputEditorSurfaceStyle: @unchecked Sendable {
    /// Root editor view background color. When nil, the root view layer is transparent.
    public var editorBackgroundColor: NSColor?
    /// Document scroll view background color. When nil, the scroll and clip views do not draw their backgrounds.
    public var scrollBackgroundColor: NSColor?
    /// Collection view background color. When nil, the collection view uses an empty `backgroundColors` array.
    public var collectionBackgroundColor: NSColor?
    /// Optional rounded editor chrome drawn by the root editor view.
    public var chrome: BlockInputEditorChromeStyle?

    /// Creates editor surface styling overrides.
    public init(
        editorBackgroundColor: NSColor? = .textBackgroundColor,
        scrollBackgroundColor: NSColor? = .textBackgroundColor,
        collectionBackgroundColor: NSColor? = .textBackgroundColor,
        chrome: BlockInputEditorChromeStyle? = nil
    ) {
        self.editorBackgroundColor = editorBackgroundColor
        self.scrollBackgroundColor = scrollBackgroundColor
        self.collectionBackgroundColor = collectionBackgroundColor
        self.chrome = chrome
    }
}

/// Root editor chrome drawn behind the editor's scrollable document surface.
public struct BlockInputEditorChromeStyle: @unchecked Sendable {
    /// Chrome fill color. When nil, the root editor background color is used.
    public var fillColor: NSColor?
    /// Optional chrome stroke color. When nil, no stroke is drawn.
    public var strokeColor: NSColor?
    /// Chrome stroke width. Negative values are clamped to zero.
    public var borderWidth: CGFloat {
        didSet {
            borderWidth = Self.validNonNegative(borderWidth)
        }
    }
    /// Chrome corner radius. Negative values are clamped to zero.
    public var cornerRadius: CGFloat {
        didSet {
            cornerRadius = Self.validNonNegative(cornerRadius)
        }
    }
    /// Corners that should use `cornerRadius`.
    public var roundedCorners: BlockInputEditorChromeCorners
    /// Whether editor content should be clipped to the rounded chrome shape.
    public var clipsContentToShape: Bool

    /// Creates rounded editor chrome styling.
    public init(
        fillColor: NSColor? = nil,
        strokeColor: NSColor? = nil,
        borderWidth: CGFloat = 0,
        cornerRadius: CGFloat = 0,
        roundedCorners: BlockInputEditorChromeCorners = .all,
        clipsContentToShape: Bool = false
    ) {
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.borderWidth = Self.validNonNegative(borderWidth)
        self.cornerRadius = Self.validNonNegative(cornerRadius)
        self.roundedCorners = roundedCorners
        self.clipsContentToShape = clipsContentToShape
    }

    private static func validNonNegative(_ value: CGFloat) -> CGFloat {
        max(0, value)
    }
}

/// Corners that can be rounded by `BlockInputEditorChromeStyle`.
public struct BlockInputEditorChromeCorners: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let topLeft = BlockInputEditorChromeCorners(rawValue: 1 << 0)
    public static let topRight = BlockInputEditorChromeCorners(rawValue: 1 << 1)
    public static let bottomLeft = BlockInputEditorChromeCorners(rawValue: 1 << 2)
    public static let bottomRight = BlockInputEditorChromeCorners(rawValue: 1 << 3)

    public static let top: BlockInputEditorChromeCorners = [.topLeft, .topRight]
    public static let bottom: BlockInputEditorChromeCorners = [.bottomLeft, .bottomRight]
    public static let all: BlockInputEditorChromeCorners = [.top, .bottom]
}

/// Fill, stroke, foreground, and rounding styling for inline chips.
///
/// This is visual-only styling for file, link-backed slash-command, and raw slash-command chips. Regular Markdown links
/// keep the editor's normal link styling unless they resolve to a chip kind.
public struct BlockInputInlineChipStyle: @unchecked Sendable {
    /// Chip fill color. When nil, the chip fill is not drawn.
    public var fillColor: NSColor?
    /// Chip stroke color. When nil, the chip stroke is not drawn.
    public var strokeColor: NSColor?
    /// Chip text foreground color, including for link-backed chips that would otherwise use the system link color.
    public var foregroundColor: NSColor
    /// Chip corner radius. Negative values are clamped to zero.
    public var cornerRadius: CGFloat {
        didSet {
            cornerRadius = Self.validCornerRadius(cornerRadius)
        }
    }

    /// Creates inline chip styling overrides.
    public init(
        fillColor: NSColor? = NSColor.controlAccentColor.withAlphaComponent(0.11),
        strokeColor: NSColor? = NSColor.controlAccentColor.withAlphaComponent(0.18),
        foregroundColor: NSColor = .labelColor,
        cornerRadius: CGFloat = 6
    ) {
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.foregroundColor = foregroundColor
        self.cornerRadius = Self.validCornerRadius(cornerRadius)
    }

    private static func validCornerRadius(_ value: CGFloat) -> CGFloat {
        max(0, value)
    }
}

/// Background, border, and corner styling for image block surfaces.
public struct BlockInputImageBlockStyle: @unchecked Sendable {
    /// Placeholder aspect ratio used for image blocks whose width and height are still unknown.
    public var placeholderAspectRatio: CGFloat? {
        didSet {
            placeholderAspectRatio = placeholderAspectRatio.flatMap(Self.validAspectRatio)
        }
    }
    /// Placeholder fill color shown before an image has loaded.
    public var placeholderColor: NSColor?
    /// Optional border color for placeholder, loaded, and failed image surfaces.
    ///
    /// When nil, image surfaces do not draw a border.
    public var borderColor: NSColor?
    /// Surface corner radius. When nil, images use the built-in radius.
    public var cornerRadius: CGFloat?

    /// Creates image block styling overrides.
    public init(
        placeholderAspectRatio: CGFloat? = nil,
        placeholderColor: NSColor? = nil,
        borderColor: NSColor? = nil,
        cornerRadius: CGFloat? = nil
    ) {
        self.placeholderAspectRatio = placeholderAspectRatio.flatMap(Self.validAspectRatio)
        self.placeholderColor = placeholderColor
        self.borderColor = borderColor
        self.cornerRadius = cornerRadius
    }

    private static func validAspectRatio(_ value: CGFloat) -> CGFloat? {
        value > 0 ? value : nil
    }
}

/// Font and foreground color styling for normal editor text.
public struct BlockInputTextStyle: @unchecked Sendable {
    /// Base font for body text. When nil, the editor uses its built-in body font.
    public var font: NSFont?
    /// Base foreground color. When nil, the editor uses the system label color.
    public var foregroundColor: NSColor?

    /// Creates normal text styling overrides.
    public init(font: NSFont? = nil, foregroundColor: NSColor? = nil) {
        self.font = font
        self.foregroundColor = foregroundColor
    }
}

/// Font, foreground, and background styling for inline code spans.
public struct BlockInputInlineCodeStyle: @unchecked Sendable {
    /// Inline code font. When nil, inline code uses a scaled monospaced variant of the surrounding text font.
    public var font: NSFont?
    /// Inline code foreground color. When nil, inline code inherits the base text foreground color.
    public var foregroundColor: NSColor?
    /// Inline code background color. When nil, inline code uses the built-in subtle background color.
    public var backgroundColor: NSColor?

    /// Creates inline code styling overrides.
    public init(font: NSFont? = nil, foregroundColor: NSColor? = nil, backgroundColor: NSColor? = nil) {
        self.font = font
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
    }
}

/// Font, foreground, background, and rounding styling for fenced code block surfaces.
public struct BlockInputCodeBlockStyle: @unchecked Sendable {
    /// Fenced code block font. When nil, code blocks use the built-in monospaced font.
    public var font: NSFont?
    /// Fenced code block foreground color. When nil, code text uses syntax highlighting with the base text color fallback.
    public var foregroundColor: NSColor?
    /// Fenced code block background color. When nil, code blocks use the built-in appearance-aware surface color.
    public var backgroundColor: NSColor?
    /// Fenced code block corner radius. When nil, code blocks use the built-in radius.
    public var cornerRadius: CGFloat?

    /// Creates fenced code block styling overrides.
    public init(
        font: NSFont? = nil,
        foregroundColor: NSColor? = nil,
        backgroundColor: NSColor? = nil,
        cornerRadius: CGFloat? = nil
    ) {
        self.font = font
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.cornerRadius = cornerRadius
    }
}
