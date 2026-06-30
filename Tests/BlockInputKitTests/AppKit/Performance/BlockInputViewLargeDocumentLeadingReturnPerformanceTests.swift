import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class LargeLeadingReturnPerformanceTests: XCTestCase {
    func testStoreBackedReturnAtFrontOfLargeNumberedListRenumbersFollowingBlocksWithoutSnapshot() throws {
        let targetIndex = largeDocumentCacheMutationLimit + 2
        let count = largeDocumentCacheMutationLimit + 5
        let blockID = BlockInputBlockID(rawValue: "number-\(targetIndex)")
        let store = DocumentReadCountingStore(document: largeNumberedListDocument(count: count))
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        var mutations: [BlockInputDocumentChange] = []
        view.configure(BlockInputConfiguration(
            documentStore: store,
            undoController: BlockInputUndoController(),
            onDocumentMutation: { mutations.append($0) }
        ))
        view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)), notify: false)
        store.resetCounts()

        _ = view.insertBlockBelowCurrentBlock()

        let insertedBlock = try XCTUnwrap(store.insertedBlockBatches.first?.blocks.first)
        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replacedBlockIDs, [blockID])
        XCTAssertEqual(store.markerTransactions.count, 1)
        XCTAssertEqual(mutations.count, 3)
        XCTAssertEqual(mutations.last, .numberedListMarkersChanged(store.markerTransactions[0]))
        XCTAssertEqual(store.insertedBlockBatches.first?.index, targetIndex + 1)
        XCTAssertEqual(store.block(at: targetIndex)?.kind, .numberedListItem(start: targetIndex + 1))
        XCTAssertEqual(store.block(at: targetIndex + 1)?.kind, .numberedListItem(start: targetIndex + 2))
        XCTAssertEqual(store.block(at: targetIndex + 2)?.kind, .numberedListItem(start: targetIndex + 3))
        XCTAssertEqual(store.block(at: targetIndex + 3)?.kind, .numberedListItem(start: targetIndex + 4))

        store.resetCounts()
        _ = view.undoStructuralEdit()

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replacedBlockIDs, [blockID])
        XCTAssertEqual(store.markerTransactions.count, 1)
        XCTAssertEqual(store.deletedBlockIDs, [[insertedBlock.id]])
        XCTAssertEqual(store.block(at: targetIndex)?.kind, .numberedListItem(start: targetIndex + 1))
        XCTAssertEqual(store.block(at: targetIndex + 1)?.kind, .numberedListItem(start: targetIndex + 2))
        XCTAssertEqual(store.block(at: targetIndex + 2)?.kind, .numberedListItem(start: targetIndex + 3))

        store.resetCounts()
        _ = view.redoStructuralEdit()

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replacedBlockIDs, [blockID])
        XCTAssertEqual(store.markerTransactions.count, 1)
        XCTAssertEqual(store.insertedBlockBatches.first?.index, targetIndex + 1)
        XCTAssertEqual(store.block(at: targetIndex + 1)?.id, insertedBlock.id)
        XCTAssertEqual(store.block(at: targetIndex + 3)?.kind, .numberedListItem(start: targetIndex + 4))
    }

    func testStoreBackedReturnAtEndOfLargeNumberedListRenumbersFollowingBlocksWithoutSnapshot() throws {
        let targetIndex = largeDocumentCacheMutationLimit + 2
        let count = largeDocumentCacheMutationLimit + 5
        let blockID = BlockInputBlockID(rawValue: "number-\(targetIndex)")
        let store = DocumentReadCountingStore(document: largeNumberedListDocument(count: count))
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        var mutations: [BlockInputDocumentChange] = []
        view.configure(BlockInputConfiguration(
            documentStore: store,
            undoController: BlockInputUndoController(),
            onDocumentMutation: { mutations.append($0) }
        ))
        view.applySelection(.cursor(BlockInputCursor(
            blockID: blockID,
            utf16Offset: ("Number \(targetIndex)" as NSString).length
        )), notify: false)
        store.resetCounts()

        _ = view.insertBlockBelowCurrentBlock()

        let insertedBlock = try XCTUnwrap(store.insertedBlockBatches.first?.blocks.first)
        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replacedBlockIDs, [])
        XCTAssertEqual(store.markerTransactions.count, 1)
        XCTAssertEqual(mutations.count, 2)
        XCTAssertEqual(mutations.last, .numberedListMarkersChanged(store.markerTransactions[0]))
        XCTAssertEqual(store.insertedBlockBatches.first?.index, targetIndex + 1)
        XCTAssertEqual(store.block(at: targetIndex)?.kind, .numberedListItem(start: targetIndex + 1))
        XCTAssertEqual(store.block(at: targetIndex + 1)?.id, insertedBlock.id)
        XCTAssertEqual(store.block(at: targetIndex + 1)?.kind, .numberedListItem(start: targetIndex + 2))
        XCTAssertEqual(store.block(at: targetIndex + 2)?.kind, .numberedListItem(start: targetIndex + 3))

        store.resetCounts()
        _ = view.undoStructuralEdit()

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.markerTransactions.count, 1)
        XCTAssertEqual(store.deletedBlockIDs, [[insertedBlock.id]])
        XCTAssertEqual(store.block(at: targetIndex + 1)?.kind, .numberedListItem(start: targetIndex + 2))

        store.resetCounts()
        _ = view.redoStructuralEdit()

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.markerTransactions.count, 1)
        XCTAssertEqual(store.insertedBlockBatches.first?.index, targetIndex + 1)
        XCTAssertEqual(store.block(at: targetIndex + 1)?.id, insertedBlock.id)
        XCTAssertEqual(store.block(at: targetIndex + 2)?.kind, .numberedListItem(start: targetIndex + 3))
    }

    func testStoreBackedReturnAtEndOfLargeNumberedListRenumbersNonMarkerStoreWithoutSnapshot() throws {
        let targetIndex = largeDocumentCacheMutationLimit + 2
        let count = largeDocumentCacheMutationLimit + 5
        let blockID = BlockInputBlockID(rawValue: "number-\(targetIndex)")
        let store = NonMarkerDocumentReadCountingStore(document: largeNumberedListDocument(count: count))
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        view.configure(BlockInputConfiguration(
            documentStore: store,
            undoController: BlockInputUndoController()
        ))
        view.applySelection(.cursor(BlockInputCursor(
            blockID: blockID,
            utf16Offset: ("Number \(targetIndex)" as NSString).length
        )), notify: false)
        store.resetCounts()

        let selection = view.insertBlockBelowCurrentBlock()

        let insertedBlock = try XCTUnwrap(store.insertedBlockBatches.first?.blocks.first)
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: insertedBlock.id, utf16Offset: 0)))
        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.insertedBlockBatches.first?.index, targetIndex + 1)
        XCTAssertEqual(store.replacedBlockIDs, [
            BlockInputBlockID(rawValue: "number-\(targetIndex + 1)"),
            BlockInputBlockID(rawValue: "number-\(targetIndex + 2)")
        ])
        XCTAssertEqual(store.block(at: targetIndex + 1)?.id, insertedBlock.id)
        XCTAssertEqual(store.block(at: targetIndex + 1)?.kind, .numberedListItem(start: targetIndex + 2))
        XCTAssertEqual(store.block(at: targetIndex + 2)?.kind, .numberedListItem(start: targetIndex + 3))

        store.resetCounts()
        _ = view.undoStructuralEdit()

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.deletedBlockIDs, [[insertedBlock.id]])
        XCTAssertEqual(store.block(at: targetIndex + 1)?.kind, .numberedListItem(start: targetIndex + 2))

        store.resetCounts()
        _ = view.redoStructuralEdit()

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.insertedBlockBatches.first?.index, targetIndex + 1)
        XCTAssertEqual(store.block(at: targetIndex + 1)?.id, insertedBlock.id)
        XCTAssertEqual(store.block(at: targetIndex + 2)?.kind, .numberedListItem(start: targetIndex + 3))
    }

    func testStoreBackedReturnAtFrontOfNestedNumberedListUsesParentSeedWithoutSnapshot() throws {
        let parentIndex = largeDocumentCacheMutationLimit + 1
        let targetIndex = parentIndex + 3
        let targetID = BlockInputBlockID(rawValue: "number-\(targetIndex)")
        let store = DocumentReadCountingStore(document: largeNestedNumberedListDocument(parentIndex: parentIndex))
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        view.configure(BlockInputConfiguration(documentStore: store))
        view.applySelection(.cursor(BlockInputCursor(blockID: targetID, utf16Offset: 0)), notify: false)
        store.resetCounts()

        _ = view.insertBlockBelowCurrentBlock()

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replacedBlockIDs, [targetID])
        XCTAssertEqual(store.markerTransactions.count, 1)
        XCTAssertEqual(store.block(at: targetIndex)?.kind, .numberedListItem(start: 2))
        XCTAssertEqual(store.block(at: targetIndex + 1)?.kind, .numberedListItem(start: 3))
        XCTAssertEqual(store.block(at: targetIndex + 2)?.kind, .numberedListItem(start: 4))
    }

    func testStoreBackedReturnAtFrontOfNestedNumberedListDoesNotRenumberNextParentChild() throws {
        let parentIndex = largeDocumentCacheMutationLimit + 1
        let targetIndex = parentIndex + 1
        let targetID = BlockInputBlockID(rawValue: "number-\(targetIndex)")
        let nextParentChildID = BlockInputBlockID(rawValue: "number-\(targetIndex + 3)")
        let store = DocumentReadCountingStore(document: nestedNumberedListWithFollowingParentDocument(parentIndex: parentIndex))
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        view.configure(BlockInputConfiguration(documentStore: store))
        view.applySelection(.cursor(BlockInputCursor(blockID: targetID, utf16Offset: 0)), notify: false)
        store.resetCounts()

        _ = view.insertBlockBelowCurrentBlock()

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replacedBlockIDs, [targetID])
        XCTAssertEqual(store.markerTransactions.count, 1)
        XCTAssertEqual(store.block(at: targetIndex)?.kind, .numberedListItem(start: 1))
        XCTAssertEqual(store.block(at: targetIndex + 1)?.kind, .numberedListItem(start: 2))
        XCTAssertEqual(store.block(at: targetIndex + 2)?.kind, .numberedListItem(start: 3))
        XCTAssertEqual(store.block(withID: nextParentChildID)?.kind, .numberedListItem(start: 1))
    }

    func testStoreBackedReturnAtFrontOfNumberedListDoesNotRenumberSeparateFollowingList() throws {
        let targetIndex = largeDocumentCacheMutationLimit + 2
        let targetID = BlockInputBlockID(rawValue: "number-\(targetIndex)")
        let separateListID = BlockInputBlockID(rawValue: "separate-list")
        let store = DocumentReadCountingStore(document: separatedNumberedListDocument(targetIndex: targetIndex))
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        view.configure(BlockInputConfiguration(documentStore: store))
        view.applySelection(.cursor(BlockInputCursor(blockID: targetID, utf16Offset: 0)), notify: false)
        store.resetCounts()

        _ = view.insertBlockBelowCurrentBlock()

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.markerTransactions.count, 1)
        XCTAssertEqual(store.block(at: targetIndex)?.kind, .numberedListItem(start: 1))
        XCTAssertEqual(store.block(at: targetIndex + 1)?.kind, .numberedListItem(start: 2))
        XCTAssertEqual(store.block(at: targetIndex + 2)?.kind, .numberedListItem(start: 3))
        XCTAssertEqual(store.block(withID: separateListID)?.kind, .numberedListItem(start: 1))
    }

    private func largeNumberedListDocument(count: Int) -> BlockInputDocument {
        BlockInputDocument(blocks: (0..<count).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "number-\(index)"),
                kind: .numberedListItem(start: index + 1),
                text: "Number \(index)"
            )
        })
    }

    private func largeNestedNumberedListDocument(parentIndex: Int) -> BlockInputDocument {
        let count = parentIndex + 6
        return BlockInputDocument(blocks: (0..<count).map { index in
            let id = BlockInputBlockID(rawValue: "number-\(index)")
            switch index {
            case parentIndex:
                return BlockInputBlock(id: id, kind: .numberedListItem(start: 1), text: "Parent")
            case parentIndex + 1:
                return BlockInputBlock(id: id, kind: .numberedListItem(start: 1), text: "First child", indentationLevel: 1)
            case parentIndex + 2:
                return BlockInputBlock(id: id, kind: .numberedListItem(start: 1), text: "Grandchild", indentationLevel: 2)
            case parentIndex + 3:
                return BlockInputBlock(id: id, kind: .numberedListItem(start: 2), text: "Second child", indentationLevel: 1)
            case parentIndex + 4:
                return BlockInputBlock(id: id, kind: .numberedListItem(start: 3), text: "Third child", indentationLevel: 1)
            default:
                return BlockInputBlock(id: id, text: "Block \(index)")
            }
        })
    }

    private func nestedNumberedListWithFollowingParentDocument(parentIndex: Int) -> BlockInputDocument {
        let count = parentIndex + 5
        return BlockInputDocument(blocks: (0..<count).map { index in
            let id = BlockInputBlockID(rawValue: "number-\(index)")
            switch index {
            case parentIndex:
                return BlockInputBlock(id: id, kind: .numberedListItem(start: 1), text: "Parent one")
            case parentIndex + 1:
                return BlockInputBlock(id: id, kind: .numberedListItem(start: 1), text: "First child", indentationLevel: 1)
            case parentIndex + 2:
                return BlockInputBlock(id: id, kind: .numberedListItem(start: 2), text: "Second child", indentationLevel: 1)
            case parentIndex + 3:
                return BlockInputBlock(id: id, kind: .numberedListItem(start: 2), text: "Parent two")
            case parentIndex + 4:
                return BlockInputBlock(id: id, kind: .numberedListItem(start: 1), text: "Other child", indentationLevel: 1)
            default:
                return BlockInputBlock(id: id, text: "Block \(index)")
            }
        })
    }

    private func separatedNumberedListDocument(targetIndex: Int) -> BlockInputDocument {
        let count = targetIndex + 5
        return BlockInputDocument(blocks: (0..<count).map { index in
            switch index {
            case targetIndex:
                return BlockInputBlock(
                    id: BlockInputBlockID(rawValue: "number-\(index)"),
                    kind: .numberedListItem(start: 1),
                    text: "First"
                )
            case targetIndex + 1:
                return BlockInputBlock(
                    id: BlockInputBlockID(rawValue: "number-\(index)"),
                    kind: .numberedListItem(start: 2),
                    text: "Second"
                )
            case targetIndex + 3:
                return BlockInputBlock(
                    id: BlockInputBlockID(rawValue: "separate-list"),
                    kind: .numberedListItem(start: 1),
                    text: "Separate"
                )
            default:
                return BlockInputBlock(id: BlockInputBlockID(rawValue: "text-\(index)"), text: "Block \(index)")
            }
        })
    }
}

