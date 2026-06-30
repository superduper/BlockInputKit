import AppKit

/// A host-registered custom inline markup (e.g. wikilinks, @mentions, #tags).
///
/// Core knows no grammar: it asks the provider to scan a row's text and emit spans, then renders each span using the
/// returned style descriptor and routes interaction back by `identifier`. All ranges are UTF-16 `NSRange` over `text`,
/// must be row-local (never cross a newline), and must lie outside `excludedRanges` (inline code), exactly like the
/// built-in passes.
public protocol BlockInputInlineMarkupProvider: Sendable {
    /// Stable identity used to route clicks/hover/rewrites back to this provider. Must be unique per registration.
    var identifier: String { get }

    /// Scans `text` and returns the markup spans it owns, in ascending `fullRange.location` order.
    ///
    /// `excludedRanges` are inline-code spans already claimed by core, widened with the spans of any earlier-registered
    /// provider. Returned spans must not intersect them; spans from this provider are likewise excluded from every
    /// built-in pass and from later providers, so a custom markup is never re-parsed as a link or emphasized run (the
    /// same precedence the built-in wikilink pass has today).
    func spans(in text: String, excluding excludedRanges: [NSRange]) -> [BlockInputInlineMarkupSpan]

    /// How this markup opens the built-in edit modal, or `nil` (the default) when it is not modal-editable and a click
    /// only routes to the host `inlineLinkClickHandler`.
    var modalMode: BlockInputInlineMarkupModalMode? { get }
}

public extension BlockInputInlineMarkupProvider {
    /// Default: the markup is not modal-editable (click/hover route only to the host handler).
    var modalMode: BlockInputInlineMarkupModalMode? { nil }
}

/// How a custom markup opens the built-in edit modal: a title field plus a plain-text "target" field backed by the same
/// completion finder, instead of the URL field. A provider returns this when it wants modal editing.
///
/// `makeSource` carries a closure so this is `Sendable` but intentionally NOT `Equatable`.
public struct BlockInputInlineMarkupModalMode: Sendable {
    /// Label for the second (plain-text) field, e.g. "Target" (was hardcoded for wikilinks).
    public var targetFieldLabel: String
    /// Completion trigger identifier driving the field's finder popup (usually the same as the token trigger).
    public var finderTriggerID: String
    /// Builds the stored source from the saved (title, target) fields. The provider owns its grammar; core writes the
    /// returned string over the span's `fullRange` with the existing granular-replacement + undo path. `nil` leaves the
    /// source unchanged (e.g. an empty/invalid target).
    public var makeSource: @Sendable (_ title: String, _ target: String) -> String?

    public init(
        targetFieldLabel: String,
        finderTriggerID: String,
        makeSource: @escaping @Sendable (String, String) -> String?
    ) {
        self.targetFieldLabel = targetFieldLabel
        self.finderTriggerID = finderTriggerID
        self.makeSource = makeSource
    }
}

/// A host hook that asynchronously rewrites a block's source off the render hot path, as ONE undoable mutation.
///
/// Called when a block is (re)configured for display (never during attribute application/measurement). The editor
/// passes the live block text; the provider returns a full replacement string (its own grammar — e.g. rewriting bare
/// `[[slug]]` to `[[slug|title]]`) or `nil` to leave the source unchanged. The editor re-validates that the block text
/// is unchanged before applying, registers undo with `rewriteActionName`, and guards re-entry per `(identifier,
/// blockID)` so an applied rewrite that yields the same text cannot loop. Return the SAME string to signal "no change".
public protocol BlockInputInlineMarkupRewriter: Sendable {
    /// Routing identity (matches the provider's `identifier`).
    var identifier: String { get }
    /// Undo action name registered for an applied rewrite (e.g. "Resolve Wikilink Title").
    var rewriteActionName: String { get }
    /// Returns the rewritten block source, or `nil`/unchanged to leave it as-is. Runs on the main actor; may await.
    @MainActor func rewrittenSource(for text: String, blockID: BlockInputBlockID) async -> String?
}

