import AppKit

/// Divider view that lets non-text horizontal-rule blocks participate in editor selection.
final class BlockInputHorizontalRuleView: NSView {
    private let lineView = NSView()
    private var lineHeightConstraint: NSLayoutConstraint?
    weak var blockItem: BlockInputBlockItem?
    var isSelected = false {
        didSet {
            updateAppearance()
        }
    }
    var accentColor = NSColor.controlAccentColor {
        didSet {
            updateAppearance()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func mouseDown(with event: NSEvent) {
        guard !isHidden else {
            return
        }
        blockItem?.beginBlockSelectionDrag()
        blockItem?.requestSelectHorizontalRule()
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isHidden else {
            return
        }
        _ = blockItem?.updateBlockSelectionDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        blockItem?.finishBlockSelectionDrag()
    }

    func resetForReuse() {
        isSelected = false
        accentColor = .controlAccentColor
        isHidden = true
        alphaValue = 0
    }

    func setVisible(_ isVisible: Bool) {
        isHidden = !isVisible
        alphaValue = isVisible ? 1 : 0
        if !isVisible {
            isSelected = false
        }
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 4
        isHidden = true
        alphaValue = 0
        setAccessibilityElement(false)
        identifier = NSUserInterfaceItemIdentifier("BlockInputHorizontalRuleView")

        lineView.translatesAutoresizingMaskIntoConstraints = false
        lineView.wantsLayer = true
        lineView.layer?.cornerRadius = 1
        addSubview(lineView)

        let lineHeightConstraint = lineView.heightAnchor.constraint(equalToConstant: 2)
        self.lineHeightConstraint = lineHeightConstraint
        NSLayoutConstraint.activate([
            lineView.leadingAnchor.constraint(equalTo: leadingAnchor),
            lineView.trailingAnchor.constraint(equalTo: trailingAnchor),
            lineView.centerYAnchor.constraint(equalTo: centerYAnchor),
            lineHeightConstraint
        ])
        updateAppearance()
    }

    private func updateAppearance() {
        lineHeightConstraint?.constant = isSelected ? 4 : 2
        layer?.backgroundColor = isSelected
            ? accentColor.withAlphaComponent(0.18).cgColor
            : NSColor.clear.cgColor
        lineView.layer?.backgroundColor = (isSelected ? accentColor : .separatorColor).cgColor
    }
}
