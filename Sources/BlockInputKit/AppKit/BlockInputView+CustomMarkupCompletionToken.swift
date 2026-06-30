import AppKit

extension BlockInputView {
    /// Detects an open registered token (e.g. `[[`) before the caret for the first matching `completionTokenTriggers`
    /// entry, since a multi-char opener is missed by single-char `@`/`/` boundary detection.
    ///
    /// Backwards-search the literal `openingToken` before the caret; abort when any
    /// `abortingSubstrings` appears in the inner text; derive the query (`.verbatim` or `.beforeFirst(separator:)`);
    /// extend the replacement across a trailing `closingToken`. Returns a `.custom(identifier)` token.
    func customMarkupCompletionToken(in text: NSString, caretOffset: Int) -> BlockInputCompletionToken? {
        for trigger in completionTokenTriggers {
            if let token = completionToken(for: trigger, in: text, caretOffset: caretOffset) {
                return token
            }
        }
        return nil
    }

    private func completionToken(
        for trigger: BlockInputCompletionTokenTrigger,
        in text: NSString,
        caretOffset: Int
    ) -> BlockInputCompletionToken? {
        let opening = trigger.openingToken as NSString
        let openingLength = opening.length
        guard openingLength > 0, caretOffset >= openingLength else {
            return nil
        }
        let openSearch = text.range(of: trigger.openingToken, options: .backwards, range: NSRange(location: 0, length: caretOffset))
        guard openSearch.location != NSNotFound,
              openSearch.location + openingLength <= caretOffset else {
            return nil
        }
        let innerLocation = openSearch.location + openingLength
        let inner = text.substring(with: NSRange(location: innerLocation, length: caretOffset - innerLocation))
        for aborting in trigger.abortingSubstrings where inner.contains(aborting) {
            return nil
        }
        let query = self.query(from: inner, for: trigger.query)
        var replacementEnd = caretOffset
        if let closing = trigger.closingToken, !closing.isEmpty {
            let closingLength = (closing as NSString).length
            if caretOffset + closingLength <= text.length,
               text.substring(with: NSRange(location: caretOffset, length: closingLength)) == closing {
                replacementEnd = caretOffset + closingLength
            }
        }
        return BlockInputCompletionToken(
            trigger: .custom(trigger.identifier),
            replacementRange: NSRange(location: openSearch.location, length: replacementEnd - openSearch.location),
            query: query,
            rawQuery: inner,
            fileQuery: nil
        )
    }

    private func query(from inner: String, for mode: BlockInputCompletionTokenQuery) -> String {
        switch mode {
        case .verbatim:
            return inner
        case let .beforeFirst(separator):
            guard let separatorIndex = inner.firstIndex(of: separator) else {
                return inner
            }
            return String(inner[inner.startIndex..<separatorIndex])
        }
    }
}
