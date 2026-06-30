import AppKit

/// The surface shown when a diagram fails to render: a "Failed to render the diagram" title, then the engine
/// error (short, with a `Show full error` toggle) and a `Fix with AI` link, over the bare diagram source.
/// Replaces the old bare placeholder so a broken diagram is actionable inline. `Fix with AI` opens the editor
/// in AI mode and auto-runs the fix; the block's ✏️ pencil (drawn by the parent surface, same place as a working
/// diagram) opens the code editor. The `Fix with AI` link appears only when a diagram-AI provider is configured.
final class BlockInputRenderedContentFailureView: NSView {
    private let titleLabel = NSTextField(labelWithString: "Failed to render the diagram")
    private let errorLabel = NSTextField(labelWithString: "")
    private let showFullErrorLink = LinkLabel()
    private let fixLink = LinkLabel()
    private let linksRow = NSStackView()
    private let column = NSStackView()
    private let sourceTextView = NSTextView()
    private let sourceScrollView = NSScrollView()

    private var fullMessage = ""
    private var isExpanded = false

    /// One shared font for the title, error text, and links so they all render at exactly the same size.
    private static let surfaceFont = NSFont.preferredFont(forTextStyle: .callout)
    private static let shortErrorLimit = 80
    /// Content inset matching the working diagram surface so failed and rendered blocks line up.
    private static let contentInset: CGFloat = 12
    private static let columnSpacing: CGFloat = 4
    private static let linkSpacing: CGFloat = 16
    private static let linksRowTopGap: CGFloat = 5
    private static let sourceTopGap: CGFloat = 6

    var onFixWithAI: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Populates the failure surface. `fixAvailable` gates the `Fix with AI` link (no diagram AI → no link).
    func configure(source: String, errorMessage: String?, fixAvailable: Bool) {
        fullMessage = (errorMessage?.isEmpty == false) ? (errorMessage ?? "") : "Content failed to render."
        isExpanded = false
        updateErrorText()
        sourceTextView.string = source
        fixLink.isHidden = !fixAvailable
        showFullErrorLink.isHidden = fullMessage.count <= Self.shortErrorLimit
    }

    private func setup() {
        wantsLayer = true

        titleLabel.font = Self.surfaceFont
        titleLabel.textColor = .systemRed

        errorLabel.font = Self.surfaceFont
        errorLabel.textColor = .secondaryLabelColor
        errorLabel.lineBreakMode = .byTruncatingTail
        errorLabel.maximumNumberOfLines = 6
        errorLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        showFullErrorLink.configure(title: "Show full error", target: self, action: #selector(toggleFullError))
        fixLink.configure(title: "Fix with AI", symbol: "sparkles", target: self, action: #selector(fixTapped))

        linksRow.orientation = .horizontal
        linksRow.spacing = Self.linkSpacing
        linksRow.alignment = .firstBaseline
        linksRow.addArrangedSubview(showFullErrorLink)
        linksRow.addArrangedSubview(fixLink)

        // Three lines: title, then the engine error, then the action links.
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = Self.columnSpacing
        column.translatesAutoresizingMaskIntoConstraints = false
        column.addArrangedSubview(titleLabel)
        column.addArrangedSubview(errorLabel)
        column.addArrangedSubview(linksRow)
        // A touch more breathing room above the action links than between the title/error lines.
        column.setCustomSpacing(Self.linksRowTopGap, after: errorLabel)
        addSubview(column)

        sourceTextView.isEditable = false
        sourceTextView.isSelectable = true
        sourceTextView.drawsBackground = false
        sourceTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        sourceTextView.textColor = .secondaryLabelColor
        sourceTextView.textContainerInset = NSSize(width: 0, height: 4)
        sourceScrollView.documentView = sourceTextView
        sourceScrollView.hasVerticalScroller = true
        sourceScrollView.drawsBackground = false
        sourceScrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sourceScrollView)

        let inset = Self.contentInset
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            column.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -inset),
            column.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            errorLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -inset * 2),
            sourceScrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            sourceScrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            sourceScrollView.topAnchor.constraint(equalTo: column.bottomAnchor, constant: Self.sourceTopGap),
            sourceScrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset)
        ])
    }

    static func linkTitle(_ title: String, symbol: String? = nil) -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.linkColor,
            .font: surfaceFont,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        let result = NSMutableAttributedString()
        if let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let attachment = NSTextAttachment()
            attachment.image = image.withSymbolConfiguration(.init(textStyle: .callout)) ?? image
            let icon = NSMutableAttributedString(attachment: attachment)
            // Underline the icon (and the trailing space) so it reads as part of the link, not a detached glyph.
            icon.append(NSAttributedString(string: " "))
            icon.addAttributes(attributes, range: NSRange(location: 0, length: icon.length))
            result.append(icon)
        }
        result.append(NSAttributedString(string: title, attributes: attributes))
        return result
    }

    private func updateErrorText() {
        errorLabel.stringValue = isExpanded ? fullMessage : shortened(fullMessage)
        errorLabel.toolTip = fullMessage
        showFullErrorLink.setTitle(isExpanded ? "Hide full error" : "Show full error")
    }

    private func shortened(_ message: String) -> String {
        let firstLine = message.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? message
        if firstLine.count <= Self.shortErrorLimit {
            return firstLine
        }
        return String(firstLine.prefix(Self.shortErrorLimit)) + "…"
    }

    @objc private func toggleFullError() {
        isExpanded.toggle()
        updateErrorText()
    }

    @objc private func fixTapped() {
        onFixWithAI?()
    }

    // MARK: - Test accessors

    var isFixLinkVisibleForTesting: Bool { !fixLink.isHidden }
    var errorTextForTesting: String { errorLabel.stringValue }
    var sourceTextForTesting: String { sourceTextView.string }
    var isExpandedForTesting: Bool { isExpanded }
    func toggleFullErrorForTesting() { toggleFullError() }
}

/// A clickable, underlined link rendered as an NSTextField (not NSButton) so its text shares the exact insets
/// of the title/error labels above it and lines up flush-left — NSButton cells add intrinsic horizontal padding
/// that no public API fully removes. Shows the pointing-hand cursor on hover.
private final class LinkLabel: NSTextField {
    private weak var clickTarget: AnyObject?
    private var clickAction: Selector?

    convenience init() {
        self.init(labelWithString: "")
        isSelectable = false
        isEditable = false
        drawsBackground = false
        isBordered = false
    }

    private var symbol: String?

    func configure(title: String, symbol: String? = nil, target: AnyObject, action: Selector) {
        clickTarget = target
        clickAction = action
        self.symbol = symbol
        setTitle(title)
    }

    func setTitle(_ title: String) {
        attributedStringValue = BlockInputRenderedContentFailureView.linkTitle(title, symbol: symbol)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        if let action = clickAction, let target = clickTarget {
            _ = target.perform(action)
        }
    }
}
