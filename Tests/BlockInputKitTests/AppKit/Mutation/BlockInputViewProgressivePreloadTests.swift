import AppKit
import XCTest
@testable import BlockInputKit

final class BlockInputViewProgressivePreloadTests: XCTestCase {
    @MainActor
    func testProgressiveLoadingStartsWhenLoadingRowEntersPreloadWindow() async throws {
        let store = DelayedRecordingProgressiveStore(blocks: Self.blocks, loadedCount: 40)
        let mounted = mountedProgressiveView(store: store)
        defer { _ = mounted.window }
        let view = mounted.view

        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        XCTAssertTrue(store.requestedLimits.isEmpty)

        let loadingIndexPath = IndexPath(item: store.loadedBlockCount, section: 0)
        let loaded = expectation(description: "Progressive preload requested")
        store.onLoadStarted = {
            loaded.fulfill()
        }
        try scrollLoadingRowIntoPreloadWindow(view: view, loadingIndexPath: loadingIndexPath)

        XCTAssertNil(view.collectionView.item(at: loadingIndexPath))
        await fulfillment(of: [loaded], timeout: 1)
        XCTAssertEqual(store.requestedLimits, [5_000])

        store.resumeLoad()
        while view.progressiveLoadTask != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @MainActor
    func testProgressivePreloadFailureDoesNotImmediatelyRetry() async throws {
        let store = FailingProgressivePreloadStore(blocks: Self.blocks, loadedCount: 40)
        let mounted = mountedProgressiveView(store: store)
        defer { _ = mounted.window }
        let view = mounted.view

        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        let loadingIndexPath = IndexPath(item: store.loadedBlockCount, section: 0)
        let loaded = expectation(description: "Progressive preload requested")
        store.onLoadStarted = {
            loaded.fulfill()
        }
        try scrollLoadingRowIntoPreloadWindow(view: view, loadingIndexPath: loadingIndexPath)

        await fulfillment(of: [loaded], timeout: 1)
        while view.progressiveLoadTask != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        view.collectionView.layoutSubtreeIfNeeded()

        XCTAssertEqual(store.requestedLimits, [5_000])
        XCTAssertEqual(view.progressiveStoreError, FailingProgressivePreloadStore.failure.localizedDescription)
    }

    @MainActor
    func testRepeatedProgressivePreloadChecksCoalesceWhileScheduled() async throws {
        let store = DelayedRecordingProgressiveStore(blocks: Self.blocks, loadedCount: 40)
        let mounted = mountedProgressiveView(store: store)
        defer { _ = mounted.window }
        let view = mounted.view

        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        let loadingIndexPath = IndexPath(item: store.loadedBlockCount, section: 0)
        let loaded = expectation(description: "Progressive preload requested once")
        loaded.assertForOverFulfill = true
        store.onLoadStarted = {
            loaded.fulfill()
        }
        try scrollLoadingRowIntoPreloadWindow(view: view, loadingIndexPath: loadingIndexPath)

        view.scheduleProgressivePreloadCheck()
        view.scheduleProgressivePreloadCheck()

        await fulfillment(of: [loaded], timeout: 1)
        XCTAssertEqual(store.requestedLimits, [5_000])

        store.resumeLoad()
        while view.progressiveLoadTask != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @MainActor
    func testLoadingRowRequestDuringScheduledPreloadStillStartsOneLoad() async throws {
        let store = DelayedRecordingProgressiveStore(blocks: Self.blocks, loadedCount: 40)
        let mounted = mountedProgressiveView(store: store)
        defer { _ = mounted.window }
        let view = mounted.view

        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        let loadingIndexPath = IndexPath(item: store.loadedBlockCount, section: 0)
        let loaded = expectation(description: "Progressive preload requested once")
        loaded.assertForOverFulfill = true
        store.onLoadStarted = {
            loaded.fulfill()
        }
        try scrollLoadingRowIntoPreloadWindow(view: view, loadingIndexPath: loadingIndexPath)

        _ = view.collectionView(
            view.collectionView,
            itemForRepresentedObjectAt: loadingIndexPath
        )

        await fulfillment(of: [loaded], timeout: 1)
        XCTAssertEqual(store.requestedLimits, [5_000])

        store.resumeLoad()
        while view.progressiveLoadTask != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @MainActor
    private func mountedProgressiveView(store: any BlockInputDocumentStore) -> (view: BlockInputView, window: NSWindow) {
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 480, height: 200))
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        view.configure(BlockInputConfiguration(documentStore: store))
        return (view, window)
    }

    @MainActor
    private func scrollLoadingRowIntoPreloadWindow(
        view: BlockInputView,
        loadingIndexPath: IndexPath
    ) throws {
        let loadingFrame = try XCTUnwrap(
            view.collectionView.collectionViewLayout?.layoutAttributesForItem(at: loadingIndexPath)?.frame
        )
        let visibleHeight = view.collectionView.visibleRect.height
        let scrollY = max(loadingFrame.minY - visibleHeight - min(80, visibleHeight / 2), 0)
        let scrollView = try XCTUnwrap(view.collectionView.enclosingScrollView)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: scrollY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private static let blocks = (0..<41).map { index in
        BlockInputBlock(
            id: BlockInputBlockID(rawValue: "block-\(index)"),
            text: "Block \(index)"
        )
    }
}