private final class NonMarkerDocumentReadCountingStore: BlockInputDocumentStore {
    private var storedDocument: BlockInputDocument
    private(set) var documentReadCount = 0
    private(set) var replaceDocumentCount = 0
    private(set) var replacedBlockIDs: [BlockInputBlockID] = []
    private(set) var insertedBlockBatches: [(blocks: [BlockInputBlock], index: Int)] = []
    private(set) var deletedBlockIDs: [[BlockInputBlockID]] = []

    var loadedBlockCount: Int {
        storedDocument.blocks.count
    }

    init(document: BlockInputDocument) {
        storedDocument = document
    }

    func resetCounts() {
        documentReadCount = 0
        replaceDocumentCount = 0
        replacedBlockIDs = []
        insertedBlockBatches = []
        deletedBlockIDs = []
    }

    func block(at index: Int) -> BlockInputBlock? {
        guard storedDocument.blocks.indices.contains(index) else {
            return nil
        }
        return storedDocument.blocks[index]
    }

    func block(withID id: BlockInputBlockID) -> BlockInputBlock? {
        storedDocument.block(withID: id)
    }

    func index(of id: BlockInputBlockID) -> Int? {
        storedDocument.index(of: id)
    }

    @MainActor
    func completeDocumentSnapshot(limit: Int) async throws -> BlockInputDocument {
        documentReadCount += 1
        return storedDocument
    }

    func replaceDocument(_ document: BlockInputDocument) {
        replaceDocumentCount += 1
        storedDocument = document
    }

    func replaceBlock(_ block: BlockInputBlock) {
        replacedBlockIDs.append(block.id)
        guard let index = storedDocument.index(of: block.id) else {
            return
        }
        storedDocument.blocks[index] = block
    }

    func insertBlocks(_ blocks: [BlockInputBlock], at index: Int) {
        insertedBlockBatches.append((blocks, index))
        storedDocument.insertBlocks(blocks, at: index)
    }

    func deleteBlocks(withIDs ids: [BlockInputBlockID]) {
        deletedBlockIDs.append(ids)
        let deletedIDs = Set(ids)
        storedDocument.blocks.removeAll { deletedIDs.contains($0.id) }
    }
}
