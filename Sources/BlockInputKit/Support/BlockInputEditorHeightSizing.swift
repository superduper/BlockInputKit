import AppKit

/// Preferred editor height behavior for hosts that want the editor to size itself from rendered content.
public struct BlockInputEditorHeightSizing {
    /// Minimum/default viewport height expressed as a rendered line count.
    ///
    /// Empty and short documents use at least this much vertical space. The line count is converted through the current
    /// paragraph row metrics and editor vertical inset, so the resulting point height follows the configured style and
    /// leaves room for the same number of one-line paragraph blocks.
    public var defaultVisibleLineCount: Int
    /// Maximum viewport height expressed as a rendered line count.
    ///
    /// A `nil` value allows the editor to grow to its rendered content height. When non-nil, the line count uses the same
    /// paragraph row metrics as `defaultVisibleLineCount`, and extra content remains in the editor and scrolls vertically.
    public var maximumVisibleLineCount: Int?
    /// Called when the editor's clamped preferred height changes.
    ///
    /// The value is the height a host should assign to the editor viewport, not the unlimited natural document height.
    public var onPreferredHeightChange: (@MainActor (CGFloat) -> Void)?
    /// Animation metadata used for non-initial preferred-height transition callbacks.
    ///
    /// Set this to nil when transition callbacks should request immediate layout.
    public var animation: BlockInputEditorHeightAnimation?
    /// Called when the editor's clamped preferred height changes, including transition metadata.
    ///
    /// Hosts still own frame or constraint mutation. The transition reports the target height and, for non-initial
    /// changes, an optional animation to apply while resizing the editor container.
    public var onPreferredHeightTransition: (@MainActor (BlockInputEditorHeightTransition) -> Void)?

    /// Creates preferred editor height behavior.
    ///
    /// Counts less than one are sanitized by the editor when measuring. If `maximumVisibleLineCount` is smaller than
    /// `defaultVisibleLineCount`, the editor treats the maximum as equal to the default.
    public init(
        defaultVisibleLineCount: Int,
        maximumVisibleLineCount: Int? = nil,
        onPreferredHeightChange: (@MainActor (CGFloat) -> Void)? = nil
    ) {
        self.defaultVisibleLineCount = defaultVisibleLineCount
        self.maximumVisibleLineCount = maximumVisibleLineCount
        self.onPreferredHeightChange = onPreferredHeightChange
        animation = .default
        onPreferredHeightTransition = nil
    }

    /// Creates preferred editor height behavior with transition metadata for animated hosts.
    ///
    /// Counts less than one are sanitized by the editor when measuring. If `maximumVisibleLineCount` is smaller than
    /// `defaultVisibleLineCount`, the editor treats the maximum as equal to the default.
    public init(
        defaultVisibleLineCount: Int,
        maximumVisibleLineCount: Int? = nil,
        animation: BlockInputEditorHeightAnimation?,
        onPreferredHeightTransition: @escaping @MainActor (BlockInputEditorHeightTransition) -> Void
    ) {
        self.defaultVisibleLineCount = defaultVisibleLineCount
        self.maximumVisibleLineCount = maximumVisibleLineCount
        onPreferredHeightChange = nil
        self.animation = animation
        self.onPreferredHeightTransition = onPreferredHeightTransition
    }
}
