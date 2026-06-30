import AppKit

@MainActor
protocol BlockInputTableViewDelegate: AnyObject {
    func tableView(_ tableView: BlockInputTableView, didBeginEditing position: BlockInputTable.CellPosition)
    func tableView(_ tableView: BlockInputTableView, didEndEditing position: BlockInputTable.CellPosition)
    func tableView(_ tableView: BlockInputTableView, didChangeSelectionIn position: BlockInputTable.CellPosition, sourceRange: NSRange)
    func tableViewDidRequestWholeTableSelection(_ tableView: BlockInputTableView)
    func tableView(
        _ tableView: BlockInputTableView,
        didChangeText text: String,
        in position: BlockInputTable.CellPosition,
        selectedLocalRange: NSRange,
        selectionBefore: BlockInputSelection?
    )
    func tableView(
        _ tableView: BlockInputTableView,
        shouldChangeTextIn position: BlockInputTable.CellPosition,
        affectedLocalRange: NSRange,
        replacementString: String?
    ) -> Bool
    func tableViewDidRequestAppendBodyRow(_ tableView: BlockInputTableView, from position: BlockInputTable.CellPosition?)
    func tableViewDidRequestAppendColumn(_ tableView: BlockInputTableView, from position: BlockInputTable.CellPosition?)
}

/// AppKit table surface used by table blocks.
///
/// The view owns a horizontally scrollable table document, editable cell text
/// views, row-selection chrome, and append controls. Its layout code mirrors
/// offscreen measurement so collection row heights remain stable when cell
/// content wraps.
final class BlockInputTableView: NSView {
    static let minimumColumnWidth: CGFloat = 120
    static let maximumColumnWidth: CGFloat = 420
    static let cellHorizontalPadding: CGFloat = 10
    static let cellVerticalPadding: CGFloat = 7
    static let fallbackViewportWidth: CGFloat = 520
    static let cornerRadius: CGFloat = 6

    let chromeView = BlockInputTableChromeView()
    let scrollView = BlockInputTableOverflowScrollView()
    let documentView = BlockInputTableDocumentView()
    let appendRowButton = BlockInputTableAppendButton()
    let appendColumnButton = BlockInputTableAppendButton()
    var cellRows: [[BlockInputTableCellView]] = []
    var table: BlockInputTable?
    var style = BlockInputStyle.default
    var blockVerticalInsetMultiplier: CGFloat = 1
    var hasAppliedInitialScrollPosition = false
    var configuredBlockID: BlockInputBlockID?
    var selectedRow: BlockInputTable.Row?
    var selectedCellRange: BlockInputTableCellSelection?
    var cellSelectionDragAnchor: BlockInputTable.CellPosition?
    var isDraggingCellSelection = false
    var isEditable = true {
        didSet {
            guard oldValue != isEditable else {
                return
            }
            chromeView.isEditable = isEditable
            if !isEditable {
                hoveredAppendTarget = nil
                appendHoverAnchor = nil
                updateAppendControlFrames()
            }
            cellRows.flatMap { $0 }.forEach { $0.updateEditableState(isEditable) }
        }
    }
    var trackingArea: NSTrackingArea?
    var hoveredAppendTarget: AppendTarget?
    var appendHoverAnchor: NSPoint?
    weak var delegate: BlockInputTableViewDelegate?
    weak var blockItem: BlockInputBlockItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var isFlipped: Bool {
        true
    }

    override func layout() {
        super.layout()
        layoutTable()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        chromeView.updateColors()
        cellRows.flatMap { $0 }.forEach { $0.updateColors() }
    }

    func configure(
        block: BlockInputBlock,
        style: BlockInputStyle,
        blockVerticalInsetMultiplier: CGFloat = 1
    ) {
        guard block.kind == .table,
              let table = BlockInputTable(markdown: block.text) else {
            resetForReuse()
            return
        }
        if configuredBlockID != block.id {
            hasAppliedInitialScrollPosition = false
            configuredBlockID = block.id
        }
        self.table = table
        self.style = style
        self.blockVerticalInsetMultiplier = BlockInputConfiguration.sanitizedBlockVerticalInsetMultiplier(
            blockVerticalInsetMultiplier
        )
        selectedRow = nil
        selectedCellRange = nil
        cellSelectionDragAnchor = nil
        isDraggingCellSelection = false
        hoveredAppendTarget = nil
        appendHoverAnchor = nil
        appendRowButton.isHidden = true
        appendColumnButton.isHidden = true
        chromeView.isEditable = isEditable
        setAccessibilityLabel(Self.accessibilityLabel(for: table))
        rebuildCells(for: table, style: style)
        isHidden = false
        needsLayout = true
    }

