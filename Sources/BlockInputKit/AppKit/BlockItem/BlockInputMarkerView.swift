import AppKit

/// Draws per-line block markers aligned to the text view's line fragments.
final class BlockInputMarkerView: NSView {
    struct MarkerLine: Equatable {
        var text: String
        var indentationLevel: Int
        var checkboxState: CheckboxState?

        init(
            text: String,
            indentationLevel: Int,
            checkboxState: CheckboxState? = nil
        ) {
            self.text = text
            self.indentationLevel = indentationLevel
            self.checkboxState = checkboxState
        }
    }

    enum CheckboxState: Equatable {
        case unchecked
        case checked
    }

    private(set) var markerLines: [MarkerLine] = []
    private(set) var markerLineYOffsets: [CGFloat] = []
    private(set) var markerLineHeights: [CGFloat] = []

    var font: NSFont? {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    var textColor: NSColor? {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        true
    }

    convenience init() {
        self.init(frame: .zero)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setAccessibilityElement(false)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setMarkerLines(_ markerLines: [MarkerLine]) {
        self.markerLines = markerLines
        markerLineYOffsets = []
        markerLineHeights = []
        let accessibilityLabel = markerLines
            .map(\.text)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        setAccessibilityElement(!accessibilityLabel.isEmpty)
        setAccessibilityLabel(accessibilityLabel)
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    func setMarkerLineMetrics(yOffsets: [CGFloat], heights: [CGFloat]) {
        // This runs from `viewDidLayout` and feeds `intrinsicContentSize`, so invalidating intrinsic size
        // re-dirties constraints mid-layout. When the metrics are unchanged that re-dirty is pure waste,
        // and because the recomputed offsets can drift slightly every pass the cycle never settles and
        // AppKit aborts with "more Update Constraints passes than views". Skip the no-op invalidation.
        let previousHeight = intrinsicContentSize.height
        markerLineYOffsets = yOffsets
        markerLineHeights = heights
        needsDisplay = true
        // Only the intrinsic height affects layout; invalidate solely when it actually changes (rounded to
        // a whole point so sub-pixel drift between layout passes does not keep the cycle alive).
        guard previousHeight.rounded() != intrinsicContentSize.height.rounded() else {
            return
        }
        invalidateIntrinsicContentSize()
    }

    func setMarkerLineYOffsets(_ markerLineYOffsets: [CGFloat]) {
        setMarkerLineMetrics(yOffsets: markerLineYOffsets, heights: [])
    }

    // Selection chrome relies on this matching draw(_:) so nested markers remain inside selected line bounds.
    func markerLineFrame(at lineIndex: Int) -> NSRect? {
        guard markerLines.indices.contains(lineIndex) else {
            return nil
        }
        let markerLine = markerLines[lineIndex]
        let resolvedFont = font ?? .preferredFont(forTextStyle: .body)
        let lineHeight = ceil(resolvedFont.ascender - resolvedFont.descender + resolvedFont.leading)
        let lineY = yOffset(forLineAt: lineIndex, lineHeight: lineHeight)
        let markerLineHeight = markerLineHeight(forLineAt: lineIndex, defaultLineHeight: lineHeight)
        if markerLine.checkboxState != nil {
            let markerSize = Self.scaledMarkerSize(16, forPointSize: resolvedFont.pointSize)
            return NSRect(
                x: Self.markerGlyphXPosition(indentationLevel: markerLine.indentationLevel, markerWidth: markerSize),
                y: lineY + max(0, (markerLineHeight - markerSize) / 2),
                width: markerSize,
                height: markerSize
            )
        }
        guard !markerLine.text.isEmpty else {
            return nil
        }
        if let markerStyle = UnorderedMarkerStyle(text: markerLine.text) {
            let markerSize = markerStyle.size(forPointSize: resolvedFont.pointSize)
            return NSRect(
                x: Self.markerGlyphXPosition(indentationLevel: markerLine.indentationLevel, markerWidth: markerSize),
                y: lineY + max(0, (markerLineHeight - markerSize) / 2),
                width: markerSize,
                height: markerSize
            )
        }
        let markerSize = (markerLine.text as NSString).size(withAttributes: [.font: resolvedFont])
        return NSRect(
            x: Self.markerGlyphXPosition(indentationLevel: markerLine.indentationLevel, markerWidth: markerSize.width),
            y: Self.textMarkerYPosition(lineY: lineY, lineHeight: markerLineHeight, markerHeight: markerSize.height),
            width: markerSize.width,
            height: markerSize.height
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !markerLines.isEmpty else {
            return
        }
        let resolvedFont = font ?? .preferredFont(forTextStyle: .body)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: resolvedFont,
            .foregroundColor: textColor ?? NSColor.tertiaryLabelColor
        ]
        let lineHeight = ceil(resolvedFont.ascender - resolvedFont.descender + resolvedFont.leading)
        for (lineIndex, markerLine) in markerLines.enumerated() {
            let lineY = yOffset(forLineAt: lineIndex, lineHeight: lineHeight)
            let markerLineHeight = markerLineHeight(forLineAt: lineIndex, defaultLineHeight: lineHeight)
            if drawChecklistMarker(
                markerLine,
                lineY: lineY,
                lineHeight: markerLineHeight
            ) {
                continue
            }
            guard !markerLine.text.isEmpty else {
                continue
            }
            if drawUnorderedListMarker(
                markerLine,
                lineY: lineY,
                lineHeight: markerLineHeight,
                font: resolvedFont
            ) {
                continue
            }
            let markerSize = (markerLine.text as NSString).size(withAttributes: attributes)
            let xPosition = Self.markerGlyphXPosition(indentationLevel: markerLine.indentationLevel, markerWidth: markerSize.width)
            let yPosition = Self.textMarkerYPosition(
                lineY: lineY,
                lineHeight: markerLineHeight,
                markerHeight: markerSize.height
            )
            (markerLine.text as NSString).draw(
                at: NSPoint(x: xPosition, y: yPosition),
                withAttributes: attributes
            )
        }
    }

    override var intrinsicContentSize: NSSize {
        let resolvedFont = font ?? .preferredFont(forTextStyle: .body)
        let lineHeight = ceil(resolvedFont.ascender - resolvedFont.descender + resolvedFont.leading)
        let measuredHeight = markerLineYOffsets.enumerated().reduce(CGFloat.zero) { height, indexedOffset in
            let lineHeight = markerLineHeight(forLineAt: indexedOffset.offset, defaultLineHeight: lineHeight)
            return max(height, indexedOffset.element + lineHeight)
        }
        let fallbackHeight = CGFloat(max(markerLines.count, 1)) * lineHeight
        return NSSize(width: Self.noIntrinsicMetric, height: max(measuredHeight, fallbackHeight))
    }

    private func yOffset(forLineAt lineIndex: Int, lineHeight: CGFloat) -> CGFloat {
        guard markerLineYOffsets.indices.contains(lineIndex) else {
            return CGFloat(lineIndex) * lineHeight
        }
        return markerLineYOffsets[lineIndex]
    }

    private func markerLineHeight(forLineAt lineIndex: Int, defaultLineHeight: CGFloat) -> CGFloat {
        guard markerLineHeights.indices.contains(lineIndex) else {
            return defaultLineHeight
        }
        return markerLineHeights[lineIndex] > 0 ? markerLineHeights[lineIndex] : defaultLineHeight
    }

    private func drawUnorderedListMarker(
        _ markerLine: MarkerLine,
        lineY: CGFloat,
        lineHeight: CGFloat,
        font: NSFont
    ) -> Bool {
        guard let markerStyle = UnorderedMarkerStyle(text: markerLine.text) else {
            return false
        }
        let color = textColor ?? NSColor.tertiaryLabelColor
        let markerSize = markerStyle.size(forPointSize: font.pointSize)
        let markerFrame = NSRect(
            x: Self.markerGlyphXPosition(indentationLevel: markerLine.indentationLevel, markerWidth: markerSize),
            y: lineY + max(0, (lineHeight - markerSize) / 2),
            width: markerSize,
            height: markerSize
        )
        color.set()
        switch markerStyle {
        case .filledCircle:
            NSBezierPath(ovalIn: markerFrame).fill()
        case .hollowCircle:
            let path = NSBezierPath(ovalIn: markerFrame.insetBy(dx: 0.75, dy: 0.75))
            path.lineWidth = 1.5
            path.stroke()
        case .filledSquare:
            NSBezierPath(rect: markerFrame).fill()
        }
        return true
    }

    private func drawChecklistMarker(_ markerLine: MarkerLine, lineY: CGFloat, lineHeight: CGFloat) -> Bool {
        guard let checkboxState = markerLine.checkboxState else {
            return false
        }
        let markerSize = Self.scaledMarkerSize(16, forPointSize: (font ?? .preferredFont(forTextStyle: .body)).pointSize)
        let markerFrame = NSRect(
            x: Self.markerGlyphXPosition(indentationLevel: markerLine.indentationLevel, markerWidth: markerSize),
            y: lineY + max(0, (lineHeight - markerSize) / 2),
            width: markerSize,
            height: markerSize
        )
        let fillColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.28)
        fillColor.setFill()
        NSBezierPath(roundedRect: markerFrame, xRadius: 5, yRadius: 5).fill()
        if checkboxState == .checked {
            let checkPath = NSBezierPath()
            checkPath.lineWidth = 1.8
            checkPath.lineCapStyle = .round
            checkPath.lineJoinStyle = .round
            checkPath.move(to: NSPoint(x: markerFrame.minX + 4, y: markerFrame.midY))
            checkPath.line(to: NSPoint(x: markerFrame.minX + 7, y: markerFrame.maxY - 4))
            checkPath.line(to: NSPoint(x: markerFrame.maxX - 4, y: markerFrame.minY + 4))
            (textColor ?? NSColor.labelColor).withAlphaComponent(0.75).setStroke()
            checkPath.stroke()
        }
        return true
    }

    static func markerGlyphXPosition(indentationLevel: Int, markerWidth: CGFloat) -> CGFloat {
        let indent = BlockInputBlockItem.contentIndent(forIndentationLevel: indentationLevel)
        let centeredOffset = max(0, (BlockInputBlockItem.markerChromeWidth - markerWidth) / 2)
        return indent + centeredOffset
    }

    static func textMarkerYPosition(lineY: CGFloat, lineHeight: CGFloat, markerHeight: CGFloat) -> CGFloat {
        lineY + max(0, (lineHeight - markerHeight) / 2)
    }

    private static func scaledMarkerSize(_ size: CGFloat, forPointSize pointSize: CGFloat) -> CGFloat {
        size * pointSize / NSFont.systemFontSize
    }
}

private enum UnorderedMarkerStyle {
    case filledCircle
    case hollowCircle
    case filledSquare

    init?(text: String) {
        switch text {
        case "•":
            self = .filledCircle
        case "◦":
            self = .hollowCircle
        case "▪":
            self = .filledSquare
        default:
            return nil
        }
    }

    func size(forPointSize pointSize: CGFloat) -> CGFloat {
        let baseSize: CGFloat
        switch self {
        case .filledCircle:
            baseSize = 7.5
        case .hollowCircle:
            baseSize = 8.5
        case .filledSquare:
            baseSize = 7
        }
        return baseSize * pointSize / NSFont.systemFontSize
    }
}
