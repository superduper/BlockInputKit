import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewPlaceholderTests: XCTestCase {
    func testPlaceholderShowsForSingleEmptyTextBlock() {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "empty", text: "")
            ]),
            placeholder: "Ask anything"
        ))

        XCTAssertFalse(mounted.view.placeholderLabel.isHidden)
        XCTAssertEqual(mounted.view.placeholderLabel.stringValue, "Ask anything")
        XCTAssertEqual(mounted.view.placeholderLabel.accessibilityLabel(), "Ask anything")
        XCTAssertEqual(mounted.view.placeholderLabel.textColor, .placeholderTextColor)
        XCTAssertGreaterThan(mounted.view.placeholderLabel.frame.width, 0)
        XCTAssertEqual(mounted.view.placeholderLabel.frame.minX, expectedPlaceholderLeadingEdge(in: mounted.view), accuracy: 0.5)
    }

    func testPlaceholderHidesForWhitespaceOnlyTextBlock() {
        let whitespaceBlocks = [
            BlockInputBlock(id: "spaces", text: "   "),
            BlockInputBlock(id: "newline", text: "\n")
        ]

        for block in whitespaceBlocks {
            let view = BlockInputView()
            view.configure(BlockInputConfiguration(
                document: BlockInputDocument(blocks: [block]),
                placeholder: "Ask anything"
            ))

            assertPlaceholderHidden(view)
        }
    }

    func testPlaceholderTracksMountedTextLeadingAfterResize() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "empty", text: "")
            ]),
            placeholder: "Ask anything"
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let initialTextLeading = textLeadingEdge(for: item, in: mounted.view)
        XCTAssertEqual(
            mounted.view.placeholderLabel.frame.minX + BlockInputPlaceholderLabel.caretAlignmentCompensation,
            initialTextLeading,
            accuracy: 0.5
        )

        mounted.window.setContentSize(NSSize(width: 980, height: 480))
        mounted.view.frame = mounted.window.contentView?.bounds ?? mounted.view.frame
        mounted.view.layoutSubtreeIfNeeded()
        mounted.view.collectionView.layoutSubtreeIfNeeded()
        mounted.view.updatePlaceholderLayout()
        let resizedItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        XCTAssertEqual(
            mounted.view.placeholderLabel.frame.minX + BlockInputPlaceholderLabel.caretAlignmentCompensation,
            textLeadingEdge(for: resizedItem, in: mounted.view),
            accuracy: 0.5
        )
    }

    func testPlaceholderStaysInsideBoundsAtNarrowWidths() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "empty", text: "")
            ]),
            placeholder: "Ask anything"
        ), size: NSSize(width: 16, height: 160), styleMask: [.borderless])

        mounted.view.layoutSubtreeIfNeeded()
        mounted.view.collectionView.layoutSubtreeIfNeeded()
        mounted.view.updatePlaceholderLayout()
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        XCTAssertGreaterThanOrEqual(mounted.view.placeholderLabel.frame.minX, mounted.view.collectionView.bounds.minX - 0.5)
        XCTAssertLessThanOrEqual(mounted.view.placeholderLabel.frame.maxX, mounted.view.collectionView.bounds.maxX + 0.5)
        // At degenerate widths the text surface keeps a minimum width and pushes its leading edge
        // off-screen; the placeholder clamps to the visible edge instead of tracking it exactly.
        XCTAssertLessThan(textLeadingEdge(for: item, in: mounted.view), 0)
        XCTAssertEqual(
            mounted.view.placeholderLabel.frame.minX,
            expectedPlaceholderLeadingEdge(in: mounted.view),
            accuracy: 0.5
        )
    }

    func testPlaceholderStaysInsideBoundsAfterNarrowWindowResize() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "empty", text: "")
            ]),
            placeholder: "Ask anything"
        ), size: NSSize(width: 720, height: 160), styleMask: [.borderless])

        resizeMountedBlockInputView(mounted, to: NSSize(width: 16, height: 160))
        mounted.view.updatePlaceholderLayout()
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        XCTAssertGreaterThanOrEqual(mounted.view.placeholderLabel.frame.minX, mounted.view.collectionView.bounds.minX - 0.5)
        XCTAssertLessThanOrEqual(mounted.view.placeholderLabel.frame.maxX, mounted.view.collectionView.bounds.maxX + 0.5)
        // Same degenerate-width contract as above: the text leading edge sits off-screen after the
        // resize, so the placeholder pins to the visible edge instead of tracking it exactly.
        XCTAssertLessThan(textLeadingEdge(for: item, in: mounted.view), 0)
        XCTAssertEqual(
            mounted.view.placeholderLabel.frame.minX,
            expectedPlaceholderLeadingEdge(in: mounted.view),
            accuracy: 0.5
        )
    }

    func testPlaceholderFallbackStaysInsideBoundsWithoutMountedRows() {
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 12, height: 80))
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: []),
            placeholder: "Empty"
        ))
        view.collectionView.frame = view.bounds
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        view.updatePlaceholderLayout()

        XCTAssertGreaterThanOrEqual(view.placeholderLabel.frame.minX, view.collectionView.bounds.minX - 0.5)
        XCTAssertLessThanOrEqual(view.placeholderLabel.frame.maxX, view.collectionView.bounds.maxX + 0.5)
    }

    func testPlaceholderShowsForCompleteStoreWithNoLoadedRows() {
        let store = EmptyLoadedStore(isComplete: true)
        let view = BlockInputView()

        view.configure(BlockInputConfiguration(documentStore: store, placeholder: "Empty"))

        XCTAssertFalse(view.placeholderLabel.isHidden)
        XCTAssertEqual(view.placeholderLabel.stringValue, "Empty")
        XCTAssertEqual(store.completeSnapshotCount, 0)
    }

    func testPlaceholderHidesForIncompleteProgressiveStoreWithNoLoadedRows() {
        let store = EmptyLoadedStore(isComplete: false)
        let view = BlockInputView()

        view.configure(BlockInputConfiguration(documentStore: store, placeholder: "Empty"))

        XCTAssertTrue(view.placeholderLabel.isHidden)
        XCTAssertEqual(store.completeSnapshotCount, 0)
    }

    func testPlaceholderShowsForIncompleteProgressiveStoreWithLoadedEmptyRow() {
        let store = LoadedStore(blocks: [
            BlockInputBlock(id: "empty", text: "")
        ], isComplete: false)
        let view = BlockInputView()

        view.configure(BlockInputConfiguration(documentStore: store, placeholder: "Empty"))

        XCTAssertFalse(view.placeholderLabel.isHidden)
        XCTAssertEqual(view.placeholderLabel.stringValue, "Empty")
        XCTAssertEqual(store.completeSnapshotCount, 0)
    }

    func testPlaceholderHidesForSingleEmptyCodeBlock() {
        let codeBlocks = [
            BlockInputBlock(id: "empty-code", kind: .code(language: nil), text: ""),
            BlockInputBlock(id: "blank-code", kind: .code(language: "swift"), text: "\n")
        ]

        for block in codeBlocks {
            let view = BlockInputView()
            view.configure(BlockInputConfiguration(
                document: BlockInputDocument(blocks: [block]),
                placeholder: "Empty"
            ))

            assertPlaceholderHidden(view)
        }
    }

    func testPlaceholderHidesForStoreBackedSingleEmptyCodeBlock() {
        let codeBlocks = [
            BlockInputBlock(id: "empty-code", kind: .code(language: nil), text: ""),
            BlockInputBlock(id: "blank-code", kind: .code(language: "swift"), text: "\n")
        ]

        for block in codeBlocks {
            let store = LoadedStore(blocks: [block], isComplete: true)
            let view = BlockInputView()
            view.configure(BlockInputConfiguration(documentStore: store, placeholder: "Empty"))

            assertPlaceholderHidden(view)
            XCTAssertEqual(store.completeSnapshotCount, 0)
        }
    }

    func testCodeFenceReturnHidesPlaceholder() throws {
        let blockID = BlockInputBlockID(rawValue: "code")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "```")
            ]),
            placeholder: "Ask anything"
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(mounted.view.document.blocks, [
            BlockInputBlock(id: blockID, kind: .code(language: nil))
        ])
        assertPlaceholderHidden(mounted.view)
    }

    func testReturnInEmptyCodeBlockShowsPlaceholderAgain() throws {
        let blockID = BlockInputBlockID(rawValue: "code")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, kind: .code(language: nil))
            ]),
            placeholder: "Ask anything"
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        assertPlaceholderHidden(mounted.view)

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(mounted.view.document.blocks, [
            BlockInputBlock(id: blockID, kind: .paragraph)
        ])
        XCTAssertFalse(mounted.view.placeholderLabel.isHidden)
        XCTAssertEqual(mounted.view.placeholderLabel.stringValue, "Ask anything")
        XCTAssertEqual(mounted.view.placeholderLabel.accessibilityLabel(), "Ask anything")
    }

    func testStoreBackedPlaceholderRefreshesWhenEmptyParagraphBecomesCodeBlock() {
        let blockID = BlockInputBlockID(rawValue: "block")
        let store = LoadedStore(blocks: [
            BlockInputBlock(id: blockID, text: "")
        ], isComplete: true)
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store, placeholder: "Empty"))
        XCTAssertFalse(view.placeholderLabel.isHidden)
        XCTAssertEqual(view.placeholderLabel.stringValue, "Empty")

        store.replaceBlock(BlockInputBlock(id: blockID, kind: .code(language: nil)))
        store.emitReplacedDocument()

        assertPlaceholderHidden(view)
        XCTAssertEqual(store.completeSnapshotCount, 0)
    }

    func testPlaceholderVisibilityTreatsNonTextAndNonEmptyBlocksAsContent() {
        let contentBlocks: [BlockInputBlock] = [
            BlockInputBlock(id: "text", text: "Content"),
            BlockInputBlock(id: "rule", kind: .horizontalRule),
            BlockInputBlock(id: "table", kind: .table, text: "| A |\n| --- |\n| B |"),
            BlockInputBlock(id: "image", kind: .image(BlockInputImage(source: "image.png"))),
            BlockInputBlock(id: "frontmatter", kind: .frontMatter)
        ]

        for block in contentBlocks {
            let view = BlockInputView()
            view.configure(BlockInputConfiguration(
                document: BlockInputDocument(blocks: [block]),
                placeholder: "Empty"
            ))

            XCTAssertTrue(view.placeholderLabel.isHidden, "Expected placeholder to hide for \(block.kind)")
        }
    }

    func testPlaceholderHidesForMultipleEmptyBlocks() {
        let view = BlockInputView()

        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "first", text: ""),
                BlockInputBlock(id: "second", text: "")
            ]),
            placeholder: "Empty"
        ))

        XCTAssertTrue(view.placeholderLabel.isHidden)
    }

    func testPlaceholderDoesNotMutateDocumentOrPublishDocumentChange() {
        let view = BlockInputView()
        var publishedDocuments: [BlockInputDocument] = []

        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "empty", text: "")
            ]),
            placeholder: "Empty",
            onDocumentChange: { publishedDocuments.append($0) }
        ))

        XCTAssertEqual(view.document.markdown, "")
        XCTAssertTrue(publishedDocuments.isEmpty)
    }
}

