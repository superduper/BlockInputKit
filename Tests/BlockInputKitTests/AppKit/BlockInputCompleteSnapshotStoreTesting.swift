import Foundation
@testable import BlockInputKit

final class CompleteSnapshotCountingStore: BlockInputDocumentStore, @unchecked Sendable {
    private var storedDocument: BlockInputDocument
    private let lock = NSLock()
    private(set) var documentReadCount = 0
    private(set) var completeSnapshotCount = 0

    var document: BlockInputDocument {
        lock.lock()
        defer { lock.unlock() }
        documentReadCount += 1
        return storedDocument
    }

    var loadedBlockCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedDocument.blocks.count
    }

    init(document: BlockInputDocument) {
        storedDocument = document
    }

    func resetCounts() {
        lock.lock()
        defer { lock.unlock() }
        documentReadCount = 0
        completeSnapshotCount = 0
    }

    func countedCompleteDocumentSnapshot() -> BlockInputDocument {
        lock.lock()
        defer { lock.unlock() }
        completeSnapshotCount += 1
        return BlockInputDocument(blocks: storedDocument.blocks.map { $0 })
    }

    @MainActor
    func completeDocumentSnapshot(limit: Int) async throws -> BlockInputDocument {
        countedCompleteDocumentSnapshot()
    }

    func block(at index: Int) -> BlockInputBlock? {
        lock.lock()
        defer { lock.unlock() }
        guard storedDocument.blocks.indices.contains(index) else {
            return nil
        }
        return storedDocument.blocks[index]
    }

    func block(withID id: BlockInputBlockID) -> BlockInputBlock? {
        lock.lock()
        defer { lock.unlock() }
        return storedDocument.block(withID: id)
    }

    func index(of id: BlockInputBlockID) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return storedDocument.index(of: id)
    }

    func replaceDocument(_ document: BlockInputDocument) {
        lock.lock()
        defer { lock.unlock() }
        storedDocument = document
    }

    func replaceBlock(_ block: BlockInputBlock) {
        lock.lock()
        defer { lock.unlock() }
        guard let index = storedDocument.index(of: block.id) else {
            return
        }
        storedDocument.blocks[index] = block
    }

    func insertBlocks(_ blocks: [BlockInputBlock], at index: Int) {
        lock.lock()
        defer { lock.unlock() }
        storedDocument.insertBlocks(blocks, at: index)
    }

    func deleteBlocks(withIDs ids: [BlockInputBlockID]) {
        lock.lock()
        defer { lock.unlock() }
        let deletedIDs = Set(ids)
        storedDocument.blocks.removeAll { deletedIDs.contains($0.id) }
    }

    func moveBlock(withID id: BlockInputBlockID, to index: Int) {
        lock.lock()
        defer { lock.unlock() }
        storedDocument.moveBlock(blockID: id, to: index)
    }
}
