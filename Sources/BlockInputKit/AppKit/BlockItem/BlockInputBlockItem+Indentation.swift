import AppKit

extension BlockInputBlockItem {
    func requestIndent() -> Bool {
        guard isEditable,
              let blockID else {
            return false
        }
        guard currentSelectionCanChangeIndent else {
            return true
        }
        delegate?.blockItemDidRequestIndent(self, blockID: blockID, selectedRange: currentSelectedRange)
        return true
    }

    func requestOutdent() -> Bool {
        guard isEditable,
              let blockID else {
            return false
        }
        guard currentSelectionCanChangeIndent else {
            return true
        }
        delegate?.blockItemDidRequestOutdent(self, blockID: blockID, selectedRange: currentSelectedRange)
        return true
    }

    private var currentSelectionCanChangeIndent: Bool {
        let selectedRange = currentSelectedRange
        guard selectedRange.length == 0 else {
            return false
        }
        let text = textView.string as NSString
        return selectedRange.location <= text.length
    }
}
