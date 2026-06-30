import AppKit

extension BlockInputView {
    /// Handles Backspace/Delete with the caret at a link/chip boundary.
    ///
    /// For a CHIP (file/slash), the first press SELECTS the whole chip instead of deleting it; the next press (now with a
    /// selection) deletes it through the normal selection-deletion path — atomic "select then delete" so one keypress
    /// can't destroy a chip by accident. A regular (non-chip) link keeps its immediate whole-link delete.
    func deleteLinkAtBoundary(
        item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        direction: BlockInputLinkBoundaryDeletionDirection
    ) -> Bool {
        guard let index = index(of: blockID),
              let block = block(at: index),
              block.id == blockID,
              Self.blockKindSupportsLinkBoundaryEditing(block.kind),
              let linkRange = linkRangeAdjacentToBoundary(item.currentSelectedRange, direction: direction, in: block.text) else {
            return false
        }
        if linkRange.inlineChipKind(in: block.text) != nil {
            // Only the chip's OUTER edge (past `]…)`) triggers select-the-chip. A caret at the inner content edge means
            // the user arrowed inside to edit the label, so let that Backspace delete a label character normally.
            guard caretAtChipOuterEdge(item.currentSelectedRange.location, chip: linkRange, direction: direction) else {
                return false
            }
            // Select the whole chip — in the mounted text view too, so the next Backspace deletes the selection.
            item.textView.setSelectedRange(linkRange.fullRange)
            applySelection(.text(BlockInputTextRange(blockID: blockID, range: linkRange.fullRange)), notify: true)
            return true
        }
        return deleteWholeLink(linkRange, block: block, at: index, blockID: blockID, item: item)
    }

    private func deleteWholeLink(
        _ linkRange: BlockInputInlineMarkdownRange,
        block: BlockInputBlock,
        at index: Int,
        blockID: BlockInputBlockID,
        item: BlockInputBlockItem
    ) -> Bool {
        let beforeText = block.text
        let afterText = NSMutableString(string: beforeText)
        afterText.deleteCharacters(in: linkRange.fullRange)
        var afterBlock = block
        afterBlock.text = afterText as String
        let afterSelection = BlockInputSelection.cursor(BlockInputCursor(blockID: blockID, utf16Offset: linkRange.fullRange.location))
        undoController?.registerTextEdit(
            blockID: blockID,
            beforeText: beforeText,
            afterText: afterBlock.text,
            beforeLineIndentationLevels: block.lineIndentationLevels,
            afterLineIndentationLevels: afterBlock.lineIndentationLevels,
            selectionBefore: .cursor(BlockInputCursor(blockID: blockID, utf16Offset: item.currentSelectedRange.location)),
            selectionAfter: afterSelection
        )
        _ = applyGranularBlockReplacement(afterBlock, at: index, selection: afterSelection)
        return true
    }

    func resolvedInlineChipBoundaryTextChange(
        item: BlockInputBlockItem,
        beforeBlock: BlockInputBlock,
        proposedText: String,
        selectionBefore: BlockInputSelection?
    ) -> (text: String, proposedOffset: Int) {
        let selectedRange = item.currentSelectedRange
        guard let correction = inlineChipBoundaryInsertionCorrection(
            beforeBlock: beforeBlock,
            proposedText: proposedText,
            selectionBefore: selectionBefore
        ) else {
            return (proposedText, selectedRange.location + selectedRange.length)
        }
        let range = NSRange(location: correction.cursorOffset, length: 0)
        item.replaceCurrentTextFromEditorCorrection(correction.text, selectedRange: range)
        return (correction.text, correction.cursorOffset)
    }

    func inlineChipBoundaryAdjustedRange(_ range: NSRange, in block: BlockInputBlock) -> NSRange {
        guard range.length == 0,
              Self.blockKindSupportsLinkBoundaryEditing(block.kind),
              let linkRange = inlineChipRangeEndingAtContentBoundary(range.location, in: block.text) else {
            return range
        }
        return NSRange(location: NSMaxRange(linkRange.fullRange), length: 0)
    }

