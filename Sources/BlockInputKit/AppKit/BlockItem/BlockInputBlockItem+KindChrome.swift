import AppKit

extension BlockInputBlockItem {
    func configureBlockKindChrome(block: BlockInputBlock) {
        let kind = block.kind
        let isHorizontalRule = kind == .horizontalRule
        let isFrontMatter = kind == .frontMatter
        let usesTableSurface = kind == .table && BlockInputTable(markdown: block.text) != nil
        let usesImageSurface: Bool
        if case .image = kind {
            usesImageSurface = true
        } else {
            usesImageSurface = false
        }
        let usesRenderedContentSurface = Self.rendersInlineContent(block, contentRenderers: blockContentRenderingContext.renderers)
        isRenderedContentBlock = usesRenderedContentSurface
        let contentIndent = Self.contentIndent(for: block)
        let verticalMetrics = Self.verticalMetrics(for: block, blockVerticalInsetMultiplier: blockVerticalInsetMultiplier)
        textView.textContainerInset = textContainerInset(for: kind, metrics: verticalMetrics)
        textView.isEditable = isEditable && !isHorizontalRule && !usesTableSurface && !usesRenderedContentSurface
        textView.isSelectable = !isHorizontalRule && !usesTableSurface && !usesRenderedContentSurface
        configureTextScrolling(for: block)
        applyTextAttributes(for: block)
        scrollView.isHidden = isHorizontalRule || usesTableSurface || usesImageSurface || usesRenderedContentSurface
        if usesTableSurface {
            tableView.configure(
                block: block,
                style: style,
                blockVerticalInsetMultiplier: blockVerticalInsetMultiplier
            )
        } else {
            tableView.resetForReuse()
        }
        configureVisualSurfaces(for: block, usesImageSurface: usesImageSurface, usesRenderedContentSurface: usesRenderedContentSurface)
        scrollViewTopConstraint?.constant = 0
        applyScaledSurfaceInsets()
        configureFrontMatterDivider(isVisible: isFrontMatter)
        handleTopConstraint?.constant = Self.dragHandleTopConstant(for: block.kind, metrics: verticalMetrics, style: style)
        kindLabelTopConstraint?.constant = 0
        checklistButtonTopConstraint?.constant = verticalMetrics.checklistButtonTopConstant(
            font: Self.font(for: block.kind, style: style),
            checkboxHeight: Self.checklistButtonHeight
        )
        horizontalRuleLeadingConstraint?.constant = Self.horizontalRuleInnerInset
        quoteBarView.isHidden = kind != .quote || isHorizontalRule
        quoteBarView.alphaValue = quoteBarView.isHidden ? 0 : 1
        horizontalRuleView.setVisible(isHorizontalRule)
        applyKindLabelAttributes(for: block)
        updateHorizontalConstraints(for: block)
        updateQuoteBarVerticalExtent()
        configureChecklistButton(for: block, contentIndent: contentIndent)
        updateImageBlockLayout(for: block)
        updateRenderedContentLayout(for: block)
    }

    private func configureVisualSurfaces(
        for block: BlockInputBlock,
        usesImageSurface: Bool,
        usesRenderedContentSurface: Bool
    ) {
        configureImageSurfaceVisibility(usesImageSurface)
        configureImageBlockIfNeeded(for: block)
        configureRenderedContentSurfaceVisibility(usesRenderedContentSurface)
        configureRenderedContentIfNeeded(for: block)
        configureCodeBackground(for: block, suppressed: usesRenderedContentSurface)
    }

    private func configureRenderedContentSurfaceVisibility(_ usesRenderedContentSurface: Bool) {
        renderedContentView.isHidden = !usesRenderedContentSurface
    }

    private func applyScaledSurfaceInsets() {
        tableViewTopConstraint?.constant = Self.scaledTableExternalVerticalInset(for: blockVerticalInsetMultiplier)
        tableViewBottomConstraint?.constant = -Self.scaledTableExternalVerticalInset(for: blockVerticalInsetMultiplier)
        imageBlockTopConstraint?.constant = Self.scaledImageExternalVerticalInset(for: blockVerticalInsetMultiplier)
        imageBlockBottomConstraint?.constant = -Self.scaledImageExternalVerticalInset(for: blockVerticalInsetMultiplier)
    }

