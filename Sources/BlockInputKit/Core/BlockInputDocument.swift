import Foundation

/// Structured block document used as the editor's model and Markdown source of truth.
public struct BlockInputDocument: Equatable, Codable, Sendable {
    /// Ordered blocks in the document. The document always contains at least one block.
    public var blocks: [BlockInputBlock] {
        didSet {
            if blocks.isEmpty {
                blocks = [.emptyParagraph()]
            }
        }
    }

    /// Creates a document from ordered blocks, normalizing empty input to one paragraph.
    public init(blocks: [BlockInputBlock] = [.emptyParagraph()]) {
        self.blocks = blocks.isEmpty ? [.emptyParagraph()] : blocks
    }

    /// Parses a Markdown snapshot into structured blocks.
    ///
    /// Use `imageParsingMode: .preserveSourceText` when the editor should keep
    /// Markdown and HTML image syntax as editable source text instead of turning
    /// it into standalone image blocks during import.
    ///
    /// - Parameters:
    ///   - markdown: Markdown source to parse.
    ///   - imageParsingMode: Import-time image syntax handling. The default
    ///     `.imageBlocks` preserves existing standalone image block behavior.
    public init(
        markdown: String,
        imageParsingMode: BlockInputMarkdownImageParsingMode = .imageBlocks
    ) {
        self = BlockInputMarkdownImporter.document(from: markdown, imageParsingMode: imageParsingMode)
    }

    /// Serializes the structured blocks into Markdown.
    public var markdown: String {
        BlockInputMarkdownSerializer.markdown(from: self)
    }

    /// Returns true when every block is empty and no frontmatter or code block is present.
    ///
    /// Empty frontmatter and code blocks are still structured content and therefore count as
    /// meaningful content for placeholder and empty-state decisions.
    public var isEffectivelyEmpty: Bool {
        blocks.allSatisfy { block in
            switch block.kind {
            case .frontMatter, .code:
                return false
            case .paragraph, .heading, .horizontalRule, .quote, .bulletedListItem, .numberedListItem, .checklistItem,
                    .table, .image, .rawMarkdown:
                return block.isEmpty
            }
        }
    }

    /// Returns a block by stable ID.
    public func block(withID id: BlockInputBlockID) -> BlockInputBlock? {
        blocks.first { $0.id == id }
    }

    /// Returns the ordered index for a stable block ID.
    public func index(of id: BlockInputBlockID) -> Int? {
        blocks.firstIndex { $0.id == id }
    }

    /// Inserts a block at a clamped document index and returns the cursor selection for it.
    ///
    /// Insertions at index `0` are placed after existing leading frontmatter so
    /// document metadata stays canonical at the physical start of the document.
    @discardableResult
    public mutating func insertBlock(
        _ block: BlockInputBlock = .emptyParagraph(),
        at index: Int
    ) -> BlockInputSelection {
        let insertionIndex = Self.insertionIndexPreservingLeadingFrontMatter(index, in: blocks)
        blocks.insert(block, at: insertionIndex)
        return .cursor(BlockInputCursor(blockID: block.id, utf16Offset: 0))
    }

    /// Inserts a new block below an existing block and returns the cursor selection for it.
    @discardableResult
    public mutating func insertBlockBelow(
        blockID: BlockInputBlockID,
        kind: BlockInputBlockKind = .paragraph
    ) -> BlockInputSelection? {
        guard let index = index(of: blockID) else {
            return nil
        }
        let block = BlockInputBlock(kind: kind)
        return insertBlock(block, at: index + 1)
    }

    /// Deletes a block and returns the cursor selection that should receive focus next.
    @discardableResult
    public mutating func deleteBlock(blockID: BlockInputBlockID) -> BlockInputSelection? {
        guard let index = index(of: blockID) else {
            return nil
        }
        return deleteBlock(at: index)
    }

    /// Deletes the block at an ordered index and returns the cursor selection that should receive focus next.
    @discardableResult
    public mutating func deleteBlock(at index: Int) -> BlockInputSelection? {
        guard blocks.indices.contains(index) else {
            return nil
        }

        if blocks.count == 1 {
            let replacement = BlockInputBlock(id: blocks[index].id, kind: .paragraph)
            blocks = [replacement]
            return .cursor(BlockInputCursor(blockID: replacement.id, utf16Offset: 0))
        }

        blocks.remove(at: index)
        if blocks.indices.contains(index - 1) {
            let previous = blocks[index - 1]
            return .cursor(BlockInputCursor(blockID: previous.id, utf16Offset: previous.cursorUTF16Length))
        }
        if let next = blocks.first {
            return .cursor(BlockInputCursor(blockID: next.id, utf16Offset: 0))
        }
        return nil
    }

