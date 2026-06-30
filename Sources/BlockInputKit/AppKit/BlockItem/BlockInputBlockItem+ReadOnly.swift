import AppKit

extension BlockInputBlockItem {
    func applyReadOnlyConfiguration(
        isEditable: Bool,
        disabledCursor: NSCursor?,
        insertionPointStyle: BlockInputInsertionPointStyle = .bar
    ) {
        self.isEditable = isEditable
        self.disabledCursor = disabledCursor
        self.insertionPointStyle = insertionPointStyle
        textView.isEditable = isEditable
        textView.isSelectable = true
        tableView.isEditable = isEditable
        imageBlockView.isEditable = isEditable
        imageBlockView.disabledCursor = disabledCursor
    }

    var disabledCursorForReadOnly: NSCursor? {
        isEditable ? nil : disabledCursor
    }

    func invalidateCursorRects() {
        guard let window = view.window else {
            return
        }
        for view in [view, scrollView, scrollView.contentView, textView, tableView, imageBlockView] {
            window.invalidateCursorRects(for: view)
        }
        for cellTextView in tableView.cellRows.flatMap({ $0 }).map(\.textView) {
            window.invalidateCursorRects(for: cellTextView)
        }
    }

    func addDisabledCursorRectIfNeeded(to view: NSView) {
        guard let cursor = disabledCursorForReadOnly else {
            return
        }
        view.addCursorRect(view.bounds, cursor: cursor)
    }

    func readOnlyForegroundColor(_ color: NSColor, for kind: BlockInputBlockKind) -> NSColor {
        guard !isEditable, shouldDimReadOnlyText(for: kind) else {
            return color
        }
        return disabledForegroundColor(color)
    }

    func disabledForegroundColor(_ color: NSColor) -> NSColor {
        guard !isEditable else {
            return color
        }
        return Self.disabledForegroundColor(color)
    }

    static func disabledForegroundColor(_ color: NSColor) -> NSColor {
        BlockInputReadOnlyStyle.disabledForegroundColor(color)
    }

    private func shouldDimReadOnlyText(for kind: BlockInputBlockKind) -> Bool {
        switch kind {
        case .code, .table:
            return false
        case .paragraph, .heading, .horizontalRule, .frontMatter, .quote, .bulletedListItem, .numberedListItem, .checklistItem, .image, .rawMarkdown:
            return true
        }
    }
}

enum BlockInputReadOnlyStyle {
    static let foregroundAlphaMultiplier: CGFloat = 0.72
    static let chromeAlpha: CGFloat = 0.55
    static let codeBackgroundAlpha: CGFloat = 0.65
    static let tableBorderAlpha: CGFloat = chromeAlpha
    static let tableHeaderBackgroundAlpha: CGFloat = 0.05
    static let tableSelectionBackgroundAlpha: CGFloat = 0.18

    static func disabledForegroundColor(_ color: NSColor) -> NSColor {
        color.withAlphaComponent(color.alphaComponent * foregroundAlphaMultiplier)
    }

    static func alpha(isEditable: Bool, editable: CGFloat = 1, readOnly: CGFloat) -> CGFloat {
        isEditable ? editable : readOnly
    }

    static func tableBorderColor(isEditable: Bool) -> CGColor {
        let color = NSColor.separatorColor.cgColor
        guard !isEditable else {
            return color
        }
        return color.copy(alpha: color.alpha * tableBorderAlpha) ?? color
    }

    static func applyDisabledForeground(to textStorage: NSTextStorage, range: NSRange? = nil) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let range = NSIntersectionRange(range ?? fullRange, fullRange)
        guard range.length > 0 else {
            return
        }
        var updates: [(range: NSRange, color: NSColor)] = []
        textStorage.enumerateAttribute(.foregroundColor, in: range) { value, range, _ in
            guard let color = value as? NSColor else {
                return
            }
            updates.append((range, disabledForegroundColor(color)))
        }
        for update in updates {
            textStorage.addAttribute(.foregroundColor, value: update.color, range: update.range)
        }
    }
}
