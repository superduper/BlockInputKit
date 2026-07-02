import Foundation

public extension BlockInputDocument {
    /// Applies Return key semantics for a block editor.
    @discardableResult
    mutating func handleReturn(
        in blockID: BlockInputBlockID,
        utf16Offset: Int? = nil,
        selectedUTF16Length: Int = 0
    ) -> BlockInputSelection? {
        guard let index = index(of: blockID) else {
            return nil
        }
        let currentBlock = blocks[index]
        if selectedUTF16Length == 0,
           (utf16Offset ?? currentBlock.utf16Length) == 0,
           currentBlock.canMoveDownOnLeadingReturn {
            return moveBlockDownOnLeadingReturn(at: index)
        }
        if let selection = convertCodeFenceToCodeBlockIfNeeded(
            at: index,
            utf16Offset: utf16Offset,
            selectedUTF16Length: selectedUTF16Length
        ) {
            return selection
        }
        if currentBlock.text.isEmpty, currentBlock.kind.exitsToParagraphOnEmptyReturn {
            if currentBlock.kind.supportsIndentation,
               outdentEmptyListBlock(at: index) {
                return .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0))
            }
            blocks[index] = BlockInputBlock(id: blockID, kind: .paragraph)
            return .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0))
        }
        if currentBlock.kind.insertsSiblingListItemOnReturn {
            return insertSiblingListItemAfterReturn(
                at: index,
                utf16Offset: utf16Offset,
                selectedUTF16Length: selectedUTF16Length
            )
        }
        if let selection = handleInlineReturnIfNeeded(
            at: index,
            utf16Offset: utf16Offset,
            selectedUTF16Length: selectedUTF16Length
        ) {
            return selection
        }
        return splitBlockAfterReturn(
            at: index,
            utf16Offset: utf16Offset,
            selectedUTF16Length: selectedUTF16Length
        )
    }
}

extension BlockInputBlock {
    func codeFenceBlockForReturn(
        utf16Offset: Int?,
        selectedUTF16Length: Int
    ) -> BlockInputBlock? {
        guard kind == .paragraph,
              selectedUTF16Length == 0,
              (utf16Offset ?? utf16Length) == utf16Length,
              let opening = BlockInputCodeParsing.codeFenceOpening(in: text) else {
            return nil
        }
        return BlockInputBlock(id: id, kind: .code(language: opening.language))
    }
}

private extension BlockInputDocument {
    mutating func convertCodeFenceToCodeBlockIfNeeded(
        at index: Int,
        utf16Offset: Int?,
        selectedUTF16Length: Int
    ) -> BlockInputSelection? {
        let currentBlock = blocks[index]
        guard let codeBlock = currentBlock.codeFenceBlockForReturn(
            utf16Offset: utf16Offset,
            selectedUTF16Length: selectedUTF16Length
        ) else {
            return nil
        }
        blocks[index] = codeBlock
        return .cursor(BlockInputCursor(blockID: currentBlock.id, utf16Offset: 0))
    }

    mutating func moveBlockDownOnLeadingReturn(at index: Int) -> BlockInputSelection {
        let currentBlock = blocks[index]
        blocks[index] = currentBlock.leadingReturnPlaceholder()
        blocks.insert(currentBlock.blockMovedDownOnLeadingReturn(), at: index + 1)
        normalizeNumberedListStartsIfNeeded(around: index)
        return .cursor(BlockInputCursor(blockID: currentBlock.id, utf16Offset: 0))
    }

    mutating func handleInlineReturnIfNeeded(
        at index: Int,
        utf16Offset: Int?,
        selectedUTF16Length: Int
    ) -> BlockInputSelection? {
        let currentBlock = blocks[index]
        guard currentBlock.kind.acceptsInlineReturn else {
            return nil
        }
        let insertionOffset = min(max(utf16Offset ?? currentBlock.utf16Length, 0), currentBlock.utf16Length)
        let mutableText = NSMutableString(string: currentBlock.text)
        let replacementLength = min(max(selectedUTF16Length, 0), currentBlock.utf16Length - insertionOffset)
        if replacementLength == 0,
           let removalRange = currentBlock.emptyInlineLineRemovalRangeForReturn(utf16Offset: insertionOffset) {
            if outdentEmptyInlineLineIfNeeded(at: index, utf16Offset: insertionOffset) {
                return .cursor(BlockInputCursor(blockID: currentBlock.id, utf16Offset: insertionOffset))
            }
            return exitInlineBlock(at: index, removing: removalRange)
        }
        mutableText.replaceCharacters(in: NSRange(location: insertionOffset, length: replacementLength), with: "\n")
        let updatedText = mutableText as String
        blocks[index].text = updatedText
        if let lineIndentationLevels = currentBlock.lineIndentationLevelsAfterReplacingTextWithLineEnding(
            utf16Offset: insertionOffset,
            selectedUTF16Length: replacementLength,
            updatedText: updatedText
        ) {
            blocks[index].lineIndentationLevels = lineIndentationLevels
        }
        return .cursor(BlockInputCursor(blockID: currentBlock.id, utf16Offset: insertionOffset + 1))
    }

