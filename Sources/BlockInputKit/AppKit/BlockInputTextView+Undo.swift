import AppKit

extension BlockInputTextView {
    /// Objective-C selector shim that keeps menu-driven undo routed through the editor undo controller.
    @objc(undo:)
    func blockInputUndo(_ sender: Any?) {
        _ = blockItem?.requestUndoShortcut(.undo)
    }

    /// Objective-C selector shim that keeps menu-driven redo routed through the editor undo controller.
    @objc(redo:)
    func blockInputRedo(_ sender: Any?) {
        _ = blockItem?.requestUndoShortcut(.redo)
    }
}
