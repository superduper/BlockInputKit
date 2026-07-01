import AppKit

extension BlockInputView {
    func setupCollectionView() {
        wantsLayer = true
        applyEditorSurfaceStyle()

        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        editorVerticalInset = BlockInputConfiguration.defaultEditorVerticalInset

        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.blockInputView = self
        collectionView.isSelectable = false
        collectionView.register(
            BlockInputBlockItem.self,
            forItemWithIdentifier: BlockInputBlockItem.reuseIdentifier
        )
        collectionView.register(
            BlockInputLoadingItem.self,
            forItemWithIdentifier: BlockInputLoadingItem.reuseIdentifier
        )
        collectionView.registerForDraggedTypes([.blockInputBlockID, .fileURL])
        collectionView.setDraggingSourceOperationMask(.move, forLocal: true)
        installSelectionExpansionKeyMonitor()

        setupDropIndicator()
        setupScrollView()
        addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        let imagePreviewConstraints = setupImagePreviewStrip()
        NSLayoutConstraint.activate([
            imagePreviewStripView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imagePreviewStripView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imagePreviewStripView.topAnchor.constraint(equalTo: topAnchor),
            imagePreviewConstraints.height,
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imagePreviewConstraints.scrollTop,
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        setupEditorChromeView()
        pinchZoomController.attach(to: self, contentView: collectionView)
    }

    private func setupDropIndicator() {
        dropIndicatorView.wantsLayer = true
        dropIndicatorView.layer?.cornerRadius = 1
        dropIndicatorView.layer?.zPosition = 10
        updateDropIndicatorColor()
        dropIndicatorView.isHidden = true
        dropIndicatorView.setAccessibilityElement(false)
        collectionView.addSubview(dropIndicatorView, positioned: .above, relativeTo: nil)
        configurePlaceholderLabel()
        collectionView.addSubview(placeholderLabel, positioned: .above, relativeTo: nil)
    }

    private func setupScrollView() {
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.blockInputView = self
        scrollView.documentView = collectionView
        scrollView.onContentBoundsDidChange = { [weak self] in
            self?.handleDocumentScrollContentBoundsChange()
        }
    }

    private func handleDocumentScrollContentBoundsChange() {
        updateCollectionViewWidthForVisibleBounds()
        scheduleProgressivePreloadCheck()
        dismissCompletionPopup()
        // Overlays are full-bleed children of editorChromeView that do not scroll with content, so
        // recompute their geometry from visible items as the document scrolls. No-op unless find is active.
        if isFindScrimInstalled {
            updateFindScrim()
        }
        if isFindActiveMatchOverlayInstalled {
            updateFindActiveMatchOverlay(animated: false)
        }
        hideLinkHoverEditAffordance()
        repositionSelectionOverlayOnScrollOrResize()
        repositionAnchoredAccessories()
    }

    private func setupEditorChromeView() {
        editorChromeView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(editorChromeView, positioned: .above, relativeTo: scrollView)
        NSLayoutConstraint.activate([
            editorChromeView.leadingAnchor.constraint(equalTo: leadingAnchor),
            editorChromeView.trailingAnchor.constraint(equalTo: trailingAnchor),
            editorChromeView.topAnchor.constraint(equalTo: topAnchor),
            editorChromeView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}
