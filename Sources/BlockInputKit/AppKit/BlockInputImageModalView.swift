import AppKit

final class BlockInputImageModalView: NSView, NSTextFieldDelegate {
    private let stackView = NSStackView()
    private let urlLabel = NSTextField(labelWithString: "URL")
    let urlField = NSTextField()
    private let altTextLabel = NSTextField(labelWithString: "Alt Text")
    let altTextField = NSTextField()
    let insertButton = NSButton(title: "Insert", target: nil, action: nil)
    private let buttonRow = NSStackView()
    private let fieldFocus = BlockInputModalFieldFocusTracker()

    var onInsert: ((String, String) -> Void)?
    var onCancel: (() -> Void)?
    var onFocusCheck: (() -> Void)?

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

    func configure(urlString: String = "", altText: String = "") {
        urlField.stringValue = urlString
        urlField.currentEditor()?.string = urlString
        altTextField.stringValue = altText
        altTextField.currentEditor()?.string = altText
        validateFields()
    }

    func focusInitialField() {
        fieldFocus.focus(urlField)
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        fieldFocus.markEditingDidBegin(notification)
    }

    func controlTextDidChange(_ notification: Notification) {
        fieldFocus.markEditingDidChange(notification)
        validateFields()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        fieldFocus.markEditingDidEnd(notification)
        onFocusCheck?()
    }

    func containsResponder(_ responder: NSResponder) -> Bool {
        fieldFocus.containsResponder(responder, modalView: self, fields: [urlField, altTextField])
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if fieldFocus.performTextCommand(commandSelector, textView: textView) {
            return true
        }
        guard commandSelector == #selector(cancelOperation(_:)) else {
            return false
        }
        onCancel?()
        return true
    }

    @objc private func insert(_ sender: Any?) {
        guard insertButton.isEnabled else {
            return
        }
        onInsert?(urlField.stringValue, altTextField.stringValue)
    }

    @objc private func fieldAction(_ sender: Any?) {
        insert(sender)
    }

    private func configureSubviews() {
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.spacing = 8
        stackView.alignment = .leading
        addSubview(stackView)
        configureFieldLabel(urlLabel)
        configureFieldLabel(altTextLabel)

        for field in [urlField, altTextField] {
            field.delegate = self
            field.target = self
            field.action = #selector(fieldAction(_:))
            field.lineBreakMode = .byTruncatingMiddle
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 268).isActive = true
        }

        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.alignment = .centerY
        buttonRow.distribution = .fillEqually
        configureButton(insertButton, systemSymbolName: "checkmark", action: #selector(insert(_:)))
        insertButton.heightAnchor.constraint(equalToConstant: 32).isActive = true
        buttonRow.addArrangedSubview(insertButton)

        stackView.addArrangedSubview(urlLabel)
        stackView.addArrangedSubview(urlField)
        stackView.setCustomSpacing(14, after: urlField)
        stackView.addArrangedSubview(altTextLabel)
        stackView.addArrangedSubview(altTextField)
        stackView.setCustomSpacing(14, after: altTextField)
        stackView.addArrangedSubview(buttonRow)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            buttonRow.widthAnchor.constraint(equalTo: stackView.widthAnchor)
        ])
    }

    private func validateFields() {
        insertButton.isEnabled = Self.validImageURLString(urlField.stringValue) != nil
    }

    static func validImageURLString(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "file"].contains(scheme) else {
            return nil
        }
        return trimmed
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

    private func refreshAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.shadowColor = NSColor.black.cgColor
        }
    }
}
