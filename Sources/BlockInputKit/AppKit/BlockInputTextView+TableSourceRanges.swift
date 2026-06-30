import AppKit

extension BlockInputTextView {
    func blockInputSourceSelectedRange() -> NSRange {
        blockItem?.sourceSelectedRange(for: self, localRange: selectedRange()) ?? selectedRange()
    }
}
