import AppKit

/// Leading gutter handle that draws centered dots and starts reordering drags after pointer movement.
final class BlockInputDragHandleView: NSView, NSDraggingSource {
    static let dotSize: CGFloat = 2.5
    static let dotSpacing: CGFloat = 3.25
    static let columnCount = 2
    static let rowCount = 3
    static var dotGridSize: NSSize {
        NSSize(
            width: dotSize * CGFloat(columnCount) + dotSpacing * CGFloat(columnCount - 1),
            height: dotSize * CGFloat(rowCount) + dotSpacing * CGFloat(rowCount - 1)
        )
    }

    weak var blockItem: BlockInputBlockItem?
    var activeCursor: NSCursor? {
        isEnabled && !isHidden ? .openHand : nil
    }
    override var isHidden: Bool {
        didSet {
            window?.invalidateCursorRects(for: self)
        }
    }
    var isEnabled = true {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    private var mouseDownEvent: NSEvent?

    init() {
        super.init(frame: .zero)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setAccessibilityLabel("Drag to reorder block")
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: BlockInputBlockItem.handleWidth, height: BlockInputBlockItem.dragHandleHeight)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let activeCursor else {
            return
        }
        addCursorRect(bounds, cursor: activeCursor)
    }

    override func cursorUpdate(with event: NSEvent) {
        guard let activeCursor else {
            super.cursorUpdate(with: event)
            return
        }
        activeCursor.set()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !isHidden else {
            return
        }
        (NSColor.secondaryLabelColor.withAlphaComponent(isEnabled ? 0.55 : 0.22)).setFill()
        let gridSize = Self.dotGridSize
        let origin = NSPoint(
            x: bounds.midX - gridSize.width / 2,
            y: bounds.midY - gridSize.height / 2
        )
        for row in 0..<Self.rowCount {
            for column in 0..<Self.columnCount {
                let dotRect = NSRect(
                    x: origin.x + CGFloat(column) * (Self.dotSize + Self.dotSpacing),
                    y: origin.y + CGFloat(row) * (Self.dotSize + Self.dotSpacing),
                    width: Self.dotSize,
                    height: Self.dotSize
                )
                NSBezierPath(ovalIn: dotRect).fill()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else {
            return
        }
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled,
              let mouseDownEvent else {
            return
        }
        blockItem?.beginDraggingHandle(with: mouseDownEvent)
        self.mouseDownEvent = nil
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }
}
