import AppKit

extension BlockInputBlockItem {
    func requestCompletionKeyDown(_ event: NSEvent) -> Bool {
        guard isEditable,
              let blockID else {
            return false
        }
        return delegate?.blockItem(
            self,
            blockID: blockID,
            didRequestCompletionKeyDown: event
        ) ?? false
    }

    func requestCompletionCommand(_ selector: Selector) -> Bool {
        guard isEditable,
              let blockID else {
            return false
        }
        return delegate?.blockItem(
            self,
            blockID: blockID,
            didRequestCompletionCommand: selector
        ) ?? false
    }

    func requestKeyDown(_ event: NSEvent) -> Bool {
        delegate?.blockItemShouldInterceptKeyDown(self, event: event) ?? false
    }
}
