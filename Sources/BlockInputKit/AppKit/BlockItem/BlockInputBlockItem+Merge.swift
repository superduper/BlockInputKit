import Foundation

extension BlockInputBlockItem {
    func requestMergeWithPreviousBlock() -> Bool {
        guard isEditable,
              let blockID else {
            return false
        }
        return delegate?.blockItemDidRequestMergeWithPreviousBlock(self, blockID: blockID) ?? false
    }
}
