import AppKit

extension BlockInputView {
    /// Routes a click on a styled custom-markup span to the host `inlineLinkClickHandler` with kind
    /// `.customMarkup(identifier)`.
    ///
    /// The destination is synthesized generically as `<identifier>:<percent-encoded payload.primary>` so the click
    /// context keeps a non-optional `destination`; `alias` is `payload.secondary` and `label` is
    /// `payload.secondary ?? payload.primary`. The shipping interaction model matches links/wikilinks: a single click on
    /// the body only places the caret (the open gate runs first); a double/command click or open-icon click opens. When
    /// no host handler decides the click (or it asks for the modal), the editor opens the provider's `modalMode` modal —
    /// or does nothing when the provider is host-only (no `modalMode`).
    func handleCustomMarkupClick(
        blockID: BlockInputBlockID,
        markupRange: BlockInputInlineMarkdownRange,
        identity: BlockInputInlineMarkupIdentity,
        event: NSEvent
    ) -> Bool {
        guard block(withID: blockID) != nil else {
            return false
        }
        if linkHoverEditAffordance, !linkClickShouldOpen(blockID: blockID, event: event) {
            return false
        }
        let payload = identity.payload
        guard let destination = synthesizedCustomMarkupURL(identifier: identity.identifier, primary: payload.primary) else {
            return false
        }
        if let action = inlineLinkClickHandler?(BlockInputInlineLinkClickContext(
            kind: .customMarkup(identity.identifier),
            destination: destination,
            alias: payload.secondary,
            label: payload.secondary ?? payload.primary,
            blockID: blockID,
            sourceRange: markupRange.fullRange,
            editorView: self,
            event: event,
            clickKind: customMarkupClickKind(for: event)
        )) {
            switch action {
            case .hostHandled, .openURL:
                return true
            case .placeCaret, .editorDefault:
                // Decline so the editor places the caret for inline editing instead of opening the markup modal.
                // Custom markup has no editor-default navigation, so `.editorDefault` mirrors the non-consuming branch.
                return false
            case .showLinkModal:
                break
            }
        }
        return showCustomMarkupModalIfAvailable(blockID: blockID, range: markupRange, identity: identity)
    }

    /// Opens the provider's generic edit modal for a clicked or hovered custom markup, prefilled with the payload's
    /// secondary value as the Title and primary as the Target. On Save the provider's `makeSource(title, target)` builds
    /// the replacement, written over the span's `fullRange` via the shared granular-replacement + undo path. Returns
    /// false (host-only) when the provider declares no `modalMode`.
    func showCustomMarkupModalIfAvailable(
        blockID: BlockInputBlockID,
        range: BlockInputInlineMarkdownRange,
        identity: BlockInputInlineMarkupIdentity
    ) -> Bool {
        guard let modalMode = modalMode(forMarkupIdentifier: identity.identifier) else {
            return false
        }
        return showCustomMarkupModal(blockID: blockID, range: range, identity: identity, modalMode: modalMode)
    }

    func showCustomMarkupModal(
        blockID: BlockInputBlockID,
        range: BlockInputInlineMarkdownRange,
        identity: BlockInputInlineMarkupIdentity,
        modalMode: BlockInputInlineMarkupModalMode
    ) -> Bool {
        guard isEditable, let block = block(withID: blockID) else {
            return false
        }
        let payload = identity.payload
        let anchorRect = visibleItem(for: blockID, refreshConfiguration: false)?
            .anchorWindowRect(forUTF16Range: range.fullRange) ?? .zero
        dismissImageModal(restoreFocus: false)
        dismissCompletionPopup()
        removeLinkModalDismissalMonitors()
        let modal = linkModalView ?? BlockInputLinkModalView()
        modal.fileBaseURL = fileBaseURL
        let prefilledTitle = payload.secondary?.isEmpty == false ? (payload.secondary ?? payload.primary) : payload.primary
        modal.configure(mode: .edit, text: prefilledTitle, urlString: payload.primary, targetFieldLabel: modalMode.targetFieldLabel)
        configureCustomMarkupModalActions(modal, blockID: blockID, sourceText: block.text, range: range, modalMode: modalMode)
        linkModalView = modal
        linkModalContext = nil
        linkModalRetargetMouseDownWindowLocation = nil
        hostMutationModal(modal, kind: .link, anchoredTo: anchorRect, minimumSize: NSSize(width: 300, height: 148))
        installLinkModalDismissalMonitors()
        modal.focusInitialField()
        return true
    }