    func resetForReuse() {
        table = nil
        configuredBlockID = nil
        style = .default
        blockVerticalInsetMultiplier = 1
        hasAppliedInitialScrollPosition = false
        selectedRow = nil
        selectedCellRange = nil
        cellSelectionDragAnchor = nil
        isDraggingCellSelection = false
        isEditable = true
        hoveredAppendTarget = nil
        appendHoverAnchor = nil
        cellRows.flatMap { $0 }.forEach { $0.removeFromSuperview() }
        cellRows = []
        documentView.frame = .zero
        chromeView.frame = .zero
        scrollView.frame = .zero
        appendRowButton.isHidden = true
        appendColumnButton.isHidden = true
        setAccessibilityLabel(nil)
        if let trackingArea {
            removeTrackingArea(trackingArea)
            self.trackingArea = nil
        }
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        isHidden = true
    }

    func updateTableAfterCellEdit(_ table: BlockInputTable) {
        self.table = table
        selectedRow = nil
        selectedCellRange = nil
        updateSelectionChrome()
        activeCellView?.refreshInlineMarkdownAttributesAfterEdit()
        needsLayout = true
        documentView.needsLayout = true
    }

    var visibleTableFrame: NSRect {
        chromeView.frame
    }

    var overflowScrollViewForTesting: NSScrollView {
        scrollView
    }

    var selectedRowForTesting: BlockInputTable.Row? {
        selectedRow
    }

    var selectedCellRangeForTesting: BlockInputTableCellSelection? {
        selectedCellRange
    }

    var appendRowButtonForTesting: NSButton {
        appendRowButton
    }

    var appendColumnButtonForTesting: NSButton {
        appendColumnButton
    }

    static func height(
        for table: BlockInputTable,
        width: CGFloat,
        style: BlockInputStyle = .default,
        blockVerticalInsetMultiplier: CGFloat = 1
    ) -> CGFloat {
        layoutMetrics(
            for: table,
            viewportWidth: width,
            style: style,
            blockVerticalInsetMultiplier: blockVerticalInsetMultiplier
        ).height
    }

    static func naturalWidth(for table: BlockInputTable, style: BlockInputStyle = .default) -> CGFloat {
        layoutMetrics(for: table, viewportWidth: fallbackViewportWidth, style: style).naturalWidth
    }

    private func setup() {
        isHidden = true
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.group)

        chromeView.translatesAutoresizingMaskIntoConstraints = true
        chromeView.wantsLayer = true
        chromeView.setAccessibilityElement(false)
        chromeView.layer?.cornerRadius = Self.cornerRadius
        chromeView.layer?.masksToBounds = true
        chromeView.layer?.borderWidth = 1
        chromeView.updateColors()
        addSubview(chromeView)

        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.documentView = documentView
        scrollView.translatesAutoresizingMaskIntoConstraints = true
        documentView.setAccessibilityElement(false)
        chromeView.addSubview(scrollView)

