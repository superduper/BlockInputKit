import AppKit

extension BlockInputView {
    func updateUnchangedCompletionSession(
        blockID: BlockInputBlockID,
        block: BlockInputBlock,
        token: BlockInputCompletionToken,
        sourceText: String,
        anchorWindowRect: NSRect
    ) -> Bool {
        guard var session = completionSession,
              session.blockID == blockID,
              session.token == token,
              session.sourceText == sourceText,
              session.sourceKind == block.kind else {
            return false
        }
        session.anchorWindowRect = anchorWindowRect
        completionSession = session
        positionCompletionPopup()
        return true
    }

    func newCompletionSession(
        blockID: BlockInputBlockID,
        block: BlockInputBlock,
        token: BlockInputCompletionToken,
        sourceText: String,
        anchorWindowRect: NSRect
    ) -> BlockInputCompletionSession {
        BlockInputCompletionSession(
            id: UUID(),
            blockID: blockID,
            token: token,
            sourceText: sourceText,
            sourceKind: block.kind,
            anchorWindowRect: anchorWindowRect,
            suggestions: [],
            highlightedIndex: 0,
            isLoading: true
        )
    }

    func continuousCompletionSession(
        blockID: BlockInputBlockID,
        block: BlockInputBlock,
        token: BlockInputCompletionToken,
        sourceText: String,
        anchorWindowRect: NSRect
    ) -> BlockInputCompletionSession? {
        guard var session = completionSession,
              session.blockID == blockID,
              session.sourceKind == block.kind,
              session.token.trigger == token.trigger,
              session.token.replacementRange.location == token.replacementRange.location else {
            return nil
        }
        session.token = token
        session.sourceText = sourceText
        session.sourceKind = block.kind
        session.anchorWindowRect = anchorWindowRect
        session.isLoading = session.suggestions.isEmpty
        session.highlightedIndex = session.suggestions.isEmpty
            ? 0
            : min(session.highlightedIndex, session.suggestions.count - 1)
        return session
    }
}
