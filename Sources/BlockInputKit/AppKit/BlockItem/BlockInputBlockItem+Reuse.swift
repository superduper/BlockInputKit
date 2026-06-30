import AppKit

extension BlockInputBlockItem {
    func clearBlockReferencesForReuse() {
        blockID = nil
        renderedBlock = nil
        delegate = nil
        selectionBeforeTextChange = nil
        isHorizontalRule = false
        isImageBlock = false
        isRenderedContentBlock = false
        renderedContentView.blockItem = nil
        setBlockSelection(false)
        handleView.blockItem = nil
        scrollView.blockItem = nil
        horizontalRuleView.blockItem = nil
        horizontalRuleView.resetForReuse()
        tableView.blockItem = nil
        tableView.delegate = nil
        renderedCodeColorScheme = nil
        rawSlashCommandChips = false
        selectAllBehavior = .focusedContentThenDocument
        slashCommandAvailability = .documentStart
        isDocumentStartBlock = false
        showsInlineLinkOpenIcon = true
        inlineMarkupProviders = []
        textView.cancelBlockSelectionDrag()
        textView.clearInlineHint()
        textView.blockItem = nil
        finishBlockSelectionDrag()
        setImageCaretOffset(nil)
    }

    func resetTextForReuse() {
        textView.string = ""
        textView.isEditable = true
        textView.textContainerInset = Self.standardTextContainerInset
        configureWrappingTextScrolling()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.font = Self.font(for: .paragraph)
        textView.hideFileDropCaret()
        style = .default
        fileBaseURL = nil
        isEditable = true
        disabledCursor = nil
        imageLoadTask?.cancel()
        imageLoadTask = nil
        imageLoadCacheKey = nil
        cancelRenderedContent()
        blockContentRenderingContext = BlockInputContentRenderingContext()
    }

    func resetLayoutForReuse() {
        allowsReordering = true
        editorHorizontalInset = BlockInputConfiguration.defaultEditorHorizontalInset
        blockVerticalInsetMultiplier = 1
        scrollView.isHidden = false
        tableView.resetForReuse()
        imageBlockView.resetForReuse()
        renderedContentView.resetForReuse()
        renderedContentWidthConstraint?.constant = 120
        codeBackgroundView.isHidden = true
        codeBackgroundView.alphaValue = 0
        scrollViewLeadingConstraint?.constant = Self.defaultTextLeading
        scrollViewWidthConstraint?.priority = .defaultLow
        scrollViewWidthConstraint?.constant = 120
        scrollViewTrailingConstraint?.constant = -Self.horizontalContentTrailingInset(allowsReordering: true)
        scrollViewTopConstraint?.constant = 0
        scrollViewBottomConstraint?.constant = 0
        handleTopConstraint?.constant = Self.dragHandleTopConstant(for: .paragraph, metrics: .standard)
        kindLabelTopConstraint?.constant = 0
        checklistButtonTopConstraint?.constant = BlockInputBlockItemVerticalMetrics.standard.checklistButtonTopConstant(
            font: Self.font(for: .paragraph),
            checkboxHeight: Self.checklistButtonHeight
        )
        quoteBarLeadingConstraint?.constant = Self.chromeFrameAlignmentOffset
        quoteBarTopConstraint?.constant = Self.quoteBarVerticalInset
        quoteBarBottomConstraint?.constant = -Self.quoteBarVerticalInset
        horizontalRuleLeadingConstraint?.constant = Self.horizontalRuleInnerInset
        horizontalRuleTrailingConstraint?.constant = -Self.horizontalRuleTrailingInset(allowsReordering: true)
        frontMatterDividerLeadingConstraint?.constant = Self.horizontalRuleInnerInset
        frontMatterDividerTrailingConstraint?.constant = -Self.horizontalRuleTrailingInset(allowsReordering: true)
        frontMatterDividerBottomConstraint?.constant = -Self.frontMatterDividerVerticalInset
        imageBlockLeadingConstraint?.constant = Self.imageSurfaceHorizontalInset
        imageBlockTrailingConstraint?.constant = -Self.imageSurfaceHorizontalInset
        imageBlockTopConstraint?.constant = Self.imageExternalVerticalInset
        imageBlockBottomConstraint?.constant = -Self.imageExternalVerticalInset
        tableViewTopConstraint?.constant = Self.tableExternalVerticalInset
        tableViewBottomConstraint?.constant = -Self.tableExternalVerticalInset
        imageBlockWidthConstraint?.constant = 120
        imageBlockView.maximumResizeWidth = Int.max
        setImageCaretOffset(nil)
    }

    func resetChromeForReuse() {
        clearFindMatchHighlights()
        quoteBarView.isHidden = true
        quoteBarView.alphaValue = 0
        kindLabel.setMarkerLines([])
        kindLabelLeadingConstraint?.constant = 0
        kindLabelWidthConstraint?.constant = 0
        checklistButton.state = .off
        checklistButton.isHidden = true
        checklistButton.isEnabled = false
        checklistButtonLeadingConstraint?.constant = Self.checklistButtonBaseLeading
        frontMatterDividerView.isHidden = true
        frontMatterDividerView.alphaValue = 0
        handleView.isEnabled = false
        handleView.isHidden = true
        handleView.alphaValue = 0
        handleView.toolTip = nil
        handleLeadingConstraint?.constant = 0
        handleWidthConstraint?.constant = 0
    }
}
