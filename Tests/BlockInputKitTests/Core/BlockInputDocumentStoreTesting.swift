import Foundation
@testable import BlockInputKit

final class CountingDocumentStore: BlockInputDocumentStore {
    private(set) var document: BlockInputDocument
    private(set) var loadedBlockCountReadCount = 0
    private(set) var blockAtReadIndexes: [Int] = []
    private(set) var indexReadIDs: [BlockInputBlockID] = []
    private(set) var replaceDocumentCount = 0
    private(set) var replaceBlockIDs: [BlockInputBlockID] = []
    private(set) var insertedBlockBatches: [(blocks: [BlockInputBlock], index: Int)] = []
    private(set) var deletedBlockIDs: [[BlockInputBlockID]] = []
    private(set) var movedBlocks: [(id: BlockInputBlockID, index: Int)] = []

    var loadedBlockCount: Int {
        loadedBlockCountReadCount += 1
        return document.blocks.count
    }

    init(document: BlockInputDocument) {
        self.document = document
    }

    func resetCounts() {
        loadedBlockCountReadCount = 0
        blockAtReadIndexes = []
        indexReadIDs = []
        replaceDocumentCount = 0
        replaceBlockIDs = []
        insertedBlockBatches = []
        deletedBlockIDs = []
        movedBlocks = []
    }

    func block(at index: Int) -> BlockInputBlock? {
        blockAtReadIndexes.append(index)
        guard document.blocks.indices.contains(index) else {
            return nil
        }
        return document.blocks[index]
    }

    func block(withID id: BlockInputBlockID) -> BlockInputBlock? {
        document.block(withID: id)
    }

    func index(of id: BlockInputBlockID) -> Int? {
        indexReadIDs.append(id)
        return document.index(of: id)
    }

    func replaceDocument(_ document: BlockInputDocument) {
        replaceDocumentCount += 1
        self.document = document
    }

    func replaceBlock(_ block: BlockInputBlock) {
        replaceBlockIDs.append(block.id)
        guard let index = document.index(of: block.id) else {
            return
        }
        document.blocks[index] = block
    }

    func insertBlocks(_ blocks: [BlockInputBlock], at index: Int) {
        insertedBlockBatches.append((blocks, index))
        document.insertBlocks(blocks, at: index)
    }

    func deleteBlocks(withIDs ids: [BlockInputBlockID]) {
        deletedBlockIDs.append(ids)
        let deletedIDs = Set(ids)
        document.blocks.removeAll { deletedIDs.contains($0.id) }
    }

    func moveBlock(withID id: BlockInputBlockID, to index: Int) {
        movedBlocks.append((id, index))
        document.moveBlock(blockID: id, to: index)
    }
}

final class StoreBackedCompletionProvider: BlockInputCompletionProvider, @unchecked Sendable {
    private(set) var requestCount = 0
    private(set) var lastContext: BlockInputCompletionContext?

    func suggestions(for context: BlockInputCompletionContext) async -> [BlockInputCompletionSuggestion] {
        requestCount += 1
        lastContext = context
        return [
            BlockInputCompletionSuggestion(
                id: "mention:store",
                title: "Store",
                insertionText: "@store",
                trigger: context.trigger
            )
        ]
    }
}
