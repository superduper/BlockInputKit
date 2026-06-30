import Foundation

extension BlockInputView {
    var blockCount: Int {
        documentStore?.loadedBlockCount ?? document.blocks.count
    }

    func block(at index: Int) -> BlockInputBlock? {
        guard let documentStore else {
            return document.blocks[safe: index]
        }
        return documentStore.block(at: index)
    }

    var loadedBlockIDs: [BlockInputBlockID] {
        (0..<blockCount).compactMap { block(at: $0)?.id }
    }

    func block(withID id: BlockInputBlockID) -> BlockInputBlock? {
        guard let documentStore else {
            return document.block(withID: id)
        }
        return documentStore.block(withID: id)
    }

    func index(of id: BlockInputBlockID) -> Int? {
        guard let documentStore else {
            return document.index(of: id)
        }
        return documentStore.index(of: id)
    }

    func containsValidSelection(_ selection: BlockInputSelection) -> Bool {
        switch selection {
        case let .cursor(cursor):
            return containsValidCursor(cursor)
        case let .text(range):
            return containsValidTextRange(range)
        case let .blocks(blockIDs):
            return !blockIDs.isEmpty
                && Set(blockIDs).count == blockIDs.count
                && blockIDs.allSatisfy { index(of: $0) != nil }
        case let .mixed(selection):
            let partialRanges = [selection.leadingTextRange, selection.trailingTextRange].compactMap { $0 }
            let allIDs = selection.blockIDs + partialRanges.map(\.blockID)
            let isStructurallyValid = !allIDs.isEmpty
                && Set(allIDs).count == allIDs.count
                && selection.blockIDs.allSatisfy { index(of: $0) != nil }
                && partialRanges.allSatisfy { $0.range.length > 0 && containsValidTextRange($0) }
            guard isStructurallyValid else {
                return false
            }
            return containsCanonicalMixedSelectionOrder(selection)
        }
    }

    func containsValidCursor(_ cursor: BlockInputCursor) -> Bool {
        guard let block = block(withID: cursor.blockID) else {
            return false
        }
        return cursor.utf16Offset >= 0 && cursor.utf16Offset <= block.cursorUTF16Length
    }

    func containsValidTextRange(_ textRange: BlockInputTextRange) -> Bool {
        guard let block = block(withID: textRange.blockID),
              textRange.range.location >= 0,
              textRange.range.length >= 0 else {
            return false
        }
        return textRange.range.location <= block.utf16Length
            && textRange.range.length <= block.utf16Length - textRange.range.location
    }

    func normalizedTableSelection(_ selection: BlockInputSelection?) -> BlockInputSelection? {
        switch selection {
        case let .cursor(cursor):
            guard let block = block(withID: cursor.blockID),
                  block.kind == .table,
                  let table = BlockInputTable(markdown: block.text) else {
                return selection
            }
            let range = NSRange(location: cursor.utf16Offset, length: 0)
            return isValidTableCellSourceRange(range, in: table) ? selection : .blocks([cursor.blockID])
        case let .text(textRange):
            switch normalizedTableTextRange(textRange) {
            case .keep:
                return selection
            case .promoteToBlockSelection(let blockID):
                return .blocks([blockID])
            }
        case let .mixed(mixedSelection):
            return normalizedMixedTableSelection(mixedSelection)
        case .blocks, nil:
            return selection
        }
    }

    private func normalizedMixedTableSelection(_ selection: BlockInputMixedSelection) -> BlockInputSelection {
        var wholeBlockIDs = selection.blockIDs
        var leadingTextRange = selection.leadingTextRange
        var trailingTextRange = selection.trailingTextRange

        if let range = leadingTextRange {
            switch normalizedTableTextRange(range) {
            case .keep:
                break
            case .promoteToBlockSelection(let blockID):
                wholeBlockIDs.append(blockID)
                leadingTextRange = nil
            }
        }
        if let range = trailingTextRange {
            switch normalizedTableTextRange(range) {
            case .keep:
                break
            case .promoteToBlockSelection(let blockID):
                wholeBlockIDs.append(blockID)
                trailingTextRange = nil
            }
        }

        let partialBlockIDs = Set([leadingTextRange?.blockID, trailingTextRange?.blockID].compactMap { $0 })
        let sortedWholeBlockIDs = Array(Set(wholeBlockIDs))
            .filter { !partialBlockIDs.contains($0) }
            .sorted { (index(of: $0) ?? Int.max) < (index(of: $1) ?? Int.max) }
        if leadingTextRange == nil, trailingTextRange == nil {
            return .blocks(sortedWholeBlockIDs)
        }
        return .mixed(BlockInputMixedSelection(
            blockIDs: sortedWholeBlockIDs,
            leadingTextRange: leadingTextRange,
            trailingTextRange: trailingTextRange
        ))
    }

    private func normalizedTableTextRange(_ textRange: BlockInputTextRange) -> TableTextRangeNormalization {
        guard let block = block(withID: textRange.blockID),
              block.kind == .table,
              let table = BlockInputTable(markdown: block.text) else {
            return .keep(textRange)
        }
        return isValidTableCellSourceRange(textRange.range, in: table) == false
            ? .promoteToBlockSelection(textRange.blockID)
            : .keep(textRange)
    }

    private func isValidTableCellSourceRange(_ range: NSRange, in table: BlockInputTable) -> Bool {
        guard let position = table.cellPosition(containingSourceRange: range) else {
            return false
        }
        return table.localRange(forSourceRange: range, in: position) != nil
    }

    private func containsCanonicalMixedSelectionOrder(_ selection: BlockInputMixedSelection) -> Bool {
        let wholeIndexes = selection.blockIDs.compactMap { index(of: $0) }.sorted()
        let leadingIndex = selection.leadingTextRange.flatMap { index(of: $0.blockID) }
        let trailingIndex = selection.trailingTextRange.flatMap { index(of: $0.blockID) }
        if let leadingIndex, let trailingIndex, leadingIndex >= trailingIndex {
            return false
        }
        let firstSelectionIndex = leadingIndex ?? wholeIndexes.first ?? trailingIndex
        let lastSelectionIndex = trailingIndex ?? wholeIndexes.last ?? leadingIndex
        guard let firstSelectionIndex, let lastSelectionIndex else {
            return false
        }
        let expectedWholeIndexes = (firstSelectionIndex...lastSelectionIndex).filter {
            $0 != leadingIndex && $0 != trailingIndex
        }
        return wholeIndexes == expectedWholeIndexes
    }
}

private enum TableTextRangeNormalization {
    case keep(BlockInputTextRange)
    case promoteToBlockSelection(BlockInputBlockID)
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
