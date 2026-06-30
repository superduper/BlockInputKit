import AppKit

extension BlockInputView {
    func installSelectionExpansionKeyMonitor() {
        selectionExpansionKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.isArrowKey {
                let responder = String(describing: self?.window?.firstResponder.map { type(of: $0) })
                BlockInputSelectionDebug.emit(
                    "monitor key=\(event.debugKeyName) modifiers=\(event.debugModifierNames) responder=\(responder)"
                )
            }
            guard let self,
                  isEditorFirstResponder,
                  !linkModalContainsCurrentResponder(),
                  handleFocusedTableCellSelectionKeyEvent(event)
                    || handleSelectionExpansionKeyEvent(event)
                    || handleLineBoundarySelectionKeyEvent(event)
                    || handleHorizontalSelectionAdjustmentKeyEvent(event)
                    || handleWordSelectionAdjustmentShortcut(event) else {
                if event.isArrowKey {
                    BlockInputSelectionDebug.emit("monitor pass selection=\(String(describing: self?.selection))")
                }
                return event
            }
            BlockInputSelectionDebug.emit("monitor consumed selection=\(String(describing: selection))")
            return nil
        }
    }

    func handleFocusedTableCellSelectionKeyEvent(_ event: NSEvent) -> Bool {
        guard let textView = window?.firstResponder as? BlockInputTextView else {
            return false
        }
        return textView.handleTableCellSelectionArrow(event)
    }

    func handleFocusedTableCellCommandArrowKeyEvent(_ event: NSEvent) -> Bool {
        guard let textView = window?.firstResponder as? BlockInputTextView else {
            return false
        }
        return textView.handleTableCellCommandArrow(event)
    }

    func handleEditorArrowKeyEvent(_ event: NSEvent) -> Bool {
        if handleFocusedTableCellCommandArrowKeyEvent(event) {
            return true
        }
        if let direction = event.blockInputDocumentBoundaryDirection,
           moveCaretToDocumentBoundary(direction) {
            return true
        }
        if handleLineBoundarySelectionKeyEvent(event) {
            return true
        }
        if handleFocusedTableCellSelectionKeyEvent(event) {
            return true
        }
        return handleSelectionExpansionShortcut(event)
    }

    func handleFocusedTableCellSelectionCommand(_ selector: Selector) -> Bool {
        guard let textView = window?.firstResponder as? BlockInputTextView else {
            return false
        }
        return textView.handleTableCellSelectionCommand(selector)
    }
}