    private func inlineChipBoundaryInsertionCorrection(
        beforeBlock: BlockInputBlock,
        proposedText: String,
        selectionBefore: BlockInputSelection?
    ) -> InlineChipBoundaryInsertionCorrection? {
        guard Self.blockKindSupportsLinkBoundaryEditing(beforeBlock.kind),
              case let .cursor(cursor) = selectionBefore,
              cursor.blockID == beforeBlock.id else {
            return nil
        }
        let beforeText = beforeBlock.text as NSString
        let proposedText = proposedText as NSString
        let cursorOffset = cursor.utf16Offset
        guard cursorOffset >= 0,
              cursorOffset <= beforeText.length,
              proposedText.length > beforeText.length else {
            return nil
        }
        let insertionLength = proposedText.length - beforeText.length
        guard proposedText.substring(to: cursorOffset) == beforeText.substring(to: cursorOffset),
              proposedText.substring(from: cursorOffset + insertionLength) == beforeText.substring(from: cursorOffset) else {
            return nil
        }
        let insertedText = proposedText.substring(with: NSRange(location: cursorOffset, length: insertionLength))
        guard !insertedText.isEmpty,
              let linkRange = inlineChipRangeEndingAtContentBoundary(cursorOffset, in: beforeBlock.text) else {
            return nil
        }
        let insertionOffset = NSMaxRange(linkRange.fullRange)
        let correctedText = NSMutableString(string: beforeBlock.text)
        correctedText.insert(insertedText, at: insertionOffset)
        return InlineChipBoundaryInsertionCorrection(
            text: correctedText as String,
            cursorOffset: insertionOffset + insertionLength
        )
    }

    private static func blockKindSupportsLinkBoundaryEditing(_ kind: BlockInputBlockKind) -> Bool {
        BlockInputBlockItem.supportsInlineMarkdownStyling(kind)
    }

    /// Whether the caret sits at the chip's OUTER edge (past the closing `)` for backward, before the opening `[` for
    /// forward) — i.e. approaching the chip from outside, not at the inner label-content edge.
    private func caretAtChipOuterEdge(
        _ offset: Int,
        chip: BlockInputInlineMarkdownRange,
        direction: BlockInputLinkBoundaryDeletionDirection
    ) -> Bool {
        switch direction {
        case .backward:
            return offset == NSMaxRange(chip.fullRange)
        case .forward:
            return offset == chip.fullRange.location
        }
    }

    private func inlineChipRangeEndingAtContentBoundary(
        _ offset: Int,
        in text: String
    ) -> BlockInputInlineMarkdownRange? {
        let inlineCodeRanges = BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange)
        return BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text, excluding: inlineCodeRanges, fileBaseURL: fileBaseURL)
            .first { range in
                range.inlineChipKind(in: text) != nil &&
                    NSMaxRange(range.contentRange) == offset
            }
    }

    /// The link/chip whose boundary the caret sits at, for the given direction. Matches regular links and chips alike;
    /// the caller decides whether to select (chip) or delete (regular link).
    private func linkRangeAdjacentToBoundary(
        _ selectedRange: NSRange,
        direction: BlockInputLinkBoundaryDeletionDirection,
        in text: String
    ) -> BlockInputInlineMarkdownRange? {
        guard selectedRange.length == 0 else {
            return nil
        }
        let inlineCodeRanges = BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange)
        return BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: text, excluding: inlineCodeRanges, fileBaseURL: fileBaseURL, inlineMarkupProviders: inlineMarkupProviders
        )
        .first { range in
            let isChip = range.inlineChipKind(in: text) != nil
            return (range.style == .link || isChip) && range.isAdjacent(to: selectedRange.location, direction: direction)
        }
    }
}

private struct InlineChipBoundaryInsertionCorrection {
    var text: String
    var cursorOffset: Int
}

private extension BlockInputInlineMarkdownRange {
    func isAdjacent(to offset: Int, direction: BlockInputLinkBoundaryDeletionDirection) -> Bool {
        switch direction {
        case .backward:
            offset == NSMaxRange(contentRange) || offset == NSMaxRange(fullRange)
        case .forward:
            offset == contentRange.location || offset == fullRange.location
        }
    }
}
