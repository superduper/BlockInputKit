import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewReorderingTests: XCTestCase {
    func testCollectionDropTargetAdjustsForwardMovesToFinalDocumentIndex() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let view = configuredReorderView(blockIDs: [firstID, secondID, thirdID])

        let targetIndex = view.collectionDropTargetIndex(
            forBlockID: firstID,
            proposedItemIndex: 2
        )

        XCTAssertEqual(targetIndex, 1)
    }

    func testCollectionDropTargetKeepsBackwardMovesAtProposedIndex() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let view = configuredReorderView(blockIDs: [firstID, secondID, thirdID])

        let targetIndex = view.collectionDropTargetIndex(
            forBlockID: thirdID,
            proposedItemIndex: 0
        )

        XCTAssertEqual(targetIndex, 0)
    }

    func testCollectionDropTargetSupportsDroppingAtEnd() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let view = configuredReorderView(blockIDs: [firstID, secondID, thirdID])

        let targetIndex = view.collectionDropTargetIndex(
            forBlockID: firstID,
            proposedItemIndex: 3
        )

        XCTAssertEqual(targetIndex, 2)
    }

    func testPasteboardWriterIsDisabledWhenReorderingIsDisabled() {
        let blockID = BlockInputBlockID(rawValue: "first")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "First")
            ]),
            allowsBlockReordering: false
        ))

        let writer = view.collectionView(
            view.collectionView,
            pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)
        )

        XCTAssertNil(writer)
    }

    func testPasteboardWriterStoresBlockIDWhenReorderingIsEnabled() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let view = configuredReorderView(blockIDs: [blockID])

        let writer = try XCTUnwrap(view.collectionView(
            view.collectionView,
            pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)
        ) as? NSPasteboardItem)

        XCTAssertEqual(writer.string(forType: .blockInputBlockID), blockID.rawValue)
    }

    func testPasteboardWriterIsDisabledForFrontMatter() {
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: "front", kind: .frontMatter, text: "title: Demo"),
            BlockInputBlock(id: "body", text: "Body")
        ])))

        let writer = view.collectionView(
            view.collectionView,
            pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)
        )

        XCTAssertNil(writer)
    }

    func testHoveringReorderHandleHidesOtherVisibleHandles() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "first", text: "First"),
            BlockInputBlock(id: "second", text: "Second")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let firstHandle = try XCTUnwrap(firstItem.testingHandleView)
        let secondHandle = try XCTUnwrap(secondItem.testingHandleView)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: mounted.window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        ))

        firstItem.mouseEntered(with: event)
        firstItem.setReorderHandleVisible(true, animated: false)
        secondItem.mouseEntered(with: event)
        secondItem.setReorderHandleVisible(true, animated: false)

        XCTAssertEqual(firstHandle.alphaValue, 0)
        XCTAssertEqual(secondHandle.alphaValue, 1)
    }

    func testHidingReorderHandleCancelsPendingFadeIn() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "first", text: "First")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let handle = try XCTUnwrap(item.testingHandleView)

        item.setReorderHandleVisible(true)
        item.setReorderHandleVisible(false, animated: false)

        XCTAssertEqual(handle.alphaValue, 0)
        XCTAssertEqual(handle.layer?.animationKeys() ?? [], [])
    }

    func testCanAcceptBlockReorderDropAcceptsKnownBlockID() {
        let blockID = BlockInputBlockID(rawValue: "first")
        let view = configuredReorderView(blockIDs: [blockID])

        XCTAssertTrue(view.canAcceptBlockReorderDrop(BlockInputDraggingInfo(blockID: blockID)))
    }

    func testCanAcceptBlockReorderDropRejectsDisabledReordering() {
        let blockID = BlockInputBlockID(rawValue: "first")
        let view = configuredReorderView(
            blockIDs: [blockID],
            allowsBlockReordering: false
        )

        XCTAssertFalse(view.canAcceptBlockReorderDrop(BlockInputDraggingInfo(blockID: blockID)))
    }

    func testCanAcceptBlockReorderDropRejectsUnknownBlockID() {
        let view = configuredReorderView(blockIDs: ["first"])

        XCTAssertFalse(view.canAcceptBlockReorderDrop(BlockInputDraggingInfo(blockID: "missing")))
    }

    func testCanAcceptBlockReorderDropRejectsFrontMatterBlockID() {
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: "front", kind: .frontMatter, text: "title: Demo"),
            BlockInputBlock(id: "body", text: "Body")
        ])))

        XCTAssertFalse(view.canAcceptBlockReorderDrop(BlockInputDraggingInfo(blockID: "front")))
    }

    func testCanAcceptBlockReorderDropRejectsMissingBlockID() {
        let view = configuredReorderView(blockIDs: ["first"])

        XCTAssertFalse(view.canAcceptBlockReorderDrop(BlockInputDraggingInfo(blockID: nil)))
    }

    func testCollectionValidateDropRejectsFileURLsWhenReorderingIsDisabled() {
        let view = configuredReorderView(
            blockIDs: ["first"],
            allowsBlockReordering: false
        )
        let draggingInfo = BlockInputDraggingInfo(fileURLs: [
            URL(fileURLWithPath: "/tmp/example.txt")
        ])
        var indexPath = NSIndexPath(forItem: 0, inSection: 0)
        var operation = NSCollectionView.DropOperation.on

        let dragOperation = withUnsafeMutablePointer(to: &indexPath) { pointer in
            view.collectionView(
                view.collectionView,
                validateDrop: draggingInfo,
                proposedIndexPath: AutoreleasingUnsafeMutablePointer(pointer),
                dropOperation: &operation
            )
        }

        XCTAssertTrue(dragOperation.isEmpty)
        XCTAssertEqual(operation, .on)
    }

    func testValidateDropRejectsRemoteURLs() throws {
        let view = configuredReorderView(blockIDs: ["first"])
        let remoteURL = try XCTUnwrap(URL(string: "https://example.com/file.txt"))
        var indexPath = NSIndexPath(forItem: 0, inSection: 0)
        var operation = NSCollectionView.DropOperation.on

        let dragOperation = withUnsafeMutablePointer(to: &indexPath) { pointer in
            view.collectionView(
                view.collectionView,
                validateDrop: BlockInputDraggingInfo(fileURLs: [remoteURL]),
                proposedIndexPath: AutoreleasingUnsafeMutablePointer(pointer),
                dropOperation: &operation
            )
        }

        XCTAssertTrue(dragOperation.isEmpty)
    }

    func testAcceptDropMovesBlockAndPublishesDocumentChange() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        var publishedDocuments: [BlockInputDocument] = []
        let view = configuredReorderView(
            blockIDs: [firstID, secondID, thirdID],
            onDocumentChange: { publishedDocuments.append($0) }
        )
        let draggingInfo = BlockInputDraggingInfo(blockID: firstID)

        let accepted = view.collectionView(
            view.collectionView,
            acceptDrop: draggingInfo,
            indexPath: IndexPath(item: 2, section: 0),
            dropOperation: .before
        )

        XCTAssertTrue(accepted)
        XCTAssertEqual(view.document.blocks.map(\.id), [secondID, firstID, thirdID])
        XCTAssertEqual(publishedDocuments.last, view.document)
    }

    func testCollectionAcceptDropRejectsFileURLs() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        var publishedDocuments: [BlockInputDocument] = []
        let view = configuredReorderView(
            blockIDs: [firstID, secondID],
            allowsBlockReordering: false,
            onDocumentChange: { publishedDocuments.append($0) }
        )

        let accepted = view.collectionView(
            view.collectionView,
            acceptDrop: BlockInputDraggingInfo(fileURLs: [
                URL(fileURLWithPath: "/tmp/example.txt")
            ]),
            indexPath: IndexPath(item: 1, section: 0),
            dropOperation: .before
        )

        XCTAssertFalse(accepted)
        XCTAssertEqual(view.document.blocks.map(\.text), [
            "first",
            "second"
        ])
        XCTAssertTrue(publishedDocuments.isEmpty)
    }

    func testCollectionAcceptFileDropDoesNotPublishGranularInsertionToStore() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ]))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            documentStore: store,
            allowsBlockReordering: false
        ))
        store.resetCounts()

        let accepted = view.collectionView(
            view.collectionView,
            acceptDrop: BlockInputDraggingInfo(fileURLs: [
                URL(fileURLWithPath: "/tmp/example.txt")
            ]),
            indexPath: IndexPath(item: 1, section: 0),
            dropOperation: .before
        )

        XCTAssertFalse(accepted)
        XCTAssertEqual(store.document.blocks.map(\.text), [
            "First",
            "Second"
        ])
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertTrue(store.insertedBlockBatches.isEmpty)
    }

    func testAcceptDropRefreshesFromConfiguredStoreBeforeMovingBlock() {
        let staleID = BlockInputBlockID(rawValue: "stale")
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: staleID, text: "Old")
        ]))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store))
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ]))
        store.resetCounts()

        let accepted = view.collectionView(
            view.collectionView,
            acceptDrop: BlockInputDraggingInfo(blockID: firstID),
            indexPath: IndexPath(item: 2, section: 0),
            dropOperation: .before
        )

        XCTAssertTrue(accepted)
        XCTAssertEqual(store.document.blocks.map(\.id), [secondID, firstID])
        XCTAssertEqual(view.document.blocks.map(\.id), [secondID, firstID])
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.movedBlocks.map(\.id), [firstID])
        XCTAssertEqual(store.movedBlocks.map(\.index), [1])
    }

    func testMoveBlockPublishesClampedFinalIndexToStore() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ]))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store))
        store.resetCounts()

        _ = view.moveBlock(blockID: firstID, to: 99)

        XCTAssertEqual(store.document.blocks.map(\.id), [secondID, thirdID, firstID])
        XCTAssertEqual(view.document.blocks.map(\.id), [secondID, thirdID, firstID])
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.movedBlocks.map(\.id), [firstID])
        XCTAssertEqual(store.movedBlocks.map(\.index), [2])
    }

    func testAcceptDropReturnsFalseWhenReorderingIsDisabled() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let view = configuredReorderView(
            blockIDs: [firstID, secondID],
            allowsBlockReordering: false
        )
        let draggingInfo = BlockInputDraggingInfo(blockID: firstID)

        let accepted = view.collectionView(
            view.collectionView,
            acceptDrop: draggingInfo,
            indexPath: IndexPath(item: 1, section: 0),
            dropOperation: .before
        )

        XCTAssertFalse(accepted)
        XCTAssertEqual(view.document.blocks.map(\.id), [firstID, secondID])
    }

    func testAcceptDropReturnsFalseForUnknownBlockID() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let view = configuredReorderView(blockIDs: [firstID, secondID])
        let draggingInfo = BlockInputDraggingInfo(blockID: "missing")

        let accepted = view.collectionView(
            view.collectionView,
            acceptDrop: draggingInfo,
            indexPath: IndexPath(item: 1, section: 0),
            dropOperation: .before
        )

        XCTAssertFalse(accepted)
        XCTAssertEqual(view.document.blocks.map(\.id), [firstID, secondID])
    }

    private func configuredReorderView(blockIDs: [BlockInputBlockID]) -> BlockInputView {
        configuredReorderView(blockIDs: blockIDs, allowsBlockReordering: true)
    }

    private func configuredReorderView(
        blockIDs: [BlockInputBlockID],
        allowsBlockReordering: Bool = true,
        onDocumentChange: ((BlockInputDocument) -> Void)? = nil
    ) -> BlockInputView {
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: blockIDs.map { blockID in
                BlockInputBlock(id: blockID, text: blockID.rawValue)
            }),
            allowsBlockReordering: allowsBlockReordering,
            onDocumentChange: onDocumentChange
        ))
        return view
    }
}
