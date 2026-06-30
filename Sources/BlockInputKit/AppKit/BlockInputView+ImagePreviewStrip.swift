import AppKit

extension BlockInputView {
    func setupImagePreviewStrip() -> (height: NSLayoutConstraint, scrollTop: NSLayoutConstraint) {
        imagePreviewStripView.onOpen = { [weak self] occurrence in
            self?.openImagePreviewOccurrence(occurrence)
        }
        imagePreviewStripView.onRemove = { [weak self] occurrence in
            self?.removeImagePreviewOccurrence(occurrence)
        }
        imagePreviewStripView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imagePreviewStripView)

        let heightConstraint = imagePreviewStripView.heightAnchor.constraint(equalToConstant: 0)
        let scrollTopConstraint = scrollView.topAnchor.constraint(equalTo: topAnchor)
        imagePreviewStripHeightConstraint = heightConstraint
        self.scrollViewTopConstraint = scrollTopConstraint
        return (heightConstraint, scrollTopConstraint)
    }

    func refreshImagePreviewStrip() {
        guard imagePresentation == .textLinksWithPreviewStrip else {
            if !imagePreviewStripView.isHidden || imagePreviewStripHeightConstraint?.constant != 0 || !imagePreviewStripView.isEmpty {
                imagePreviewStripView.configureItems([])
                updateImagePreviewStripHeight(0)
                imagePreviewStripView.isHidden = true
            }
            return
        }
        let occurrences = imagePreviewOccurrencesInLoadedBlocks()
        imagePreviewStripView.isHidden = occurrences.isEmpty
        imagePreviewStripView.configureStyle(style.imagePreviewStrip)
        imagePreviewStripView.configureImageLoading(imageLoadingContext)
        imagePreviewStripView.configureItems(occurrences)
        updateImagePreviewStripHeight(occurrences.isEmpty ? 0 : style.imagePreviewStrip.preferredHeight)
    }

    func imagePreviewStripPreferredHeightForLoadedBlocks() -> CGFloat {
        guard imagePresentation == .textLinksWithPreviewStrip,
              !imagePreviewOccurrencesInLoadedBlocks().isEmpty else {
            return 0
        }
        return style.imagePreviewStrip.preferredHeight
    }

    func openImagePreviewOccurrence(_ occurrence: BlockInputImagePreviewOccurrence) {
        guard let resolvedURL = occurrence.image.resolvedURL(relativeTo: imageBaseURL),
              let url = BlockInputLinkURL.supportedURL(from: resolvedURL.absoluteString) else {
            return
        }
        _ = linkURLOpener(url)
    }

    func removeImagePreviewOccurrence(_ occurrence: BlockInputImagePreviewOccurrence) {
        guard isEditable,
              let index = index(of: occurrence.blockID),
              var block = block(at: index),
              block.kind.supportsImageSyntaxSplitting else {
            return
        }
        let text = block.text as NSString
        guard NSMaxRange(occurrence.sourceRange) <= text.length,
              text.substring(with: occurrence.sourceRange) == occurrence.sourceText else {
            return
        }
        let beforeBlock = block
        let beforeSelection = selection
        let removalRange = imagePreviewOccurrenceRemovalRange(occurrence.sourceRange, in: text)
        let replacementText = NSMutableString(string: block.text)
        replacementText.replaceCharacters(in: removalRange, with: "")
        block.text = replacementText as String
        let afterOffset = min(occurrence.sourceRange.location, replacementText.length)
        let afterSelection = BlockInputSelection.cursor(BlockInputCursor(
            blockID: block.id,
            utf16Offset: afterOffset
        ))
        guard applyGranularBlockReplacement(block, at: index, selection: afterSelection) else {
            return
        }
        undoController?.registerBlockReplacementStructuralEdit(
            actionName: "Remove Image",
            beforeBlock: beforeBlock,
            afterBlock: block,
            selectionBefore: beforeSelection,
            selectionAfter: afterSelection
        )
    }

    private func imagePreviewOccurrenceRemovalRange(_ sourceRange: NSRange, in text: NSString) -> NSRange {
        let trailingLocation = NSMaxRange(sourceRange)
        if trailingLocation < text.length,
           text.character(at: trailingLocation) == spaceCharacter {
            return NSRange(location: sourceRange.location, length: sourceRange.length + 1)
        }
        let leadingLocation = sourceRange.location - 1
        if leadingLocation >= 0,
           text.character(at: leadingLocation) == spaceCharacter {
            return NSRange(location: leadingLocation, length: sourceRange.length + 1)
        }
        return sourceRange
    }

    private func updateImagePreviewStripHeight(_ height: CGFloat) {
        imagePreviewStripHeightConstraint?.constant = height
        scrollViewTopConstraint?.constant = height
        imagePreviewStripView.needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private func imagePreviewOccurrencesInLoadedBlocks() -> [BlockInputImagePreviewOccurrence] {
        var occurrences: [BlockInputImagePreviewOccurrence] = []
        for index in 0..<blockCount {
            guard let block = block(at: index),
                  block.kind.supportsImageSyntaxSplitting else {
                continue
            }
            let source = block.text as NSString
            for match in BlockInputImageSyntaxParser.imageMatches(in: block.text) {
                guard NSMaxRange(match.range) <= source.length else {
                    continue
                }
                occurrences.append(BlockInputImagePreviewOccurrence(
                    blockID: block.id,
                    sourceRange: match.range,
                    sourceText: source.substring(with: match.range),
                    image: match.image
                ))
            }
        }
        return occurrences
    }
}

private let spaceCharacter: unichar = 0x20
