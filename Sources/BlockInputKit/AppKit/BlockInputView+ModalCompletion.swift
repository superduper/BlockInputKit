import AppKit

/// Live state for the link modal's "Target" fuzzy finder.
///
/// The finder is the SAME engine as the inline completion (same `completionProvider`, same ranker, same
/// `BlockInputCompletionPopupView` + `BlockInputCompletionPopupState`, same key handling); only the presentation
/// differs: the popup is anchored under the modal's Target field and accepting a row fills the modal fields with the
/// picked suggestion's target/title instead of rewriting block text.
struct BlockInputModalCompletionState {
    /// Block whose markup is being edited; used as the provider request's block context.
    var blockID: BlockInputBlockID
    /// Completion trigger the finder requests under (`.custom(id)` for the markup's registered `finderTriggerID`).
    var trigger: BlockInputCompletionTrigger
    /// Identity of the in-flight provider request, so a stale response cannot replace newer suggestions.
    var requestID: UUID
    /// Latest query text taken from the Target field.
    var query: String
    /// Ranked suggestions returned by the provider for `query`.
    var suggestions: [BlockInputCompletionSuggestion]
    /// Highlighted row index for keyboard/hover selection.
    var highlightedIndex: Int
    /// Whether a provider request is outstanding.
    var isLoading: Bool
}

extension BlockInputView {
    /// Runs a completion for the modal Target field's current text and presents the shared popup anchored to the field.
    /// Called whenever the Target field's text changes while a custom-markup edit modal is shown; the finder drives the
    /// markup's registered `.custom(finderTriggerID)` trigger.
    func refreshModalCompletion(query: String, blockID: BlockInputBlockID, triggerID: String) {
        let trigger: BlockInputCompletionTrigger = .custom(triggerID)
        guard isEditable, completionProvider != nil else {
            dismissModalCompletionPopup()
            return
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            dismissModalCompletionPopup()
            return
        }
        let requestID = UUID()
        var state = modalCompletionState ?? BlockInputModalCompletionState(
            blockID: blockID,
            trigger: trigger,
            requestID: requestID,
            query: query,
            suggestions: [],
            highlightedIndex: 0,
            isLoading: true
        )
        state.blockID = blockID
        state.trigger = trigger
        state.requestID = requestID
        state.query = query
        state.isLoading = state.suggestions.isEmpty
        modalCompletionState = state
        showModalCompletionPopup()
        requestModalCompletionSuggestions(trigger: trigger, query: query, blockID: blockID, requestID: requestID)
    }

    /// Whether the modal note finder popup is currently presented.
    var isModalCompletionPopupVisible: Bool {
        modalCompletionState != nil && modalCompletionPopupView?.superview != nil
    }

    /// Field-editor command cooperation: while the popup is open it handles arrows/Return/Tab/Escape; otherwise declines
    /// so the modal's field editor behaves normally. Mirrors the inline finder's `handleCompletionCommand` key set.
    func handleModalCompletionCommand(_ selector: Selector) -> Bool {
        guard let state = modalCompletionState else {
            return false
        }
        switch selector {
        case #selector(NSResponder.moveUp(_:)):
            moveModalCompletionHighlight(delta: -1)
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveModalCompletionHighlight(delta: 1)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            dismissModalCompletionPopup()
            return true
        case #selector(NSResponder.insertTab(_:)),
             #selector(NSResponder.insertNewline(_:)),
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            return acceptHighlightedModalCompletionSuggestion(state: state)
        default:
            return false
        }
    }

    func dismissModalCompletionPopup() {
        modalCompletionRequestTask?.cancel()
        modalCompletionRequestTask = nil
        modalCompletionState = nil
        modalCompletionPopupEventCaptureView.removeFromSuperview()
        modalCompletionPopupView?.removeFromSuperview()
        modalCompletionPopupView = nil
        removeModalCompletionDismissalMonitor()
    }

    /// Whether a window-space point falls inside the modal finder popup, so the modal's outside-click dismissal can defer.
    func modalCompletionPopupContains(windowPoint: NSPoint) -> Bool {
        guard let popup = modalCompletionPopupView, popup.superview != nil else {
            return false
        }
        let locationInPopup = popup.convert(windowPoint, from: nil)
        return popup.bounds.contains(locationInPopup)
    }

    private func requestModalCompletionSuggestions(
        trigger: BlockInputCompletionTrigger,
        query: String,
        blockID: BlockInputBlockID,
        requestID: UUID
    ) {
        modalCompletionRequestTask?.cancel()
        guard let request = completionRequest(
            trigger: trigger,
            query: query,
            blockID: blockID,
            replacementRange: nil,
            rawQuery: query,
            fileQuery: nil,
            refreshesDocumentFromStore: false
        ) else {
            dismissModalCompletionPopup()
            return
        }
        modalCompletionRequestTask = Task.detached(
            priority: .userInitiated
        ) { [weak self, provider = request.provider, context = request.context] in
            let suggestions = await provider.suggestions(for: context)
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run { [weak self] in
                self?.applyModalCompletionSuggestions(suggestions, requestID: requestID)
            }
        }
    }

