import Foundation

enum BlockInputProgressiveMemoryLoadStart {
    case started([@MainActor (BlockInputDocumentStoreChange) -> Void])
    case wait
    case finished
}

struct BlockInputProgressiveMemoryFinishedLoad {
    var batch: BlockInputDocumentStoreBatch
    var observers: [@MainActor (BlockInputDocumentStoreChange) -> Void]
    var waiters: [CheckedContinuation<Void, Never>]
}

struct BlockInputProgressiveMemoryFailedLoad {
    var observers: [@MainActor (BlockInputDocumentStoreChange) -> Void]
    var waiters: [CheckedContinuation<Void, Never>]
}