    /// Deletes selected whole blocks and returns the cursor selection that should receive focus next.
    @discardableResult
    public mutating func deleteBlocks(blockIDs: [BlockInputBlockID]) -> BlockInputSelection? {
        let selectedBlockIDs = Set(blockIDs)
        let deletionIndices = blocks.indices.filter { selectedBlockIDs.contains(blocks[$0].id) }
        guard let firstDeletionIndex = deletionIndices.first else {
            return nil
        }

        if deletionIndices.count == blocks.count {
            let replacement = BlockInputBlock(id: blocks[firstDeletionIndex].id, kind: .paragraph)
            blocks = [replacement]
            return .cursor(BlockInputCursor(blockID: replacement.id, utf16Offset: 0))
        }

        for index in deletionIndices.reversed() {
            blocks.remove(at: index)
        }
        if blocks.indices.contains(firstDeletionIndex - 1) {
            let previous = blocks[firstDeletionIndex - 1]
            return .cursor(BlockInputCursor(blockID: previous.id, utf16Offset: previous.cursorUTF16Length))
        }
        if blocks.indices.contains(firstDeletionIndex) {
            let next = blocks[firstDeletionIndex]
            return .cursor(BlockInputCursor(blockID: next.id, utf16Offset: 0))
        }
        return nil
    }

    /// Deletes a selection that spans whole blocks and partial text edges, returning the unified-text cursor start.
    @discardableResult
    public mutating func deleteMixedSelection(_ selection: BlockInputMixedSelection) -> BlockInputCursor? {
        let partialRanges = [selection.leadingTextRange, selection.trailingTextRange].compactMap { $0 }
        guard !selection.blockIDs.isEmpty || !partialRanges.isEmpty else {
            return nil
        }

        let selectedIDs = Set(selection.blockIDs + partialRanges.map(\.blockID))
        guard let firstSelectedIndex = blocks.indices.first(where: { selectedIDs.contains(blocks[$0].id) }) else {
            return nil
        }
        if let joinedCursor = deleteMixedSelectionByJoiningPartialEdges(selection) {
            return joinedCursor
        }
        let preferredCursor = mixedSelectionStartCursor(selection, firstSelectedIndex: firstSelectedIndex)

        let groupedRanges = Dictionary(grouping: partialRanges, by: \.blockID)
        for (blockID, ranges) in groupedRanges {
            let sortedRanges = ranges.map(\.range).sorted { lhs, rhs in
                lhs.location > rhs.location
            }
            for range in sortedRanges {
                replaceText(in: blockID, range: range, replacement: "")
            }
        }

        let fallbackSelection = selection.blockIDs.isEmpty ? nil : deleteBlocks(blockIDs: selection.blockIDs)
        if let preferredCursor,
           block(withID: preferredCursor.blockID) != nil {
            return preferredCursor
        }
        if case let .cursor(cursor) = fallbackSelection {
            return cursor
        }
        if blocks.indices.contains(firstSelectedIndex) {
            let block = blocks[firstSelectedIndex]
            return BlockInputCursor(blockID: block.id, utf16Offset: 0)
        }
        return blocks.last.map { BlockInputCursor(blockID: $0.id, utf16Offset: $0.cursorUTF16Length) }
    }

    /// Applies Backspace/Delete key semantics for an empty block.
    @discardableResult
    public mutating func deleteEmptyBlockForBackspaceOrDelete(blockID: BlockInputBlockID) -> BlockInputSelection? {
        guard let block = block(withID: blockID), block.isEmpty else {
            return nil
        }
        return deleteBlock(blockID: blockID)
    }

    /// Merges a paragraph into the previous text block and returns the join-point cursor selection.
    @discardableResult
    public mutating func mergeBlockIntoPrevious(blockID: BlockInputBlockID) -> BlockInputSelection? {
        guard let index = index(of: blockID),
              index > 0,
              blocks[index].kind == .paragraph,
              blocks[index - 1].kind.isSelectableStandaloneBlock == false,
              blocks[index - 1].kind != .frontMatter else {
            return nil
        }
        let cursorOffset = blocks[index - 1].utf16Length
        let mergedText = blocks[index - 1].text + blocks[index].text
        blocks[index - 1].text = mergedText
        blocks.remove(at: index)
        return .cursor(BlockInputCursor(blockID: blocks[index - 1].id, utf16Offset: cursorOffset))
    }

