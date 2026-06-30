import AppKit

extension BlockInputView {
    /// Toggles code formatting for the active text selection.
    ///
    /// Multiline selections convert the owner block to a fenced code block (or back to a paragraph
    /// when it is already code); single-line selections toggle inline code around the selection.
    func performFormatCodeCommand(_ command: BlockInputEditorCommand) -> Bool? {
        guard case .formatCode = command else {
            return nil
        }
        guard isEditable else {
            return false
        }
        if isMultilineFormatCodeSelection {
            return performMultilineFormatCode()
        }
        return performTextFormattingShortcut(.inlineCode)
    }

    func canPerformFormatCodeCommand(_ command: BlockInputEditorCommand) -> Bool? {
        guard case .formatCode = command else {
            return nil
        }
        if isMultilineFormatCodeSelection {
            return canPerformBlockKindCommand(.setBlockKind(multilineFormatCodeKind)) ?? false
        }
        return textFormattingCommandState(.inlineCode) != .unavailable
    }

    private var isOwnerBlockCode: Bool {
        guard let blockID = currentSelectionOwnerBlockID(),
              let block = block(withID: blockID),
              case .code = block.kind else {
            return false
        }
        return true
    }

    /// Returns `.on` when the active selection is already inline code (single-line) or the owner
    /// block is already a code block (multiline); `.off` when the command can run; `.unavailable`
    /// otherwise.
    func formatCodeCommandState() -> BlockInputEditorCommandState {
        guard isMultilineFormatCodeSelection else {
            return textFormattingCommandState(.inlineCode)
        }
        if isOwnerBlockCode {
            return .on
        }
        // Availability mirrors the block-kind command, so the eligible-kind list lives in one place.
        return (canPerformBlockKindCommand(.setBlockKind(.code(language: nil))) ?? false) ? .off : .unavailable
    }

    private var isMultilineFormatCodeSelection: Bool {
        switch selection {
        case .mixed:
            return true
        case let .text(textRange):
            guard let block = block(withID: textRange.blockID) else {
                return false
            }
            // An existing code block always uses the block path so re-running toggles the fence back
            // off; otherwise the inline branch would no-op (code blocks have no inline styling).
            if case .code = block.kind {
                return true
            }
            let nsText = block.text as NSString
            let clampedRange = nsText.blockInputClampedFormatCodeRange(textRange.range)
            guard clampedRange.length > 0 else {
                return false
            }
            return nsText.substring(with: clampedRange).rangeOfCharacter(from: .newlines) != nil
        case .cursor, .blocks, .none:
            return false
        }
    }

    /// The block kind the multiline branch should apply: `.paragraph` to toggle an existing code block
    /// back off, otherwise `.code` to wrap. Eligibility is enforced by the block-kind command itself.
    private var multilineFormatCodeKind: BlockInputBlockKind {
        isOwnerBlockCode ? .paragraph : .code(language: nil)
    }

    private func performMultilineFormatCode() -> Bool {
        performBlockKindCommand(.setBlockKind(multilineFormatCodeKind)) ?? false
    }
}

private extension NSString {
    func blockInputClampedFormatCodeRange(_ range: NSRange) -> NSRange {
        let location = min(max(range.location, 0), length)
        let clampedLength = min(max(range.length, 0), max(length - location, 0))
        return NSRange(location: location, length: clampedLength)
    }
}
