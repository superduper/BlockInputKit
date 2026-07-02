import AppKit

extension BlockInputView {
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestPasteURL urlString: String,
        selectedRange: NSRange
    ) -> Bool {
        guard isEditable else {
            return false
        }
        // The mounted text view sees paste first, so mirror its selection into the editor before mutating source.
        if selectedRange.length > 0 {
            applySelection(.text(BlockInputTextRange(blockID: blockID, range: selectedRange)), notify: false)
        } else {
            applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: selectedRange.location)), notify: false)
        }
        return pasteURLString(urlString, blockID: blockID, selectedRange: selectedRange)
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestLinkContextMenuItemsFor event: NSEvent,
        selectedRange: NSRange
    ) -> [NSMenuItem] {
        linkContextMenuItems(blockID: blockID, selectedRange: selectedRange, event: event)
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestInsertFileURLs fileURLs: [URL],
        atUTF16Offset utf16Offset: Int
    ) -> Bool {
        guard isEditable else {
            return false
        }
        if fileDropHandler != nil {
            return handleDroppedFileURLs(fileURLs, placement: .inline(blockID: blockID, utf16Offset: utf16Offset))
        }
        if imagePresentation == .textLinksWithPreviewStrip {
            return insertFileURLsInline(fileURLs, into: blockID, atUTF16Offset: utf16Offset, item: item) != nil
        }
        let imageURLs = fileURLs.filter { Self.imageBlock(for: $0) != nil }
        let otherURLs = fileURLs.filter { Self.imageBlock(for: $0) == nil }
        guard !imageURLs.isEmpty else {
            return insertFileURLsInline(otherURLs, into: blockID, atUTF16Offset: utf16Offset, item: item) != nil
        }
        guard !otherURLs.isEmpty else {
            return insertImageFileURLs(imageURLs, below: blockID) != nil
        }
        return insertMixedImageFileURLsAndFileURLsInline(
            imageURLs: imageURLs,
            fileURLs: otherURLs,
            into: blockID,
            atUTF16Offset: utf16Offset
        ) != nil
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestPasteRichContentAtUTF16Offset utf16Offset: Int,
        onDeclined: @escaping () -> Void
    ) -> Bool {
        guard isEditable else {
            return false
        }
        // The mounted text view sees paste first, so mirror its caret into the editor before any source mutation.
        applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: utf16Offset)), notify: false)
        return handlePasteContent(placement: .inline(blockID: blockID, utf16Offset: utf16Offset), onDeclined: onDeclined)
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didClickLinkAt selectedRange: NSRange,
        clickedLinkRange: BlockInputInlineMarkdownRange?,
        event: NSEvent
    ) -> Bool {
        handleLinkClick(blockID: blockID, selectedRange: selectedRange, clickedLinkRange: clickedLinkRange, event: event)
    }

    func blockItemLinkHoverEditAffordanceEnabled(_ item: BlockInputBlockItem) -> Bool {
        linkHoverEditAffordance && isEditable
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didHoverLink sourceLinkRange: BlockInputInlineMarkdownRange,
        windowRects: [NSRect]
    ) {
        showLinkHoverEditAffordance(blockID: blockID, sourceLinkRange: sourceLinkRange, windowRects: windowRects)
    }

    func blockItemDidRequestDismissLinkHoverAffordance(_ item: BlockInputBlockItem) {
        scheduleLinkHoverDismissal()
    }

    func blockItem(_ item: BlockInputBlockItem, blockID: BlockInputBlockID, didResizeImageToWidth width: Int, height: Int) {
        guard isEditable else {
            return
        }
        updateImageDimensions(
            blockID: blockID,
            width: width,
            height: height,
            actionName: "Resize Image",
            forcesHTMLExport: true
        )
    }

    func blockItem(_ item: BlockInputBlockItem, blockID: BlockInputBlockID, didResolveImageDimensions dimensions: BlockInputImageDimensions) {
        guard isEditable else {
            return
        }
        updateImageDimensions(
            blockID: blockID,
            width: dimensions.width,
            height: dimensions.height,
            actionName: "Resolve Image Dimensions",
            forcesHTMLExport: false
        )
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didResolveRenderedContentDimensions dimensions: BlockInputImageDimensions
    ) {
        // Rendered content dimensions are visual-only: they never mutate the document or register undo, and they
        // must update even in read-only editors. Cache them and re-measure the row in place.
        guard resolvedContentDimensionsByBlockID[blockID] != dimensions,
              let index = index(of: blockID) else {
            return
        }
        resolvedContentDimensionsByBlockID[blockID] = dimensions
        let item = collectionView.visibleItems()
            .compactMap { $0 as? BlockInputBlockItem }
            .first { $0.representedBlockID == blockID }
        invalidateLayoutForBlock(at: index, editedItem: item, block: item?.renderedBlock)
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestExpandRenderedContent expansion: BlockInputRenderedContentExpansion
    ) {
        presentRenderedContentZoomModal(expansion: expansion)
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestEditBlockContent contentIdentifier: String
    ) {
        guard let block = block(withID: blockID) else {
            return
        }
        guard interactiveBlockContentProvider != nil else { return }
        presentInteractiveBlockContent(blockID: blockID, contentIdentifier: contentIdentifier, source: block.text)
    }

    var blockItemAutoPresentsEmptyBlock: Bool { autoPresentsEmptyRenderableContent }

    func blockItem(_ item: BlockInputBlockItem, blockID: BlockInputBlockID,
                   didRequestCreateEmptyBlockContent contentIdentifier: String) {
        guard interactiveBlockContentProvider != nil else { return }
        presentInteractiveBlockContent(blockID: blockID, contentIdentifier: contentIdentifier,
                                       source: "", isEmptyCreation: true)
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestFixBlockContent contentIdentifier: String
    ) {
        guard let block = block(withID: blockID) else {
            return
        }
        guard interactiveBlockContentProvider != nil else { return }
        presentInteractiveBlockContent(blockID: blockID, contentIdentifier: contentIdentifier,
                                  source: block.text, autoFixOnOpen: true)
    }

    func blockItemDidFailToRenderContent(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) {
        // Size the failure surface to a COMPACT box (error banner + a few source lines + buttons) rather than
        // the tall 16:9 placeholder. Encode a wide, short aspect so it scales to ~a third of the placeholder
        // height at any column width, instead of dropping dimensions (which would fall back to 16:9).
        resolvedContentDimensionsByBlockID[blockID] = BlockInputImageDimensions(width: 1_000, height: 280)
        guard let index = index(of: blockID) else {
            return
        }
        let visibleItem = collectionView.visibleItems()
            .compactMap { $0 as? BlockInputBlockItem }
            .first { $0.representedBlockID == blockID }
        invalidateLayoutForBlock(at: index, editedItem: visibleItem, block: visibleItem?.renderedBlock)
    }

    private func updateImageDimensions(
        blockID: BlockInputBlockID,
        width: Int,
        height: Int,
        actionName: String,
        forcesHTMLExport: Bool
    ) {
        guard isEditable else {
            return
        }
        guard let index = index(of: blockID),
              var block = block(at: index),
              case var .image(image) = block.kind else {
            return
        }
        guard image.width != width || image.height != height else {
            return
        }
        let beforeBlock = block
        let beforeSelection = selection
        image.width = width
        image.height = height
        if forcesHTMLExport {
            image.sourceStyle = .html
        }
        block.kind = .image(image)
        let afterSelection = forcesHTMLExport ? BlockInputSelection.blocks([blockID]) : beforeSelection
        _ = applyGranularBlockReplacement(block, at: index, selection: afterSelection)
        undoController?.registerBlockReplacementStructuralEdit(
            actionName: actionName,
            beforeBlock: beforeBlock,
            afterBlock: block,
            selectionBefore: beforeSelection,
            selectionAfter: afterSelection
        )
    }
}