    /// Increases a block's nesting level.
    @discardableResult
    public mutating func indentBlock(
        blockID: BlockInputBlockID,
        activeUTF16Offset: Int? = nil
    ) -> BlockInputSelection? {
        guard let index = index(of: blockID) else {
            return nil
        }
        guard blocks[index].kind.supportsIndentation else {
            return nil
        }
        if let activeUTF16Offset,
           blocks[index].text.contains("\n") || !blocks[index].lineIndentationLevels.isEmpty {
            let lineIndex = blocks[index].lineIndex(containingUTF16Offset: activeUTF16Offset)
            blocks[index].setIndentationLevel(
                blocks[index].indentationLevel(forLine: lineIndex) + 1,
                forLine: lineIndex
            )
            normalizeNumberedListStartsIfNeeded(around: index)
            return .cursor(BlockInputCursor(blockID: blockID, utf16Offset: activeUTF16Offset))
        }
        blocks[index].indentationLevel += 1
        normalizeNumberedListStartsIfNeeded(around: index)
        return .cursor(BlockInputCursor(blockID: blockID, utf16Offset: blocks[index].utf16Length))
    }

    /// Decreases a block's nesting level.
    @discardableResult
    public mutating func outdentBlock(
        blockID: BlockInputBlockID,
        activeUTF16Offset: Int? = nil
    ) -> BlockInputSelection? {
        guard let index = index(of: blockID) else {
            return nil
        }
        guard blocks[index].kind.supportsIndentation else {
            return nil
        }
        if let activeUTF16Offset,
           blocks[index].text.contains("\n") || !blocks[index].lineIndentationLevels.isEmpty {
            let lineIndex = blocks[index].lineIndex(containingUTF16Offset: activeUTF16Offset)
            let currentLevel = blocks[index].indentationLevel(forLine: lineIndex)
            guard currentLevel > 0 else {
                return nil
            }
            blocks[index].setIndentationLevel(currentLevel - 1, forLine: lineIndex)
            normalizeNumberedListStartsIfNeeded(around: index)
            return .cursor(BlockInputCursor(blockID: blockID, utf16Offset: activeUTF16Offset))
        }
        guard blocks[index].indentationLevel > 0 else {
            return nil
        }
        blocks[index].indentationLevel = max(0, blocks[index].indentationLevel - 1)
        normalizeNumberedListStartsIfNeeded(around: index)
        return .cursor(BlockInputCursor(blockID: blockID, utf16Offset: blocks[index].utf16Length))
    }

    /// Changes a block's semantic kind.
    @discardableResult
    public mutating func changeBlockKind(
        blockID: BlockInputBlockID,
        to kind: BlockInputBlockKind
    ) -> BlockInputSelection? {
        guard let index = index(of: blockID) else {
            return nil
        }
        guard blocks[index].kind != kind else {
            return nil
        }
        blocks[index].kind = kind
        return .cursor(BlockInputCursor(blockID: blockID, utf16Offset: blocks[index].utf16Length))
    }

    /// Toggles a checklist item and returns a cursor selection for that block.
    @discardableResult
    public mutating func toggleChecklistItem(blockID: BlockInputBlockID) -> BlockInputSelection? {
        guard let index = index(of: blockID),
              case let .checklistItem(isChecked) = blocks[index].kind else {
            return nil
        }
        blocks[index].kind = .checklistItem(isChecked: !isChecked)
        return .cursor(BlockInputCursor(blockID: blockID, utf16Offset: blocks[index].utf16Length))
    }

    /// Replaces a UTF-16 range in a block's text and returns the resulting cursor selection.
    @discardableResult
    public mutating func replaceText(
        in blockID: BlockInputBlockID,
        range: NSRange,
        replacement: String
    ) -> BlockInputSelection? {
        guard let index = index(of: blockID) else {
            return nil
        }
        if blocks[index].kind == .horizontalRule {
            return .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0))
        }
        let beforeBlock = blocks[index]
        let editRange = beforeBlock.text.clampedUTF16Range(range)
        let edit = beforeBlock.text.replacingUTF16Characters(in: editRange, with: replacement)
        blocks[index].text = edit.text
        if let lineIndentationLevels = beforeBlock.lineIndentationLevelsAfterReplacingText(
            utf16Offset: editRange.location,
            selectedUTF16Length: editRange.length,
            updatedText: edit.text
        ) {
            blocks[index].lineIndentationLevels = lineIndentationLevels
        }
        return .cursor(BlockInputCursor(
            blockID: blockID,
            utf16Offset: edit.selectionOffset
        ))
    }

    /// Implements Cmd+A escalation from current block text selection to all blocks.
    ///
    /// The default behavior selects the current block contents before promoting to all blocks. `.document` selects all
    /// blocks immediately after confirming `currentBlockID` is valid, unless all blocks are already selected.
    public func selectAll(
        currentBlockID: BlockInputBlockID,
        currentSelection: BlockInputSelection?,
        behavior: BlockInputSelectAllBehavior = .focusedContentThenDocument
    ) -> BlockInputSelection? {
        let allBlockIDs = blocks.map(\.id)
        if currentSelection == .blocks(allBlockIDs) {
            return .blocks(allBlockIDs)
        }
        guard let block = block(withID: currentBlockID) else {
            return nil
        }
        if behavior == .document {
            return .blocks(allBlockIDs)
        }
        if block.kind == .horizontalRule,
           currentSelection == .blocks([currentBlockID]) {
            return .blocks(allBlockIDs)
        }
        let fullRange = BlockInputTextRange(
            blockID: currentBlockID,
            range: NSRange(location: 0, length: block.utf16Length)
        )
        if block.kind != .frontMatter, block.utf16Length == 0 {
            return .blocks(allBlockIDs)
        }
        if block.kind == .frontMatter {
            let blockSelection = BlockInputSelection.blocks([currentBlockID])
            if currentSelection == blockSelection {
                return .blocks(allBlockIDs)
            }
            if block.text.isEmpty || currentSelection == .text(fullRange) {
                return blockSelection
            }
        }
        if currentSelection == .text(fullRange) {
            return .blocks(allBlockIDs)
        }
        return .text(fullRange)
    }
}