    private func applyModalCompletionSuggestions(_ suggestions: [BlockInputCompletionSuggestion], requestID: UUID) {
        guard var state = modalCompletionState, state.requestID == requestID else {
            return
        }
        state.suggestions = suggestions
        state.highlightedIndex = suggestions.isEmpty ? 0 : min(state.highlightedIndex, suggestions.count - 1)
        state.isLoading = false
        modalCompletionState = state
        modalCompletionRequestTask = nil
        showModalCompletionPopup()
    }

    private func showModalCompletionPopup() {
        guard let state = modalCompletionState,
              let layout = modalCompletionPopupLayout(for: state) else {
            dismissModalCompletionPopup()
            return
        }
        let popup = modalCompletionPopupView ?? BlockInputCompletionPopupView()
        modalCompletionPopupView = popup
        presentCompletionPopup(
            popup,
            captureView: modalCompletionPopupEventCaptureView,
            layout: layout,
            state: modalCompletionPopupState(for: state),
            onSelect: { [weak self] suggestion in
                self?.acceptModalCompletionSuggestion(suggestion)
            },
            onHighlight: { [weak self] index in
                self?.highlightModalCompletionSuggestion(at: index)
            }
        )
        installModalCompletionDismissalMonitor()
    }

    private func modalCompletionPopupState(for state: BlockInputModalCompletionState) -> BlockInputCompletionPopupState {
        BlockInputCompletionPopupState(
            suggestions: state.suggestions,
            highlightedIndex: state.highlightedIndex,
            isLoading: state.isLoading,
            sessionID: state.requestID
        )
    }

    /// Anchors the popup directly under the modal's Target field, hosted in the same container as the modal.
    private func modalCompletionPopupLayout(for state: BlockInputModalCompletionState) -> BlockInputCompletionPopupOverlay? {
        guard let modal = linkModalView,
              let container = modal.superview else {
            return nil
        }
        let fieldFrameInWindow = modal.targetFieldWindowRect
        let height = BlockInputCompletionPopupView.measuredHeight(for: modalCompletionPopupState(for: state))
        let originInContainer = container.convert(fieldFrameInWindow.origin, from: nil)
        let width = fieldFrameInWindow.width
        let popupY = container.isFlipped
            ? originInContainer.y + fieldFrameInWindow.height + 6
            : originInContainer.y - height - 6
        return BlockInputCompletionPopupOverlay(
            container: container,
            frame: NSRect(x: originInContainer.x, y: popupY, width: width, height: height)
        )
    }

    private func moveModalCompletionHighlight(delta: Int) {
        guard var state = modalCompletionState, !state.suggestions.isEmpty else {
            return
        }
        state.highlightedIndex = min(max(0, state.highlightedIndex + delta), state.suggestions.count - 1)
        modalCompletionState = state
        modalCompletionPopupView?.suppressHoverUntilPointerMoves()
        showModalCompletionPopup()
    }

    private func highlightModalCompletionSuggestion(at index: Int) {
        guard var state = modalCompletionState,
              state.suggestions.indices.contains(index),
              state.highlightedIndex != index else {
            return
        }
        state.highlightedIndex = index
        modalCompletionState = state
        showModalCompletionPopup()
    }

    private func acceptHighlightedModalCompletionSuggestion(state: BlockInputModalCompletionState) -> Bool {
        guard let suggestion = state.suggestions[safe: state.highlightedIndex] else {
            return false
        }
        acceptModalCompletionSuggestion(suggestion)
        return true
    }

    /// Fills the modal Target field with the picked note's target and, when empty, the Title field with its title.
    ///
    /// Core never parses a custom markup's grammar: the target is the suggestion's `exactMatchText ?? insertionText`
    /// (the plugin sets `exactMatchText` to the bare target), and the title is the suggestion's `title`.
    private func acceptModalCompletionSuggestion(_ suggestion: BlockInputCompletionSuggestion) {
        guard let modal = linkModalView else {
            dismissModalCompletionPopup()
            return
        }
        dismissModalCompletionPopup()
        let picked = modalCompletionPick(for: suggestion)
        modal.fillTarget(slug: picked.target, title: picked.title)
    }

    /// Recovers (target, title) for the modal fields from a picked suggestion, grammar-free.
    private func modalCompletionPick(
        for suggestion: BlockInputCompletionSuggestion
    ) -> (target: String, title: String) {
        let target = (suggestion.exactMatchText ?? suggestion.insertionText).trimmingCharacters(in: .whitespacesAndNewlines)
        let title = suggestion.title.isEmpty ? target : suggestion.title
        return (target, title)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
