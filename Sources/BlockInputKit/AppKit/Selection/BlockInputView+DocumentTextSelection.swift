import AppKit

extension BlockInputView {
    func selection(
        from anchor: BlockInputDocumentTextBoundary,
        to active: BlockInputDocumentTextBoundary
    ) -> BlockInputSelection? {
        guard let anchorIndex = index(of: anchor.blockID),
              let activeIndex = index(of: active.blockID) else {
            return nil
        }
        let ordered = orderedBoundaries(anchor, anchorIndex: anchorIndex, active, activeIndex: activeIndex)
        if ordered.start == ordered.end {
            return collapsedSelection(at: ordered.start)
        }
        if ordered.startIndex == ordered.endIndex {
            return singleBlockSelection(from: ordered.start, to: ordered.end)
        }
        return multiBlockSelection(
            start: ordered.start,
            startIndex: ordered.startIndex,
            end: ordered.end,
            endIndex: ordered.endIndex
        )
    }

    private func orderedBoundaries(
        _ lhs: BlockInputDocumentTextBoundary,
        anchorIndex lhsIndex: Int,
        _ rhs: BlockInputDocumentTextBoundary,
        activeIndex rhsIndex: Int
    ) -> BlockInputOrderedTextBoundarySpan {
        if lhsIndex < rhsIndex || (lhsIndex == rhsIndex && lhs.utf16Offset <= rhs.utf16Offset) {
            return BlockInputOrderedTextBoundarySpan(start: lhs, startIndex: lhsIndex, end: rhs, endIndex: rhsIndex)
        }
        return BlockInputOrderedTextBoundarySpan(start: rhs, startIndex: rhsIndex, end: lhs, endIndex: lhsIndex)
    }

    private func collapsedSelection(at boundary: BlockInputDocumentTextBoundary) -> BlockInputSelection? {
        guard let block = block(withID: boundary.blockID), block.kind != .horizontalRule else {
            return .blocks([boundary.blockID])
        }
        return .cursor(BlockInputCursor(
            blockID: boundary.blockID,
            utf16Offset: min(max(boundary.utf16Offset, 0), block.utf16Length)
        ))
    }

    private func singleBlockSelection(
        from start: BlockInputDocumentTextBoundary,
        to end: BlockInputDocumentTextBoundary
    ) -> BlockInputSelection? {
        guard let block = block(withID: start.blockID) else {
            return nil
        }
        let startOffset = min(max(start.utf16Offset, 0), block.utf16Length)
        let endOffset = min(max(end.utf16Offset, startOffset), block.utf16Length)
        guard block.kind != .horizontalRule, endOffset > startOffset else {
            return .blocks([block.id])
        }
        if startOffset == 0, endOffset == block.utf16Length {
            return .blocks([block.id])
        }
        return .mixed(BlockInputMixedSelection(blockIDs: [], leadingTextRange: BlockInputTextRange(
            blockID: block.id,
            range: NSRange(location: startOffset, length: endOffset - startOffset)
        )))
    }

    private func multiBlockSelection(
        start: BlockInputDocumentTextBoundary,
        startIndex: Int,
        end: BlockInputDocumentTextBoundary,
        endIndex: Int
    ) -> BlockInputSelection? {
        // Rebuild the narrowest canonical selection for the flattened span: fully covered blocks become `.blocks`,
        // and partial edges around whole middle blocks become `.mixed`.
        var blockIDs: [BlockInputBlockID] = []
        var leadingTextRange: BlockInputTextRange?
        var trailingTextRange: BlockInputTextRange?

        for index in startIndex...endIndex {
            guard let block = block(at: index) else {
                return nil
            }
            let blockStart = index == startIndex ? min(max(start.utf16Offset, 0), block.utf16Length) : 0
            let blockEnd = index == endIndex ? min(max(end.utf16Offset, 0), block.utf16Length) : block.utf16Length
            let coversWholeBlock = blockStart == 0 && blockEnd == block.utf16Length
            if block.kind == .horizontalRule || block.utf16Length == 0 || coversWholeBlock {
                if coversWholeBlock || startIndex != endIndex {
                    blockIDs.append(block.id)
                }
            } else if blockEnd > blockStart {
                let textRange = BlockInputTextRange(
                    blockID: block.id,
                    range: NSRange(location: blockStart, length: blockEnd - blockStart)
                )
                if index == startIndex {
                    leadingTextRange = textRange
                } else if index == endIndex {
                    trailingTextRange = textRange
                } else {
                    blockIDs.append(block.id)
                }
            }
        }

        if leadingTextRange == nil, trailingTextRange == nil {
            return blockIDs.isEmpty ? nil : .blocks(blockIDs)
        }
        return .mixed(BlockInputMixedSelection(
            blockIDs: blockIDs,
            leadingTextRange: leadingTextRange,
            trailingTextRange: trailingTextRange
        ))
    }
}

private struct BlockInputOrderedTextBoundarySpan {
    var start: BlockInputDocumentTextBoundary
    var startIndex: Int
    var end: BlockInputDocumentTextBoundary
    var endIndex: Int
}
