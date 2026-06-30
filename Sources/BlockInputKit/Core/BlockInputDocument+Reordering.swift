import Foundation

extension BlockInputDocument {
    /// Moves a block to a document index and returns a block selection for the moved block.
    @discardableResult
    public mutating func moveBlock(blockID: BlockInputBlockID, to targetIndex: Int) -> BlockInputSelection? {
        moveBlockWithChangedBlocks(blockID: blockID, to: targetIndex)?.selection
    }

    @discardableResult
    mutating func moveBlockWithChangedBlocks(
        blockID: BlockInputBlockID,
        to targetIndex: Int
    ) -> BlockInputMoveResult? {
        guard let sourceIndex = index(of: blockID) else {
            return nil
        }
        return moveBlockWithChangedBlocks(sourceIndex: sourceIndex, to: targetIndex)
    }

    @discardableResult
    mutating func moveBlockWithChangedBlocks(
        sourceIndex: Int,
        to targetIndex: Int
    ) -> BlockInputMoveResult? {
        guard blocks.indices.contains(sourceIndex) else {
            return nil
        }
        let finalTargetIndex = min(max(targetIndex, 0), blocks.count - 1)
        guard finalTargetIndex != sourceIndex else {
            return nil
        }
        guard Self.canMovePreservingLeadingFrontMatter(sourceIndex: sourceIndex, targetIndex: finalTargetIndex, in: blocks) else {
            return nil
        }
        let sourceBlock = blocks[sourceIndex]
        let sourceListRange = sourceBlock.kind.isNumberedListItem ? listRange(near: sourceIndex) : nil
        let sourceListFirstTopLevelStart = sourceBlock.kind.isNumberedListItem
            ? firstTopLevelNumberedStart(in: sourceListRange)
            : nil
        let isSameListNumberedMove = sourceListRange?.contains(finalTargetIndex) == true
        let block = blocks.remove(at: sourceIndex)
        let sourceIndexAfterRemoval = min(sourceIndex, blocks.count - 1)
        let didMergeNumberedListRunsAtSource = removedBlockMergedNumberedListRuns(at: sourceIndexAfterRemoval)
        let sourceNormalizationIndex = finalTargetIndex <= sourceIndexAfterRemoval
            ? sourceIndexAfterRemoval + 1
            : sourceIndexAfterRemoval
        blocks.insert(block, at: finalTargetIndex)
        let firstTopLevelStart = isSameListNumberedMove ? sourceListFirstTopLevelStart : nil
        var changedBlocks: [BlockInputBlock] = []
        if block.kind.isNumberedListItem,
           isFirstListItem(at: finalTargetIndex) {
            let normalizedKind = BlockInputBlockKind.numberedListItem(start: firstTopLevelStart ?? 1)
            if blocks[finalTargetIndex].kind != normalizedKind {
                blocks[finalTargetIndex].kind = normalizedKind
                changedBlocks.append(blocks[finalTargetIndex])
            }
        }
        if block.kind.isNumberedListItem || didMergeNumberedListRunsAtSource {
            changedBlocks.append(contentsOf: normalizeNumberedListStarts(
                around: sourceNormalizationIndex,
                firstTopLevelStart: firstTopLevelStart
            ))
        }
        if block.kind.isNumberedListItem {
            changedBlocks.append(contentsOf: normalizeNumberedListStarts(
                around: finalTargetIndex,
                firstTopLevelStart: firstTopLevelStart
            ))
        }
        return BlockInputMoveResult(
            selection: .blocks([block.id]),
            changedBlocks: uniqueChangedBlocks(changedBlocks),
            finalIndex: finalTargetIndex
        )
    }

    @discardableResult
    mutating func normalizeNumberedListStartsAround(_ index: Int) -> [BlockInputBlock] {
        normalizeNumberedListStarts(around: index)
    }

    mutating func normalizeNumberedListStartsIfNeeded(around index: Int) {
        guard blocks.indices.contains(index),
              blocks[index].kind.isNumberedListItem else {
            return
        }
        _ = normalizeNumberedListStarts(around: index)
    }

