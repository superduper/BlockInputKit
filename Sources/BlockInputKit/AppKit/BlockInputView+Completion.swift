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
        let range = clampedCompletionRange(
            replacementRange ?? completionReplacementRange(in: resolvedBlockID, block: block),
            in: block
        )
        switch resolvedSlashAcceptAction(for: suggestion, blockID: resolvedBlockID, range: range) {
        case .insertText:
            break
        case .replaceWithMarkdown(let markdown):
            return applySlashReplaceWithMarkdown(markdown, replacing: range, in: resolvedBlockID)
        case .none:
            return nil
        }
        return applyInsertionTextSplice(suggestion, block: block, at: index, blockID: resolvedBlockID, range: range)
    }

    private func applyInsertionTextSplice(
        _ suggestion: BlockInputCompletionSuggestion,
        block: BlockInputBlock,
        at index: Int,
        blockID: BlockInputBlockID,
        range: NSRange
    ) -> BlockInputSelection? {
        let beforeText = block.text
        let beforeSelection = completionSelectionBefore(in: blockID, replacementRange: range)
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
            blockID: blockID,
            utf16Offset: range.location + (suggestion.insertionText as NSString).length
        ))
        undoController?.registerTextEdit(
            blockID: blockID,
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

    // MARK: - Slash-command accept helpers

    private func resolvedSlashAcceptAction(
        for suggestion: BlockInputCompletionSuggestion,
        blockID: BlockInputBlockID,
        range: NSRange
    ) -> BlockInputSlashCommandAcceptAction {
        guard suggestion.trigger == .slashCommand,
              let handler = onSlashCommandAccepted else {
            return .insertText
        }
        return handler(BlockInputSlashCommandAcceptContext(
            suggestion: suggestion, blockID: blockID, replacementRange: range))
    }

    // Performs token-clear and block insertion in a single registered structural edit.
    //
    // Undo-step count:
    //   - Single-block doc (lone empty paragraph): 1 step — whole-document replacement.
    //   - Multi-block, token on its own line (owning block empty after clear): 1 step — owning
    //     block replaced in-place with the parsed blocks; no stray empty paragraph.
    //   - Multi-block, token inline (owning block non-empty after clear): 1 step — parsed blocks
    //     inserted below the owning block.
    private func applySlashReplaceWithMarkdown(
        _ markdown: String,
        replacing range: NSRange,
        in blockID: BlockInputBlockID
    ) -> BlockInputSelection? {
        guard let index = index(of: blockID), let block = block(at: index) else {
            return nil
        }
        let clamped = clampedCompletionRange(range, in: block)
        let trimmedMarkdown = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMarkdown.isEmpty else {
            return nil
        }
        let imageMode: BlockInputMarkdownImageParsingMode =
            imagePresentation == .textLinksWithPreviewStrip ? .preserveSourceText : .imageBlocks
        let parsedBlocks = BlockInputDocument(markdown: markdown, imageParsingMode: imageMode).blocks
        guard !parsedBlocks.isEmpty else {
            return nil
        }
        return performStructuralEdit(
            named: "Insert Slash Command",
            edit: { document in
                // Step 1: strip the trigger token from the owning block.
                if let idx = document.index(of: blockID), clamped.length > 0 {
                    let storage = NSMutableString(string: document.blocks[idx].text)
                    storage.replaceCharacters(in: clamped, with: "")
                    document.blocks[idx].text = storage as String
                }
                // Step 2: decide placement based on whether the owning block is now empty.
                if document.blocks.count == 1,
                   document.blocks[0].kind == .paragraph,
                   document.blocks[0].isEmpty {
                    // Lone empty paragraph: replace the whole document.
                    document.blocks = parsedBlocks
                    guard let first = parsedBlocks.first else { return nil }
                    return .cursor(BlockInputCursor(blockID: first.id, utf16Offset: 0))
                }
                if let idx = document.index(of: blockID),
                   document.blocks[idx].isEmpty {
                    // Owning block became empty (token was the whole block): replace it in-place
                    // with the parsed blocks so no stray empty paragraph remains.
                    document.blocks.replaceSubrange(idx...idx, with: parsedBlocks)
                    guard let first = parsedBlocks.first else { return nil }
                    return .cursor(BlockInputCursor(blockID: first.id, utf16Offset: 0))
                }
                // Token was inline (owning block has remaining text): insert parsed blocks below.
                guard let idx = document.index(of: blockID) else { return nil }
                return document.insertBlocks(parsedBlocks, at: idx + 1)
            }
        )
    }

    // MARK: - Test accessors

    var documentForTesting: BlockInputDocument { document }

    var onSlashCommandAcceptedForTesting:
        (@MainActor (BlockInputSlashCommandAcceptContext) -> BlockInputSlashCommandAcceptAction)? {
        onSlashCommandAccepted
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
