import AppKit

extension NSAttributedString.Key {
    /// Marks the single trailing hidden-chrome character of a link/wikilink that should render the inline "open" icon.
    ///
    /// The value is a `BlockInputLinkOpenAttachment` carrying the icon image and its reserved advance width. The marked
    /// character stays in the source markdown (it is real chrome, e.g. the `]` closing `[label]`), so the storage string
    /// still equals the source — no U+FFFC is inserted and the length never changes. The glyph keeps a near-zero advance;
    /// a matching `.kern` reserves the icon's width, and `BlockInputTextView` paints the icon into that reserved gap.
    static let blockInputLinkOpenIcon = NSAttributedString.Key("BlockInputLinkOpenIcon")
}

/// Presentation-only descriptor for the inline link "open" icon painted at a link's trailing edge.
///
/// `NSTextAttachment`/the standard `.attachment` attribute only renders on a U+FFFC object-replacement character, which
/// would have to be inserted into the editable storage and would change the source length. To keep the storage string
/// equal to the source, this is drawn by `BlockInputTextView` over a `.kern`-reserved gap on an existing hidden chrome
/// character instead, so the icon still flows and wraps inline with the text without any source mutation.
final class BlockInputLinkOpenAttachment: NSObject {
    let image: NSImage
    /// Advance width reserved (via `.kern`) for the icon so it draws in a gap rather than overlapping the next glyph.
    let advance: CGFloat

    private init(image: NSImage, advance: CGFloat) {
        self.image = image
        self.advance = advance
    }

    /// Builds an icon sized to the link's font/line and tinted for the current appearance.
    static func make(font: NSFont, appearance: NSAppearance) -> BlockInputLinkOpenAttachment? {
        let pointSize = max(font.pointSize * 0.78, 8)
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        guard let baseImage = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: "Open Link")?
            .withSymbolConfiguration(configuration) else {
            return nil
        }
        let tinted = baseImage.blockInputTinted(with: tintColor(for: appearance))
        // A small leading inset keeps the icon from hugging the label's last glyph.
        let advance = tinted.size.width + 3
        return BlockInputLinkOpenAttachment(image: tinted, advance: advance)
    }

    private static func tintColor(for appearance: NSAppearance) -> NSColor {
        var color = NSColor.secondaryLabelColor
        appearance.performAsCurrentDrawingAppearance {
            color = BlockInputCompletionPopupStyle.defaultBorderColor.blended(
                withFraction: 0.45,
                of: .secondaryLabelColor
            ) ?? .secondaryLabelColor
        }
        return color
    }
}

private extension NSImage {
    /// Returns a copy flood-filled with `color` so the SF Symbol adopts the appearance-aware open-icon tint.
    func blockInputTinted(with color: NSColor) -> NSImage {
        let tinted = NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }
}
