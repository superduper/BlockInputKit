import AppKit
import XCTest
@testable import BlockInputKit

/// Tests that verify the document scroll view stays in sync with the active cursor after
/// navigation and structural edits.  These cover the two core failure modes:
///
/// 1. **Cursor navigation**: pressing `moveDown` / `moveAfterCurrentBlock` past the bottom
///    of the visible viewport should scroll the outer document scroll view so the newly
///    active block is within the visible rect.
///
/// 2. **Block insertion at end of document**: inserting one or more blocks below the last
///    visible block must grow the scroll view's content size AND scroll to show the new
///    block.
@MainActor
final class BlockInputViewScrollVisibilityTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a mounted view with `count` short single-line paragraph blocks.
    /// The viewport height is intentionally small so that only the first few blocks fit.
    private func makeShortViewport(blockCount: Int, height: CGFloat = 160) -> (view: BlockInputView, window: NSWindow) {
        let blocks = (0..<blockCount).map { i in
            BlockInputBlock(id: .init(rawValue: "block-\(i)"), text: "Line \(i)")
        }
        let mounted = makeMountedBlockInputView(
            configuration: BlockInputConfiguration(document: BlockInputDocument(blocks: blocks)),
            size: NSSize(width: 400, height: height)
        )
        mounted.view.layoutSubtreeIfNeeded()
        mounted.view.collectionView.layoutSubtreeIfNeeded()
        return mounted
    }

    /// Returns the visible rect of the outer document scroll view in collection-view coordinates.
    private func visibleCollectionRect(_ view: BlockInputView) -> NSRect {
        view.scrollView.contentView.bounds
    }

    /// Returns the frame of a block item at `index` using layout attributes (works for off-screen items too).
    private func itemFrame(_ view: BlockInputView, at index: Int) -> NSRect? {
        let indexPath = IndexPath(item: index, section: 0)
        return view.collectionView.collectionViewLayout?
            .layoutAttributesForItem(at: indexPath)?.frame
    }

    private func makeBlockID(_ index: Int) -> BlockInputBlockID {
        .init(rawValue: "block-\(index)")
    }

    // MARK: - Content size grows after insertion

    func testScrollViewContentSizeGrowsAfterInsertingBlocksAtEnd() {
        let mounted = makeShortViewport(blockCount: 2, height: 240)
        let initialContentHeight = mounted.view.collectionView.frame.height
        let lastID = makeBlockID(1)

        // Insert 15 more blocks at end
        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: lastID, utf16Offset: 0)))
        for _ in 0..<15 {
            mounted.view.performCommand(.insertBlockBelow)
        }
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        let newContentHeight = mounted.view.collectionView.frame.height
        XCTAssertGreaterThan(
            newContentHeight,
            initialContentHeight,
            "content height must grow after inserting blocks at end of document"
        )
        XCTAssertGreaterThan(
            newContentHeight,
            mounted.view.scrollView.contentSize.height,
            "document must be taller than viewport after many insertions"
        )
    }

    // MARK: - insertBlockBelow scrolls to new block

    func testInsertBlockBelowScrollsViewportToNewBlock() {
        // Start with just 2 blocks in a small viewport, then insert many blocks at end.
        // The last inserted block should be visible in the scroll view.
        let mounted = makeShortViewport(blockCount: 2, height: 200)
        let lastID = makeBlockID(1)

        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: lastID, utf16Offset: 0)))

        // Insert 10 blocks below last block
        for _ in 0..<10 {
            mounted.view.performCommand(.insertBlockBelow)
        }
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        // Active block should be within the visible rect
        guard let activeBlockID = mounted.view.activeBlockID,
              let activeIndex = mounted.view.document.blocks.firstIndex(where: { $0.id == activeBlockID }),
              let frame = itemFrame(mounted.view, at: activeIndex) else {
            XCTFail("Active block item not mounted after insertBlockBelow")
            return
        }
        let visibleRect = visibleCollectionRect(mounted.view)
        XCTAssertTrue(
            frame.intersects(visibleRect),
            "active block (index \(activeIndex)) frame \(frame) must intersect visible rect \(visibleRect) after insertBlockBelow"
        )
    }

    // MARK: - insertBlockBelowWithContent scrolls to new block

    func testInsertBlockBelowWithContentScrollsViewportToNewBlock() {
        let loremIpsum = String(repeating: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ", count: 10)
        let mounted = makeShortViewport(blockCount: 3, height: 200)
        let lastID = makeBlockID(2)

        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: lastID, utf16Offset: 0)))

        // Simulate vim p: insert a large paragraph block at end
        for _ in 0..<3 {
            mounted.view.performCommand(.insertBlockBelowWithContent(kind: .paragraph, text: loremIpsum))
        }
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        guard let activeBlockID = mounted.view.activeBlockID,
              let activeIndex = mounted.view.document.blocks.firstIndex(where: { $0.id == activeBlockID }),
              let frame = itemFrame(mounted.view, at: activeIndex) else {
            XCTFail("Active block not mounted after insertBlockBelowWithContent")
            return
        }
        let visibleRect = visibleCollectionRect(mounted.view)
        XCTAssertTrue(
            frame.intersects(visibleRect),
            "active block (index \(activeIndex)) frame \(frame) must intersect visible rect \(visibleRect) after insertBlockBelowWithContent"
        )
    }

    // MARK: - insertMarkdown scrolls to inserted content

    func testInsertMarkdownAtEndScrollsViewportToNewBlocks() {
        let mounted = makeShortViewport(blockCount: 3, height: 200)
        let lastID = makeBlockID(2)
        let markdown = """
        # New Section

        First paragraph of the new section.

        Second paragraph with more content.

        ## Subsection

        Final paragraph here.
        """

        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: lastID, utf16Offset: 0)))
        mounted.view.insertMarkdown(markdown)
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        // Content size must grow to include new blocks
        let contentHeight = mounted.view.collectionView.frame.height
        XCTAssertGreaterThan(
            contentHeight,
            mounted.view.scrollView.contentSize.height,
            "content must overflow viewport after inserting markdown"
        )

        // Active block must be visible
        guard let activeBlockID = mounted.view.activeBlockID,
              let activeIndex = mounted.view.document.blocks.firstIndex(where: { $0.id == activeBlockID }),
              let frame = itemFrame(mounted.view, at: activeIndex) else {
            XCTFail("Active block not mounted after insertMarkdown")
            return
        }
        let visibleRect = visibleCollectionRect(mounted.view)
        XCTAssertTrue(
            frame.intersects(visibleRect),
            "active block (index \(activeIndex)) frame \(frame) must intersect visible rect \(visibleRect) after insertMarkdown"
        )
    }

    // MARK: - insertMarkdown replaces empty document and shows first block

    func testInsertMarkdownIntoEmptyDocumentShowsFirstBlock() {
        let mounted = makeMountedBlockInputView(
            configuration: BlockInputConfiguration(
                document: BlockInputDocument(blocks: [BlockInputBlock(id: .init(rawValue: "empty"), text: "")])
            ),
            size: NSSize(width: 400, height: 200)
        )
        mounted.view.layoutSubtreeIfNeeded()

        let markdown = "# Title\n\n" + (0..<12).map { "Paragraph \($0)." }.joined(separator: "\n\n")
        mounted.view.insertMarkdown(markdown)
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        guard let firstBlock = mounted.view.document.blocks.first else {
            XCTFail("Document must have blocks after markdown insertion")
            return
        }
        XCTAssertEqual(firstBlock.kind, .heading(level: 1), "first inserted block must be h1")
        // First block's layout frame must be within the visible rect (scroll view at top).
        if let frame = itemFrame(mounted.view, at: 0) {
            let visibleRect = visibleCollectionRect(mounted.view)
            XCTAssertTrue(
                frame.intersects(visibleRect),
                "first block frame \(frame) must intersect visible rect \(visibleRect)"
            )
        }
    }

    // MARK: - moveAfterCurrentBlock scrolls off-screen block into view

    func testMoveAfterCurrentBlockScrollsIntoViewWhenTargetIsOffScreen() {
        // Create a tall document where block 0 is visible and block 8 is off-screen.
        let mounted = makeShortViewport(blockCount: 12, height: 160)
        let firstID = makeBlockID(0)

        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: firstID, utf16Offset: 0)))
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        // Confirm block 8 is initially off-screen (below visible area).
        mounted.view.collectionView.layoutSubtreeIfNeeded()
        let indexPath8 = IndexPath(item: 8, section: 0)
        let block8ItemBefore = mounted.view.collectionView.item(at: indexPath8) as? BlockInputBlockItem
        let visibleBefore = visibleCollectionRect(mounted.view)
        if let frame8 = block8ItemBefore?.view.frame {
            XCTAssertFalse(
                frame8.intersects(visibleBefore),
                "block 8 (frame \(frame8)) should be off-screen initially (visible rect \(visibleBefore))"
            )
        }

        // Move forward to block 8 using moveAfterCurrentBlock
        for _ in 0..<8 {
            mounted.view.performCommand(.moveAfterCurrentBlock)
        }
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        guard let activeBlockID = mounted.view.activeBlockID,
              let activeIndex = mounted.view.document.blocks.firstIndex(where: { $0.id == activeBlockID }),
              let frame = itemFrame(mounted.view, at: activeIndex) else {
            XCTFail("Active block not mounted after 8× moveAfterCurrentBlock")
            return
        }
        let visibleRect = visibleCollectionRect(mounted.view)
        XCTAssertTrue(
            frame.intersects(visibleRect),
            "block \(activeIndex) frame \(frame) must be within visible rect \(visibleRect) after moveAfterCurrentBlock"
        )
    }

    // MARK: - insertLineBreak stays within block

    func testInsertLineBreakInsertsNewlineWithinBlock() {
        let blockID = BlockInputBlockID(rawValue: "para")
        let mounted = makeMountedBlockInputView(
            configuration: BlockInputConfiguration(document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "Hello world")
            ])),
            size: NSSize(width: 400, height: 400)
        )
        mounted.view.layoutSubtreeIfNeeded()
        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 5)))

        // Move to line end then insert literal newline — same as vim o
        mounted.view.performCommand(.moveToLineEnd)
        mounted.view.performCommand(.insertLineBreak)
        mounted.view.layoutSubtreeIfNeeded()

        // Should still be ONE block (not split into two)
        XCTAssertEqual(mounted.view.document.blocks.count, 1, "insertLineBreak must not split the block")
        // The block now contains a newline
        let text = mounted.view.document.blocks[0].text
        XCTAssertTrue(text.contains("\n"), "block text must contain a literal newline after insertLineBreak: '\(text)'")
    }

    // MARK: - moveDown exits multiline wrapped paragraph

    /// Reproduces: pressing `j` (moveDown) inside a paragraph that wraps over multiple
    /// visual lines (due to narrow viewport width, with NO literal newlines) never exits
    /// that block — the cursor stays in block 0 forever.
    ///
    /// - **Bug present**: after 20× moveDown the active block is still block 0.
    /// - **Bug fixed**: the active block has advanced to block 1 (or beyond).
    func testMoveDownCanExitMultilineWrappedParagraph() {
        // A long single-line paragraph (no \n) that wraps to 3+ visual lines at 200px wide.
        let longParagraph = "Lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua ut enim ad minim veniam quis nostrud exercitation ullamco laboris"
        let block0ID = BlockInputBlockID(rawValue: "wrapped-para")
        let block1ID = BlockInputBlockID(rawValue: "next-block")
        let blocks = [
            BlockInputBlock(id: block0ID, text: longParagraph),
            BlockInputBlock(id: block1ID, text: "Second block"),
        ]
        let mounted = makeMountedBlockInputView(
            configuration: BlockInputConfiguration(document: BlockInputDocument(blocks: blocks)),
            size: NSSize(width: 200, height: 600)
        )
        mounted.view.layoutSubtreeIfNeeded()
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        // Place cursor at the start of the first (wrapping) block.
        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: block0ID, utf16Offset: 0)))

        // Press moveDown 20 times — far more than the number of visual wrap lines.
        for _ in 0..<20 {
            mounted.view.performCommand(.moveDown)
        }
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        // Extract the active block ID from the current selection.
        func activeBlockIDFromSelection(_ view: BlockInputView) -> BlockInputBlockID? {
            switch view.selection {
            case let .cursor(c): return c.blockID
            case let .text(r): return r.blockID
            case let .blocks(ids): return ids.first
            default: return nil
            }
        }

        let activeID = activeBlockIDFromSelection(mounted.view)

        // The active block must have moved out of block 0; if it has not, the bug is present.
        XCTAssertNotEqual(
            activeID,
            block0ID,
            "After 20× moveDown the cursor must have exited the wrapped paragraph (block 0) and moved to block 1 or beyond. If this fails the bug is present: moveDown never exits a multiline-wrapped paragraph."
        )
    }

    // MARK: - insertBlockBelow below image block

    func testInsertBlockBelowImageBlockInsertsAfterIt() {
        let imageID = BlockInputBlockID(rawValue: "img")
        let afterID = BlockInputBlockID(rawValue: "after")
        let blocks: [BlockInputBlock] = [
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/img.png"))),
            BlockInputBlock(id: afterID, text: "After image")
        ]
        let mounted = makeMountedBlockInputView(
            configuration: BlockInputConfiguration(document: BlockInputDocument(blocks: blocks)),
            size: NSSize(width: 400, height: 600)
        )
        mounted.view.layoutSubtreeIfNeeded()

        // Select the image block (simulating vim j into image → block-select)
        mounted.view.applySelectionForTesting(.blocks([imageID]))

        // o = insert block below current
        mounted.view.performCommand(.insertBlockBelowWithContent(kind: .paragraph, text: ""))
        mounted.view.layoutSubtreeIfNeeded()

        let doc = mounted.view.document
        XCTAssertEqual(doc.blocks.count, 3, "inserting below image should add one block")
        XCTAssertEqual(doc.blocks[0].id, imageID, "image must remain first")
        let newBlock = doc.blocks[1]
        XCTAssertEqual(newBlock.kind, .paragraph, "new block must be a paragraph")
        XCTAssertTrue(newBlock.text.isEmpty, "new block must be empty")
        XCTAssertEqual(doc.blocks[2].id, afterID, "original second block must remain last")
    }

    // MARK: - insertMarkdown creates multiple blocks from multi-paragraph text

    func testInsertMarkdownSplitsFiveParagraphsIntoFiveBlocks() {
        let paragraphs = (1...5).map { "Paragraph \($0) lorem ipsum dolor sit amet consectetur." }
        let markdown = paragraphs.joined(separator: "\n\n")

        let mounted = makeMountedBlockInputView(
            configuration: BlockInputConfiguration(document: BlockInputDocument(blocks: [
                BlockInputBlock(id: .init(rawValue: "seed"), text: "")
            ])),
            size: NSSize(width: 600, height: 800)
        )
        mounted.view.layoutSubtreeIfNeeded()

        mounted.view.insertMarkdown(markdown)
        mounted.view.layoutSubtreeIfNeeded()

        let paragraphBlocks = mounted.view.document.blocks.filter { $0.kind == .paragraph }
        XCTAssertEqual(
            paragraphBlocks.count,
            5,
            "inserting 5 \\n\\n-separated paragraphs must produce 5 paragraph blocks, got: \(mounted.view.document.blocks.map { "\($0.kind): \($0.text.prefix(20))" })"
        )
    }

    // MARK: - moveDown scrolls viewport after successive presses

    func testMoveDownScrollsDocumentViewportAfterCrossingMultipleBlocks() {
        let mounted = makeShortViewport(blockCount: 20, height: 160)
        let firstID = makeBlockID(0)

        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: firstID, utf16Offset: 0)))
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        let initialScrollY = visibleCollectionRect(mounted.view).minY

        // Press moveDown enough times to cross into blocks that were off-screen.
        // With ~160px height and ~30px/block, about 5 blocks fit; 15 presses should scroll.
        for _ in 0..<15 {
            mounted.view.performCommand(.moveDown)
        }
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        let finalScrollY = visibleCollectionRect(mounted.view).minY
        XCTAssertGreaterThan(
            finalScrollY,
            initialScrollY,
            "scroll origin must advance after 15× moveDown on a document taller than viewport"
        )

        // Active block must still be within the visible rect.
        guard let activeBlockID = mounted.view.activeBlockID,
              let activeIndex = mounted.view.document.blocks.firstIndex(where: { $0.id == activeBlockID }),
              let frame = itemFrame(mounted.view, at: activeIndex) else {
            return
        }
        let visibleRect = visibleCollectionRect(mounted.view)
        XCTAssertTrue(
            frame.intersects(visibleRect),
            "active block frame \(frame) must be within visible rect \(visibleRect) after moveDown scrolling"
        )
    }
}
