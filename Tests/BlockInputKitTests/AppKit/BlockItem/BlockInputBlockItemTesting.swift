import AppKit
@testable import BlockInputKit

extension BlockInputBlockItem {
    static func configuredForTesting(
        block: BlockInputBlock,
        allowsReordering: Bool,
        editorHorizontalInset: CGFloat = BlockInputConfiguration.defaultEditorHorizontalInset,
        style: BlockInputStyle = .default,
        blockVerticalInsetMultiplier: CGFloat = 1,
        inlineHint: BlockInputInlineHint? = nil,
        rawSlashCommandChips: Bool = false,
        selectAllBehavior: BlockInputSelectAllBehavior = .focusedContentThenDocument,
        slashCommandAvailability: BlockInputSlashCommandAvailability = .documentStart,
        isDocumentStartBlock: Bool = false,
        isSelected: Bool = false,
        delegate: BlockInputBlockItemDelegate
    ) -> BlockInputBlockItem {
        let item = BlockInputBlockItem()
        item.loadView()
        item.viewDidLoad()
        item.configure(
            block: block,
            allowsReordering: allowsReordering,
            editorHorizontalInset: editorHorizontalInset,
            accentColor: .controlAccentColor,
            style: style,
            blockVerticalInsetMultiplier: blockVerticalInsetMultiplier,
            inlineHint: inlineHint,
            rawSlashCommandChips: rawSlashCommandChips,
            selectAllBehavior: selectAllBehavior,
            slashCommandAvailability: slashCommandAvailability,
            isDocumentStartBlock: isDocumentStartBlock,
            isSelected: isSelected,
            delegate: delegate
        )
        return item
    }

    var testingTextView: BlockInputTextView? {
        view.firstDescendant(of: BlockInputTextView.self)
    }

    var testingTextScrollView: NSScrollView? {
        view.firstDescendant(of: NSScrollView.self)
    }

    var testingInlineHintView: BlockInputInlineHintView {
        textView.inlineHintView
    }

    var testingQuoteBarView: NSView? {
        view.firstDescendant(of: NSView.self) { view in
            view.identifier == BlockInputBlockItem.quoteBarIdentifier
        }
    }

    var testingCodeBackgroundView: NSView {
        codeBackgroundView
    }

    var testingTableView: BlockInputTableView {
        tableView
    }

    var testingImageBlockView: BlockInputImageBlockView {
        imageBlockView
    }

    var testingImageCaretView: NSView {
        imageCaretView
    }

    var testingTableOverflowScrollView: NSScrollView {
        tableView.overflowScrollViewForTesting
    }

    var testingTableCellTextViews: [BlockInputTableCellTextView] {
        view.descendants(of: BlockInputTableCellTextView.self)
    }

    var testingSelectedTableRow: BlockInputTable.Row? {
        tableView.selectedRowForTesting
    }

    var testingSelectedTableCellRange: BlockInputTableCellSelection? {
        tableView.selectedCellRangeForTesting
    }

    var testingTableCellViews: [BlockInputTableCellView] {
        view.descendants(of: BlockInputTableCellView.self)
    }

    var testingAppendTableRowButton: NSButton {
        tableView.appendRowButtonForTesting
    }

    var testingAppendTableColumnButton: NSButton {
        tableView.appendColumnButtonForTesting
    }

    var testingHandleView: BlockInputDragHandleView? {
        view.firstDescendant(of: BlockInputDragHandleView.self)
    }

    var testingKindLabel: BlockInputMarkerView? {
        testingMarkerView
    }

    var testingMarkerView: BlockInputMarkerView? {
        view.firstDescendant(of: BlockInputMarkerView.self)
    }

    var testingHandleWidthConstraint: NSLayoutConstraint? {
        guard let handleView = testingHandleView else {
            return nil
        }
        return (handleView.constraints + view.constraints).first { constraint in
            (constraint.firstItem as? NSView) === handleView
                && constraint.firstAttribute == .width
        }
    }

    var testingChecklistButton: NSButton? {
        view.firstDescendant(of: NSButton.self) { button in
            button.toolTip == "Toggle checklist item"
        }
    }

    var testingHorizontalRuleView: NSView? {
        view.firstDescendant(of: NSView.self) { view in
            view.identifier?.rawValue == "BlockInputHorizontalRuleView"
        }
    }

    var testingHorizontalRuleSelectionView: BlockInputHorizontalRuleView? {
        view.firstDescendant(of: BlockInputHorizontalRuleView.self)
    }

    var testingFrontMatterDividerView: NSView? {
        view.firstDescendant(of: NSView.self) { view in
            view.identifier?.rawValue == "BlockInputFrontMatterDividerView"
        }
    }

    var testingSelectionBackgroundView: BlockInputSelectionBackgroundView {
        selectionBackgroundView
    }

    var testingSelectionBackgroundSegmentFrames: [NSRect] {
        selectionBackgroundView.segmentRects.map {
            $0.offsetBy(dx: selectionBackgroundView.frame.minX, dy: selectionBackgroundView.frame.minY)
        }
    }
}

extension BlockInputHorizontalRuleView {
    var testingLineView: NSView? {
        subviews.first
    }

    var testingLineHeight: CGFloat? {
        testingLineView?.constraints.first { constraint in
            constraint.firstAttribute == .height
        }?.constant
    }
}

private extension NSView {
    func firstDescendant<View: NSView>(
        of type: View.Type,
        where matches: (View) -> Bool = { _ in true }
    ) -> View? {
        if let view = self as? View, matches(view) {
            return view
        }
        for subview in subviews {
            if let match = subview.firstDescendant(of: type, where: matches) {
                return match
            }
        }
        return nil
    }

    func descendants<View: NSView>(of type: View.Type) -> [View] {
        var matches: [View] = []
        if let view = self as? View {
            matches.append(view)
        }
        for subview in subviews {
            matches.append(contentsOf: subview.descendants(of: type))
        }
        return matches
    }
}
