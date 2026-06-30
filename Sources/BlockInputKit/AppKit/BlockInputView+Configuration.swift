import Foundation

extension BlockInputView {
    /// Convenience access to `completionPopupConfiguration.placement`.
    var completionPopupPlacement: BlockInputCompletionPopupPlacement {
        get { completionPopupConfiguration.placement }
        set { completionPopupConfiguration.placement = newValue }
    }

    /// Applies configuration and reloads the editor from its document store.
    func applyInsertionPointStyleChange(from oldStyle: BlockInputInsertionPointStyle) {
        guard insertionPointStyle != oldStyle else { return }
        for item in collectionView.visibleItems().compactMap({ $0 as? BlockInputBlockItem }) {
            item.insertionPointStyle = insertionPointStyle
            item.textView.setNeedsDisplay(item.textView.bounds)
        }
    }

    public func configure(_ configuration: BlockInputConfiguration) {
        configure(configuration, restoresFocus: true)
    }

    func configure(_ configuration: BlockInputConfiguration, restoresFocus: Bool) {
        let configuredDocumentStore = configuration.documentStore
        let previousDocumentStore = documentStore
        let previousDocument = document
        let wasEditable = isEditable
        let wasDocumentCacheSynchronized = isDocumentCacheSynchronized
        let documentStoreChanged = previousDocumentStore.map { ($0 as AnyObject) !== (configuredDocumentStore as AnyObject) } ?? false
        if documentStoreChanged {
            detachDocumentStoreObservation()
            cancelAsyncContentTasks()
        }
        documentStore = configuredDocumentStore
        let reusesLargeDocumentCache = previousDocumentStore != nil
            && !documentStoreChanged
            && configuredDocumentStore.loadedBlockCount > largeDocumentCacheMutationLimit
        let configuredDocument = reusesLargeDocumentCache ? previousDocument : configuration.document.detachedStorage()
        document = configuredDocument
        pruneResolvedContentDimensions()
        isDocumentCacheSynchronized = reusesLargeDocumentCache ? wasDocumentCacheSynchronized : true
        configureStyle(configuration)
        configureEditorSurface(configuration)
        dismissMutationUIIfNeeded(wasEditable: wasEditable)
        configureImageLoading(configuration)
        configureUndoController(
            previousDocumentStore: previousDocumentStore,
            previousDocument: previousDocument,
            documentStoreChanged: documentStoreChanged,
            configuration: configuration,
            configuredDocument: configuredDocument
        )
        configureCommandDispatcher(configuration.commandDispatcher)
        keyboardShortcuts = configuration.keyboardShortcuts
        keyDownHandler = configuration.keyDownHandler
        configurePinchZoom(configuration)
        configureCompletion(configuration)
        if documentStoreChanged || previousDocument != configuredDocument {
            dismissCompletionPopup()
            cancelAsyncContentTasks()
        }
        configureHostCallbacks(configuration)
        if documentStoreChanged || configuration.onDocumentChange == nil {
            cancelPendingDocumentSnapshot()
        }
        updateDropIndicatorColor()
        hideDropIndicator()
        invalidateReadOnlyCursorRects()
        clearStaleFocusState()
        reloadConfiguredDocument(restoresFocus: restoresFocus)
        refreshImagePreviewStrip()
        attachDocumentStoreObservationIfNeeded()
        invalidatePreferredHeight()
    }

    private func configureHeightSizing(_ sizing: BlockInputEditorHeightSizing?) {
        heightSizing = sizing
        if sizing == nil {
            lastReportedPreferredHeight = nil
            isPreferredHeightCallbackScheduled = false
            invalidateIntrinsicContentSize()
        }
    }

