import AppKit

/// Editor-owned find bar shown at the top of the editor when a find begins.
///
/// Hosts a query field, a `current/total` count label, and a close button. The bar owns no
/// match state; it forwards query edits, Enter (next), and Escape (close) to `BlockInputView`
/// through its closures. It is a plain child view rather than a window accessory so tests and
/// snapshots render the same deterministic surface that is used at runtime.
final class BlockInputFindBarView: NSView, NSTextFieldDelegate {
    /// Fixed height of a single bar row used by the editor when anchoring the bar.
    static let barHeight: CGFloat = 38
    /// Height of the bar when the replace row is revealed (find row + replace row).
    static let expandedBarHeight: CGFloat = barHeight * 2

    let queryField = NSTextField()
    private let countLabel = NSTextField(labelWithString: "0/0")
    private let replaceCheckbox = NSButton()
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private let closeButton = NSButton()
    private let findRow = NSStackView()
    private let replaceField = NSTextField()
    private let replaceButton = NSButton()
    private let replaceAllButton = NSButton()
    private let replaceRow = NSStackView()
    private let rootStack = NSStackView()

    /// Whether the replace row is currently revealed (driven by the "Replace" checkbox).
    private(set) var isReplaceExpanded = false {
        didSet { replaceRow.isHidden = !isReplaceExpanded }
    }

    /// Editor-installed height constraint, updated when the replace row expands/collapses.
    weak var heightConstraint: NSLayoutConstraint?

    /// Current desired bar height for the install constraint, tracking the expanded state.
    var desiredHeight: CGFloat {
        isReplaceExpanded ? Self.expandedBarHeight : Self.barHeight
    }

