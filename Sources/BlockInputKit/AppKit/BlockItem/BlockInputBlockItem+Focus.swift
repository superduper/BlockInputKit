import AppKit

extension BlockInputBlockItem {
    func focusText(atUTF16Offset offset: Int) {
        if !tableView.isHidden,
           tableView.focusSourceRange(NSRange(location: offset, length: 0)) {
            updateSelectionDependentAttributesForCurrentSelection()
            return
        }
        view.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(
            location: min(max(offset, 0), (textView.string as NSString).length),
            length: 0
        ))
        textView.scrollRangeToVisible(textView.selectedRange())
        updateSelectionDependentAttributesForCurrentSelection()
    }

    func focusText(inUTF16Range range: NSRange) {
        if !tableView.isHidden,
           tableView.focusSourceRange(range) {
            updateSelectionDependentAttributesForCurrentSelection()
            return
        }
        view.window?.makeFirstResponder(textView)
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        updateSelectionDependentAttributesForCurrentSelection()
    }

    func setSelectedRange(_ range: NSRange) {
        if !tableView.isHidden,
           tableView.focusSourceRange(range) {
            updateSelectionDependentAttributesForCurrentSelection()
            return
        }
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        updateSelectionDependentAttributesForCurrentSelection()
    }

}
