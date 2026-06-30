import AppKit

struct BlockInputTableCellConfiguration {
    var text: String
    var isHeader: Bool
    var alignment: NSTextAlignment
    var style: BlockInputStyle
    var blockVerticalInsetMultiplier: CGFloat
    var isEditable: Bool
    var position: BlockInputTable.CellPosition
    var tableView: BlockInputTableView?
    var blockItem: BlockInputBlockItem?
}

/// Border, background, accessibility, row-selection chrome, and text editing
/// host for one rendered table cell.
final class BlockInputTableCellView: NSView, NSTextViewDelegate {
    let textView = BlockInputTableCellTextView()
    private let hiddenDelimiterLayoutDelegate = BlockInputDelimiterGlyphs()
    private weak var tableView: BlockInputTableView?
    private var isConfiguring = false
    private var selectionBeforeTextChange: BlockInputSelection?
    private var isHeader = false
    private var alignment: NSTextAlignment = .left
    private var style = BlockInputStyle.default
    private var blockVerticalInsetMultiplier: CGFloat = 1
    private var isEditable = true
    private var isRowSelected = false
    private var isCellSelected = false
    var position = BlockInputTable.CellPosition(row: .header, column: 0)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var isFlipped: Bool {
        true
    }

    override func layout() {
        super.layout()
        textView.frame = bounds.insetBy(
            dx: BlockInputTableView.cellHorizontalPadding,
            dy: BlockInputTableView.scaledCellVerticalPadding(for: blockVerticalInsetMultiplier)
        )
        textView.textContainer?.containerSize = NSSize(width: textView.frame.width, height: CGFloat.greatestFiniteMagnitude)
        textView.layoutSubtreeIfNeeded()
    }

    func configure(_ configuration: BlockInputTableCellConfiguration) {
        isConfiguring = true
        defer { isConfiguring = false }
        isHeader = configuration.isHeader
        alignment = configuration.alignment
        style = configuration.style
        blockVerticalInsetMultiplier = BlockInputConfiguration.sanitizedBlockVerticalInsetMultiplier(
            configuration.blockVerticalInsetMultiplier
        )
        isEditable = configuration.isEditable
        position = configuration.position
        tableView = configuration.tableView
        textView.blockItem = configuration.blockItem
        textView.isEditable = configuration.isEditable
        textView.isSelectable = true
        textView.textStorage?.setAttributedString(BlockInputTableView.attributedString(
            configuration.text,
            isHeader: configuration.isHeader,
            alignment: configuration.alignment,
            style: configuration.style,
            usesPlaceholder: false,
            appliesInlineMarkdown: true,
            isEditable: configuration.isEditable
        ))
        updateAccessibility()
        updateColors()
    }

    func updateEditableState(_ isEditable: Bool) {
        self.isEditable = isEditable
        textView.isEditable = isEditable
        refreshInlineMarkdownAttributesAfterEdit()
        updateColors()
    }

    func refreshInlineMarkdownAttributesAfterEdit() {
        guard !isConfiguring,
              !textView.hasMarkedText(),
              let textStorage = textView.textStorage else {
            return
        }
        let selectedRange = textView.selectedRange()
        let refreshedText = BlockInputTableView.attributedString(
            textView.string,
            isHeader: isHeader,
            alignment: alignment,
            style: style,
            usesPlaceholder: false,
            appliesInlineMarkdown: true,
            isEditable: isEditable
        )
        isConfiguring = true
        defer { isConfiguring = false }
        textStorage.setAttributedString(refreshedText)
        textView.setSelectedRange(Self.clampedRange(selectedRange, in: textView.string))
        textView.needsDisplay = true
    }

    func updateColors() {
        wantsLayer = true
        if isRowSelected || isCellSelected {
            let alpha = BlockInputReadOnlyStyle.alpha(
                isEditable: isEditable,
                editable: 0.22,
                readOnly: BlockInputReadOnlyStyle.tableSelectionBackgroundAlpha
            )
            layer?.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(alpha).cgColor
        } else {
            let headerAlpha = BlockInputReadOnlyStyle.alpha(
                isEditable: isEditable,
                editable: 0.08,
                readOnly: BlockInputReadOnlyStyle.tableHeaderBackgroundAlpha
            )
            layer?.backgroundColor = isHeader
                ? NSColor.separatorColor.withAlphaComponent(headerAlpha).cgColor
                : NSColor.textBackgroundColor.withAlphaComponent(0.01).cgColor
        }
        layer?.borderColor = BlockInputReadOnlyStyle.tableBorderColor(isEditable: isEditable)
        layer?.borderWidth = 0.5
    }

