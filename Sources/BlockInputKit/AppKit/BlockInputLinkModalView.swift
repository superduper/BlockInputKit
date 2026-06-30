import AppKit

/// Editor-owned popover-style control for creating and editing Markdown links.
///
/// This is an ordinary child view instead of an `NSPopover` so tests and
/// snapshots render the same deterministic surface that is used at runtime.
final class BlockInputLinkModalView: NSView, NSTextFieldDelegate {
    private let stackView = NSStackView()
    private let textLabel = NSTextField(labelWithString: "Text")
    let textField = NSTextField()
    private let urlLabel = NSTextField(labelWithString: "URL")
    let urlField = NSTextField()
    // When non-nil the second field is a plain-text "target" labeled with this string (e.g. "Target" for wikilinks and
    // custom markups), validated as non-empty plain text instead of a supported URL. Nil ⇒ the URL field with URL
    // validation. Replaces the old wikilink-only `targetIsPlainSlug` flag.
    private var targetFieldLabel: String?
    private let urlRow = NSStackView()
    let openButton = NSButton(title: "Open", target: nil, action: nil)
    let saveButton = NSButton(title: "Save", target: nil, action: nil)
    let removeButton = NSButton(title: "Remove", target: nil, action: nil)
    private let removeButtonBackground = BlockInputCriticalButtonBackground()
    private let removeButtonContent = BlockInputCriticalButtonContent()
    private let removeButtonIcon = NSImageView()
    private let removeButtonLabel = NSTextField(labelWithString: "Remove")
    private let buttonRow = NSStackView()
    private let fieldFocus = BlockInputModalFieldFocusTracker()
    private var mode: BlockInputLinkModalMode = .create

