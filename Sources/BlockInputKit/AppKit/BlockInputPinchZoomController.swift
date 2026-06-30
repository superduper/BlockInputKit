import AppKit

/// Canvas pinch zoom + pan driven by a magnification gesture recognizer and a layer transform, with an
/// iOS-like kinetic feel: both the zoom and the pan track velocity during the gesture and, on release,
/// project further with a decaying glide before settling (a small flick travels more than 1:1). Pan
/// rubber-bands at the content edges; zoom springs back if flung past its range.
///
/// Why a layer transform, not `NSScrollView.allowsMagnification`: that scales the collection view's bounds,
/// making `NSCollectionViewFlowLayout` assert on invalid item sizes. A layer transform scales rendered pixels
/// only — the collection view's bounds and layout never change — so it stays crash-free and smooth.
@MainActor
final class BlockInputPinchZoomController {
    /// Whether pinch magnification is active. Disabling resets to 1x.
    var isEnabled = true {
        didSet {
            updateRecognizerEnabled()
            if !isEnabled {
                reset()
            }
        }
    }

    /// Temporarily suspends pinch handling without resetting the current zoom/pan — used while a modal
    /// overlay (e.g. the rendered-content zoom view) owns trackpad gestures.
    var isSuspended = false {
        didSet { updateRecognizerEnabled() }
    }

    private func updateRecognizerEnabled() {
        recognizer.isEnabled = isEnabled && !isSuspended
    }

    /// Smallest canvas scale (<= 1).
    var minimumScale: CGFloat = 1 {
        didSet { reclampToRange() }
    }
    /// Largest canvas scale (>= 1).
    var maximumScale: CGFloat = 4 {
        didSet { reclampToRange() }
    }

    /// Current canvas scale (`1` is unscaled).
    private(set) var scale: CGFloat = 1
    /// Current pan translation applied on top of the scale, in host points.
    private(set) var panOffset = CGSize.zero

    /// True while zoomed in, so the host should route two-finger scroll to `pan` instead of normal scroll.
    var isZoomed: Bool { scale > 1.0001 }

    private let recognizer = NSMagnificationGestureRecognizer()
    private weak var hostView: NSView?
    private weak var contentView: NSView?

    // Kinetic state shared by zoom and pan.
    private var gestureStartScale: CGFloat = 1
    private var scaleVelocity: CGFloat = 0          // scale units / second
    private var panVelocity = CGVector.zero          // points / second
    private var lastEventTime: TimeInterval?
    private var glideTimer: Timer?
    private var lastAnchor: NSPoint?

    /// Points of springy overscroll allowed past a pan edge before resistance fully pins it.
    private let rubberBandLimit: CGFloat = 110

    init() {
        recognizer.target = self
        recognizer.action = #selector(handleMagnify(_:))
    }

    /// Tears down the gesture recognizer and any running glide. The host calls this from its `deinit` to
    /// break the controller↔recognizer reference (NSGestureRecognizer retains its target) and stop the timer.
    func detach() {
        stopGlide()
        recognizer.target = nil
        recognizer.view?.removeGestureRecognizer(recognizer)
        hostView = nil
        contentView = nil
    }

    /// Installs the recognizer on `hostView` and transforms `contentView` (the scrollable document content).
    func attach(to hostView: NSView, contentView: NSView) {
        self.hostView = hostView
        self.contentView = contentView
        contentView.wantsLayer = true
        if recognizer.view !== hostView {
            recognizer.view.map { _ in hostView.removeGestureRecognizer(recognizer) }
            hostView.addGestureRecognizer(recognizer)
        }
    }

    /// Re-clamps the committed scale (and pan) into the current range — e.g. after the host reconfigures a
    /// tighter `maximumScale` while already zoomed past it — so the canvas never stays out of bounds.
    private func reclampToRange() {
        let clamped = clampScale(scale)
        guard clamped != scale else {
            return
        }
        scale = clamped
        panOffset = clampedPan(panOffset)
        applyTransform(anchor: lastAnchor, animated: true)
    }

    /// Resets the canvas to unscaled and unpanned.
    func reset() {
        stopGlide()
        scale = 1
        panOffset = .zero
        scaleVelocity = 0
        panVelocity = .zero
        applyTransform(anchor: nil)
    }

    // MARK: - Pan (host routes two-finger scroll here while zoomed)

