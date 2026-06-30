import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewHeightSizingTests: XCTestCase {
    func testSizingDisabledPreservesNoIntrinsicHeight() {
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 360, height: 200))

        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: "first", text: "Short")
        ])))

        XCTAssertEqual(view.intrinsicContentSize.height, NSView.noIntrinsicMetric)
    }

    func testPreferredHeightUsesDefaultVisibleLineCountForShortContent() {
        let view = configuredView(text: "Short", defaultLines: 3, maxLines: 6)

        XCTAssertEqual(view.preferredHeight(forWidth: 360), expectedLineHeight(lines: 3, in: view), accuracy: 0.5)
        XCTAssertEqual(view.intrinsicContentSize.height, expectedLineHeight(lines: 3, in: view), accuracy: 0.5)
    }

    func testReconfiguringWithoutHeightSizingRemovesIntrinsicHeight() {
        let view = configuredView(text: "Short", defaultLines: 3, maxLines: 6)

        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: "first", text: "Short")
        ])))

        XCTAssertEqual(view.intrinsicContentSize.height, NSView.noIntrinsicMetric)
    }

    func testPreferredHeightGrowsWithRenderedContentAndCapsAtMaximumLineCount() {
        let shortView = configuredView(text: "One\nTwo\nThree", defaultLines: 1, maxLines: 8)
        let tallView = configuredView(
            text: (0..<20).map { "Line \($0)" }.joined(separator: "\n"),
            defaultLines: 1,
            maxLines: 4
        )

        XCTAssertGreaterThan(shortView.preferredHeight(forWidth: 360), expectedLineHeight(lines: 1, in: shortView))
        XCTAssertEqual(tallView.preferredHeight(forWidth: 360), expectedLineHeight(lines: 4, in: tallView), accuracy: 0.5)
    }

    func testPreferredHeightRespondsToWidthAndStyleChanges() {
        let text = "This paragraph is long enough to wrap at narrow widths but stay shorter when the editor is wide."
        let view = configuredView(text: text, defaultLines: 1, maxLines: nil)
        let wideHeight = view.preferredHeight(forWidth: 720)
        let narrowHeight = view.preferredHeight(forWidth: 180)

        XCTAssertGreaterThan(narrowHeight, wideHeight)

        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "first", text: text)]),
            style: BlockInputStyle(baseText: BlockInputTextStyle(font: .systemFont(ofSize: 24))),
            heightSizing: BlockInputEditorHeightSizing(defaultVisibleLineCount: 1)
        ))

        XCTAssertGreaterThan(view.preferredHeight(forWidth: 720), wideHeight)
    }

    func testPreferredHeightUsesBlockVerticalInsetMultiplier() {
        let text = "One\nTwo\nThree\nFour"
        let defaultView = configuredView(text: text, defaultLines: 1, maxLines: nil)
        let compactView = configuredView(text: text, defaultLines: 1, maxLines: nil, blockVerticalInsetMultiplier: 0.5)

        XCTAssertLessThan(compactView.preferredHeight(forWidth: 360), defaultView.preferredHeight(forWidth: 360))
        XCTAssertEqual(
            compactView.preferredHeight(forWidth: 360),
            expectedSoftLineHeight(lines: 4, in: compactView),
            accuracy: 0.5
        )
    }

    func testSizingUsesActualVeryNarrowWrappingWidth() {
        let block = BlockInputBlock(id: "first", text: Array(repeating: "a", count: 40).joined(separator: " "))
        let narrowTextWidth = BlockInputBlockItem.measuredTextWidth(
            for: 16,
            block: block,
            allowsReordering: true
        )
        let widerTextWidth = BlockInputBlockItem.measuredTextWidth(
            for: 140,
            block: block,
            allowsReordering: true
        )

        XCTAssertLessThan(narrowTextWidth, widerTextWidth)
    }

    func testMaximumLineCountCannotShrinkBelowDefaultLineCount() {
        let view = configuredView(text: "Short", defaultLines: 5, maxLines: 2)

        XCTAssertEqual(view.preferredHeight(forWidth: 360), expectedLineHeight(lines: 5, in: view), accuracy: 0.5)
    }

    func testCappedContentRemainsVerticallyScrollable() {
        let view = configuredView(
            text: (0..<30).map { "Line \($0)" }.joined(separator: "\n"),
            defaultLines: 1,
            maxLines: 3
        )
        let preferredHeight = view.preferredHeight(forWidth: 360)
        view.frame = NSRect(x: 0, y: 0, width: 360, height: preferredHeight)
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()

        let contentHeight = view.collectionView.collectionViewLayout?.collectionViewContentSize.height ?? 0

        XCTAssertGreaterThan(contentHeight, view.scrollView.contentSize.height)
        view.scrollView.contentView.scroll(to: NSPoint(x: 0, y: contentHeight))
        view.clampVerticalScrollOffsetIfNeeded()
        XCTAssertLessThanOrEqual(
            view.scrollView.contentView.bounds.origin.y,
            max(0, contentHeight - view.scrollView.contentSize.height) + 0.5
        )
    }

    func testPreferredHeightCallbackPublishesInitialAndChangedHeightOnce() async {
        var reportedHeights: [CGFloat] = []
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 360, height: 200))
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "first", text: "Short")]),
            heightSizing: BlockInputEditorHeightSizing(
                defaultVisibleLineCount: 1,
                maximumVisibleLineCount: 6,
                onPreferredHeightChange: { reportedHeights.append($0) }
            )
        ))
        view.layoutSubtreeIfNeeded()
        await Task.yield()

        let firstHeightCount = reportedHeights.count
        view.invalidatePreferredHeight()
        await Task.yield()
        XCTAssertEqual(reportedHeights.count, firstHeightCount)

        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "first", text: (0..<5).map { "Line \($0)" }.joined(separator: "\n"))
            ]),
            heightSizing: BlockInputEditorHeightSizing(
                defaultVisibleLineCount: 1,
                maximumVisibleLineCount: 6,
                onPreferredHeightChange: { reportedHeights.append($0) }
            )
        ))
        view.layoutSubtreeIfNeeded()
        await Task.yield()

        XCTAssertGreaterThan(reportedHeights.count, firstHeightCount)
        XCTAssertGreaterThan(reportedHeights.last ?? 0, reportedHeights.first ?? 0)
    }

    func testPreferredHeightTransitionPublishesInitialAndAnimatedChanges() async {
        var transitions: [BlockInputEditorHeightTransition] = []
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 360, height: 200))
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "first", text: "Short")]),
            heightSizing: BlockInputEditorHeightSizing(
                defaultVisibleLineCount: 1,
                maximumVisibleLineCount: 6,
                animation: .default,
                onPreferredHeightTransition: { transitions.append($0) }
            )
        ))
        view.layoutSubtreeIfNeeded()
        await Task.yield()

        XCTAssertEqual(transitions.count, 1)
        XCTAssertTrue(transitions[0].isInitial)
        XCTAssertNil(transitions[0].previousHeight)
        XCTAssertNil(transitions[0].animation)

        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "first", text: (0..<5).map { "Line \($0)" }.joined(separator: "\n"))
            ]),
            heightSizing: BlockInputEditorHeightSizing(
                defaultVisibleLineCount: 1,
                maximumVisibleLineCount: 6,
                animation: .default,
                onPreferredHeightTransition: { transitions.append($0) }
            )
        ))
        view.layoutSubtreeIfNeeded()
        await Task.yield()

        XCTAssertGreaterThan(transitions.count, 1)
        XCTAssertFalse(transitions.last?.isInitial ?? true)
        XCTAssertNotNil(transitions.last?.previousHeight)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            XCTAssertNil(transitions.last?.animation)
        } else {
            XCTAssertEqual(transitions.last?.animation, .default)
        }
        XCTAssertGreaterThan(transitions.last?.targetHeight ?? 0, transitions.first?.targetHeight ?? 0)
    }

    func testHeightSizingWithoutCallbacksDoesNotConsumeInitialTransition() async {
        let document = BlockInputDocument(blocks: [BlockInputBlock(id: "first", text: "Short")])
        var transitions: [BlockInputEditorHeightTransition] = []
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 360, height: 200))
        view.configure(BlockInputConfiguration(
            document: document,
            heightSizing: BlockInputEditorHeightSizing(defaultVisibleLineCount: 1)
        ))
        view.layoutSubtreeIfNeeded()
        await Task.yield()

        view.configure(BlockInputConfiguration(
            document: document,
            heightSizing: BlockInputEditorHeightSizing(
                defaultVisibleLineCount: 1,
                animation: .default,
                onPreferredHeightTransition: { transitions.append($0) }
            )
        ))
        view.layoutSubtreeIfNeeded()
        await Task.yield()

        XCTAssertEqual(transitions.count, 1)
        XCTAssertTrue(transitions[0].isInitial)
        XCTAssertNil(transitions[0].previousHeight)
        XCTAssertNil(transitions[0].animation)
    }

    func testPreferredHeightTransitionCanPublishWithLegacyCallbackAndNoAnimation() async {
        var reportedHeights: [CGFloat] = []
        var transitions: [BlockInputEditorHeightTransition] = []
        var heightSizing = BlockInputEditorHeightSizing(
            defaultVisibleLineCount: 1,
            maximumVisibleLineCount: 6,
            onPreferredHeightChange: { reportedHeights.append($0) }
        )
        heightSizing.animation = nil
        heightSizing.onPreferredHeightTransition = { transitions.append($0) }

        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 360, height: 200))
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "first", text: "Short")]),
            heightSizing: heightSizing
        ))
        view.layoutSubtreeIfNeeded()
        await Task.yield()

        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "first", text: (0..<5).map { "Line \($0)" }.joined(separator: "\n"))
            ]),
            heightSizing: heightSizing
        ))
        view.layoutSubtreeIfNeeded()
        await Task.yield()

        XCTAssertEqual(reportedHeights.count, transitions.count)
        XCTAssertGreaterThan(transitions.count, 1)
        XCTAssertNil(transitions.last?.animation)
        XCTAssertFalse(transitions.last?.isInitial ?? true)
        XCTAssertEqual(reportedHeights.last, transitions.last?.targetHeight)
    }

    func testHostViewCanResizeEditorFromFittingSize() {
        let host = HeightSizingHostView(frame: NSRect(x: 0, y: 0, width: 360, height: 260))
        host.configure(text: "Short", defaultLines: 1, maxLines: 3)
        host.layoutSubtreeIfNeeded()
        let shortHeight = host.editor.frame.height

        host.configure(text: (0..<20).map { "Line \($0)" }.joined(separator: "\n"), defaultLines: 1, maxLines: 3)
        host.layoutSubtreeIfNeeded()
        let cappedHeight = host.editor.frame.height

        XCTAssertGreaterThan(cappedHeight, shortHeight)
        XCTAssertEqual(cappedHeight, expectedLineHeight(lines: 3, in: host.editor), accuracy: 0.5)
        XCTAssertGreaterThan(host.editor.collectionView.collectionViewLayout?.collectionViewContentSize.height ?? 0, cappedHeight)
    }

    func testCappedMeasurementStopsReadingProgressiveStoreAfterMaximumHeight() {
        let blocks = (0..<100).map { BlockInputBlock(id: BlockInputBlockID(rawValue: "block-\($0)"), text: "Line \($0)") }
        let store = ReadCountingStore(blocks: blocks)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 360, height: 200))

        view.configure(BlockInputConfiguration(
            documentStore: store,
            heightSizing: BlockInputEditorHeightSizing(defaultVisibleLineCount: 1, maximumVisibleLineCount: 2)
        ))
        store.resetReadCount()
        _ = view.preferredHeight(forWidth: 360)

        XCTAssertLessThan(store.readIndexes.count, blocks.count)
    }

    func testEmptyCompletedProgressiveBatchPublishesHeightAfterLoadingRowDisappears() async {
        var reportedHeights: [CGFloat] = []
        let store = MutableCompletionStore(blocks: [BlockInputBlock(id: "first", text: "Short")], isComplete: false)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 360, height: 200))
        view.configure(BlockInputConfiguration(
            documentStore: store,
            heightSizing: BlockInputEditorHeightSizing(
                defaultVisibleLineCount: 1,
                onPreferredHeightChange: { reportedHeights.append($0) }
            )
        ))
        let heightWithLoadingRow = view.preferredHeight(forWidth: 360)

        store.isComplete = true
        view.appendProgressiveBatch(BlockInputDocumentStoreBatch(startIndex: 1, blocks: [], isComplete: true))
        await Task.yield()

        XCTAssertLessThan(view.preferredHeight(forWidth: 360), heightWithLoadingRow)
        XCTAssertEqual(reportedHeights.last ?? 0, view.preferredHeight(forWidth: 360), accuracy: 0.5)
    }

    private func configuredView(
        text: String,
        defaultLines: Int,
        maxLines: Int?,
        blockVerticalInsetMultiplier: CGFloat = 1
    ) -> BlockInputView {
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 360, height: 200))
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "first", text: text)
            ]),
            blockVerticalInsetMultiplier: blockVerticalInsetMultiplier,
            heightSizing: BlockInputEditorHeightSizing(
                defaultVisibleLineCount: defaultLines,
                maximumVisibleLineCount: maxLines
            )
        ))
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func expectedLineHeight(lines: Int, in view: BlockInputView) -> CGFloat {
        let rowHeight = BlockInputBlockItem.height(
            for: BlockInputBlock(id: "expected", text: "x"),
            textWidth: 10_000,
            style: view.style,
            blockVerticalInsetMultiplier: view.blockVerticalInsetMultiplier
        )
        return ceil((rowHeight * CGFloat(lines)) + (view.editorVerticalInset * 2))
    }

    private func expectedSoftLineHeight(lines: Int, in view: BlockInputView) -> CGFloat {
        let text = Array(repeating: "x", count: lines).joined(separator: "\n")
        let rowHeight = BlockInputBlockItem.height(
            for: BlockInputBlock(id: "expected", text: text),
            textWidth: 10_000,
            style: view.style,
            blockVerticalInsetMultiplier: view.blockVerticalInsetMultiplier
        )
        return ceil(rowHeight + (view.editorVerticalInset * 2))
    }
}

