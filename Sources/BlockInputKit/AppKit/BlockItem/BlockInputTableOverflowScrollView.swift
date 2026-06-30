import AppKit

/// Horizontal-only table overflow scroller.
///
/// Mostly vertical wheel sequences are forwarded to the nearest vertical
/// ancestor so table overflow remains stable inside the editor's vertical
/// scroll view. Phase-less vertical events reset on the next main-loop turn,
/// matching Alveary transcript table behavior.
final class BlockInputTableOverflowScrollView: NSScrollView {
    private var isForwardingVerticalScrollSequence = false
    private var verticalScrollSequenceToken = UUID()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        contentView = BlockInputTableClipView()
        configureOverflowScroller()
        configureBoundsObservation()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        contentView = BlockInputTableClipView()
        configureOverflowScroller()
        configureBoundsObservation()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func scrollWheel(with event: NSEvent) {
        if shouldForwardVerticalScroll(event),
           let verticalAncestorScrollView {
            isForwardingVerticalScrollSequence = true
            schedulePhaseLessVerticalScrollSequenceResetIfNeeded(for: event)
            verticalAncestorScrollView.scrollWheel(with: event)
            updateVerticalScrollSequenceState(after: event)
            return
        }
        if isForwardingVerticalScrollSequence,
           let verticalAncestorScrollView {
            verticalAncestorScrollView.scrollWheel(with: event)
            schedulePhaseLessVerticalScrollSequenceResetIfNeeded(for: event)
            updateVerticalScrollSequenceState(after: event)
            return
        }
        updateVerticalScrollSequenceState(after: event)
        super.scrollWheel(with: event)
    }

    private func configureOverflowScroller() {
        autohidesScrollers = true
        scrollerStyle = .overlay
        verticalScrollElasticity = .none
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
        if contentView.bounds.origin.y != 0 {
            contentView.scroll(to: NSPoint(x: contentView.bounds.origin.x, y: 0))
            reflectScrolledClipView(contentView)
        }
        tableViewAncestor?.updateAppendControlFrames()
    }

    private func shouldForwardVerticalScroll(_ event: NSEvent) -> Bool {
        let deltaY = abs(event.scrollingDeltaY)
        return deltaY > 0 && deltaY >= abs(event.scrollingDeltaX)
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
               scrollView !== self {
                return scrollView
            }
            candidate = view.superview
        }
        return nil
    }

    private var tableViewAncestor: BlockInputTableView? {
        var candidate = superview
        while let view = candidate {
            if let tableView = view as? BlockInputTableView {
                return tableView
            }
            candidate = view.superview
        }
        return nil
    }
}

private final class BlockInputTableClipView: NSClipView {
    override var isFlipped: Bool {
        true
    }
}