/// Inline-code exclusion helper for custom-markup providers and rewriters that run their own row-local scan.
///
/// Core already excludes inline-code spans from the `spans(in:excluding:)` it passes a provider. A rewriter (or any
/// provider re-scanning a block's full source on its own) uses this to honor the same contract without importing core
/// internals: pass the returned ranges as the scanner's exclusions so a `[[...]]` inside `` `code` `` is ignored.
public enum BlockInputInlineMarkupExclusions {
    /// The UTF-16 `NSRange`s of every inline-code span (`` `code` ``) in `text`, including the backtick delimiters.
    public static func inlineCodeRanges(in text: String) -> [NSRange] {
        BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange)
    }
}

/// One custom-markup span: where it is, what shows, what chrome to hide, how to paint it, and click payload.
public struct BlockInputInlineMarkupSpan: Equatable, Sendable {
    /// Full source span including all chrome (the analogue of `fullRange`).
    public var fullRange: NSRange
    /// The visible, styled, hit-tested sub-range (the analogue of `contentRange`). Must be inside `fullRange`.
    public var contentRange: NSRange
    /// Sub-ranges hidden via the null-glyph mechanism (the analogue of `delimiterRanges`). Each must be inside
    /// `fullRange` and outside `contentRange`.
    public var hiddenRanges: [NSRange]
    /// Visual styling applied to `contentRange` (and across the open-icon gap).
    public var style: BlockInputInlineMarkupStyle
    /// Opaque payload echoed back in the click/hover context (slug, alias, target id, …). Core never inspects it.
    public var payload: BlockInputInlineMarkupPayload

    public init(
        fullRange: NSRange,
        contentRange: NSRange,
        hiddenRanges: [NSRange],
        style: BlockInputInlineMarkupStyle,
        payload: BlockInputInlineMarkupPayload
    ) {
        self.fullRange = fullRange
        self.contentRange = contentRange
        self.hiddenRanges = hiddenRanges
        self.style = style
        self.payload = payload
    }
}

/// Opaque, value-typed payload a provider attaches to a span and reads back on click/hover/rewrite.
///
/// Keeps core grammar-free: a wikilink plugin stores `target`/`alias`; a tag plugin stores its tag string.
public struct BlockInputInlineMarkupPayload: Equatable, Hashable, Sendable {
    /// Primary token used to synthesize the click destination URL (`<scheme>:<percent-encoded>`), e.g. the wikilink slug.
    public var primary: String
    /// Optional secondary display string, e.g. the wikilink alias. Surfaced as `alias`/`label` in the click context.
    public var secondary: String?

    public init(primary: String, secondary: String? = nil) {
        self.primary = primary
        self.secondary = secondary
    }
}

/// Declarative appearance for a custom markup's visible content. Core applies only these attributes; it never
/// hardcodes a markup's look. Mirrors how the built-in wikilink branch styles its content and open-icon gap.
///
/// NSColor makes this AppKit-coupled, like the other style descriptors; it is marked `@unchecked Sendable` to match
/// `BlockInputStyle`.
public struct BlockInputInlineMarkupStyle: Equatable, Hashable, @unchecked Sendable {
    /// Foreground color for the visible content. `nil` keeps the inherited text color.
    public var foregroundColor: NSColor?
    /// Single-underline the visible content (and the open-icon gap) in `underlineColor` (defaults to `foregroundColor`).
    public var underlines: Bool
    public var underlineColor: NSColor?
    /// Faint background fill behind the visible content (and the open-icon gap). `nil` = none.
    public var backgroundColor: NSColor?
    /// Attach the presentation-only trailing "open" icon (gated by `showsInlineLinkOpenButton`), like links/wikilinks.
    public var showsOpenIcon: Bool

    public init(
        foregroundColor: NSColor? = nil,
        underlines: Bool = false,
        underlineColor: NSColor? = nil,
        backgroundColor: NSColor? = nil,
        showsOpenIcon: Bool = false
    ) {
        self.foregroundColor = foregroundColor
        self.underlines = underlines
        self.underlineColor = underlineColor
        self.backgroundColor = backgroundColor
        self.showsOpenIcon = showsOpenIcon
    }
}