    /// Pans the zoomed canvas. `phase` mirrors `NSEvent.phase`: `.changed` accumulates with velocity tracking,
    /// `.ended` launches a projected glide. Ignore native `momentumPhase` frames — we run our own kinetics.
    /// Returns true when consumed.
    @discardableResult
    func pan(deltaX: CGFloat, deltaY: CGFloat, phase: NSEvent.Phase, momentumPhase: NSEvent.Phase) -> Bool {
        guard isZoomed, !isSuspended else {
            return false
        }
        // Our own glide owns momentum; swallow the OS momentum stream so the two don't compound.
        if !momentumPhase.isEmpty {
            return true
        }
        switch phase {
        case .began, .mayBegin:
            // Apply the opening delta immediately (don't just reset) so the pan responds to the very first
            // movement instead of waiting for the first `.changed` — that lag is the "hold it a little" feel.
            stopGlide()
            lastEventTime = ProcessInfo.processInfo.systemUptime
            panVelocity = .zero
            applyPanDelta(deltaX: deltaX, deltaY: deltaY, trackVelocity: false)
            return true
        case .changed:
            applyPanDelta(deltaX: deltaX, deltaY: deltaY, trackVelocity: true)
            return true
        case .ended, .cancelled:
            launchPanGlide()
            return true
        default:
            // No-phase events (the first trackpad scroll frames before macOS recognizes the gesture, or a
            // legacy mouse wheel): apply directly so pan starts on frame one while zoomed.
            applyPanDelta(deltaX: deltaX, deltaY: deltaY, trackVelocity: true)
            return true
        }
    }

    private func applyPanDelta(deltaX: CGFloat, deltaY: CGFloat, trackVelocity: Bool) {
        if trackVelocity {
            let now = ProcessInfo.processInfo.systemUptime
            if let last = lastEventTime, now > last {
                let elapsed = CGFloat(now - last)
                // Blend toward the instantaneous velocity so a quick flick at the end dominates.
                let instantaneous = CGVector(dx: deltaX / elapsed, dy: deltaY / elapsed)
                panVelocity = CGVector(
                    dx: panVelocity.dx * 0.2 + instantaneous.dx * 0.8,
                    dy: panVelocity.dy * 0.2 + instantaneous.dy * 0.8
                )
            }
            lastEventTime = now
        }
        panOffset = rubberBanded(CGSize(width: panOffset.width + deltaX, height: panOffset.height + deltaY))
        applyTransform(anchor: nil)
    }

    // MARK: - Pinch

    @objc
    private func handleMagnify(_ sender: NSMagnificationGestureRecognizer) {
        let now = ProcessInfo.processInfo.systemUptime
        switch sender.state {
        case .began:
            stopGlide()
            gestureStartScale = scale
            scaleVelocity = 0
            // Clear leftover pan velocity so a pinch that follows a flicked pan doesn't inherit that drift.
            panVelocity = .zero
            lastEventTime = now
            lastAnchor = hostView.map { sender.location(in: $0) }
        case .changed:
            let previousScale = scale
            // While the fingers are still down, let the scale overshoot the range with resistance (held =
            // adjustable/elastic). It springs back to the clamped range on release via the settle.
            scale = rubberBandedScale(gestureStartScale * (1 + sender.magnification))
            lastAnchor = hostView.map { sender.location(in: $0) }
            if let last = lastEventTime, now > last {
                scaleVelocity = (scale - previousScale) / CGFloat(now - last)
            }
            lastEventTime = now
            panOffset = rubberBanded(panOffset)
            applyTransform(anchor: lastAnchor)
        case .ended:
            lastAnchor = hostView.map { sender.location(in: $0) }
            launchZoomGlide()
        case .cancelled, .failed:
            scaleVelocity = 0
            settleNow()
        default:
            break
        }
    }

    // MARK: - Kinetic glide (shared by zoom + pan)

    private func launchZoomGlide() {
        guard abs(scaleVelocity) > 0.05 || abs(panVelocity.dx) + abs(panVelocity.dy) > 1 else {
            settleNow()
            return
        }
        startGlide()
    }

    private func launchPanGlide() {
        guard abs(panVelocity.dx) + abs(panVelocity.dy) > 1 else {
            settleNow()
            return
        }
        startGlide()
    }