    /// Splits a non-list, non-inline block at the caret: text before the caret stays in the current
    /// block, text after it moves into a new paragraph below. A non-empty selection is consumed by the
    /// break. Headings split into a heading prefix and a paragraph suffix; the caret lands at the start
    /// of the new block. With the caret at the end, the suffix is empty and a plain empty paragraph is
    /// inserted (preserving the prior append-on-Return behavior).
    ///
    /// When the caret sits inside an open inline-markdown span (bold/italic/underline/strikethrough/inline
    /// code), `BlockInputInlineMarkupSplitTermination` closes the span at the prefix end and reopens it at
    /// the suffix start so both halves stay valid Markdown; the caret then lands AFTER the reopened opening
    /// delimiters, at the start of the visible content, so the user keeps typing inside the span.
    mutating func splitBlockAfterReturn(
        at index: Int,
        utf16Offset: Int?,
        selectedUTF16Length: Int
    ) -> BlockInputSelection {
        let currentBlock = blocks[index]
        let textStorage = currentBlock.text as NSString
        let insertionOffset = min(max(utf16Offset ?? textStorage.length, 0), textStorage.length)
        let replacementLength = min(max(selectedUTF16Length, 0), textStorage.length - insertionOffset)
        let termination = BlockInputInlineMarkupSplitTermination.terminate(
            text: currentBlock.text,
            splitOffset: insertionOffset,
            replacementLength: replacementLength
        )
        blocks[index].text = termination.prefix
        let insertedBlock = BlockInputBlock(kind: .paragraph, text: termination.suffix)
        blocks.insert(insertedBlock, at: index + 1)
        return .cursor(BlockInputCursor(blockID: insertedBlock.id, utf16Offset: termination.suffixCaretOffset))
    }

    mutating func insertSiblingListItemAfterReturn(
        at index: Int,
        utf16Offset: Int?,
        selectedUTF16Length: Int
    ) -> BlockInputSelection {
        let currentBlock = blocks[index]
        let textStorage = currentBlock.text as NSString
        let insertionOffset = min(max(utf16Offset ?? currentBlock.utf16Length, 0), textStorage.length)
        let replacementLength = min(max(selectedUTF16Length, 0), textStorage.length - insertionOffset)
        let prefix = Self.removingOneTrailingLineEnding(textStorage.substring(to: insertionOffset))
        let suffix = textStorage.substring(from: insertionOffset + replacementLength)
        let insertedLineIndentationLevels = lineIndentationLevelsAfterListReturn(
            in: currentBlock,
            insertionOffset: insertionOffset,
            suffixOffset: insertionOffset + replacementLength,
            suffix: suffix
        )
        blocks[index].text = prefix
        let insertedBlock = BlockInputBlock(
            kind: siblingListKind(after: currentBlock.kind),
            text: suffix,
            indentationLevel: insertedLineIndentationLevels.first ?? currentBlock.indentationLevel(forLine: 0),
            lineIndentationLevels: insertedLineIndentationLevels
        )
        blocks.insert(insertedBlock, at: index + 1)
        normalizeNumberedListStartsIfNeeded(around: index + 1)
        return .cursor(BlockInputCursor(blockID: insertedBlock.id, utf16Offset: 0))
    }

    func siblingListKind(after kind: BlockInputBlockKind) -> BlockInputBlockKind {
        switch kind {
        case .bulletedListItem:
            return .bulletedListItem
        case let .numberedListItem(start):
            return .numberedListItem(start: start + 1)
        case .checklistItem:
            return .checklistItem(isChecked: false)
        case .paragraph, .heading, .code, .horizontalRule, .frontMatter, .quote, .table, .image, .rawMarkdown:
            return kind
        }
    }

