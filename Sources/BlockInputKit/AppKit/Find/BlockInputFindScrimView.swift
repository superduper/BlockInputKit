import AppKit

/// Dim overlay drawn over the editor while find is active. The currently visible match rects are
/// "punched through" (left bright) so highlighted matches stand out against the dimmed content.
///
/// Modeled on `BlockInputSelectionBackgroundView`: layer-backed, redraws when its rects change, and
/// `hitTest` returns `nil` so it never intercepts events and the editor stays fully interactive.
final class BlockInputFindScrimView: NSView {
    /// On-screen match rects (in this view's coordinate space) that stay bright.
    var holeRects: [NSRect] = [] {
        didSet {
            needsDisplay = true
        }
    }

    /// Rounding applied to each punched-through hole, matching the find highlight chrome feel.
    var holeCornerRadius: CGFloat = 3

    /// Slight inset so the hole hugs the highlighted glyphs without leaking a bright border.
    var holeInset: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        dimColor.setFill()
        // Even-odd winding: the outer bounds rect plus each hole sub-rect cancel out where they
        // overlap, leaving the holes uncovered so matches below remain bright.
        let path = NSBezierPath()
        path.windingRule = .evenOdd
        path.appendRect(bounds)
        for hole in holeRects {
            let inset = hole.insetBy(dx: holeInset, dy: holeInset)
            guard inset.width > 0, inset.height > 0 else {
                continue
            }
            path.append(NSBezierPath(roundedRect: inset, xRadius: holeCornerRadius, yRadius: holeCornerRadius))
        }
        path.fill()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// Subtle, appearance-aware dim. Dark mode dims with white so content stays legible; light mode
    /// dims with black. Both kept low-alpha so the overlay reads as a wash, not a blackout.
    private var dimColor: NSColor {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor.black.withAlphaComponent(0.32)
            : NSColor.black.withAlphaComponent(0.18)
    }
}

extension BlockInputFindScrimView {
    /// Test accessor for the current punch-through rects.
    var holeRectsForTesting: [NSRect] {
        holeRects
    }
}
