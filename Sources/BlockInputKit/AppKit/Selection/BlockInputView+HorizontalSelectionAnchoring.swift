import Foundation

extension BlockInputView {
    func anchoredHorizontalSelectionSpan(
        anchor: BlockInputDocumentTextBoundary,
        selectedBounds: (start: BlockInputDocumentTextBoundary, end: BlockInputDocumentTextBoundary)
    ) -> (anchor: BlockInputDocumentTextBoundary, active: BlockInputDocumentTextBoundary)? {
        if anchor == selectedBounds.start {
            return (anchor: anchor, active: selectedBounds.end)
        }
        if anchor == selectedBounds.end {
            return (anchor: anchor, active: selectedBounds.start)
        }
        if compareDocumentBoundary(anchor, selectedBounds.start) == .orderedAscending {
            return (anchor: anchor, active: selectedBounds.end)
        }
        if compareDocumentBoundary(anchor, selectedBounds.end) == .orderedDescending {
            return (anchor: anchor, active: selectedBounds.start)
        }
        return nil
    }

    private func compareDocumentBoundary(
        _ lhs: BlockInputDocumentTextBoundary,
        _ rhs: BlockInputDocumentTextBoundary
    ) -> ComparisonResult {
        guard let lhsIndex = index(of: lhs.blockID),
              let rhsIndex = index(of: rhs.blockID) else {
            return .orderedSame
        }
        if lhsIndex < rhsIndex {
            return .orderedAscending
        }
        if lhsIndex > rhsIndex {
            return .orderedDescending
        }
        if lhs.utf16Offset < rhs.utf16Offset {
            return .orderedAscending
        }
        if lhs.utf16Offset > rhs.utf16Offset {
            return .orderedDescending
        }
        return .orderedSame
    }
}
