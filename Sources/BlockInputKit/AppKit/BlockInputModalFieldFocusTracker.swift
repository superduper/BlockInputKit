import AppKit

@MainActor
final class BlockInputModalFieldFocusTracker {
    private weak var activeField: NSTextField?

    func focus(_ field: NSTextField) {
        activeField = field
        field.window?.makeFirstResponder(field)
    }

    func markEditingDidBegin(_ notification: Notification) {
        activeField = notification.object as? NSTextField
    }

    func markEditingDidChange(_ notification: Notification) {
        if let field = notification.object as? NSTextField {
            activeField = field
        }
    }

    func markEditingDidEnd(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              activeField === field else {
            return
        }
        activeField = nil
    }

    func performTextCommand(_ commandSelector: Selector, textView: NSTextView) -> Bool {
        switch commandSelector {
        case #selector(NSText.copy(_:)):
            textView.copy(nil)
        case #selector(NSText.cut(_:)):
            textView.cut(nil)
        case #selector(NSText.paste(_:)):
            textView.paste(nil)
        case #selector(NSText.selectAll(_:)):
            textView.selectAll(nil)
        default:
            return false
        }
        return true
    }

    func containsResponder(_ responder: NSResponder, modalView: NSView, fields: [NSTextField]) -> Bool {
        if fields.contains(where: { $0.currentEditor() === responder }) {
            return true
        }
        if let fieldEditor = responder as? NSTextView,
           fieldEditor.isFieldEditor,
           activeField?.window === modalView.window,
           modalView.window?.firstResponder === fieldEditor {
            return true
        }
        var candidateView = responder as? NSView
        while let view = candidateView {
            if view === modalView {
                return true
            }
            candidateView = view.superview
        }
        return false
    }
}
