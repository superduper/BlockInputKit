import AppKit

@MainActor
final class BlockInputCompletionPopupRowView: NSView {
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")
    private let detailField = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var index = 0
    private var isHighlighted = false
    private var popupStyle = BlockInputCompletionPopupStyle.default
    private var onSelect: () -> Void = {}
    private var onScrollWheel: (NSEvent) -> Bool = { _ in false }
    private var shouldHighlight: (NSEvent, Bool) -> Bool = { _, _ in true }
    private var onHighlight: (Int) -> Void = { _ in }

    var highlightedRowCornerRadiusForTesting: CGFloat {
        popupStyle.resolvedHighlightedRowCornerRadius
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(
        suggestion: BlockInputCompletionSuggestion,
        index: Int,
        isHighlighted: Bool,
        onSelect: @escaping () -> Void,
        onScrollWheel: @escaping (NSEvent) -> Bool,
        shouldHighlight: @escaping (NSEvent, Bool) -> Bool,
        onHighlight: @escaping (Int) -> Void
    ) {
        self.index = index
        self.isHighlighted = isHighlighted
        self.onSelect = onSelect
        self.onScrollWheel = onScrollWheel
        self.shouldHighlight = shouldHighlight
        self.onHighlight = onHighlight
        applyFieldText(titleField, text: suggestion.title, matchRanges: suggestion.titleMatchRanges)
        applyFieldText(subtitleField, text: suggestion.subtitle ?? "", matchRanges: suggestion.subtitleMatchRanges)
        detailField.stringValue = suggestion.detailText ?? ""
        let iconSystemName = suggestion.iconSystemName ?? Self.fallbackIconSystemName(for: suggestion)
        iconView.image = NSImage(systemSymbolName: iconSystemName, accessibilityDescription: suggestion.title) ??
            NSImage(systemSymbolName: Self.fallbackIconSystemName(for: suggestion), accessibilityDescription: suggestion.title)
        setAccessibilityLabel(accessibilityLabel(for: suggestion))
        needsLayout = true
        needsDisplay = true
    }

    /// Renders a field plainly, or with matched needle characters emphasized (bold + accent) when match ranges are present.
    ///
    /// Plain `stringValue` is kept for the no-match case so existing `@`/`/` rows render byte-for-byte unchanged.
    private func applyFieldText(_ field: NSTextField, text: String, matchRanges: [NSRange]) {
        guard !matchRanges.isEmpty else {
            field.stringValue = text
            return
        }
        let baseFont = field.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [.font: baseFont, .foregroundColor: field.textColor ?? .labelColor]
        )
        let emphasisFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
        let textLength = (text as NSString).length
        for matchRange in matchRanges {
            let clamped = NSRange(
                location: min(max(matchRange.location, 0), textLength),
                length: min(max(matchRange.length, 0), max(textLength - min(max(matchRange.location, 0), textLength), 0))
            )
            guard clamped.length > 0 else {
                continue
            }
            attributed.addAttributes([.font: emphasisFont, .foregroundColor: NSColor.controlAccentColor], range: clamped)
        }
        field.attributedStringValue = attributed
    }

    func applyPopupStyle(_ popupStyle: BlockInputCompletionPopupStyle) {
        self.popupStyle = popupStyle
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let iconSize: CGFloat = 14
        iconView.frame = NSRect(
            x: 10,
            y: floor((bounds.height - iconSize) / 2),
            width: iconSize,
            height: iconSize
        )
        let contentX: CGFloat = 32
        let detailWidth = completionDetailWidth()
        let detailX = bounds.maxX - detailWidth - 10
        detailField.frame = NSRect(
            x: detailX,
            y: floor((bounds.height - detailField.intrinsicContentSize.height) / 2),
            width: detailWidth,
            height: detailField.intrinsicContentSize.height
        )
        let titleWidth = max(0, detailX - contentX - 8)
        let hasSubtitle = !subtitleField.stringValue.isEmpty
        if hasSubtitle {
            titleField.frame = NSRect(x: contentX, y: 19, width: titleWidth, height: 16)
            subtitleField.frame = NSRect(x: contentX, y: 5, width: titleWidth, height: 13)
        } else {
            titleField.frame = NSRect(
                x: contentX,
                y: floor((bounds.height - titleField.intrinsicContentSize.height) / 2),
                width: titleWidth,
                height: titleField.intrinsicContentSize.height
            )
            subtitleField.frame = NSRect(x: contentX, y: bounds.maxY, width: titleWidth, height: 0)
        }
        subtitleField.isHidden = !hasSubtitle
        detailField.isHidden = detailField.stringValue.isEmpty
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        highlightPointerRow(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        highlightPointerRow(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        highlightPointerRow(with: event, ignoresHoverSuppression: true)
    }

    override func mouseUp(with event: NSEvent) {
        highlightPointerRow(with: event, ignoresHoverSuppression: true)
        onSelect()
    }

    override func scrollWheel(with event: NSEvent) {
        if onScrollWheel(event) {
            return
        }
        super.scrollWheel(with: event)
    }

    override func accessibilityPerformPress() -> Bool {
        onSelect()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isHighlighted else {
            return
        }
        popupStyle.highlightedRowBackgroundColor.setFill()
        let cornerRadius = popupStyle.resolvedHighlightedRowCornerRadius
        NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
    }

    private func completionDetailWidth() -> CGFloat {
        guard !detailField.stringValue.isEmpty else {
            return 0
        }
        let paddedIntrinsicWidth = ceil(detailField.intrinsicContentSize.width) + 8
        return min(max(0, paddedIntrinsicWidth), max(0, bounds.width * 0.34))
    }

    private func setup() {
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        titleField.font = .systemFont(ofSize: 13, weight: .medium)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingMiddle
        subtitleField.font = .systemFont(ofSize: 11)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.lineBreakMode = .byTruncatingMiddle
        detailField.font = .systemFont(ofSize: 11)
        detailField.textColor = .tertiaryLabelColor
        detailField.alignment = .right
        detailField.lineBreakMode = .byTruncatingTail
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        [iconView, titleField, subtitleField, detailField].forEach(addSubview)
    }

    private func highlightPointerRow(
        with event: NSEvent,
        ignoresHoverSuppression: Bool = false
    ) {
        guard shouldHighlight(event, ignoresHoverSuppression) else {
            return
        }
        guard !isHighlighted else {
            return
        }
        isHighlighted = true
        onHighlight(index)
        needsDisplay = true
    }

    private static func fallbackIconSystemName(for suggestion: BlockInputCompletionSuggestion) -> String {
        switch suggestion.trigger {
        case .mention:
            return "text.cursor"
        case .slashCommand:
            return "command"
        default:
            // `.custom(_)` triggers fall back to the generic link glyph.
            return "link"
        }
    }

    private func accessibilityLabel(for suggestion: BlockInputCompletionSuggestion) -> String {
        [suggestion.title, suggestion.subtitle, suggestion.detailText]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: ", ")
    }
}
