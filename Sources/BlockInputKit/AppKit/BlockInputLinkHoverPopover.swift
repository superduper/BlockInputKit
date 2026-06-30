import AppKit

/// A button shown in the hover affordance: a title and the action to run when clicked.
struct BlockInputLinkHoverButton {
    let title: String
    let accessibilityLabel: String
    let action: () -> Void
}

/// Small editor-owned hover affordance anchored below a hovered inline link or chip.
///
/// Renders a configurable row of compact buttons (built-in "Open"/"Edit", plus any host-supplied extra actions such as
/// "Show in Finder" for file chips). It is an ordinary child view (not an `NSPopover`) so it shares the deterministic,
/// snapshot-friendly surface used by the editor's other hover and modal affordances.
final class BlockInputLinkHoverPopover: NSView {
    static let preferredHeight: CGFloat = 22
    static let anchorGap: CGFloat = 3

    /// Invoked when the pointer leaves the popover so the editor can schedule a graced dismissal.
    var onMouseExited: (() -> Void)?

    private var buttons: [NSButton] = []
    private let stack = NSStackView()
    private var hoverTrackingArea: NSTrackingArea?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 88, height: BlockInputLinkHoverPopover.preferredHeight))
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        layer?.masksToBounds = false
        layer?.shadowOpacity = 0.22
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        configureStack()
        refreshAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Replaces the popover's buttons with `items`, in order.
    func setButtons(_ items: [BlockInputLinkHoverButton]) {
        for button in buttons {
            stack.removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        buttons = items.enumerated().map { index, item in
            let button = NSButton(title: item.title, target: self, action: #selector(buttonClicked(_:)))
            button.tag = index
            button.bezelStyle = .inline
            button.controlSize = .mini
            button.font = .systemFont(ofSize: 10, weight: .medium)
            button.setAccessibilityLabel(item.accessibilityLabel)
            stack.addArrangedSubview(button)
            return button
        }
        actions = items.map(\.action)
    }

    private var actions: [() -> Void] = []

    /// Current button titles, in order. For tests.
    var buttonTitlesForTesting: [String] { buttons.map(\.title) }

    /// Runs the action for the button at `index`. For tests.
    func performButtonForTesting(at index: Int) {
        guard actions.indices.contains(index) else {
            return
        }
        actions[index]()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
        super.mouseExited(with: event)
    }

    /// Frame size that snugly fits the current buttons.
    var preferredSize: NSSize {
        let buttonsWidth = buttons.reduce(CGFloat(0)) { $0 + ceil($1.intrinsicContentSize.width) }
        let spacing = CGFloat(max(buttons.count - 1, 0)) * stack.spacing
        return NSSize(width: max(72, buttonsWidth + spacing + 18), height: Self.preferredHeight)
    }

    private func configureStack() {
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    private func refreshAppearance() {
        layer?.backgroundColor = BlockInputCompletionPopupStyle.defaultBackgroundColor.cgColor
        layer?.borderColor = BlockInputCompletionPopupStyle.defaultBorderColor.cgColor
    }

    @objc private func buttonClicked(_ sender: NSButton) {
        guard actions.indices.contains(sender.tag) else {
            return
        }
        actions[sender.tag]()
    }
}
