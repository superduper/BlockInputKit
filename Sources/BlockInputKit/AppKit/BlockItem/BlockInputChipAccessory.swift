import AppKit

extension NSAttributedString.Key {
    /// Marks the leading hidden-chrome character of a file chip that carries a host-drawn leading accessory.
    ///
    /// The value is a `BlockInputChipAccessoryAttachment`. The marked character (the `[` opening `[label]`) stays in the
    /// source markdown, so storage still equals the source; a matching `.kern` reserves the accessory's width and
    /// `BlockInputTextView` calls the accessory's draw closure to paint into that gap.
    static let blockInputChipLeadingAccessory = NSAttributedString.Key("BlockInputChipLeadingAccessory")
    /// Marks the trailing hidden-chrome character of a file chip that carries a host-drawn trailing accessory (e.g. a
    /// `PDF`-style pill after the label). Same kern-reserve + paint technique as the leading accessory.
    static let blockInputChipTrailingAccessory = NSAttributedString.Key("BlockInputChipTrailingAccessory")
}

/// Host-supplied leading chrome for a file chip (a type icon, a `PDF`-style pill tag, etc.).
///
/// Core is policy-free: it reserves `reservedWidth` before the chip label and calls `draw` to paint into that gap; it
/// never knows what is drawn. `hidesLabelExtension` optionally collapses the file extension out of the visible label
/// (the extension stays in the source). Mirrors the trailing link "open icon" technique so storage equals the source.
public struct BlockInputChipAccessory: Sendable {
    /// Advance reserved (via `.kern`) before the chip label so the leading accessory draws in its own gap.
    public var reservedWidth: CGFloat
    /// Advance reserved (via `.kern`) after the chip label so the trailing accessory draws in its own gap.
    public var trailingReservedWidth: CGFloat
    /// Whether to hide the chip label's trailing file extension (e.g. show `Report` for `Report.pdf`).
    public var hidesLabelExtension: Bool
    /// Paints the LEADING accessory into `rect`, in the text view's coordinate space (flipped: y increases downward).
    /// Standard AppKit drawing (`NSString.draw(in:)`, `NSBezierPath`, `NSImage.draw(in:)`) renders upright here.
    public var draw: @MainActor @Sendable (_ rect: NSRect) -> Void
    /// Paints the TRAILING accessory into `rect` (after the label). Same coordinate space as `draw`. Nil = no trailing.
    public var drawTrailing: (@MainActor @Sendable (_ rect: NSRect) -> Void)?

    /// Creates a chip accessory with an optional leading and/or trailing component.
    ///
    /// `reservedWidth`/`draw` reserve and paint chrome before the label; `trailingReservedWidth`/`drawTrailing` do the
    /// same after the label. Either side may be zero/nil. For a leading-only accessory, omit the trailing parameters.
    public init(
        reservedWidth: CGFloat,
        hidesLabelExtension: Bool = false,
        draw: @escaping @MainActor @Sendable (_ rect: NSRect) -> Void,
        trailingReservedWidth: CGFloat = 0,
        drawTrailing: (@MainActor @Sendable (_ rect: NSRect) -> Void)? = nil
    ) {
        self.reservedWidth = max(reservedWidth, 0)
        self.trailingReservedWidth = max(trailingReservedWidth, 0)
        self.hidesLabelExtension = hidesLabelExtension
        self.draw = draw
        self.drawTrailing = drawTrailing
    }
}

/// Context describing the chip an accessory is being requested for.
public struct BlockInputChipContext {
    /// The chip's resolved file destination URL.
    public var destination: URL
    /// The chip's visible label (the Markdown link text).
    public var label: String

    /// Creates chip context for accessory resolution.
    public init(destination: URL, label: String) {
        self.destination = destination
        self.label = label
    }
}

/// Storage wrapper letting a `BlockInputChipAccessory` (a value type) ride on a text attribute and be kept by the
/// delimiter-glyph delegate. Mirrors `BlockInputLinkOpenAttachment`.
final class BlockInputChipAccessoryAttachment: NSObject {
    let accessory: BlockInputChipAccessory

    init(accessory: BlockInputChipAccessory) {
        self.accessory = accessory
    }
}
