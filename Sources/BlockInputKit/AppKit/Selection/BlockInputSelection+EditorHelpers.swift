import Foundation

extension BlockInputSelection {
    var wholeSelectedBlockIDs: [BlockInputBlockID] {
        switch self {
        case let .blocks(blockIDs):
            return blockIDs
        case let .mixed(selection):
            return selection.blockIDs
        case .cursor, .text:
            return []
        }
    }

    func partialTextRange(for blockID: BlockInputBlockID) -> BlockInputTextRange? {
        guard case let .mixed(selection) = self else {
            return nil
        }
        if selection.leadingTextRange?.blockID == blockID {
            return selection.leadingTextRange
        }
        if selection.trailingTextRange?.blockID == blockID {
            return selection.trailingTextRange
        }
        return nil
    }

    func textRange(for blockID: BlockInputBlockID) -> BlockInputTextRange? {
        guard case let .text(textRange) = self, textRange.blockID == blockID else {
            return nil
        }
        return textRange
    }
}
