import AppKit

extension BlockInputView {
    func cancelPasteContentTasks() {
        for task in pasteContentTasks.values {
            task.cancel()
        }
        pasteContentTasks.removeAll()
    }

    /// Cancels both pending file-drop and paste resolution tasks; used where a document/store change invalidates them.
    func cancelAsyncContentTasks() {
        cancelFileDropTasks()
        cancelPasteContentTasks()
    }

    /// Offers the current pasteboard to registered paste handlers before native paste runs.
    ///
    /// Returns `true` when at least one handler claims a present type (suppressing native insertion); resolution is
    /// async, so the matching handlers are tried in order on the main actor and the first non-empty result is inserted.
    /// When every matching handler declines, `onDeclined` runs so the caller falls through to native AppKit paste.
    /// Returns `false` when no handler matches a present type, so the caller runs native paste synchronously.
    func handlePasteContent(placement: BlockInputFileDropPlacement, onDeclined: @escaping () -> Void) -> Bool {
        guard isEditable, !pasteContentHandlers.isEmpty else {
            return false
        }
        let pasteboard = NSPasteboard.general
        let presentTypes = Set(pasteboard.types ?? [])
        guard !presentTypes.isEmpty else {
            return false
        }
        // Validate the edit target up front so a stale or unsupported placement never starts async work.
        guard let acceptedDrop = acceptedDrop(placement: placement) else {
            return false
        }
        let matches: [(handler: any BlockInputPasteContentHandler, type: NSPasteboard.PasteboardType)] =
            pasteContentHandlers.compactMap { handler in
                handler.handledTypes.first(where: presentTypes.contains).map { (handler, $0) }
            }
        guard !matches.isEmpty else {
            return false
        }
        schedulePasteContent(matches: matches, acceptedDrop: acceptedDrop, onDeclined: onDeclined)
        return true
    }

    private func schedulePasteContent(
        matches: [(handler: any BlockInputPasteContentHandler, type: NSPasteboard.PasteboardType)],
        acceptedDrop: BlockInputAcceptedFileDrop,
        onDeclined: @escaping () -> Void
    ) {
        let id = UUID()
        let pasteboard = NSPasteboard.general
        let placement = acceptedDrop.context.placement
        let document = acceptedDrop.context.document
        pasteContentTasks[id] = Task { [weak self] in
            var resolved: [BlockInputFileDropReference]?
            for match in matches {
                let references = await match.handler.references(
                    from: pasteboard,
                    type: match.type,
                    placement: placement,
                    document: document
                )
                if let references, !references.isEmpty {
                    resolved = references
                    break
                }
            }
            guard !Task.isCancelled else {
                return
            }
            guard let self else {
                return
            }
            pasteContentTasks[id] = nil
            guard let resolved else {
                // Every matching handler declined: fall through to native paste instead of swallowing the paste.
                onDeclined()
                return
            }
            _ = applyFileDropReferences(resolved, acceptedDrop: acceptedDrop)
        }
    }
}