    /// One decaying-velocity animator advancing scale and pan each frame until both are slow, then a spring
    /// settle pins them to valid bounds. This is what makes a small flick travel further than the raw gesture.
    private func startGlide() {
        stopGlide()
        let interval = 1.0 / 60.0
        // Pan glides for a while (iOS-like distance); pinch carries only a short, quickly-fading kinetic tail.
        let panDecay: CGFloat = 0.94
        let scaleDecay: CGFloat = 0.80
        glideTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.advanceGlide(elapsed: CGFloat(interval), scaleDecay: scaleDecay, panDecay: panDecay)
            }
        }
    }

    /// One frame of the kinetic glide: advance scale + pan by their decaying velocities, then stop and settle
    /// once both are slow.
    private func advanceGlide(elapsed: CGFloat, scaleDecay: CGFloat, panDecay: CGFloat) {
        if abs(scaleVelocity) > 0.001 {
            scale = clampScale(scale + scaleVelocity * elapsed)
        }
        if abs(panVelocity.dx) + abs(panVelocity.dy) > 0.01 {
            panOffset = rubberBanded(CGSize(
                width: panOffset.width + panVelocity.dx * elapsed,
                height: panOffset.height + panVelocity.dy * elapsed
            ))
        }
        applyTransform(anchor: lastAnchor)
        scaleVelocity *= scaleDecay
        panVelocity = CGVector(dx: panVelocity.dx * panDecay, dy: panVelocity.dy * panDecay)
        let slow = abs(scaleVelocity) < 0.02 && abs(panVelocity.dx) + abs(panVelocity.dy) < 6
        if slow {
            stopGlide()
            settleNow()
        }
    }

    private func stopGlide() {
        glideTimer?.invalidate()
        glideTimer = nil
    }

    /// Springs scale and pan to their valid ranges with a short ease-out (cleans up rubber-band overscroll).
    private func settleNow() {
        scaleVelocity = 0
        panVelocity = .zero
        scale = clampScale(scale)
        panOffset = clampedPan(panOffset)
        applyTransform(anchor: lastAnchor, animated: true)
    }

    // MARK: - Clamping

    private func clampScale(_ value: CGFloat) -> CGFloat {
        min(max(value, minimumScale), maximumScale)
    }

    /// Allows elastic overshoot past the scale range while a pinch is held, with diminishing resistance, so a
    /// held pinch stays adjustable instead of hard-stopping. The settle springs it back into range on release.
    private func rubberBandedScale(_ value: CGFloat) -> CGFloat {
        let overshootLimit: CGFloat = 0.6  // max elastic overshoot in scale units
        if value > maximumScale {
            let over = value - maximumScale
            return maximumScale + overshootLimit * (1 - 1 / (over / overshootLimit + 1))
        }
        if value < minimumScale {
            let under = minimumScale - value
            return minimumScale - overshootLimit * (1 - 1 / (under / overshootLimit + 1))
        }
        return value
    }

    /// Hard pan bounds: the extra content each side that the scale reveals.
    private func panBounds() -> CGSize {
        guard let contentView, scale > 1 else {
            return .zero
        }
        return CGSize(
            width: max(0, contentView.bounds.width * (scale - 1) / 2),
            height: max(0, contentView.bounds.height * (scale - 1) / 2)
        )
    }

    private func clampedPan(_ pan: CGSize) -> CGSize {
        let bounds = panBounds()
        return CGSize(
            width: min(max(pan.width, -bounds.width), bounds.width),
            height: min(max(pan.height, -bounds.height), bounds.height)
        )
    }

    /// Like `clampedPan` but allows decaying overscroll past the edge (rubber-band) for an elastic feel.
    private func rubberBanded(_ pan: CGSize) -> CGSize {
        let bounds = panBounds()
        return CGSize(
            width: rubberBandAxis(pan.width, limit: bounds.width),
            height: rubberBandAxis(pan.height, limit: bounds.height)
        )
    }

    private func rubberBandAxis(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        guard abs(value) > limit else {
            return value
        }
        let overshoot = abs(value) - limit
        // Diminishing-returns resistance (UIScrollView-style): the further past the edge, the stiffer.
        let resisted = rubberBandLimit * (1 - 1 / (overshoot / rubberBandLimit + 1))
        return (value < 0 ? -1 : 1) * (limit + resisted)
    }

    // MARK: - Transform

    private func applyTransform(anchor: NSPoint?, animated: Bool = false) {
        guard let contentView, let layer = contentView.layer else {
            return
        }
        let bounds = contentView.bounds
        if let anchor, let hostView, bounds.width > 0, bounds.height > 0 {
            let anchorInContent = contentView.convert(anchor, from: hostView)
            let unit = CGPoint(
                x: (anchorInContent.x - bounds.minX) / bounds.width,
                y: (anchorInContent.y - bounds.minY) / bounds.height
            )
            setAnchorPreservingPosition(layer, unit: unit)
        }
        var transform = CATransform3DMakeTranslation(panOffset.width, panOffset.height, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.22)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        layer.transform = transform
        CATransaction.commit()
    }

    private func setAnchorPreservingPosition(_ layer: CALayer, unit: CGPoint) {
        guard layer.anchorPoint != unit else {
            return
        }
        let size = layer.bounds.size
        let shiftX = (unit.x - layer.anchorPoint.x) * size.width
        let shiftY = (unit.y - layer.anchorPoint.y) * size.height
        layer.anchorPoint = unit
        layer.position = CGPoint(x: layer.position.x + shiftX, y: layer.position.y + shiftY)
    }

    /// Test hook: force a committed scale (production scale is only set by the gesture recognizer).
    func applyScaleForTesting(_ newScale: CGFloat) {
        scale = clampScale(newScale)
        applyTransform(anchor: nil)
    }

    /// Test hook: apply a pan delta directly (bypassing phase/velocity tracking).
    @discardableResult
    func panByForTesting(deltaX: CGFloat, deltaY: CGFloat) -> Bool {
        guard isZoomed else { return false }
        panOffset = clampedPan(CGSize(width: panOffset.width + deltaX, height: panOffset.height + deltaY))
        applyTransform(anchor: nil)
        return true
    }
}
