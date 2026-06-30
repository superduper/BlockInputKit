import AppKit

extension BlockInputView {
    func shouldPassthroughCompletionReturn() -> Bool {
        guard completionReturnBehavior == .passthroughExactMatch,
              let session = completionSession,
              session.suggestions.indices.contains(session.highlightedIndex) else {
            return false
        }
        let suggestion = session.suggestions[session.highlightedIndex]
        return completionReplacementText(in: session) == (suggestion.exactMatchText ?? suggestion.insertionText)
    }

    func completionReplacementText(in session: BlockInputCompletionSession) -> String? {
        guard let block = block(withID: session.blockID),
              block.text == session.sourceText,
              block.kind == session.sourceKind else {
            return nil
        }
        let text = block.text as NSString
        let range = session.token.replacementRange
        guard range.location >= 0,
              range.length >= 0,
              NSMaxRange(range) <= text.length else {
            return nil
        }
        return text.substring(with: range)
    }
}
