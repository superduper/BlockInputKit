import AppKit

final class BlockInputInlineHintView: NSView {
    var text = "" {
        didSet {
            needsDisplay = true
        }
    }
    var font = NSFont.preferredFont(forTextStyle: .body) {
        didSet {
            needsDisplay = true
        }
    }
    var color = NSColor.placeholderTextColor {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityElement(false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty else {
            return
        }
        (text as NSString).draw(
            in: bounds,
            withAttributes: [
                .font: font,
                .foregroundColor: color
            ]
        )
    }
}