@MainActor
private func expectedPlaceholderLeadingEdge(in view: BlockInputView) -> CGFloat {
    if let item = view.visibleBlockItemForTesting(at: 0) {
        return max(textLeadingEdge(for: item, in: view) - BlockInputPlaceholderLabel.caretAlignmentCompensation, 0)
    }
    return max(
        BlockInputBlockItem.visualContentInset(
            allowsReordering: view.allowsBlockReordering,
            editorHorizontalInset: view.editorHorizontalInset
        ) - BlockInputPlaceholderLabel.caretAlignmentCompensation,
        0
    )
}

@MainActor
private func textLeadingEdge(for item: BlockInputBlockItem, in view: BlockInputView) -> CGFloat {
    guard let textContainer = item.testingTextView?.textContainer,
          let textView = item.testingTextView else {
        return 0
    }
    let textViewX = textView.textContainerInset.width + textContainer.lineFragmentPadding
    return textView.convert(NSPoint(x: textViewX, y: 0), to: view.collectionView).x
}

@MainActor
private func assertPlaceholderHidden(
    _ view: BlockInputView,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertTrue(view.placeholderLabel.isHidden, file: file, line: line)
    XCTAssertEqual(view.placeholderLabel.stringValue, "", file: file, line: line)
    XCTAssertNil(view.placeholderLabel.accessibilityLabel(), file: file, line: line)
}

