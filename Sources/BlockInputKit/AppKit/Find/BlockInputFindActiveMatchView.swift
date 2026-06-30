import AppKit
import QuartzCore

/// Subtle Apple-Notes-style emphasis drawn over the active find match. The dim scrim already
/// brightens the match; this overlay adds a thin accent ring and a brief scale pulse that draws the
/// eye when the user lands on a match (initial, next/prev, Return, button click).
///
/// Layer-backed like `BlockInputFindScrimView`; `hitTest` returns `nil` so it never intercepts
/// events and the editor stays interactive. Scroll-driven repositioning does not pulse.
final class BlockInputFindActiveMatchView: NSView {
    /// Rounding applied to the accent ring, matching the find highlight chrome feel.
    var cornerRadius: CGFloat = 3

    /// Number of times `pulse()` has run. A test seam so tests can assert that landing on a match
    /// kicked off the animation without depending on Core Animation interpolation.
    private(set) var pulseCount = 0

    /// Optional injected animator used by tests in place of the real Core Animation pulse.
    var animator: ((CALayer) -> Void)?

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
        let ring = bounds.insetBy(dx: ringWidth / 2, dy: ringWidth / 2)
        guard ring.width > 0, ring.height > 0 else {
            return
        }
        let path = NSBezierPath(roundedRect: ring, xRadius: cornerRadius, yRadius: cornerRadius)
        path.lineWidth = ringWidth
        accentColor.setStroke()
        path.stroke()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// Runs the subtle scale pulse (1.15 -> 1.0 over ~0.25s) about the layer's center, drawing the
    /// eye to the freshly landed match. Increments `pulseCount` so tests can assert it fired.
    func pulse() {
        pulseCount += 1
        guard let layer else {
            return
        }
        if let animator {
            animator(layer)
            return
        }
        centerLayerAnchor(layer)
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.15
        pulse.toValue = 1.0
        pulse.duration = 0.25
        pulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(pulse, forKey: "findActiveMatchPulse")
    }

    /// Anchors the layer at its own center so the scale grows about the rect center without moving
    /// the view frame. Position is compensated to the frame center to match the new anchor point.
    private func centerLayerAnchor(_ layer: CALayer) {
        guard layer.anchorPoint != CGPoint(x: 0.5, y: 0.5) else {
            return
        }
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: frame.midX, y: frame.midY)
    }

    private var ringWidth: CGFloat { 1.5 }

    private var accentColor: NSColor {
        NSColor.controlAccentColor.withAlphaComponent(0.9)
    }
}
