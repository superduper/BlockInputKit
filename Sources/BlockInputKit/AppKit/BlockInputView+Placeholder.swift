import AppKit

extension BlockInputView {
    func configurePlaceholderLabel() {
        placeholderLabel.isHidden = true
        placeholderLabel.isEditable = false
        placeholderLabel.isSelectable = false
        placeholderLabel.isBordered = false
        placeholderLabel.drawsBackground = false
        placeholderLabel.backgroundColor = .clear
        placeholderLabel.textColor = .placeholderTextColor
        placeholderLabel.lineBreakMode = .byWordWrapping
        placeholderLabel.maximumNumberOfLines = 0
        placeholderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        placeholderLabel.setAccessibilityElement(true)
        placeholderLabel.setAccessibilityRole(.staticText)
    }

    func updatePlaceholderVisibility() {
        let placeholderText = placeholder ?? ""
        let shouldShow = !placeholderText.isEmpty && shouldShowPlaceholder
        placeholderLabel.stringValue = shouldShow ? placeholderText : ""
        placeholderLabel.setAccessibilityLabel(shouldShow ? placeholderText : nil)
        placeholderLabel.isHidden = !shouldShow
        updatePlaceholderLayout()
    }

    func updatePlaceholderLayout() {
        guard !placeholderLabel.isHidden else {
            return
        }
        placeholderLabel.font = BlockInputBlockItem.font(for: .paragraph, style: style)
        placeholderLabel.textColor = .placeholderTextColor

        let textLineFrame = placeholderTextLineFrame()
        let textLeading = textLineFrame?.minX ?? placeholderFallbackTextLeadingEdge()
        let labelX = min(
            max(textLeading - BlockInputPlaceholderLabel.caretAlignmentCompensation, 0),
            collectionView.bounds.maxX
        )
        let metrics = BlockInputBlockItem.verticalMetrics(
            for: BlockInputBlock(kind: .paragraph),
            blockVerticalInsetMultiplier: blockVerticalInsetMultiplier
        )
        let maxLabelX = textLineFrame.map { min($0.maxX, collectionView.bounds.maxX) }
            ?? collectionView.bounds.maxX
        let maxWidth = max(maxLabelX - labelX, 0)
        placeholderLabel.preferredMaxLayoutWidth = maxWidth
        let fittingHeight = placeholderLabel.cell?.cellSize(
            forBounds: NSRect(x: 0, y: 0, width: maxWidth, height: CGFloat.greatestFiniteMagnitude)
        ).height ?? placeholderLabel.intrinsicContentSize.height
        let labelHeight = ceil(fittingHeight)
        let topOffset = editorVerticalInset + metrics.topContentInset
        let labelY = collectionView.isFlipped
            ? topOffset
            : max(collectionView.bounds.height - topOffset - labelHeight, 0)
        placeholderLabel.frame = NSRect(
            x: labelX,
            y: labelY,
            width: maxWidth,
            height: labelHeight
        )
    }

    var shouldShowPlaceholder: Bool {
        if let documentStore, !documentStore.isComplete, documentStore.loadedBlockCount == 0 {
            return false
        }
        switch blockCount {
        case 0:
            return true
        case 1:
            guard let block = block(at: 0) else {
                return true
            }
            return block.isPlaceholderEligibleEmptyTextBlock
        default:
            return false
        }
    }

    var isSingleEmptyPlaceholderEligibleDocument: Bool {
        blockCount == 1 && block(at: 0)?.isPlaceholderEligibleEmptyTextBlock == true
    }

    private func placeholderTextLineFrame() -> NSRect? {
        guard blockCount == 1,
              let item = collectionView.item(at: IndexPath(item: 0, section: 0)) as? BlockInputBlockItem,
              let textContainer = item.textView.textContainer else {
            return nil
        }
        item.view.layoutSubtreeIfNeeded()
        item.scrollView.layoutSubtreeIfNeeded()
        let textInset = item.textView.textContainerInset.width + textContainer.lineFragmentPadding
        let trailingX = max(textInset, item.textView.bounds.maxX - textInset)
        return item.textView.convert(
            NSRect(x: textInset, y: 0, width: trailingX - textInset, height: 1),
            to: collectionView
        )
    }

    private func placeholderFallbackTextLeadingEdge() -> CGFloat {
        let block = BlockInputBlock(kind: .paragraph)
        return BlockInputBlockItem.horizontalMetrics(
            for: collectionView.bounds.width,
            block: block,
            allowsReordering: allowsBlockReordering,
            editorHorizontalInset: editorHorizontalInset,
            style: style
        ).glyphLeadingX
    }
}

final class BlockInputPlaceholderLabel: NSTextField {
    static let caretAlignmentCompensation: CGFloat = 3

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

extension BlockInputBlock {
    var isPlaceholderEligibleEmptyTextBlock: Bool {
        guard text.isEmpty else {
            return false
        }
        switch kind {
        case .paragraph, .heading, .quote, .bulletedListItem, .numberedListItem, .checklistItem, .rawMarkdown:
            return true
        case .code, .horizontalRule, .frontMatter, .table, .image:
            return false
        }
    }
}