@MainActor
private final class HeightSizingHostView: NSView {
    let editor = BlockInputView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(editor)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addSubview(editor)
    }

    func configure(text: String, defaultLines: Int, maxLines: Int?) {
        editor.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "first", text: text)]),
            heightSizing: BlockInputEditorHeightSizing(
                defaultVisibleLineCount: defaultLines,
                maximumVisibleLineCount: maxLines,
                onPreferredHeightChange: { [weak self] _ in
                    self?.needsLayout = true
                }
            )
        ))
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let height = editor.fittingSize.height
        editor.frame = NSRect(x: 0, y: 0, width: bounds.width, height: height)
        editor.layoutSubtreeIfNeeded()
    }
}

private final class ReadCountingStore: BlockInputDocumentStore, @unchecked Sendable {
    private let blocks: [BlockInputBlock]
    private(set) var readIndexes: [Int] = []

    init(blocks: [BlockInputBlock]) {
        self.blocks = blocks
    }

    var loadedBlockCount: Int { blocks.count }
    var isComplete: Bool { false }

    func block(at index: Int) -> BlockInputBlock? {
        readIndexes.append(index)
        return blocks.indices.contains(index) ? blocks[index] : nil
    }

    func resetReadCount() {
        readIndexes.removeAll()
    }

    func block(withID id: BlockInputBlockID) -> BlockInputBlock? {
        blocks.first { $0.id == id }
    }

    func index(of id: BlockInputBlockID) -> Int? {
        blocks.firstIndex { $0.id == id }
    }

    func replaceDocument(_ document: BlockInputDocument) {}
}

private final class MutableCompletionStore: BlockInputDocumentStore, @unchecked Sendable {
    private let blocks: [BlockInputBlock]
    var isComplete: Bool

    init(blocks: [BlockInputBlock], isComplete: Bool) {
        self.blocks = blocks
        self.isComplete = isComplete
    }

    var loadedBlockCount: Int { blocks.count }

    func block(at index: Int) -> BlockInputBlock? {
        blocks.indices.contains(index) ? blocks[index] : nil
    }

    func block(withID id: BlockInputBlockID) -> BlockInputBlock? {
        blocks.first { $0.id == id }
    }

    func index(of id: BlockInputBlockID) -> Int? {
        blocks.firstIndex { $0.id == id }
    }

    func replaceDocument(_ document: BlockInputDocument) {}
}
