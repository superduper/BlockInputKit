import Foundation
@testable import BlockInputKit

final class DelayedRecordingProgressiveStore: BlockInputDocumentStore, @unchecked Sendable {
    var onLoadStarted: (() -> Void)?
    private(set) var requestedLimits: [Int] = []
    private let blocks: [BlockInputBlock]
    private let loadedCountValue: Int
    private var continuation: CheckedContinuation<Void, Never>?

    init(blocks: [BlockInputBlock], loadedCount: Int) {
        self.blocks = blocks
        loadedCountValue = loadedCount
    }

    var loadedBlockCount: Int {
        loadedCountValue
    }

    var isComplete: Bool {
        loadedCountValue >= blocks.count
    }

    var isLoading: Bool {
        continuation != nil
    }

    @MainActor
    func loadNextBlockBatch(limit: Int) async throws {
        requestedLimits.append(limit)
        onLoadStarted?()
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resumeLoad() {
        continuation?.resume()
        continuation = nil
    }

    func block(at index: Int) -> BlockInputBlock? {
        guard index >= 0,
              index < loadedCountValue,
              blocks.indices.contains(index) else {
            return nil
        }
        return blocks[index]
    }

    func block(withID id: BlockInputBlockID) -> BlockInputBlock? {
        blocks.prefix(loadedCountValue).first { $0.id == id }
    }

    func index(of id: BlockInputBlockID) -> Int? {
        blocks.prefix(loadedCountValue).firstIndex { $0.id == id }
    }

    func replaceDocument(_ document: BlockInputDocument) {}
}

final class FailingProgressivePreloadStore: BlockInputDocumentStore, @unchecked Sendable {
    static let failure = NSError(domain: "FailingProgressivePreloadStore", code: 1)

    var onLoadStarted: (() -> Void)?
    private(set) var requestedLimits: [Int] = []
    private let blocks: [BlockInputBlock]
    private let loadedCountValue: Int

    init(blocks: [BlockInputBlock], loadedCount: Int) {
        self.blocks = blocks
        loadedCountValue = loadedCount
    }

    var loadedBlockCount: Int {
        loadedCountValue
    }

    var isComplete: Bool {
        false
    }

    @MainActor
    func loadNextBlockBatch(limit: Int) async throws {
        requestedLimits.append(limit)
        onLoadStarted?()
        throw Self.failure
    }

    func block(at index: Int) -> BlockInputBlock? {
        guard index >= 0,
              index < loadedCountValue,
              blocks.indices.contains(index) else {
            return nil
        }
        return blocks[index]
    }

    func block(withID id: BlockInputBlockID) -> BlockInputBlock? {
        blocks.prefix(loadedCountValue).first { $0.id == id }
    }

    func index(of id: BlockInputBlockID) -> Int? {
        blocks.prefix(loadedCountValue).firstIndex { $0.id == id }
    }

    func replaceDocument(_ document: BlockInputDocument) {}
}