    func setRowSelected(_ isSelected: Bool) {
        guard isRowSelected != isSelected else {
            return
        }
        isRowSelected = isSelected
        updateColors()
        updateAccessibility()
    }

    func setCellSelected(_ isSelected: Bool) {
        guard isCellSelected != isSelected else {
            return
        }
        isCellSelected = isSelected
        updateColors()
        updateAccessibility()
    }

    var isCellSelectedForTesting: Bool {
        isCellSelected
    }

    private func setup() {
        wantsLayer = true
        setAccessibilityElement(false)
        textView.isEditable = true
        textView.isSelectable = true
        textView.selectedTextAttributes = BlockInputBlockSelectionChrome.nativeSelectedTextAttributes
        textView.drawsBackground = false
        textView.linkTextAttributes = [:]
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.layoutManager?.delegate = hiddenDelimiterLayoutDelegate
        textView.isRichText = true
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.allowsUndo = false
        textView.delegate = self
        addSubview(textView)
        updateColors()
    }

    private func updateAccessibility() {
        let rowDescription: String
        let rowNumber: Int
        switch position.row {
        case .header:
            rowDescription = "header row"
            rowNumber = 1
        case .body(let rowIndex):
            rowDescription = "body row"
            rowNumber = rowIndex + 1
        }
        let selectedSuffix: String
        if isRowSelected {
            selectedSuffix = ", row selected"
        } else if isCellSelected {
            selectedSuffix = ", selected"
        } else {
            selectedSuffix = ""
        }
        textView.setAccessibilityLabel(
            "Table cell, \(rowDescription) \(rowNumber), column \(position.column + 1)\(selectedSuffix)"
        )
    }

    func textDidBeginEditing(_ notification: Notification) {
        guard !isConfiguring,
              let tableView else {
            return
        }
        tableView.clearRowSelection()
        tableView.clearCellSelection()
        tableView.delegate?.tableView(tableView, didBeginEditing: position)
        if let sourceRange = tableView.sourceRange(for: textView, localRange: textView.selectedRange()) {
            tableView.delegate?.tableView(tableView, didChangeSelectionIn: position, sourceRange: sourceRange)
        }
    }

    func textDidEndEditing(_ notification: Notification) {
        guard !isConfiguring,
              let tableView else {
            return
        }
        tableView.delegate?.tableView(tableView, didEndEditing: position)
    }

    func textDidChange(_ notification: Notification) {
        guard !isConfiguring,
              let tableView,
              !textView.hasMarkedText() else {
            return
        }
        tableView.delegate?.tableView(
            tableView,
            didChangeText: textView.string,
            in: position,
            selectedLocalRange: textView.selectedRange(),
            selectionBefore: selectionBeforeTextChange
        )
        selectionBeforeTextChange = nil
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isConfiguring,
              let tableView,
              let sourceRange = tableView.sourceRange(for: textView, localRange: textView.selectedRange()) else {
            return
        }
        tableView.clearRowSelection()
        tableView.clearCellSelectionUnlessDragging()
        tableView.delegate?.tableView(tableView, didChangeSelectionIn: position, sourceRange: sourceRange)
    }

    func textView(
        _ textView: NSTextView,
        shouldChangeTextIn affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        guard !isConfiguring else {
            return true
        }
        guard isEditable else {
            return false
        }
        if let replacementString,
           replacementString.rangeOfCharacter(from: .newlines) != nil {
            let singleLineReplacement = Self.singleLineCellReplacement(replacementString)
            textView.insertText(singleLineReplacement, replacementRange: affectedCharRange)
            return false
        }
        guard let tableView else {
            return true
        }
        selectionBeforeTextChange = tableView.sourceSelection(for: textView, localRange: affectedCharRange)
        return tableView.delegate?.tableView(
            tableView,
            shouldChangeTextIn: position,
            affectedLocalRange: affectedCharRange,
            replacementString: replacementString
        ) ?? true
    }

    private static func singleLineCellReplacement(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private static func clampedRange(_ range: NSRange, in text: String) -> NSRange {
        let text = text as NSString
        let location = min(max(range.location, 0), text.length)
        let length = min(max(range.length, 0), max(text.length - location, 0))
        return NSRange(location: location, length: length)
    }
}
