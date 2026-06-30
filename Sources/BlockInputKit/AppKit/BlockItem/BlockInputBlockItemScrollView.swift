import AppKit

/// Nested text scroller used by a block item.
///
/// Code blocks own horizontal overflow, but mostly vertical wheel sequences should keep moving the editor document.
final class BlockInputBlockItemScrollView: NSScrollView {
    weak var blockItem: BlockInputBlockItem?
    private var isForwardingVerticalScrollSequence = false
    private var verticalScrollSequenceToken = UUID()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        contentView = BlockInputBlockItemClipView()
        configureBoundsObservation()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        contentView = BlockInputBlockItemClipView()
        configureBoundsObservation()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        guard let event else {
            return false
        }
        return blockItem?.usesEditableTextSurfaceCursor == true || blockItem?.textView.linkHitResult(for: event) != nil
    }

    override func mouseDown(with event: NSEvent) {
        if blockItem?.textView.linkHitResult(for: event) != nil {
            blockItem?.textView.mouseDown(with: event)
            return
        }
        if blockItem?.routeEditableTextSurfaceMouseDown(event) == true {
            return
        }
        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        blockItem?.addEditableTextSurfaceCursorRectIfNeeded(to: self)
        blockItem?.addDisabledCursorRectIfNeeded(to: self)
    }

    override func cursorUpdate(with event: NSEvent) {
        guard blockItem?.applyEditableTextSurfaceCursor(at: nil) == true else {
            super.cursorUpdate(with: event)
            return
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if shouldBreakVerticalSequenceForHorizontalScroll(event),
           scrollHorizontallyIfNeeded(for: event) {
            isForwardingVerticalScrollSequence = false
            verticalScrollSequenceToken = UUID()
            return
        }
        if isForwardingVerticalScrollSequence,
           let verticalAncestorScrollView {
            verticalAncestorScrollView.scrollWheel(with: event)
            schedulePhaseLessVerticalScrollSequenceResetIfNeeded(for: event)
            updateVerticalScrollSequenceState(after: event)
            return
        }
        if scrollHorizontallyIfNeeded(for: event) {
            return
        }
        if shouldForwardVerticalScroll(event),
           let verticalAncestorScrollView {
            isForwardingVerticalScrollSequence = true
            schedulePhaseLessVerticalScrollSequenceResetIfNeeded(for: event)
            verticalAncestorScrollView.scrollWheel(with: event)
            updateVerticalScrollSequenceState(after: event)
            return
        }
        updateVerticalScrollSequenceState(after: event)
        super.scrollWheel(with: event)
    }

    private func configureBoundsObservation() {
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: contentView
        )
    }

    @objc
    private func contentBoundsDidChange() {
        guard contentView.bounds.origin.y != 0 else {
            blockItem?.textScrollViewDidChangeVisibleBounds()
            return
        }
        let origin = NSPoint(x: contentView.bounds.origin.x, y: 0)
        contentView.scroll(to: origin)
        reflectScrolledClipView(contentView)
        blockItem?.textScrollViewDidChangeVisibleBounds()
    }

    private func shouldForwardVerticalScroll(_ event: NSEvent) -> Bool {
        guard !event.modifierFlags.contains(.shift) else {
            return false
        }
        let deltaY = abs(verticalScrollDelta(for: event))
        return deltaY > 0 && deltaY >= abs(horizontalRawScrollDelta(for: event))
    }

    private func scrollHorizontallyIfNeeded(for event: NSEvent) -> Bool {
        guard hasHorizontalScroller,
              let horizontalDelta = horizontalScrollDelta(for: event),
              let documentView else {
            return false
        }
        let maximumX = max(0, documentView.frame.width - contentView.bounds.width)
        guard maximumX > 0 else {
            return false
        }
        let proposedX = contentView.bounds.origin.x - horizontalDelta
        let clampedX = min(max(0, proposedX), maximumX)
        guard clampedX != contentView.bounds.origin.x else {
            return true
        }
        contentView.scroll(to: NSPoint(x: clampedX, y: 0))
        reflectScrolledClipView(contentView)
        blockItem?.textScrollViewDidChangeVisibleBounds()
        return true
    }

    private func horizontalScrollDelta(for event: NSEvent) -> CGFloat? {
        let deltaX = horizontalRawScrollDelta(for: event)
        let deltaY = verticalScrollDelta(for: event)
        let rawDelta: CGFloat
        if abs(deltaX) > abs(deltaY) {
            rawDelta = deltaX
        } else if event.modifierFlags.contains(.shift), abs(deltaY) > 0 {
            rawDelta = deltaY
        } else {
            return nil
        }
        if event.hasPreciseScrollingDeltas {
            return rawDelta
        }
        return rawDelta * max(horizontalLineScroll, 1)
    }

    private func shouldBreakVerticalSequenceForHorizontalScroll(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.shift) &&
            (abs(verticalScrollDelta(for: event)) > 0 || abs(horizontalRawScrollDelta(for: event)) > 0)
    }

    private func horizontalRawScrollDelta(for event: NSEvent) -> CGFloat {
        event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.deltaX
    }

    private func verticalScrollDelta(for event: NSEvent) -> CGFloat {
        event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY
    }

    private func updateVerticalScrollSequenceState(after event: NSEvent) {
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) ||
            event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
            isForwardingVerticalScrollSequence = false
            verticalScrollSequenceToken = UUID()
        }
    }

    private func schedulePhaseLessVerticalScrollSequenceResetIfNeeded(for event: NSEvent) {
        guard event.phase == [], event.momentumPhase == [] else {
            return
        }
        let token = UUID()
        verticalScrollSequenceToken = token
        DispatchQueue.main.async { [weak self] in
            guard self?.verticalScrollSequenceToken == token else {
                return
            }
            self?.isForwardingVerticalScrollSequence = false
        }
    }

    private var verticalAncestorScrollView: NSScrollView? {
        var candidate = superview
        while let view = candidate {
            if let scrollView = view as? NSScrollView,
               scrollView !== self,
               scrollView.hasVerticalScroller {
                return scrollView
            }
            candidate = view.superview
        }
        return nil
    }
}

/// Clip view that preserves first-click link delivery when AppKit targets the scroll viewport instead of the text view.
private final class BlockInputBlockItemClipView: NSClipView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        guard let event,
              let scrollView = superview as? BlockInputBlockItemScrollView else {
            return false
        }
        return scrollView.blockItem?.usesEditableTextSurfaceCursor == true ||
            scrollView.blockItem?.textView.linkHitResult(for: event) != nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let scrollView = superview as? BlockInputBlockItemScrollView else {
            super.mouseDown(with: event)
            return
        }
        if scrollView.blockItem?.textView.linkHitResult(for: event) != nil {
            scrollView.blockItem?.textView.mouseDown(with: event)
            return
        }
        if scrollView.blockItem?.routeEditableTextSurfaceMouseDown(event) == true {
            return
        }
        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let scrollView = superview as? BlockInputBlockItemScrollView else {
            return
        }
        scrollView.blockItem?.addEditableTextSurfaceCursorRectIfNeeded(to: self)
        scrollView.blockItem?.addDisabledCursorRectIfNeeded(to: self)
    }

    override func cursorUpdate(with event: NSEvent) {
        guard let scrollView = superview as? BlockInputBlockItemScrollView,
              scrollView.blockItem?.applyEditableTextSurfaceCursor(at: nil) == true else {
            super.cursorUpdate(with: event)
            return
        }
    }
}
