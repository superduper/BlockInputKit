import AppKit

extension BlockInputView {
    /// When a paragraph block gains `\n\n`, splits it at each blank line into separate
    /// paragraph blocks. This is a single structural edit so it is undoable in one step.
    /// Returns true if a split was performed (caller should skip `applyPlainTextChange`).
    func splitParagraphAtBlankLinesIfNeeded(
        blockID: BlockInputBlockID,
        beforeBlock: BlockInputBlock,
        afterText: String,
        proposedOffset: Int,
        selectionBefore: BlockInputSelection?
    ) -> Bool {
        guard beforeBlock.kind == .paragraph, afterText.contains("\n\n") else { return false }
        let components = afterText.components(separatedBy: "\n\n")
        guard components.count > 1 else { return false }
        let (componentIndex, offsetInComponent) = blankLineSplitCursorPosition(
            originalOffset: proposedOffset,
            components: components
        )
        _ = performStructuralEdit(
            named: "Split Paragraph",
            selectionBeforeOverride: selectionBefore ?? selection,
            edit: { [beforeBlock] document in
                guard let index = document.index(of: blockID) else { return nil }
                var blocks: [BlockInputBlock] = []
                blocks.append(BlockInputBlock(id: beforeBlock.id, kind: .paragraph, text: components[0]))
                for component in components.dropFirst() {
                    blocks.append(BlockInputBlock(kind: .paragraph, text: component))
                }
                document.blocks.replaceSubrange(index...index, with: blocks)
                let targetBlock = blocks[componentIndex]
                let clampedOffset = min(offsetInComponent, (targetBlock.text as NSString).length)
                return .cursor(BlockInputCursor(blockID: targetBlock.id, utf16Offset: clampedOffset))
            }
        )
        return true
    }

    private func blankLineSplitCursorPosition(
        originalOffset: Int,
        components: [String]
    ) -> (componentIndex: Int, offset: Int) {
        var pos = 0
        for (index, component) in components.enumerated() {
            let compLen = (component as NSString).length
            let isLast = index == components.count - 1
            if isLast || originalOffset <= pos + compLen {
                return (index, min(max(0, originalOffset - pos), compLen))
            }
            let separatorEnd = pos + compLen + 2  // 2 = length of "\n\n"
            if originalOffset < separatorEnd {
                return (index + 1, 0)
            }
            pos = separatorEnd
        }
        let last = components.count - 1
        return (last, (components[last] as NSString).length)
    }
}