    func lineIndentationLevelsAfterListReturn(
        in block: BlockInputBlock,
        insertionOffset: Int,
        suffixOffset: Int,
        suffix: String
    ) -> [Int] {
        let insertionLineIndex = block.lineIndex(containingUTF16Offset: insertionOffset)
        return BlockInputLineBreaks.lineStartOffsets(in: suffix).map { suffixLineStart in
            guard suffixLineStart > 0 else {
                return block.indentationLevel(forLine: insertionLineIndex)
            }
            return block.indentationLevel(forLine: block.lineIndex(containingUTF16Offset: suffixOffset + suffixLineStart))
        }
    }

    mutating func outdentEmptyListBlock(at index: Int) -> Bool {
        guard blocks[index].kind.supportsIndentation else {
            return false
        }
        let lineIndentation = blocks[index].indentationLevel(forLine: 0)
        guard lineIndentation > 0 else {
            return false
        }
        if blocks[index].lineIndentationLevels.isEmpty {
            blocks[index].indentationLevel -= 1
            normalizeNumberedListStartsIfNeeded(around: index)
            return true
        }
        blocks[index].setIndentationLevel(lineIndentation - 1, forLine: 0)
        normalizeNumberedListStartsIfNeeded(around: index)
        return true
    }

    mutating func outdentEmptyInlineLineIfNeeded(at index: Int, utf16Offset: Int) -> Bool {
        guard blocks[index].kind.supportsIndentation else {
            return false
        }
        let lineIndex = blocks[index].lineIndex(containingUTF16Offset: utf16Offset)
        let indentationLevel = blocks[index].indentationLevel(forLine: lineIndex)
        guard indentationLevel > 0 else {
            return false
        }
        blocks[index].setIndentationLevel(indentationLevel - 1, forLine: lineIndex)
        return true
    }

    /// The removal range comes from `emptyInlineLineRemovalRangeForReturn`, which only matches the
    /// two trailing blank lines at the very END of the block, so there is never trailing text to
    /// carry into a continuation block after the escape.
    mutating func exitInlineBlock(at index: Int, removing removalRange: NSRange) -> BlockInputSelection {
        let currentBlock = blocks[index]
        let textStorage = currentBlock.text as NSString
        let prefix = Self.removingOneTrailingLineEnding(textStorage.substring(to: removalRange.location))
        if prefix.isEmpty {
            blocks[index] = BlockInputBlock(id: currentBlock.id, kind: .paragraph)
            return .cursor(BlockInputCursor(blockID: currentBlock.id, utf16Offset: 0))
        }

        blocks[index].text = prefix
        let paragraph = BlockInputBlock()
        blocks.insert(paragraph, at: index + 1)
        return .cursor(BlockInputCursor(blockID: paragraph.id, utf16Offset: 0))
    }

    static func removingOneTrailingLineEnding(_ text: String) -> String {
        if text.hasSuffix("\r\n") {
            return String(text.dropLast(2))
        }
        guard text.last == "\n" || text.last == "\r" else {
            return text
        }
        return String(text.dropLast())
    }
}

extension BlockInputBlock {
    var canMoveDownOnLeadingReturn: Bool {
        guard !isEmpty else {
            return false
        }
        switch kind {
        case .paragraph, .heading, .code, .quote, .bulletedListItem, .numberedListItem, .checklistItem, .table, .image, .rawMarkdown:
            return true
        case .horizontalRule, .frontMatter:
            return false
        }
    }

    func leadingReturnPlaceholder() -> BlockInputBlock {
        switch kind {
        case .bulletedListItem:
            return BlockInputBlock(
                id: id,
                kind: .bulletedListItem,
                indentationLevel: indentationLevel(forLine: 0)
            )
        case let .numberedListItem(start):
            return BlockInputBlock(
                id: id,
                kind: .numberedListItem(start: start),
                indentationLevel: indentationLevel(forLine: 0)
            )
        case .checklistItem:
            return BlockInputBlock(
                id: id,
                kind: .checklistItem(isChecked: false),
                indentationLevel: indentationLevel(forLine: 0)
            )
        case .paragraph, .heading, .code, .quote, .table, .image, .rawMarkdown:
            return BlockInputBlock(id: id, kind: .paragraph)
        case .horizontalRule, .frontMatter:
            return self
        }
    }

    func blockMovedDownOnLeadingReturn() -> BlockInputBlock {
        var movedBlock = self
        movedBlock.id = .unique()
        if case let .numberedListItem(start) = kind {
            movedBlock.kind = .numberedListItem(start: start + 1)
        }
        return movedBlock
    }
}
