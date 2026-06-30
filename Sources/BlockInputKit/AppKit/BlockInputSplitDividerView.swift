import AppKit
/// A thin draggable divider between the editor and preview; reports the drag delta along its axis.
final class BlockInputSplitDividerView: NSView {
    enum Orientation { case horizontal, vertical }

    var orientation: Orientation = .horizontal {
        didSet { window?.invalidateCursorRects(for: self) }
    }
    var onDrag: ((CGFloat) -> Void)?
    private var dragOrigin: NSPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // A subtle grip line down the middle of the divider track.
        NSColor.separatorColor.setFill()
        let lineThickness: CGFloat = 2
        let line: NSRect
        switch orientation {
        case .horizontal:
            line = NSRect(x: bounds.midX - 12, y: bounds.midY - lineThickness / 2, width: 24, height: lineThickness)
        case .vertical:
            line = NSRect(x: bounds.midX - lineThickness / 2, y: bounds.midY - 12, width: lineThickness, height: 24)
        }
        NSBezierPath(roundedRect: line, xRadius: 1, yRadius: 1).fill()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: orientation == .horizontal ? .resizeUpDown : .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let previous = dragOrigin else {
            return
        }
        let current = event.locationInWindow
        // Incremental delta since the last event (the divider moves under the cursor as the ratio changes).
        // Dragging down/right grows the editor (the leading pane); AppKit Y is flipped, so invert it.
        let delta = orientation == .horizontal ? (previous.y - current.y) : (current.x - previous.x)
        dragOrigin = current
        onDrag?(delta)
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
    }
}