    func updateRenderedContentLayout(for block: BlockInputBlock) {
        guard isRenderedContentBlock else {
            return
        }
        let itemWidth = view.bounds.width > 0 ? view.bounds.width : 0
        let textWidth = Self.measuredTextWidth(
            for: itemWidth,
            block: block,
            allowsReordering: allowsReordering,
            editorHorizontalInset: editorHorizontalInset,
            style: style
        )
        let displaySize = Self.renderedContentDisplaySize(
            resolvedDimensions: blockContentRenderingContext.resolvedDimensions(for: block.id),
            textWidth: textWidth,
            defaultAspectRatio: style.imageBlock.placeholderAspectRatio ?? 16.0 / 9.0
        )
        renderedContentWidthConstraint?.constant = displaySize.width
    }

    private func configureImageSurfaceVisibility(_ usesImageSurface: Bool) {
        imageBlockView.isHidden = !usesImageSurface
        if !usesImageSurface {
            setImageCaretOffset(nil)
        }
    }

    private func configureFrontMatterDivider(isVisible: Bool) {
        scrollViewBottomConstraint?.constant = isVisible
            ? -((Self.scaledFrontMatterDividerVerticalInset(for: blockVerticalInsetMultiplier) * 2) + Self.frontMatterDividerHeight)
            : 0
        frontMatterDividerBottomConstraint?.constant = -Self.scaledFrontMatterDividerVerticalInset(for: blockVerticalInsetMultiplier)
        frontMatterDividerView.isHidden = !isVisible
        frontMatterDividerView.alphaValue = isVisible
            ? BlockInputReadOnlyStyle.alpha(isEditable: isEditable, readOnly: BlockInputReadOnlyStyle.chromeAlpha)
            : 0
    }

    private func configureChecklistButton(for block: BlockInputBlock, contentIndent: CGFloat) {
        switch block.kind {
        case let .checklistItem(isChecked):
            checklistButton.isHidden = false
            checklistButton.isEnabled = isEditable
            checklistButton.state = isChecked ? .on : .off
            checklistButtonLeadingConstraint?.constant = Self.checklistButtonLeadingConstant(
                indentationLevel: block.indentationLevel(forLine: 0),
                rowContentIndent: contentIndent
            )
        default:
            checklistButton.isHidden = true
            checklistButton.isEnabled = false
            checklistButton.state = .off
            checklistButtonLeadingConstraint?.constant = Self.checklistButtonBaseLeading
        }
    }

    func textContainerInset(
        for kind: BlockInputBlockKind,
        metrics: BlockInputBlockItemVerticalMetrics
    ) -> NSSize {
        guard case .code = kind else {
            return metrics.textContainerInset
        }
        return NSSize(
            width: metrics.textContainerInset.width + Self.codeTextHorizontalPadding,
            height: metrics.textContainerInset.height
        )
    }

    static func checklistButtonLeadingConstant(
        indentationLevel: Int,
        rowContentIndent: CGFloat
    ) -> CGFloat {
        checklistButtonBaseLeading + contentIndent(forIndentationLevel: indentationLevel) - rowContentIndent
    }

    static func markerGutterWidth(for block: BlockInputBlock, style: BlockInputStyle = .default) -> CGFloat {
        guard block.kind.needsVisibleMarkerLane else {
            return 0
        }
        guard block.kind.supportsIndentation else {
            return markerGutterWidth
        }
        let markerLines = markerLines(for: block)
        let markerTexts = markerLines.isEmpty ? [prefix(for: block.kind, indentationLevel: block.indentationLevel)] : markerLines.map(\.text)
        let widestMarker = markerTexts.reduce(CGFloat.zero) { widest, marker in
            guard !marker.isEmpty else {
                return widest
            }
            let width = (marker as NSString).size(withAttributes: [.font: font(for: block.kind, style: style)]).width
            return max(widest, width)
        }
        return max(markerGutterWidth, widestMarker + minimumMarkerTextGap)
    }

    func draggingPreviewImage() -> NSImage {
        let image = NSImage(size: view.bounds.size)
        guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return image
        }
        view.cacheDisplay(in: view.bounds, to: representation)
        image.addRepresentation(representation)
        return image
    }
}

private extension BlockInputBlockKind {
    var needsVisibleMarkerLane: Bool {
        switch self {
        case .quote, .bulletedListItem, .numberedListItem, .checklistItem:
            return true
        case .paragraph, .heading, .code, .horizontalRule, .frontMatter, .table, .image, .rawMarkdown:
            return false
        }
    }
}
