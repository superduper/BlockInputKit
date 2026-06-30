import AppKit

/// Draws editor-owned blue selection chrome as independent line fragments.
///
/// Multiline code and quote blocks are still one logical block, but selected text inside them should read like a unified
/// Markdown document: each selected line gets its own rounded background instead of one rectangle spanning every line.
final class BlockInputSelectionBackgroundView: NSView {
    var fillColor: NSColor = .clear {
        didSet {
            needsDisplay = true
        }
    }

    var cornerRadius: CGFloat = 0 {
        didSet {
            needsDisplay = true
        }
    }

    var segmentRects: [NSRect] = [] {
        didSet {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        fillColor.setFill()
        let rects = segmentRects.isEmpty ? [bounds] : segmentRects
        for rect in rects where rect.intersects(dirtyRect) {
            NSBezierPath(
                roundedRect: rect,
                xRadius: cornerRadius,
                yRadius: cornerRadius
            ).fill()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

/// Selection chrome mode owned by `BlockInputBlockItem`.
///
/// Editor-level multi-selection keeps AppKit's native selected-text background transparent and paints this chrome
/// instead, which prevents inactive gray `NSTextView` selections from drifting out of sync with block selection state.
enum BlockInputBlockSelectionChrome {
    case none
    case partial
    case whole

    static var nativeSelectedTextAttributes: [NSAttributedString.Key: Any] {
        [
            .backgroundColor: NSColor.clear,
            .foregroundColor: NSColor.selectedTextColor
        ]
    }

    static var suppressedNativeSelectedTextAttributes: [NSAttributedString.Key: Any] {
        [
            .backgroundColor: NSColor.clear,
            .foregroundColor: NSColor.selectedTextColor
        ]
    }

    var showsContentBackground: Bool {
        switch self {
        case .none:
            return false
        case .partial, .whole:
            return true
        }
    }

    func contentBackgroundColor(style: BlockInputStyle) -> NSColor {
        switch self {
        case .none:
            return .clear
        case .partial, .whole:
            return style.selectionBackgroundColor
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .none:
            return 0
        case .partial, .whole:
            return 5
        }
    }
}
