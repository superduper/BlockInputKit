import AppKit

extension BlockInputView {
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestCompletionKeyDown event: NSEvent
    ) -> Bool {
        handleCompletionKeyDown(event)
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestCompletionCommand selector: Selector
    ) -> Bool {
        handleCompletionCommand(selector)
    }
}