    private func configureCustomMarkupModalActions(
        _ modal: BlockInputLinkModalView,
        blockID: BlockInputBlockID,
        sourceText: String,
        range: BlockInputInlineMarkdownRange,
        modalMode: BlockInputInlineMarkupModalMode
    ) {
        modal.onSave = { [weak self] title, target in
            guard let self else { return }
            _ = applyCustomMarkupEdit(
                blockID: blockID,
                sourceText: sourceText,
                range: range,
                modalMode: modalMode,
                title: title,
                target: target
            )
            dismissLinkModal(restoreFocus: false)
        }
        modal.onRemove = { [weak self] in
            self?.dismissLinkModal(restoreFocus: false)
        }
        modal.onOpen = { [weak self, weak modal] target in
            guard let self,
                  let event = NSApp.currentEvent,
                  let url = synthesizedCustomMarkupURL(identifier: modalMode.finderTriggerID, primary: target) else { return }
            let titleField = modal?.textField.stringValue ?? ""
            _ = inlineLinkClickHandler?(BlockInputInlineLinkClickContext(
                kind: .customMarkup(modalMode.finderTriggerID),
                destination: url,
                alias: titleField.isEmpty ? nil : titleField,
                label: target,
                blockID: blockID,
                sourceRange: range.fullRange,
                editorView: self,
                event: event,
                clickKind: .plainClick
            ))
        }
        modal.onCancel = { [weak self] in
            self?.dismissLinkModal(restoreFocus: true)
        }
        modal.onFocusCheck = { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.dismissLinkModalIfFocusMovedOutside()
            }
        }
        modal.onTargetQueryChange = { [weak self] query in
            self?.refreshModalCompletion(query: query, blockID: blockID, triggerID: modalMode.finderTriggerID)
        }
        modal.targetCompletionCommandHandler = { [weak self] selector in
            self?.handleModalCompletionCommand(selector) ?? false
        }
    }

    /// Writes the custom-markup source built by the provider's `makeSource(title, target)`, failing closed when the
    /// backing text drifted since the modal opened or the provider returns `nil`.
    private func applyCustomMarkupEdit(
        blockID: BlockInputBlockID,
        sourceText: String,
        range: BlockInputInlineMarkdownRange,
        modalMode: BlockInputInlineMarkupModalMode,
        title: String,
        target: String
    ) -> Bool {
        guard let replacementText = modalMode.makeSource(title, target),
              let index = index(of: blockID),
              var block = block(at: index),
              block.text == sourceText else {
            return false
        }
        let replacementRange = block.text.blockInputLinkClampedRange(range.fullRange)
        let beforeBlock = block
        let beforeSelection = selection
        let mutableText = NSMutableString(string: block.text)
        mutableText.replaceCharacters(in: replacementRange, with: replacementText)
        block.text = mutableText as String
        let afterSelection = BlockInputSelection.cursor(BlockInputCursor(
            blockID: blockID,
            utf16Offset: replacementRange.location + (replacementText as NSString).length
        ))
        _ = applyGranularBlockReplacement(block, at: index, selection: afterSelection)
        undoController?.registerBlockReplacementStructuralEdit(
            actionName: "Edit Markup",
            beforeBlock: beforeBlock,
            afterBlock: block,
            selectionBefore: beforeSelection,
            selectionAfter: afterSelection
        )
        return true
    }

    /// The registered modal mode for a markup identifier, or `nil` when no provider with that identifier exposes one.
    func modalMode(forMarkupIdentifier identifier: String) -> BlockInputInlineMarkupModalMode? {
        for provider in inlineMarkupProviders where provider.identifier == identifier {
            if let modalMode = provider.modalMode {
                return modalMode
            }
        }
        return nil
    }

    private func synthesizedCustomMarkupURL(identifier: String, primary: String) -> URL? {
        let encoded = primary.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? primary
        return URL(string: "\(identifier):\(encoded)")
    }

    private func customMarkupClickKind(for event: NSEvent) -> BlockInputSlashCommandChipClickKind {
        event.modifierFlags.contains(.command) ? .commandClick : .plainClick
    }
}