        configureAppendButton(appendRowButton, action: #selector(appendRowButtonClicked(_:)), label: "Append Table Row")
        configureAppendButton(appendColumnButton, action: #selector(appendColumnButtonClicked(_:)), label: "Append Table Column")
        addSubview(appendRowButton)
        addSubview(appendColumnButton)
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        guard isEditable, table != nil else {
            return nil
        }
        return [
            NSAccessibilityCustomAction(
                name: "Append Table Row",
                target: self,
                selector: #selector(accessibilityAppendTableRow(_:))
            ),
            NSAccessibilityCustomAction(
                name: "Append Table Column",
                target: self,
                selector: #selector(accessibilityAppendTableColumn(_:))
            )
        ]
    }

    private func rebuildCells(for table: BlockInputTable, style: BlockInputStyle) {
        cellRows.flatMap { $0 }.forEach { $0.removeFromSuperview() }
        let rowModels = Self.rowModels(for: table)
        cellRows = rowModels.enumerated().map { rowIndex, row in
            (0..<table.columnCount).map { columnIndex in
                let cell = BlockInputTableCellView()
                cell.configure(BlockInputTableCellConfiguration(
                    text: row[columnIndex].text,
                    isHeader: rowIndex == 0,
                    alignment: Self.textAlignment(for: table.alignments[columnIndex]),
                    style: style,
                    blockVerticalInsetMultiplier: blockVerticalInsetMultiplier,
                    isEditable: isEditable,
                    position: Self.cellPosition(rowIndex: rowIndex, columnIndex: columnIndex),
                    tableView: self,
                    blockItem: blockItem
                ))
                documentView.addSubview(cell)
                return cell
            }
        }
    }

    private static func cellPosition(rowIndex: Int, columnIndex: Int) -> BlockInputTable.CellPosition {
        rowIndex == 0
            ? .init(row: .header, column: columnIndex)
            : .init(row: .body(rowIndex - 1), column: columnIndex)
    }

    private func layoutTable() {
        guard let table, table.columnCount > 0 else {
            chromeView.frame = .zero
            scrollView.frame = .zero
            documentView.frame = .zero
            return
        }
        let previousOrigin = scrollView.contentView.bounds.origin
        let metrics = Self.layoutMetrics(
            for: table,
            viewportWidth: bounds.width,
            style: style,
            blockVerticalInsetMultiplier: blockVerticalInsetMultiplier
        )
        var currentY: CGFloat = 0
        for (rowIndex, row) in cellRows.enumerated() {
            var currentX: CGFloat = 0
            let rowHeight = metrics.rowHeights[rowIndex]
            for (columnIndex, cell) in row.enumerated() {
                let columnWidth = metrics.columnWidths[columnIndex]
                cell.frame = NSRect(x: currentX, y: currentY, width: columnWidth, height: rowHeight)
                cell.layoutSubtreeIfNeeded()
                currentX += columnWidth
            }
            currentY += rowHeight
        }

        chromeView.frame = NSRect(x: 0, y: 0, width: metrics.viewportWidth, height: metrics.height)
        scrollView.frame = chromeView.bounds
        documentView.frame = NSRect(x: 0, y: 0, width: metrics.naturalWidth, height: metrics.tableHeight)
        restoreScrollPosition(previousOrigin, documentWidth: metrics.naturalWidth, viewportWidth: metrics.viewportWidth)
        updateAppendControlFrames()
    }

    private func restoreScrollPosition(_ previousOrigin: NSPoint, documentWidth: CGFloat, viewportWidth: CGFloat) {
        let maximumX = max(0, documentWidth - viewportWidth)
        let targetOrigin: NSPoint
        if hasAppliedInitialScrollPosition {
            targetOrigin = NSPoint(x: min(max(previousOrigin.x, 0), maximumX), y: 0)
        } else {
            targetOrigin = .zero
            hasAppliedInitialScrollPosition = true
        }
        if scrollView.contentView.bounds.origin != targetOrigin {
            scrollView.contentView.scroll(to: targetOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    func updateSelectionChrome() {
        for row in cellRows.flatMap({ $0 }) {
            row.setRowSelected(row.position.row == selectedRow)
            row.setCellSelected(selectedCellRange?.contains(row.position) == true)
        }
    }

    func updateRowSelectionChrome() {
        updateSelectionChrome()
    }

    @objc private func accessibilityAppendTableRow(_ action: NSAccessibilityCustomAction) -> Bool {
        appendRowButtonClicked(action)
        return true
    }

    @objc private func accessibilityAppendTableColumn(_ action: NSAccessibilityCustomAction) -> Bool {
        appendColumnButtonClicked(action)
        return true
    }

    private static func accessibilityLabel(for table: BlockInputTable) -> String {
        let rowCount = table.bodyRows.count + 1
        let rowLabel = rowCount == 1 ? "row" : "rows"
        let columnLabel = table.columnCount == 1 ? "column" : "columns"
        return "Table, \(rowCount) \(rowLabel), \(table.columnCount) \(columnLabel)"
    }

}

final class BlockInputTableChromeView: NSView {
    var isEditable = true {
        didSet {
            updateColors()
        }
    }

    override var isFlipped: Bool {
        true
    }

    func updateColors() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.01).cgColor
        layer?.borderColor = BlockInputReadOnlyStyle.tableBorderColor(isEditable: isEditable)
    }
}

final class BlockInputTableDocumentView: NSView {
    override var isFlipped: Bool {
        true
    }
}

/// Hover-visible plus button for appending one table row or column.
final class BlockInputTableAppendButton: NSButton {
    override func accessibilityPerformPress() -> Bool {
        performClick(nil)
        return true
    }
}

struct BlockInputTableLayoutMetrics {
    var columnWidths: [CGFloat]
    var rowHeights: [CGFloat]
    var naturalWidth: CGFloat
    var viewportWidth: CGFloat
    var tableHeight: CGFloat
    var height: CGFloat
}

enum AppendTarget {
    case row
    case column
}

let appendControlSize: CGFloat = 18
let appendHoverTolerance: CGFloat = 8

/// Visual table-cell selection used while dragging across cells.
struct BlockInputTableCellSelection: Equatable {
    var anchor: BlockInputTable.CellPosition
    var focus: BlockInputTable.CellPosition

    var rowRange: ClosedRange<Int> {
        let anchorRow = Self.displayRowIndex(for: anchor.row)
        let focusRow = Self.displayRowIndex(for: focus.row)
        return min(anchorRow, focusRow)...max(anchorRow, focusRow)
    }

    var columnRange: ClosedRange<Int> {
        min(anchor.column, focus.column)...max(anchor.column, focus.column)
    }

    init(anchor: BlockInputTable.CellPosition, focus: BlockInputTable.CellPosition) {
        self.anchor = anchor
        self.focus = focus
    }

    func contains(_ position: BlockInputTable.CellPosition) -> Bool {
        rowRange.contains(Self.displayRowIndex(for: position.row)) && columnRange.contains(position.column)
    }

    static func displayRowIndex(for row: BlockInputTable.Row) -> Int {
        switch row {
        case .header:
            return 0
        case .body(let rowIndex):
            return rowIndex + 1
        }
    }

    static func row(forDisplayRowIndex rowIndex: Int) -> BlockInputTable.Row {
        rowIndex == 0 ? .header : .body(rowIndex - 1)
    }
}
