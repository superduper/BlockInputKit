import AppKit

struct BlockInputTableCellLinkReplacement {
    var block: BlockInputBlock
    var beforeBlock: BlockInputBlock
    var beforeSelection: BlockInputSelection?
    var index: Int
    var replacementRange: NSRange
    var replacement: BlockInputLinkReplacement
}

extension BlockInputView {
    func replaceTableCellLinkSource(_ context: BlockInputTableCellLinkReplacement) -> Bool {
        guard isEditable else {
            return false
        }
        var block = context.block
        guard let table = BlockInputTable(markdown: block.text),
              let position = table.cellPosition(containingSourceRange: context.replacementRange),
              let localReplacementRange = table.localRange(forSourceRange: context.replacementRange, in: position),
              let cell = table.cell(at: position) else {
            return false
        }
        let mutableCellText = NSMutableString(string: cell.text)
        mutableCellText.replaceCharacters(in: localReplacementRange, with: context.replacement.text)
        guard let updatedTable = table.replacingCellText(
            row: position.row,
            column: position.column,
            text: mutableCellText as String
        ) else {
            return false
        }
        block.text = updatedTable.markdown
        guard let afterSelection = tableCellLinkSelection(
            block: block,
            table: updatedTable,
            position: position,
            localReplacementRange: localReplacementRange,
            replacement: context.replacement
        ) else {
            return false
        }
        _ = applyGranularBlockReplacement(block, at: context.index, selection: afterSelection)
        undoController?.registerBlockReplacementStructuralEdit(
            actionName: context.replacement.actionName,
            beforeBlock: context.beforeBlock,
            afterBlock: block,
            selectionBefore: context.beforeSelection,
            selectionAfter: afterSelection
        )
        return true
    }

    private func tableCellLinkSelection(
        block: BlockInputBlock,
        table: BlockInputTable,
        position: BlockInputTable.CellPosition,
        localReplacementRange: NSRange,
        replacement: BlockInputLinkReplacement
    ) -> BlockInputSelection? {
        let localSelection: NSRange
        if replacement.selectsResultingText {
            let contentOffset = replacement.actionName == "Remove Link"
                ? localReplacementRange.location
                : localReplacementRange.location + 1
            localSelection = NSRange(location: contentOffset, length: replacement.selectedUTF16Length)
        } else {
            localSelection = NSRange(
                location: localReplacementRange.location + (replacement.text as NSString).length,
                length: 0
            )
        }
        guard let sourceRange = table.sourceRange(forLocalRange: localSelection, in: position) else {
            return nil
        }
        if sourceRange.length == 0 {
            return .cursor(BlockInputCursor(blockID: block.id, utf16Offset: sourceRange.location))
        }
        return .text(BlockInputTextRange(blockID: block.id, range: sourceRange))
    }
}