    private mutating func normalizeNumberedListStarts(
        around index: Int,
        firstTopLevelStart: Int? = nil
    ) -> [BlockInputBlock] {
        guard let range = listRange(near: index) else {
            return []
        }
        var startsByIndentationLevel: [Int: Int] = [:]
        var changedBlocks: [BlockInputBlock] = []
        for index in range {
            let indentationLevel = blocks[index].indentationLevel(forLine: 0)
            startsByIndentationLevel = startsByIndentationLevel.filter { $0.key <= indentationLevel }
            guard case let .numberedListItem(start) = blocks[index].kind else {
                continue
            }
            let normalizedStart: Int
            if let previousStart = startsByIndentationLevel[indentationLevel] {
                normalizedStart = previousStart + 1
            } else if indentationLevel > 0 {
                normalizedStart = 1
            } else {
                normalizedStart = firstTopLevelStart ?? start
            }
            let normalizedKind = BlockInputBlockKind.numberedListItem(start: normalizedStart)
            if blocks[index].kind != normalizedKind {
                blocks[index].kind = normalizedKind
                changedBlocks.append(blocks[index])
            }
            startsByIndentationLevel[indentationLevel] = normalizedStart
        }
        return changedBlocks
    }

    private func listRange(near index: Int) -> Range<Int>? {
        guard !blocks.isEmpty else {
            return nil
        }
        let clampedIndex = min(max(index, 0), blocks.count - 1)
        let listIndex: Int
        if blocks[clampedIndex].kind.isListItem {
            listIndex = clampedIndex
        } else if clampedIndex > 0, blocks[clampedIndex - 1].kind.isListItem {
            listIndex = clampedIndex - 1
        } else {
            return nil
        }
        var lowerBound = listIndex
        while lowerBound > 0, blocks[lowerBound - 1].kind.isListItem {
            lowerBound -= 1
        }
        var upperBound = listIndex + 1
        while upperBound < blocks.count, blocks[upperBound].kind.isListItem {
            upperBound += 1
        }
        return lowerBound..<upperBound
    }

    private func firstTopLevelNumberedStart(in range: Range<Int>?) -> Int? {
        guard let range else {
            return nil
        }
        for index in range where blocks[index].indentationLevel(forLine: 0) == 0 {
            guard case let .numberedListItem(start) = blocks[index].kind else {
                continue
            }
            return start
        }
        return nil
    }

    private func removedBlockMergedNumberedListRuns(at index: Int) -> Bool {
        guard blocks.indices.contains(index),
              blocks.indices.contains(index - 1) else {
            return false
        }
        return blocks[index - 1].kind.isListItem
            && blocks[index].kind.isListItem
            && listRangeContainsNumberedItem(near: index)
    }

    private func listRangeContainsNumberedItem(near index: Int) -> Bool {
        guard let range = listRange(near: index) else {
            return false
        }
        return range.contains { blocks[$0].kind.isNumberedListItem }
    }

    private func isFirstListItem(at index: Int) -> Bool {
        guard blocks.indices.contains(index),
              blocks[index].kind.isListItem else {
            return false
        }
        return !blocks.indices.contains(index - 1) || !blocks[index - 1].kind.isListItem
    }

    private func uniqueChangedBlocks(_ changedBlocks: [BlockInputBlock]) -> [BlockInputBlock] {
        var indexesByID: [BlockInputBlockID: Int] = [:]
        var uniqueBlocks: [BlockInputBlock] = []
        for block in changedBlocks {
            if let index = indexesByID[block.id] {
                uniqueBlocks[index] = block
            } else {
                indexesByID[block.id] = uniqueBlocks.count
                uniqueBlocks.append(block)
            }
        }
        return uniqueBlocks
    }

    /// Returns whether a move keeps existing frontmatter document-leading.
    ///
    /// Custom stores that mutate their own block arrays should use this helper
    /// before applying granular move mutations. A misplaced frontmatter block can
    /// still move back to index `0` only when doing so does not displace an
    /// existing leading frontmatter block.
    public static func canMovePreservingLeadingFrontMatter(
        sourceIndex: Int,
        targetIndex: Int,
        in blocks: [BlockInputBlock]
    ) -> Bool {
        guard blocks.indices.contains(sourceIndex),
              blocks.indices.contains(targetIndex) else {
            return false
        }
        if blocks[sourceIndex].kind == .frontMatter {
            guard targetIndex == 0 else {
                return false
            }
            return sourceIndex == 0 || blocks.first?.kind != .frontMatter
        }
        return !(blocks.first?.kind == .frontMatter && targetIndex == 0)
    }
}

private extension BlockInputBlockKind {
    var isNumberedListItem: Bool {
        if case .numberedListItem = self {
            return true
        }
        return false
    }

    var isListItem: Bool {
        switch self {
        case .bulletedListItem, .numberedListItem, .checklistItem:
            return true
        case .paragraph, .heading, .code, .horizontalRule, .frontMatter, .quote, .table, .image, .rawMarkdown:
            return false
        }
    }
}
