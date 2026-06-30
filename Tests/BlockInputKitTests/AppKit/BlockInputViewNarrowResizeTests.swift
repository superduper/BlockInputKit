import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewNarrowResizeTests: XCTestCase {
    func testMountedEditorCollapsesTextGuttersAtNarrowWidth() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "paragraph", text: "First")
            ]),
            allowsBlockReordering: true
        ), size: NSSize(width: 32, height: 160), styleMask: [.borderless])

        useLegacyDocumentScroller(mounted)
        mounted.view.layoutSubtreeIfNeeded()
        mounted.view.collectionView.layoutSubtreeIfNeeded()
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let scrollView = try XCTUnwrap(item.testingTextScrollView)

        XCTAssertGreaterThanOrEqual(scrollView.frame.minX, item.view.bounds.minX - 0.5)
        XCTAssertLessThanOrEqual(scrollView.frame.maxX, item.view.bounds.maxX + 0.5)
        XCTAssertEqual(mounted.view.scrollView.contentView.bounds.origin.x, 0, accuracy: 0.5)
    }

    func testMountedEditorShrinksVisibleTextRowsAfterWindowResize() throws {
        for block in Self.wrappingBlocks {
            let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
                document: BlockInputDocument(blocks: [block])
            ), size: NSSize(width: 720, height: 160), styleMask: [.borderless])
            let initialItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
            XCTAssertGreaterThan(initialItem.view.bounds.width, 200, "\(block.kind)")

            useLegacyDocumentScroller(mounted)
            resizeMountedBlockInputView(mounted, to: NSSize(width: 40, height: 160))
            let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
            let scrollView = try XCTUnwrap(item.testingTextScrollView)
            let clipWidth = mounted.view.scrollView.contentView.bounds.width

            XCTAssertLessThanOrEqual(mounted.view.collectionView.frame.width, clipWidth + 0.5, "\(block.kind)")
            XCTAssertLessThanOrEqual(item.view.frame.width, mounted.view.collectionView.bounds.width + 0.5, "\(block.kind)")
            XCTAssertGreaterThanOrEqual(scrollView.frame.minX, item.view.bounds.minX - 0.5, "\(block.kind)")
            XCTAssertLessThanOrEqual(scrollView.frame.maxX, item.view.bounds.maxX + 0.5, "\(block.kind)")
            XCTAssertEqual(mounted.view.scrollView.contentView.bounds.origin.x, 0, accuracy: 0.5, "\(block.kind)")
        }
    }

    func testNarrowCodeBlockKeepsHorizontalOverflowInsideNestedScroller() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [Self.codeBlock])
        ), size: NSSize(width: 48, height: 160), styleMask: [.borderless])

        useLegacyDocumentScroller(mounted)
        mounted.view.layoutSubtreeIfNeeded()
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        try assertCodeBlockKeepsHorizontalOverflowInsideNestedScroller(mounted)
    }

    func testCodeBlockKeepsHorizontalOverflowInsideNestedScrollerAfterWindowResize() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [Self.codeBlock])
        ), size: NSSize(width: 720, height: 160), styleMask: [.borderless])

        useLegacyDocumentScroller(mounted)
        resizeMountedBlockInputView(mounted, to: NSSize(width: 48, height: 160))

        try assertCodeBlockKeepsHorizontalOverflowInsideNestedScroller(mounted)
    }

    func testNarrowTableKeepsHorizontalOverflowInsideNestedScroller() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [Self.tableBlock])
        ), size: NSSize(width: 56, height: 180), styleMask: [.borderless])

        useLegacyDocumentScroller(mounted)
        mounted.view.layoutSubtreeIfNeeded()
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        try assertTableKeepsHorizontalOverflowInsideNestedScroller(mounted)
    }

    func testTableKeepsHorizontalOverflowInsideNestedScrollerAfterWindowResize() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [Self.tableBlock])
        ), size: NSSize(width: 720, height: 180), styleMask: [.borderless])

        useLegacyDocumentScroller(mounted)
        resizeMountedBlockInputView(mounted, to: NSSize(width: 56, height: 180))

        try assertTableKeepsHorizontalOverflowInsideNestedScroller(mounted)
    }

    private func assertCodeBlockKeepsHorizontalOverflowInsideNestedScroller(
        _ mounted: (view: BlockInputView, window: NSWindow),
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0), file: file, line: line)
        let scrollView = try XCTUnwrap(item.testingTextScrollView, file: file, line: line)
        let textView = try XCTUnwrap(item.testingTextView, file: file, line: line)

        XCTAssertLessThanOrEqual(mounted.view.collectionView.frame.width, mounted.view.scrollView.contentView.bounds.width + 0.5)
        XCTAssertGreaterThanOrEqual(scrollView.frame.minX, item.view.bounds.minX - 0.5, file: file, line: line)
        XCTAssertLessThanOrEqual(scrollView.frame.maxX, item.view.bounds.maxX + 0.5, file: file, line: line)
        XCTAssertGreaterThan(textView.frame.width, scrollView.contentView.bounds.width, file: file, line: line)
        XCTAssertEqual(mounted.view.scrollView.contentView.bounds.origin.x, 0, accuracy: 0.5, file: file, line: line)
    }

    private func assertTableKeepsHorizontalOverflowInsideNestedScroller(
        _ mounted: (view: BlockInputView, window: NSWindow),
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0), file: file, line: line)
        let tableView = item.testingTableView
        let overflowScrollView = item.testingTableOverflowScrollView

        XCTAssertLessThanOrEqual(mounted.view.collectionView.frame.width, mounted.view.scrollView.contentView.bounds.width + 0.5)
        XCTAssertGreaterThanOrEqual(tableView.frame.minX, item.view.bounds.minX - 0.5, file: file, line: line)
        XCTAssertLessThanOrEqual(tableView.frame.maxX, item.view.bounds.maxX + 0.5, file: file, line: line)
        XCTAssertGreaterThan(overflowScrollView.documentView?.frame.width ?? 0, overflowScrollView.contentView.bounds.width)
        XCTAssertEqual(overflowScrollView.contentView.bounds.origin.y, 0, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(mounted.view.scrollView.contentView.bounds.origin.x, 0, accuracy: 0.5, file: file, line: line)
    }

    private static let wrappingBlocks = [
        BlockInputBlock(id: "paragraph", kind: .paragraph, text: "Plain text"),
        BlockInputBlock(id: "heading", kind: .heading(level: 2), text: "Heading"),
        BlockInputBlock(id: "bullet", kind: .bulletedListItem, text: "Bullet"),
        BlockInputBlock(id: "checklist", kind: .checklistItem(isChecked: false), text: "Task"),
        BlockInputBlock(id: "quote", kind: .quote, text: "Quoted")
    ]

    private static let codeBlock = BlockInputBlock(
        id: "code",
        kind: .code(language: "swift"),
        text: "let veryLongIdentifierNameThatShouldOverflowHorizontally = 1"
    )

    private static let tableBlock = BlockInputBlock(
        id: "table",
        kind: .table,
        text: """
        | First column with a long heading | Second column with a long heading |
        | --- | --- |
        | First cell with long content | Second cell with long content |
        """
    )

    private func useLegacyDocumentScroller(_ mounted: (view: BlockInputView, window: NSWindow)) {
        mounted.view.scrollView.scrollerStyle = .legacy
        mounted.view.layoutSubtreeIfNeeded()
        mounted.view.scrollView.layoutSubtreeIfNeeded()
        mounted.view.collectionView.layoutSubtreeIfNeeded()
    }
}