    /// Configures trackpad canvas pinch zoom. Implemented with a magnification gesture recognizer driving a
    /// layer transform on the document content — NOT `NSScrollView.allowsMagnification`, which scales the
    /// collection view's bounds and makes `NSCollectionViewFlowLayout` assert on invalid item sizes.
    private func configurePinchZoom(_ configuration: BlockInputConfiguration) {
        pinchZoomController.isEnabled = configuration.pinchToZoomEnabled
        pinchZoomController.minimumScale = configuration.pinchZoomMinimum
        pinchZoomController.maximumScale = configuration.pinchZoomMaximum
    }

    private func configureEditorSurface(_ configuration: BlockInputConfiguration) {
        allowsBlockReordering = configuration.allowsBlockReordering
        editorHorizontalInset = configuration.editorHorizontalInset
        editorVerticalInset = configuration.editorVerticalInset
        blockVerticalInsetMultiplier = configuration.blockVerticalInsetMultiplier
        placeholder = configuration.placeholder
        isEditable = configuration.isEditable
        insertionPointStyle = configuration.insertionPointStyle
        disabledCursor = configuration.disabledCursor
        inlineHintProvider = configuration.inlineHintProvider
        rawSlashCommandChips = configuration.rawSlashCommandChips
        linkHoverEditAffordance = configuration.linkHoverEditAffordance
        showsInlineLinkOpenButton = configuration.showsInlineLinkOpenButton
        selectAllBehavior = configuration.selectAllBehavior
        findEnabled = configuration.findEnabled
        headingAnchorsEnabled = configuration.headingAnchorsEnabled
        completionReturnBehavior = configuration.completionReturnBehavior
        dropIndicatorColor = configuration.dropIndicatorColor
        imagePresentation = configuration.imagePresentation
        applyEditorSurfaceStyle()
        configureHeightSizing(configuration.heightSizing)
    }

    private func reloadConfiguredDocument(restoresFocus: Bool) {
        if restoresFocus {
            reloadDataKeepingFocus()
        } else {
            reloadDataWithoutRestoringFocus()
        }
    }

    private func configureCommandDispatcher(_ dispatcher: BlockInputEditorCommandDispatcher?) {
        if commandDispatcher !== dispatcher {
            commandDispatcher?.unbind(from: self)
        }
        commandDispatcher = dispatcher
        dispatcher?.bind(to: self)
    }

    private func configureHostCallbacks(_ configuration: BlockInputConfiguration) {
        onDocumentMutation = configuration.onDocumentMutation
        onDocumentChange = configuration.onDocumentChange
        documentChangeSnapshotDelay = configuration.documentChangeSnapshotDelay
        onSelectionChange = configuration.onSelectionChange
        onFocusChange = configuration.onFocusChange
        fileDropHandler = configuration.fileDropHandler
        pasteContentHandlers = configuration.pasteContentHandlers
        modalOverlayProvider = configuration.modalOverlayProvider
        selectionOverlayProvider = configuration.selectionOverlayProvider
        refreshMutationModalPresentation()
        if selectionOverlayProvider == nil {
            dismissSelectionOverlay()
        } else {
            refreshSelectionOverlayPresentation()
        }
    }

    func configureUndoController(
        previousDocumentStore: (any BlockInputDocumentStore)?,
        previousDocument: BlockInputDocument,
        documentStoreChanged: Bool,
        configuration: BlockInputConfiguration,
        configuredDocument: BlockInputDocument
    ) {
        if let configuredUndoController = configuration.undoController {
            undoController = configuredUndoController
        } else {
            if let previousDocumentStore,
               documentStoreChanged,
               shouldResetFallbackUndoController(
                   previousDocumentStore: previousDocumentStore,
                   previousDocument: previousDocument,
                   configuration: configuration,
                   configuredDocument: configuredDocument
               ) {
                fallbackUndoController = BlockInputUndoController()
            }
            undoController = fallbackUndoController
        }
    }

    private func configureStyle(_ configuration: BlockInputConfiguration) {
        style = configuration.style
        if style.imageBlock.placeholderAspectRatio == nil {
            style.imageBlock.placeholderAspectRatio = configuration.defaultImagePlaceholderAspectRatio
        }
        imagePreviewStripView.configureStyle(style.imagePreviewStrip)
    }