private final class EmptyLoadedStore: BlockInputDocumentStore {
    var loadedBlockCount: Int { 0 }
    var isComplete: Bool
    var completeSnapshotCount = 0

    init(isComplete: Bool) {
        self.isComplete = isComplete
    }

    func block(at index: Int) -> BlockInputBlock? {
        nil
    }

    func block(withID id: BlockInputBlockID) -> BlockInputBlock? {
        nil
    }

    func index(of id: BlockInputBlockID) -> Int? {
        nil
    }

    @MainActor
    func completeDocumentSnapshot(limit: Int) async throws -> BlockInputDocument {
        completeSnapshotCount += 1
        return BlockInputDocument(blocks: [])
    }

    func replaceDocument(_ document: BlockInputDocument) {}
}

private final class LoadedStore: BlockInputDocumentStore, @unchecked Sendable {
    var loadedBlockCount: Int { blocks.count }
    var isComplete: Bool
    var completeSnapshotCount = 0

    private var blocks: [BlockInputBlock]
    private var observers: [UUID: @MainActor (BlockInputDocumentStoreChange) -> Void] = [:]

    init(blocks: [BlockInputBlock], isComplete: Bool) {
        self.blocks = blocks
        self.isComplete = isComplete
    }

    func block(at index: Int) -> BlockInputBlock? {
        blocks.indices.contains(index) ? blocks[index] : nil
    }

    func block(withID id: BlockInputBlockID) -> BlockInputBlock? {
        blocks.first { $0.id == id }
    }

    func index(of id: BlockInputBlockID) -> Int? {
        blocks.firstIndex { $0.id == id }
    }

    func observeChanges(_ observer: @escaping @MainActor (BlockInputDocumentStoreChange) -> Void) -> BlockInputDocumentStoreObservation {
        let id = UUID()
        observers[id] = observer
        return BlockInputDocumentStoreObservation { [weak self] in
            self?.observers[id] = nil
        }
    }

    @MainActor
    func completeDocumentSnapshot(limit: Int) async throws -> BlockInputDocument {
        completeSnapshotCount += 1
        return BlockInputDocument(blocks: blocks)
    }

    func replaceDocument(_ document: BlockInputDocument) {
        blocks = document.blocks
    }

    func replaceBlock(_ block: BlockInputBlock) {
        guard let index = index(of: block.id) else {
            return
        }
        blocks[index] = block
    }

    @MainActor
    func emitReplacedDocument() {
        observers.values.forEach { $0(.replacedDocument) }
    }
}