private extension BlockInputDocument {
    mutating func deleteMixedSelectionByJoiningPartialEdges(_ selection: BlockInputMixedSelection) -> BlockInputCursor? {
        guard let leadingTextRange = selection.leadingTextRange,
              let trailingTextRange = selection.trailingTextRange,
              leadingTextRange.blockID != trailingTextRange.blockID,
              let leadingIndex = index(of: leadingTextRange.blockID),
              let trailingIndex = index(of: trailingTextRange.blockID),
              leadingIndex < trailingIndex else {
            return nil
        }
        let leadingBlock = blocks[leadingIndex]
        let trailingBlock = blocks[trailingIndex]
        // Frontmatter is document metadata, so deleting a mixed selection across
        // its boundary should trim both edge blocks instead of merging body text
        // into the raw frontmatter source.
        guard leadingBlock.kind != .frontMatter,
              trailingBlock.kind != .frontMatter else {
            return nil
        }
        let leadingRange = leadingBlock.text.clampedUTF16Range(leadingTextRange.range)
        let trailingRange = trailingBlock.text.clampedUTF16Range(trailingTextRange.range)
        let leadingText = leadingBlock.text as NSString
        let trailingText = trailingBlock.text as NSString
        var mergedBlock = leadingBlock
        mergedBlock.text = leadingText.substring(to: leadingRange.location)
            + trailingText.substring(from: NSMaxRange(trailingRange))
        blocks[leadingIndex] = mergedBlock

        let deletedIDs = Set(selection.blockIDs + [trailingTextRange.blockID])
        for index in blocks.indices.reversed() where index != leadingIndex && deletedIDs.contains(blocks[index].id) {
            blocks.remove(at: index)
        }
        return BlockInputCursor(blockID: leadingTextRange.blockID, utf16Offset: leadingRange.location)
    }

    func mixedSelectionStartCursor(
        _ selection: BlockInputMixedSelection,
        firstSelectedIndex: Int
    ) -> BlockInputCursor? {
        let partialRanges = [selection.leadingTextRange, selection.trailingTextRange].compactMap { $0 }
        let indexedPartialRanges = partialRanges.compactMap { textRange -> (index: Int, range: BlockInputTextRange)? in
            guard let index = index(of: textRange.blockID) else {
                return nil
            }
            return (index, textRange)
        }
        if let firstPartial = indexedPartialRanges
            .filter({ $0.index == firstSelectedIndex })
            .sorted(by: { $0.range.range.location < $1.range.range.location })
            .first {
            return BlockInputCursor(
                blockID: firstPartial.range.blockID,
                utf16Offset: firstPartial.range.range.location
            )
        }
        if let nextPartial = indexedPartialRanges
            .filter({ $0.index > firstSelectedIndex })
            .sorted(by: { $0.index < $1.index })
            .first {
            return BlockInputCursor(
                blockID: nextPartial.range.blockID,
                utf16Offset: nextPartial.range.range.location
            )
        }
        return nil
    }
}

private extension String {
    func clampedUTF16Range(_ range: NSRange) -> NSRange {
        let text = self as NSString
        let location = min(max(range.location, 0), text.length)
        let length = min(max(range.length, 0), max(text.length - location, 0))
        return NSRange(location: location, length: length)
    }

    func replacingUTF16Characters(in range: NSRange, with replacement: String) -> (text: String, selectionOffset: Int) {
        let mutable = NSMutableString(string: self)
        let clampedRange = clampedUTF16Range(range)
        mutable.replaceCharacters(in: clampedRange, with: replacement)
        return (mutable as String, clampedRange.location + (replacement as NSString).length)
    }
}