    private func configureImageLoading(_ configuration: BlockInputConfiguration) {
        imageLoader = configuration.imageLoader
        blockContentRenderers = configuration.blockContentRenderers
        renderedContentZoomProvider = configuration.renderedContentZoomProvider
        interactiveBlockContentProvider = configuration.interactiveBlockContentProvider
        blockContentAIBackend = configuration.blockContentAIBackend
        imageDiskCache = configuration.imageDiskCache
        imageBaseURL = configuration.imageBaseURL
        fileBaseURL = configuration.fileBaseURL
        inlineChipAccessoryProvider = configuration.inlineChipAccessoryProvider
        allowsRemoteImageLoading = configuration.allowsRemoteImageLoading
        maximumImageSourceBytes = configuration.maximumImageSourceBytes
        maximumImagePixelDimension = configuration.maximumImagePixelDimension
        defaultImagePlaceholderAspectRatio = configuration.defaultImagePlaceholderAspectRatio
    }

    func shouldResetFallbackUndoController(
        previousDocumentStore: any BlockInputDocumentStore,
        previousDocument: BlockInputDocument,
        configuration: BlockInputConfiguration,
        configuredDocument: BlockInputDocument
    ) -> Bool {
        if configuration.usesDefaultDocumentStore,
           previousDocumentStore is BlockInputMemoryDocumentStore,
           previousDocument == configuredDocument {
            return false
        }
        return true
    }

    func configureCompletion(_ configuration: BlockInputConfiguration) {
        let previousCompletionProvider = completionProvider
        let previousCompletionPopupPlacement = completionPopupPlacement
        let previousSlashCommandAvailability = slashCommandAvailability
        completionProvider = configuration.completionProvider
        slashCommandAvailability = configuration.slashCommandAvailability
        slashCommandChipClickHandler = configuration.slashCommandChipClickHandlerStorage
        inlineLinkClickHandler = configuration.inlineLinkClickHandler
        onSlashCommandAccepted = configuration.onSlashCommandAccepted
        linkHoverActionsProvider = configuration.linkHoverActionsProvider
        inlineMarkupProviders = configuration.inlineMarkupProviders
        completionTokenTriggers = configuration.completionTokenTriggers
        inlineMarkupRewriters = configuration.inlineMarkupRewriters
        completionPopupConfiguration = configuration.completionPopupConfiguration
        if !isEditable ||
            completionProvider == nil ||
            previousCompletionPopupPlacement != completionPopupPlacement ||
            previousSlashCommandAvailability != slashCommandAvailability ||
            !Self.sameCompletionProvider(previousCompletionProvider, completionProvider) {
            dismissCompletionPopup()
        } else {
            refreshCompletionPopupPresentation()
        }
    }

    private static func sameCompletionProvider(
        _ lhs: (any BlockInputCompletionProvider)?,
        _ rhs: (any BlockInputCompletionProvider)?
    ) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return (lhs as AnyObject) === (rhs as AnyObject)
        default:
            return false
        }
    }
}

extension BlockInputView {
    func detachDocumentStoreObservation() {
        pendingProgressivePreloadWorkItem?.cancel()
        pendingProgressivePreloadWorkItem = nil
        progressiveLoadTask?.cancel()
        progressiveLoadTask = nil
        documentStoreObservation?.cancel()
        documentStoreObservation = nil
        progressiveStoreError = nil
    }

    func attachDocumentStoreObservationIfNeeded() {
        guard documentStoreObservation == nil,
              let documentStore else {
            return
        }
        let observedStore = documentStore as AnyObject
        documentStoreObservation = documentStore.observeChanges { [weak self, weak observedStore] change in
            guard let self,
                  let observedStore,
                  self.isCurrentDocumentStore(observedStore) else {
                return
            }
            self.handleDocumentStoreChange(change)
        }
    }
}
