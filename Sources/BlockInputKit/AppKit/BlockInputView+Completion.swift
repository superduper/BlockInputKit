import AppKit

extension BlockInputView {
    /// Requests host-provided suggestions for the active block, or an explicit block.
    public func completionSuggestions(
        trigger: BlockInputCompletionTrigger,
        query: String,
        blockID: BlockInputBlockID? = nil,
        replacementRange: NSRange? = nil,
        rawQuery: String? = nil,
        fileQuery: BlockInputCompletionFileQuery? = nil
    ) async -> [BlockInputCompletionSuggestion] {
        await completionSuggestions(
            trigger: trigger,
            query: query,
            blockID: blockID,
            replacementRange: replacementRange,
            rawQuery: rawQuery,
            fileQuery: fileQuery,
            refreshesDocumentFromStore: true
        )
    }

    func completionSuggestions(
        trigger: BlockInputCompletionTrigger,
        query: String,
        blockID: BlockInputBlockID? = nil,
        replacementRange: NSRange? = nil,
        rawQuery: String? = nil,
        fileQuery: BlockInputCompletionFileQuery? = nil,
        refreshesDocumentFromStore: Bool
    ) async -> [BlockInputCompletionSuggestion] {
        guard let request = completionRequest(
            trigger: trigger,
            query: query,
            blockID: blockID,
            replacementRange: replacementRange,
            rawQuery: rawQuery,
            fileQuery: fileQuery,
            refreshesDocumentFromStore: refreshesDocumentFromStore
        ) else {
            return []
        }
        return await Self.completionSuggestions(provider: request.provider, context: request.context)
    }

    func completionRequest(
        trigger: BlockInputCompletionTrigger,
        query: String,
        blockID: BlockInputBlockID? = nil,
        replacementRange: NSRange? = nil,
        rawQuery: String? = nil,
        fileQuery: BlockInputCompletionFileQuery? = nil,
        refreshesDocumentFromStore: Bool
    ) -> (provider: any BlockInputCompletionProvider, context: BlockInputCompletionContext)? {
        guard let provider = completionProvider else {
            return nil
        }
        if refreshesDocumentFromStore {
            refreshDocumentFromStore()
        }
        guard
              let resolvedBlockID = blockID ?? activeBlockID,
              index(of: resolvedBlockID) != nil else {
            return nil
        }
        let context = BlockInputCompletionContext(
            trigger: trigger,
            query: query,
            document: document,
            blockID: resolvedBlockID,
            selectedRange: completionSelectedRange(in: resolvedBlockID),
            replacementRange: replacementRange,
            rawQuery: rawQuery,
            fileQuery: fileQuery
        )
        return (provider, context)
    }

    /// Applies a host-provided completion suggestion to the active block.
    @discardableResult
    public func acceptCompletionSuggestion(
        _ suggestion: BlockInputCompletionSuggestion,
        in blockID: BlockInputBlockID? = nil,
        replacing replacementRange: NSRange? = nil
    ) -> BlockInputSelection? {
        guard isEditable,
              let resolvedBlockID = blockID ?? activeBlockID,
              let index = index(of: resolvedBlockID),
              let block = block(at: index),
              block.id == resolvedBlockID,
              block.kind != .horizontalRule else {
            return nil
        }
        let beforeText = block.text
        let range = clampedCompletionRange(
            replacementRange ?? completionReplacementRange(in: resolvedBlockID, block: block),
            in: block
        )
        let beforeSelection = completionSelectionBefore(in: resolvedBlockID, replacementRange: range)
        let textStorage = NSMutableString(string: block.text)
        textStorage.replaceCharacters(in: range, with: suggestion.insertionText)
        var updatedBlock = block
        updatedBlock.text = textStorage as String
        if let lineIndentationLevels = block.lineIndentationLevelsAfterReplacingText(
            utf16Offset: range.location,
            selectedUTF16Length: range.length,
            updatedText: updatedBlock.text
        ) {
            updatedBlock.lineIndentationLevels = lineIndentationLevels
        }
        guard updatedBlock.text != beforeText else {
            return nil
        }
        let afterSelection = BlockInputSelection.cursor(BlockInputCursor(
            blockID: resolvedBlockID,
            utf16Offset: range.location + (suggestion.insertionText as NSString).length
        ))
        undoController?.registerTextEdit(
            blockID: resolvedBlockID,
            beforeText: beforeText,
            afterText: updatedBlock.text,
            beforeLineIndentationLevels: block.lineIndentationLevels,
            afterLineIndentationLevels: updatedBlock.lineIndentationLevels,
            selectionBefore: beforeSelection,
            selectionAfter: afterSelection
        )
        _ = applyGranularBlockReplacement(updatedBlock, at: index, selection: afterSelection)
        return afterSelection
    }
}

private extension BlockInputView {
    nonisolated static func completionSuggestions(
        provider: any BlockInputCompletionProvider,
        context: BlockInputCompletionContext
    ) async -> [BlockInputCompletionSuggestion] {
        let task = Task.detached(priority: .userInitiated) { [provider, context] in
            await provider.suggestions(for: context)
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func completionSelectedRange(in blockID: BlockInputBlockID) -> NSRange? {
        switch selection {
        case let .cursor(cursor) where cursor.blockID == blockID:
            return NSRange(location: cursor.utf16Offset, length: 0)
        case let .text(textRange) where textRange.blockID == blockID:
            return textRange.range
        default:
            return nil
        }
    }

    func completionReplacementRange(in blockID: BlockInputBlockID, block: BlockInputBlock) -> NSRange {
        switch selection {
        case let .cursor(cursor) where cursor.blockID == blockID:
            return NSRange(location: cursor.utf16Offset, length: 0)
        case let .text(textRange) where textRange.blockID == blockID:
            return textRange.range
        default:
            return NSRange(location: block.utf16Length, length: 0)
        }
    }

    func clampedCompletionRange(_ range: NSRange, in block: BlockInputBlock) -> NSRange {
        let utf16Length = block.utf16Length
        let location = min(max(range.location, 0), utf16Length)
        let length = min(max(range.length, 0), utf16Length - location)
        return NSRange(location: location, length: length)
    }

    func completionSelectionBefore(
        in blockID: BlockInputBlockID,
        replacementRange: NSRange
    ) -> BlockInputSelection {
        if replacementRange.length == 0 {
            return .cursor(BlockInputCursor(blockID: blockID, utf16Offset: replacementRange.location))
        }
        return .text(BlockInputTextRange(blockID: blockID, range: replacementRange))
    }
}
