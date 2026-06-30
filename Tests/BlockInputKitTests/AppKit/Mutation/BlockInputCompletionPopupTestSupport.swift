import AppKit
import Darwin
@testable import BlockInputKit

final class TestScrollWheelEvent: NSEvent {
    private weak var testWindow: NSWindow?
    private let testWindowNumber: Int
    private let testLocationInWindow: NSPoint
    private let testScrollingDeltaY: CGFloat
    private let testScrollingDeltaX: CGFloat
    private let testDeltaY: CGFloat

    init(
        window: NSWindow? = nil,
        windowNumber: Int = 0,
        location: NSPoint = .zero,
        deltaY: CGFloat,
        deltaX: CGFloat = 0,
        fallbackDeltaY: CGFloat? = nil
    ) {
        testWindow = window
        testWindowNumber = windowNumber
        testLocationInWindow = location
        testScrollingDeltaY = deltaY
        testScrollingDeltaX = deltaX
        testDeltaY = fallbackDeltaY ?? deltaY
        super.init()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var scrollingDeltaY: CGFloat {
        testScrollingDeltaY
    }

    override var scrollingDeltaX: CGFloat {
        testScrollingDeltaX
    }

    override var deltaY: CGFloat {
        testDeltaY
    }

    override var type: NSEvent.EventType {
        .scrollWheel
    }

    override var window: NSWindow? {
        testWindow
    }

    override var windowNumber: Int {
        testWindowNumber
    }

    override var locationInWindow: NSPoint {
        testLocationInWindow
    }
}

final class CompletionPopupMouseLocationWindow: NSWindow {
    var testMouseLocationOutsideOfEventStream: NSPoint = .zero

    override var mouseLocationOutsideOfEventStream: NSPoint {
        testMouseLocationOutsideOfEventStream
    }
}

final class PopupCompletionProvider: BlockInputCompletionProvider, @unchecked Sendable {
    private let suggestions: [BlockInputCompletionSuggestion]
    private(set) var contexts: [BlockInputCompletionContext] = []

    var lastContext: BlockInputCompletionContext? {
        contexts.last
    }

    init(suggestions: [BlockInputCompletionSuggestion]) {
        self.suggestions = suggestions
    }

    func suggestions(for context: BlockInputCompletionContext) async -> [BlockInputCompletionSuggestion] {
        contexts.append(context)
        return suggestions
    }
}

final class ThreadCapturingPopupCompletionProvider: BlockInputCompletionProvider, @unchecked Sendable {
    private let suggestions: [BlockInputCompletionSuggestion]
    private(set) var requestRanOnMainThread: Bool?

    init(suggestions: [BlockInputCompletionSuggestion]) {
        self.suggestions = suggestions
    }

    func suggestions(for context: BlockInputCompletionContext) async -> [BlockInputCompletionSuggestion] {
        requestRanOnMainThread = pthread_main_np() == 1
        return suggestions
    }
}

final class DelayedPopupCompletionProvider: BlockInputCompletionProvider, @unchecked Sendable {
    private let suggestions: [BlockInputCompletionSuggestion]
    private var continuation: CheckedContinuation<[BlockInputCompletionSuggestion], Never>?

    var isWaiting: Bool {
        continuation != nil
    }

    init(suggestions: [BlockInputCompletionSuggestion]) {
        self.suggestions = suggestions
    }

    func suggestions(for context: BlockInputCompletionContext) async -> [BlockInputCompletionSuggestion] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume(returning: suggestions)
        continuation = nil
    }
}

final class DelayedRefreshPopupCompletionProvider: BlockInputCompletionProvider, @unchecked Sendable {
    private let initialSuggestions: [BlockInputCompletionSuggestion]
    private var refreshContinuation: CheckedContinuation<[BlockInputCompletionSuggestion], Never>?
    private(set) var contexts: [BlockInputCompletionContext] = []

    var isWaitingForRefresh: Bool {
        refreshContinuation != nil
    }

    init(initialSuggestions: [BlockInputCompletionSuggestion]) {
        self.initialSuggestions = initialSuggestions
    }

    func suggestions(for context: BlockInputCompletionContext) async -> [BlockInputCompletionSuggestion] {
        contexts.append(context)
        guard contexts.count > 1 else {
            return initialSuggestions
        }
        return await withCheckedContinuation { continuation in
            refreshContinuation = continuation
        }
    }

    func resumeRefresh(with suggestions: [BlockInputCompletionSuggestion]) {
        refreshContinuation?.resume(returning: suggestions)
        refreshContinuation = nil
    }
}

/// A mutable in-memory document store whose blocks can be updated by tests.
final class MutableCompletionTestStore: BlockInputDocumentStore {
    private var blocks: [BlockInputBlock]

    var loadedBlockCount: Int { blocks.count }

    init(blocks: [BlockInputBlock]) {
        self.blocks = blocks
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

    func replaceDocument(_ document: BlockInputDocument) {
        blocks = document.blocks
    }

    func replaceBlock(_ block: BlockInputBlock) {
        guard let index = blocks.firstIndex(where: { $0.id == block.id }) else { return }
        blocks[index] = block
    }

    /// Test helper alias for `replaceBlock(_:)`.
    func updateBlock(_ block: BlockInputBlock) {
        replaceBlock(block)
    }
}

/// A completion provider that suspends every call and queues continuations in order.
/// Use `pendingCount` to confirm a fetch has started, then `resume(at:with:)` to resolve it.
final class QueuedDelayedCompletionProvider: BlockInputCompletionProvider, @unchecked Sendable {
    private var continuations: [CheckedContinuation<[BlockInputCompletionSuggestion], Never>] = []
    private(set) var callCount = 0

    var pendingCount: Int {
        continuations.count
    }

    func suggestions(for context: BlockInputCompletionContext) async -> [BlockInputCompletionSuggestion] {
        callCount += 1
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resume(at index: Int, with suggestions: [BlockInputCompletionSuggestion]) {
        guard continuations.indices.contains(index) else { return }
        let continuation = continuations.remove(at: index)
        continuation.resume(returning: suggestions)
    }
}