    /// Called whenever the query text changes; the editor recomputes matches.
    var onQueryChange: ((String) -> Void)?
    /// Called when Enter is pressed in the field; the editor advances to the next match.
    var onCommit: (() -> Void)?
    /// Called when Shift+Enter is pressed in the field; the editor moves to the previous match.
    var onCommitPrevious: (() -> Void)?
    /// Called when the next button is clicked; the editor advances to the next match.
    var onFindNext: (() -> Void)?
    /// Called when the previous button is clicked; the editor moves to the previous match.
    var onFindPrevious: (() -> Void)?
    /// Called when the disclosure toggle changes the replace row's visibility.
    var onToggleReplace: (() -> Void)?
    /// Called when Replace is clicked; the editor replaces the current match with the argument.
    var onReplace: ((String) -> Void)?
    /// Called when Replace All is clicked; the editor replaces every match with the argument.
    var onReplaceAll: ((String) -> Void)?
    /// Called when Escape is pressed or the close button is clicked; the editor ends find.
    var onClose: (() -> Void)?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: Self.barHeight))
        wantsLayer = true
        layer?.borderWidth = 1
        configureSubviews()
        refreshAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    /// Current query text shown in the field.
    var query: String {
        queryField.stringValue
    }

    /// Updates the displayed `current/total` count.
    func updateCount(current: Int, total: Int) {
        countLabel.stringValue = "\(current)/\(total)"
    }

    /// Sets the field text and makes it the window first responder, selecting all text.
    ///
    /// When opened from vim `/`, this runs *inside* a block text view's `keyDown`; AppKit finishes
    /// that key cycle on the original text view and reclaims first responder on the next runloop
    /// turn, so a synchronous `makeFirstResponder` alone does not stick. Re-assert focus on the next
    /// tick (idempotent — a no-op when the field already holds focus, e.g. the Cmd+F path).
    func focusField(initialQuery: String?) {
        if let initialQuery {
            queryField.stringValue = initialQuery
        }
        makeQueryFieldFirstResponder()
        DispatchQueue.main.async { [weak self] in
            self?.makeQueryFieldFirstResponder()
        }
    }

    private func makeQueryFieldFirstResponder() {
        guard let window, window.firstResponder !== queryField,
              (window.firstResponder as? NSTextView)?.delegate !== queryField else {
            return
        }
        window.makeFirstResponder(queryField)
        queryField.currentEditor()?.selectAll(nil)
    }

    func controlTextDidChange(_ notification: Notification) {
        onQueryChange?(queryField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSTextView.insertNewline(_:)):
            // Return in the query field cycles matches (Shift+Return goes back — for a single-line
            // field editor Shift+Return still resolves to `insertNewline`, so read the modifier).
            // Return in the replace field replaces the current match.
            if control === replaceField {
                onReplace?(replaceField.stringValue)
            } else if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                onCommitPrevious?()
            } else {
                onCommit?()
            }
            return true
        case #selector(NSTextView.cancelOperation(_:)):
            // Escape from either field closes the whole bar (and tears down find state + the dim).
            onClose?()
            return true
        default:
            return false
        }
    }

    @objc private func nextButtonClicked(_ sender: Any?) {
        focusQueryFieldForNavigation()
        onFindNext?()
    }

    @objc private func previousButtonClicked(_ sender: Any?) {
        focusQueryFieldForNavigation()
        onFindPrevious?()
    }

    @objc private func closeButtonClicked(_ sender: Any?) {
        onClose?()
    }

    @objc private func replaceCheckboxToggled(_ sender: Any?) {
        isReplaceExpanded = replaceCheckbox.state == .on
        onToggleReplace?()
    }

    @objc private func replaceButtonClicked(_ sender: Any?) {
        focusQueryFieldForNavigation()
        onReplace?(replaceField.stringValue)
    }

    @objc private func replaceAllButtonClicked(_ sender: Any?) {
        focusQueryFieldForNavigation()
        onReplaceAll?(replaceField.stringValue)
    }

    /// Restores the query field as first responder before a button-driven navigation so the
    /// editor's find-bar focus check still sees the field, keeping it active for further cycling
    /// and typing. A button click would otherwise move first responder to the button.
    private func focusQueryFieldForNavigation() {
        window?.makeFirstResponder(queryField)
    }

    private func configureSubviews() {
        queryField.placeholderString = "Find"
        queryField.delegate = self
        queryField.lineBreakMode = .byTruncatingTail
        queryField.translatesAutoresizingMaskIntoConstraints = false
        queryField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true

        countLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true

        configureReplaceCheckbox()
        configureNavigationButtons()
        configureCloseButton()
        configureReplaceControls()
        configureRows()
    }

    private func configureRows() {
        configureHorizontalRow(
            findRow,
            views: [queryField, countLabel, previousButton, nextButton, replaceCheckbox, closeButton]
        )
        configureHorizontalRow(replaceRow, views: [replaceField, replaceButton, replaceAllButton])
        replaceRow.isHidden = true

        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.distribution = .fillEqually
        rootStack.spacing = 0
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addArrangedSubview(findRow)
        rootStack.addArrangedSubview(replaceRow)
        addSubview(rootStack)

        NSLayoutConstraint.activate([
            findRow.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            replaceRow.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            rootStack.topAnchor.constraint(equalTo: topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func configureHorizontalRow(_ row: NSStackView, views: [NSView]) {
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        views.forEach { row.addArrangedSubview($0) }
    }

    private func configureReplaceCheckbox() {
        replaceCheckbox.setButtonType(.switch)
        replaceCheckbox.title = "Replace"
        replaceCheckbox.state = .off
        replaceCheckbox.target = self
        replaceCheckbox.action = #selector(replaceCheckboxToggled(_:))
        replaceCheckbox.setContentHuggingPriority(.required, for: .horizontal)
        replaceCheckbox.setAccessibilityLabel("Replace")
    }

    private func configureReplaceControls() {
        replaceField.placeholderString = "Replace with"
        replaceField.delegate = self
        replaceField.lineBreakMode = .byTruncatingTail
        replaceField.translatesAutoresizingMaskIntoConstraints = false
        replaceField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true

        configureTextButton(replaceButton, title: "Replace", action: #selector(replaceButtonClicked(_:)))
        configureTextButton(replaceAllButton, title: "Replace All", action: #selector(replaceAllButtonClicked(_:)))
    }

    private func configureTextButton(_ button: NSButton, title: String, action: Selector) {
        button.bezelStyle = .rounded
        button.title = title
        button.target = self
        button.action = action
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func configureNavigationButtons() {
        configureIconButton(
            previousButton,
            symbolName: "chevron.up",
            accessibilityLabel: "Previous Match",
            action: #selector(previousButtonClicked(_:))
        )
        configureIconButton(
            nextButton,
            symbolName: "chevron.down",
            accessibilityLabel: "Next Match",
            action: #selector(nextButtonClicked(_:))
        )
    }

    private func configureIconButton(
        _ button: NSButton,
        symbolName: String,
        accessibilityLabel: String,
        action: Selector
    ) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = action
        button.setAccessibilityLabel(accessibilityLabel)
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func configureCloseButton() {
        configureIconButton(
            closeButton,
            symbolName: "xmark.circle.fill",
            accessibilityLabel: "Close Find",
            action: #selector(closeButtonClicked(_:))
        )
    }

    private func refreshAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }
}

extension BlockInputFindBarView {
    /// Current `current/total` text shown in the count label.
    var countLabelTextForTesting: String {
        countLabel.stringValue
    }

    /// Sets the field text and fires the query-change handler, mirroring live typing.
    func simulateQueryInputForTesting(_ query: String) {
        queryField.stringValue = query
        onQueryChange?(query)
    }

    /// Fires the commit (Enter) handler.
    func simulateReturnForTesting() {
        onCommit?()
    }

    /// Fires the previous-match (Shift+Enter) handler.
    func simulateShiftReturnForTesting() {
        onCommitPrevious?()
    }

    /// Next-match button, exposed for click-driven navigation tests.
    var nextButtonForTesting: NSButton {
        nextButton
    }

    /// Previous-match button, exposed for click-driven navigation tests.
    var previousButtonForTesting: NSButton {
        previousButton
    }

    /// Fires the next-match (button) handler.
    func simulateFindNextForTesting() {
        nextButtonClicked(nil)
    }

    /// Fires the previous-match (button) handler.
    func simulateFindPreviousForTesting() {
        previousButtonClicked(nil)
    }

    /// Fires the close (Escape) handler.
    func simulateEscapeForTesting() {
        onClose?()
    }

    /// Whether the replace row is currently revealed.
    var isReplaceExpandedForTesting: Bool {
        isReplaceExpanded
    }

    /// Current desired bar height tracking the expanded state.
    var desiredHeightForTesting: CGFloat {
        desiredHeight
    }

    /// Replace button, exposed for click-driven replace tests.
    var replaceButtonForTesting: NSButton {
        replaceButton
    }

    /// Replace All button, exposed for click-driven replace tests.
    var replaceAllButtonForTesting: NSButton {
        replaceAllButton
    }

    /// Replacement text field, exposed for replace tests.
    var replaceFieldForTesting: NSTextField {
        replaceField
    }

    /// Replace checkbox, exposed for expand/collapse tests.
    var replaceCheckboxForTesting: NSButton {
        replaceCheckbox
    }

    /// Toggles the replace checkbox (and row) and fires the toggle handler, mirroring a click.
    func toggleReplaceForTesting() {
        replaceCheckbox.state = replaceCheckbox.state == .on ? .off : .on
        replaceCheckboxToggled(nil)
    }

    /// Sets the replacement field's text.
    func setReplaceTextForTesting(_ text: String) {
        replaceField.stringValue = text
    }

    /// Fires the Replace handler with the current replacement text.
    func simulateReplaceForTesting() {
        replaceButtonClicked(nil)
    }

    /// Fires the Replace All handler with the current replacement text.
    func simulateReplaceAllForTesting() {
        replaceAllButtonClicked(nil)
    }

    /// Simulates pressing Return in the replace field (which performs Replace, not match cycling).
    func simulateReplaceFieldReturnForTesting() {
        guard let editor = replaceField.currentEditor() as? NSTextView else {
            onReplace?(replaceField.stringValue)
            return
        }
        _ = control(replaceField, textView: editor, doCommandBy: #selector(NSTextView.insertNewline(_:)))
    }
}
