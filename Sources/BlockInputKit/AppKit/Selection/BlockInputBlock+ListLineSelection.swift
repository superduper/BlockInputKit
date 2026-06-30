import Foundation

extension BlockInputBlock {
    var usesIncrementalListLineSelection: Bool {
        kind.usesIncrementalListLineSelection && BlockInputLineBreaks.lineCount(in: text) > 1
    }

    var incrementalListLineCount: Int {
        BlockInputLineBreaks.lineCount(in: text)
    }

    func incrementalListLineRange(at lineIndex: Int) -> NSRange? {
        let lineStarts = BlockInputLineBreaks.lineStartOffsets(in: text)
        guard lineStarts.indices.contains(lineIndex) else {
            return nil
        }
        let location = lineStarts[lineIndex]
        let end = lineStarts.indices.contains(lineIndex + 1) ? lineStarts[lineIndex + 1] : utf16Length
        return NSRange(location: location, length: max(0, end - location))
    }

    func incrementalListTextRange(covering lines: ClosedRange<Int>) -> NSRange? {
        guard let firstLine = incrementalListLineRange(at: lines.lowerBound),
              let lastLine = incrementalListLineRange(at: lines.upperBound) else {
            return nil
        }
        let end = NSMaxRange(lastLine)
        return NSRange(location: firstLine.location, length: max(0, end - firstLine.location))
    }

    func incrementalListSelectedLineBounds(for range: NSRange) -> ClosedRange<Int>? {
        let clampedRange = clampedTextRange(range)
        guard usesIncrementalListLineSelection,
              clampedRange.length > 0 else {
            return nil
        }
        let lineCount = incrementalListLineCount
        let lowerLine = min(max(lineIndex(containingUTF16Offset: clampedRange.location), 0), lineCount - 1)
        let selectedEndOffset = max(clampedRange.location, NSMaxRange(clampedRange) - 1)
        let upperLine = min(max(lineIndex(containingUTF16Offset: selectedEndOffset), 0), lineCount - 1)
        return lowerLine...max(lowerLine, upperLine)
    }

    func incrementalListSelectionRangeAfterExpanding(
        _ range: NSRange,
        direction: BlockInputVerticalMovementDirection
    ) -> NSRange? {
        guard let lineBounds = incrementalListSelectedLineBounds(for: range),
              let fullBounds = BlockInputLinearSelectionLadder.bounds(count: incrementalListLineCount) else {
            return nil
        }
        let expandedBounds = BlockInputLinearSelectionLadder.boundsAfterExpanding(
            lineBounds,
            direction: direction,
            within: fullBounds
        )
        return expandedBounds == lineBounds ? clampedTextRange(range) : incrementalListTextRange(covering: expandedBounds)
    }

    func incrementalListSelectionRangeAfterContracting(
        _ range: NSRange,
        expansionDirection: BlockInputVerticalMovementDirection
    ) -> NSRange? {
        let clampedRange = clampedTextRange(range)
        guard let lineBounds = incrementalListSelectedLineBounds(for: clampedRange) else {
            return nil
        }
        guard let contractedBounds = BlockInputLinearSelectionLadder.boundsAfterContracting(
            lineBounds,
            expansionDirection: expansionDirection
        ) else {
            return nil
        }
        return incrementalListTextRange(covering: contractedBounds)
    }

    func incrementalListSelectionRangeAfterDemotingWholeBlock(
        expansionDirection: BlockInputVerticalMovementDirection
    ) -> NSRange? {
        guard usesIncrementalListLineSelection,
              let fullBounds = BlockInputLinearSelectionLadder.bounds(count: incrementalListLineCount),
              let demotedBounds = BlockInputLinearSelectionLadder.boundsAfterDemotingWholeSelection(
                within: fullBounds,
                expansionDirection: expansionDirection
              ) else {
            return nil
        }
        return incrementalListTextRange(covering: demotedBounds)
    }

    func incrementalListEdgeRange(direction: BlockInputVerticalMovementDirection) -> NSRange? {
        guard let bounds = BlockInputLinearSelectionLadder.bounds(count: incrementalListLineCount) else {
            return nil
        }
        return incrementalListLineRange(at: BlockInputLinearSelectionLadder.edgeIndex(in: bounds, direction: direction))
    }

    func incrementalListSelectionCoversWholeBlock(_ range: NSRange) -> Bool {
        let clampedRange = clampedTextRange(range)
        return clampedRange.location <= 0 && NSMaxRange(clampedRange) >= utf16Length
    }

    func incrementalListAnchorOffset(for range: NSRange, expansionDirection: BlockInputVerticalMovementDirection) -> Int {
        let clampedRange = clampedTextRange(range)
        switch expansionDirection {
        case .upward:
            return NSMaxRange(clampedRange)
        case .downward:
            return clampedRange.location
        }
    }

    private func clampedTextRange(_ range: NSRange) -> NSRange {
        let location = min(max(range.location, 0), utf16Length)
        let length = min(max(range.length, 0), max(utf16Length - location, 0))
        return NSRange(location: location, length: length)
    }
}

private extension BlockInputBlockKind {
    var usesIncrementalListLineSelection: Bool {
        switch self {
        case .bulletedListItem, .numberedListItem, .checklistItem:
            return true
        case .paragraph, .heading, .code, .horizontalRule, .frontMatter, .quote, .table, .image, .rawMarkdown:
            return false
        }
    }
}
