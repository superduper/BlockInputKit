import AppKit

extension BlockInputView {
    func configureBlockItem(_ item: BlockInputBlockItem, block: BlockInputBlock, blockIndex: Int? = nil) {
        let resolvedBlockIndex = blockIndex ?? index(of: block.id)
        item.configure(
            block: block,
            allowsReordering: allowsBlockReordering,
            editorHorizontalInset: editorHorizontalInset,
            hidesListMarkers: hidesListMarkers,
            accentColor: dropIndicatorColor,
            style: style,
            blockVerticalInsetMultiplier: blockVerticalInsetMultiplier,
            imageLoadingContext: imageLoadingContext,
            blockContentRenderingContext: blockContentRenderingContext,
            fileBaseURL: fileBaseURL,
            allowsAnchorLinks: headingAnchorsEnabled || (inlineLinkClickHandler != nil),
            isEditable: isEditable,
            insertionPointStyle: insertionPointStyle,
            disabledCursor: disabledCursor,
            inlineHint: inlineHint(for: item, block: block, blockIndex: resolvedBlockIndex),
            rawSlashCommandChips: rawSlashCommandChips,
            selectAllBehavior: selectAllBehavior,
            slashCommandAvailability: slashCommandAvailability,
            isDocumentStartBlock: resolvedBlockIndex == 0,
            showsInlineLinkOpenIcon: showsInlineLinkOpenButton,
            inlineMarkupProviders: inlineMarkupProviders,
            inlineChipAccessoryProvider: inlineChipAccessoryProvider,
            isSelected: isBlockSelected(block.id),
            delegate: self
        )
        if findController.hasMatches {
            applyFindHighlight(to: item)
            updateFindScrim()
        }
        if let highlights = transientHighlightsByBlock[block.id], !highlights.isEmpty {
            item.applyTransientHighlights(highlights)
        }
        requestInlineMarkupRewritesIfNeeded(for: block)
    }

    var imageLoadingContext: BlockInputImageBlockLoadingContext {
        BlockInputImageBlockLoadingContext(
            loader: imageLoader,
            diskCache: imageDiskCache,
            baseURL: imageBaseURL,
            allowsRemoteLoading: allowsRemoteImageLoading,
            maximumSourceBytes: maximumImageSourceBytes,
            maximumPixelDimension: maximumImagePixelDimension
        )
    }

    var blockContentRenderingContext: BlockInputContentRenderingContext {
        BlockInputContentRenderingContext(
            renderers: blockContentRenderers,
            pixelScale: renderedContentPixelScale,
            baseURL: imageBaseURL ?? fileBaseURL,
            isBlockContentEditingAvailable: interactiveBlockContentProvider != nil,
            resolvedDimensionsLookup: { [weak self] blockID in
                self?.resolvedContentDimensions(for: blockID)
            }
        )
    }

    /// Pixel scale used to rasterize rendered content (e.g. Mermaid PNGs). It oversamples beyond the
    /// backing scale so the inline image stays crisp through canvas pinch zoom; deep zoom uses the live
    /// WebView in the expand modal rather than an even larger inline image.
    private var renderedContentPixelScale: CGFloat {
        let backingScale = window?.backingScaleFactor ?? 2
        let pinchCeiling = max(1, min(pinchZoomController.maximumScale, 2))
        return backingScale * pinchCeiling
    }
}
