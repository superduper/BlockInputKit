import AppKit

extension BlockInputView {
    /// Presents a plugin-supplied interactive diagram view (Phase-1 seam) inside the reusable scaffold. When no
    /// provider is set or it returns nil, shows the bare failure surface. Commits the plugin's edited source to
    /// the document on close.
    func presentInteractiveBlockContent(
        blockID: BlockInputBlockID,
        contentIdentifier: String,
        source: String,
        autoFixOnOpen: Bool = false
    ) {
        if interactiveBlockContentScaffold != nil {
            dismissInteractiveBlockContent()
        }
        let scaffold = BlockInputContentSurfaceScaffold()
        let context = BlockInputInteractiveBlockContent.Context(
            contentIdentifier: contentIdentifier,
            source: source,
            validate: { [weak self] candidate in
                await self?.validateBlockContentSource(candidate, contentIdentifier: contentIdentifier)
                    ?? .invalid(message: "Editor unavailable")
            },
            aiBackend: blockContentAIBackend,
            autoFix: autoFixOnOpen
        )
        if let view = interactiveBlockContentProvider?(context) {
            interactiveBlockContentView = view
            view.onCommitSource = { [weak self] newSource in
                self?.interactiveBlockContentPendingSource = newSource
            }
            scaffold.setContentView(view.nsView)
        } else {
            interactiveBlockContentShowingFailure = true
            let failure = BlockInputContentFailureSurfaceView()
            failure.configure(message: "This diagram could not be opened.")
            scaffold.setContentView(failure)
        }
        scaffold.onDismiss = { [weak self] in self?.dismissInteractiveBlockContent() }
        scaffold.onFullscreen = { [weak self] in
            guard let self else { return }
            if self.diagramFullscreenWindow.isPresented {
                self.diagramFullscreenWindow.dismiss()
            } else {
                self.diagramFullscreenWindow.present(scaffold, restoringTo: self)
            }
            scaffold.setFullscreenActive(self.diagramFullscreenWindow.isPresented)
        }
        scaffold.translatesAutoresizingMaskIntoConstraints = true
        scaffold.frame = bounds
        scaffold.autoresizingMask = [.width, .height]
        addSubview(scaffold, positioned: .above, relativeTo: nil)
        interactiveBlockContentScaffold = scaffold
        interactiveBlockContentBlockID = blockID
        // The scaffold is now live (isBlockContentSurfacePresented is true); kill any open hover popover so it
        // doesn't bleed through the surface.
        hideLinkHoverEditAffordance()
        pinchZoomController.isSuspended = true
        scaffold.startEscapeMonitor()
    }

    func dismissInteractiveBlockContent() {
        exitFullscreenIfNeeded()
        interactiveBlockContentScaffold?.stopEscapeMonitor()
        commitInteractiveBlockContentSource()
        interactiveBlockContentView?.tearDown()
        interactiveBlockContentScaffold?.removeFromSuperview()
        interactiveBlockContentScaffold = nil
        interactiveBlockContentView = nil
        interactiveBlockContentBlockID = nil
        interactiveBlockContentPendingSource = nil
        interactiveBlockContentShowingFailure = false
        pinchZoomController.isSuspended = false
        window?.makeFirstResponder(self)
    }

    /// Returns the active diagram surface from the borderless fullscreen window to its in-document parent, so
    /// closing a surface never leaves an orphaned screen-covering window. Shared by both diagram surfaces; the
    /// app window is never put into macOS native fullscreen.
    func exitFullscreenIfNeeded() {
        if diagramFullscreenWindow.isPresented {
            diagramFullscreenWindow.dismiss()
        }
    }

    private func commitInteractiveBlockContentSource() {
        guard let blockID = interactiveBlockContentBlockID,
              let index = index(of: blockID),
              var block = block(at: index) else {
            return
        }
        let newText = interactiveBlockContentPendingSource ?? interactiveBlockContentView?.currentSource
        guard let newText, block.text != newText else {
            return
        }
        block.text = newText
        _ = applyGranularBlockReplacement(block, at: index, selection: selection)
    }

    /// Runs candidate source through the registered renderer; the interactive plugin's `validate` oracle uses this.
    nonisolated func validateBlockContentSource(
        _ source: String,
        contentIdentifier: String
    ) async -> BlockInputInteractiveBlockContent.Validation {
        let renderer = await MainActor.run { blockContentRenderers.renderer(for: contentIdentifier) }
        guard let renderer else {
            return .invalid(message: "No renderer registered for \(contentIdentifier)")
        }
        let request = BlockInputBlockContentRequest(
            contentIdentifier: contentIdentifier,
            source: source,
            targetWidth: 600,
            pixelScale: await MainActor.run { window?.backingScaleFactor ?? 2 },
            // Key on the source so each distinct edit re-renders instead of returning a stale cached image.
            cacheKey: "\(contentIdentifier)|preview|\(source.hashValue)"
        )
        do {
            let content = try await renderer.render(request)
            guard case let .image(image) = content else {
                return .invalid(message: "Renderer did not produce an image")
            }
            return .valid(image)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            return .invalid(message: message)
        }
    }

    // MARK: - Test accessors

    var blockContentScaffoldForTesting: NSView? { interactiveBlockContentScaffold }
    var blockContentFailureForTesting: Bool { interactiveBlockContentShowingFailure }
}