    var onSave: ((String, String) -> Void)?
    var onRemove: (() -> Void)?
    var onOpen: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var onFocusCheck: (() -> Void)?
    var fileBaseURL: URL?
    /// Notifies the editor when the Target field's text changes in wikilink mode, so it can drive the note finder.
    var onTargetQueryChange: ((String) -> Void)?
    /// Gives the editor's note-finder popup first crack at a field-editor command while it is open (arrows/Return/Tab/Esc).
    /// Returns true when the popup consumed the command.
    var targetCompletionCommandHandler: ((Selector) -> Bool)?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 148))
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.masksToBounds = false
        layer?.shadowOpacity = 0.28
        layer?.shadowRadius = 18
        layer?.shadowOffset = CGSize(width: 0, height: -5)
        configureSubviews()
        refreshAppearance()
        validateFields()
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

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        refreshAppearance()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for button in [openButton, removeButton, saveButton] where !button.isHidden {
            addCursorRect(convert(button.bounds, from: button), cursor: .arrow)
        }
    }

    func configure(mode: BlockInputLinkModalMode, text: String, urlString: String, targetFieldLabel: String? = nil) {
        self.mode = mode
        self.targetFieldLabel = targetFieldLabel
        textField.stringValue = text
        textField.currentEditor()?.string = text
        urlField.stringValue = urlString
        urlField.currentEditor()?.string = urlString
        urlLabel.stringValue = targetFieldLabel ?? "URL"
        openButton.isHidden = false
        removeButton.isHidden = mode == .create
        validateFields()
        window?.invalidateCursorRects(for: self)
    }

    func focusInitialField() {
        fieldFocus.focus(textField)
    }

    /// The Target (URL) field's frame in window coordinates, used to anchor the note-finder popup beneath it.
    var targetFieldWindowRect: NSRect {
        urlField.convert(urlField.bounds, to: nil)
    }

    /// Fills the Target field with a picked note's slug and, when the Title field is empty, its title; re-validates Save.
    func fillTarget(slug: String, title: String) {
        urlField.stringValue = slug
        urlField.currentEditor()?.string = slug
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !trimmedTitle.isEmpty {
            textField.stringValue = title
            textField.currentEditor()?.string = title
        }
        validateFields()
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        fieldFocus.markEditingDidBegin(notification)
    }

    func controlTextDidChange(_ notification: Notification) {
        fieldFocus.markEditingDidChange(notification)
        validateFields()
        if targetFieldLabel != nil, notification.object as AnyObject? === urlField {
            onTargetQueryChange?(urlField.stringValue)
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        fieldFocus.markEditingDidEnd(notification)
        onFocusCheck?()
    }

    func containsResponder(_ responder: NSResponder) -> Bool {
        fieldFocus.containsResponder(responder, modalView: self, fields: [textField, urlField])
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // While the Target note-finder popup is open it gets first crack at arrows/Return/Tab/Escape; only after it
        // declines does the modal's own field-editor handling run, so the modal behaves normally with no popup.
        if control === urlField, targetCompletionCommandHandler?(commandSelector) == true {
            return true
        }
        if fieldFocus.performTextCommand(commandSelector, textView: textView) {
            return true
        }
        guard commandSelector == #selector(cancelOperation(_:)) else {
            return false
        }
        // Field editors receive Escape here instead of through the modal view's keyDown path.
        onCancel?()
        return true
    }

    @objc private func save(_ sender: Any?) {
        guard saveButton.isEnabled else {
            return
        }
        onSave?(textField.stringValue, urlField.stringValue)
    }

    @objc private func remove(_ sender: Any?) {
        onRemove?()
    }

    @objc private func open(_ sender: Any?) {
        guard currentTargetIsValid else {
            return
        }
        onOpen?(urlField.stringValue)
    }

    @objc private func fieldAction(_ sender: Any?) {
        save(sender)
    }

    private func configureSubviews() {
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.spacing = 8
        stackView.alignment = .leading
        addSubview(stackView)
        configureFieldLabel(textLabel)
        configureFieldLabel(urlLabel)

        for field in [textField, urlField] {
            field.delegate = self
            field.target = self
            field.action = #selector(fieldAction(_:))
            field.lineBreakMode = .byTruncatingMiddle
            field.translatesAutoresizingMaskIntoConstraints = false
        }
        textField.widthAnchor.constraint(equalToConstant: 268).isActive = true

        urlRow.orientation = .horizontal
        urlRow.spacing = 8
        urlRow.alignment = .centerY
        urlRow.translatesAutoresizingMaskIntoConstraints = false
        urlField.widthAnchor.constraint(equalToConstant: 218).isActive = true

        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.alignment = .centerY
        buttonRow.distribution = .fillEqually

        configureIconButton(openButton, systemSymbolName: "arrow.up.right.square", action: #selector(open(_:)))
        configureButton(removeButton, systemSymbolName: "trash.fill", action: #selector(remove(_:)))
        configureButton(saveButton, systemSymbolName: "checkmark", action: #selector(save(_:)))
        configureCriticalButton(removeButton)
        for button in [removeButton, saveButton] {
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        }

        buttonRow.addArrangedSubview(removeButton)
        buttonRow.addArrangedSubview(saveButton)
        urlRow.addArrangedSubview(urlField)
        urlRow.addArrangedSubview(openButton)
        stackView.addArrangedSubview(textLabel)
        stackView.addArrangedSubview(textField)
        stackView.setCustomSpacing(14, after: textField)
        stackView.addArrangedSubview(urlLabel)
        stackView.addArrangedSubview(urlRow)
        stackView.setCustomSpacing(14, after: urlRow)
        stackView.addArrangedSubview(buttonRow)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            buttonRow.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            urlRow.widthAnchor.constraint(equalTo: stackView.widthAnchor)
        ])
    }

    private func validateFields() {
        let hasText = !textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasTarget = currentTargetIsValid
        saveButton.isEnabled = hasText && hasTarget
        openButton.isEnabled = hasTarget
    }

    /// Validity of the second field. URL mode requires a supported scheme; plain-text target mode (any non-nil
    /// `targetFieldLabel`, e.g. wikilinks) only requires non-empty text because the target is a bare slug, not a URL.
    private var currentTargetIsValid: Bool {
        if targetFieldLabel != nil {
            return !urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return currentURLIsSupported
    }

    private var currentURLIsSupported: Bool {
        BlockInputLinkURL.supportedURL(
            from: urlField.stringValue,
            allowsCustomSchemes: textField.stringValue.hasPrefix("/"),
            fileBaseURL: fileBaseURL
        ) != nil
    }

    private func configureButton(_ button: NSButton, systemSymbolName: String, action: Selector) {
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
        button.imagePosition = .imageLeading
        button.image = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: button.title)
    }

    private func configureFieldLabel(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .secondaryLabelColor
    }

    private func configureCriticalButton(_ button: NSButton) {
        button.bezelStyle = .shadowlessSquare
        button.isBordered = false
        button.wantsLayer = true
        button.title = ""
        button.image = nil
        button.setAccessibilityLabel("Remove Link")
        // Layer a red pill inside the NSButton so the control keeps normal AppKit hit testing and focus behavior.
        removeButtonBackground.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(removeButtonBackground, positioned: .below, relativeTo: nil)
        configureCriticalButtonContent()
        button.addSubview(removeButtonContent)
        NSLayoutConstraint.activate([
            removeButtonBackground.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            removeButtonBackground.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            removeButtonBackground.topAnchor.constraint(equalTo: button.topAnchor, constant: 4),
            removeButtonBackground.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -4),
            removeButtonContent.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            removeButtonContent.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
        button.contentTintColor = .white
    }

    private func configureCriticalButtonContent() {
        removeButtonContent.translatesAutoresizingMaskIntoConstraints = false
        removeButtonContent.orientation = .horizontal
        removeButtonContent.alignment = .centerY
        removeButtonContent.spacing = 6
        removeButtonIcon.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Remove Link")
        removeButtonIcon.image?.isTemplate = true
        removeButtonIcon.translatesAutoresizingMaskIntoConstraints = false
        removeButtonLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        removeButtonContent.addArrangedSubview(removeButtonIcon)
        removeButtonContent.addArrangedSubview(removeButtonLabel)
    }

    private func configureIconButton(_ button: NSButton, systemSymbolName: String, action: Selector) {
        button.target = self
        button.action = action
        button.title = ""
        button.bezelStyle = .rounded
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: "Open Link")
        button.setAccessibilityLabel("Open Link")
        button.widthAnchor.constraint(equalToConstant: 42).isActive = true
    }

    private func refreshAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.shadowColor = NSColor.black.cgColor
            removeButtonBackground.layer?.backgroundColor = NSColor.systemRed.cgColor
            removeButtonIcon.contentTintColor = .white
            removeButtonLabel.textColor = .white
            removeButton.contentTintColor = .white
        }
    }
}

/// Link modal presentation mode. Create mode inserts Markdown; edit mode exposes open and remove actions.
enum BlockInputLinkModalMode {
    case create
    case edit
}

/// Non-interactive red background used to make the remove button read as a critical action.
private final class BlockInputCriticalButtonBackground: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

/// Non-interactive icon/title container layered above the critical button background.
private final class BlockInputCriticalButtonContent: NSStackView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
