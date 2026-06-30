import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputCompletionPopupRefreshTests: XCTestCase {
    func testPopupReusesRowsWhenSuggestionContentsChange() {
        let popup = makePopup(suggestions: [
            suggestion(title: "README.md"),
            suggestion(title: "Sources")
        ])
        let originalRows = popup.rowViewsForTesting

        popup.configure(
            state: BlockInputCompletionPopupState(
                suggestions: [
                    suggestion(title: "README-more.md"),
                    suggestion(title: "Package.swift")
                ],
                highlightedIndex: 1,
                isLoading: false,
                sessionID: UUID()
            ),
            style: .default,
            onSelect: { _ in },
            onHighlight: { _ in }
        )

        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting, ["README-more.md", "Package.swift"])
        XCTAssertEqual(popup.rowViewsForTesting.count, originalRows.count)
        XCTAssertTrue(popup.rowViewsForTesting[0] === originalRows[0])
        XCTAssertTrue(popup.rowViewsForTesting[1] === originalRows[1])
    }

    func testPopupReusesRowsAcrossCountChangingSuggestionRefreshes() {
        let popup = makePopup(suggestions: [
            suggestion(title: "README.md"),
            suggestion(title: "Sources"),
            suggestion(title: "Tests")
        ])
        let originalRows = popup.rowViewsForTesting

        popup.configure(
            state: BlockInputCompletionPopupState(
                suggestions: [suggestion(title: "Package.swift")],
                highlightedIndex: 0,
                isLoading: false,
                sessionID: UUID()
            ),
            style: .default,
            onSelect: { _ in },
            onHighlight: { _ in }
        )

        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting, ["Package.swift"])
        XCTAssertEqual(popup.rowViewsForTesting.count, 1)
        XCTAssertTrue(popup.rowViewsForTesting[0] === originalRows[0])
        XCTAssertNil(originalRows[1].superview)
        XCTAssertNil(originalRows[2].superview)

        popup.configure(
            state: BlockInputCompletionPopupState(
                suggestions: [
                    suggestion(title: "Package.swift"),
                    suggestion(title: "Sources"),
                    suggestion(title: "Tests"),
                    suggestion(title: "README.md")
                ],
                highlightedIndex: 0,
                isLoading: false,
                sessionID: UUID()
            ),
            style: .default,
            onSelect: { _ in },
            onHighlight: { _ in }
        )

        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting, ["Package.swift", "Sources", "Tests", "README.md"])
        XCTAssertEqual(popup.rowViewsForTesting.count, 4)
        XCTAssertTrue(popup.rowViewsForTesting[0] === originalRows[0])
    }

    func testOverlayPopupRefreshAppliesFrameAndRowsBeforeNextLayoutPass() async throws {
        let provider = DelayedRefreshPopupCompletionProvider(initialSuggestions: [
            suggestion(title: "README.md"),
            suggestion(title: "Sources"),
            suggestion(title: "Tests")
        ])
        let mounted = try await startCompletion(text: "@read", provider: provider)
        let popup = try XCTUnwrap(mounted.view.completionPopupView)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)

        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        textView.insertText("m", replacementRange: textView.selectedRange())
        while !provider.isWaitingForRefresh {
            await Task.yield()
        }

        let refreshedSuggestions = [suggestion(title: "Package.swift")]
        provider.resumeRefresh(with: refreshedSuggestions)
        await mounted.view.completionRequestTask?.value

        let refreshedState = BlockInputCompletionPopupState(
            suggestions: refreshedSuggestions,
            highlightedIndex: 0,
            isLoading: false
        )
        let row = try XCTUnwrap(popup.rowViewsForTesting.first)
        XCTAssertEqual(popup.frame.height, BlockInputCompletionPopupView.measuredHeight(for: refreshedState), accuracy: 0.5)
        XCTAssertEqual(popup.rowViewsForTesting.count, 1)
        XCTAssertEqual(row.frame.minY, 8, accuracy: 0.5)
        XCTAssertEqual(row.frame.height, 36, accuracy: 0.5)
        XCTAssertEqual(row.frame.width, popup.bounds.width - 16, accuracy: 0.5)
        XCTAssertLessThanOrEqual(row.frame.maxY, popup.bounds.maxY)
    }

    func testOverlayPopupKeepsRowsVisibleWhileQueryRefreshes() async throws {
        let provider = DelayedRefreshPopupCompletionProvider(initialSuggestions: [
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])
        let mounted = try await startCompletion(text: "@read", provider: provider)
        let popup = try XCTUnwrap(mounted.view.completionPopupView)
        let originalRows = popup.rowViewsForTesting
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)

        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting, ["README.md"])

        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        textView.insertText("m", replacementRange: textView.selectedRange())
        while !provider.isWaitingForRefresh {
            await Task.yield()
        }

        XCTAssertTrue(mounted.view.completionPopupView === popup)
        XCTAssertEqual(mounted.view.completionSession?.token.query, "readm")
        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting, ["README.md"])

        provider.resumeRefresh(with: [
            .fileLink(label: "README-more.md", fileURL: URL(fileURLWithPath: "/tmp/README-more.md"))
        ])
        await mounted.view.completionRequestTask?.value

        XCTAssertTrue(mounted.view.completionPopupView === popup)
        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting, ["README-more.md"])
        XCTAssertEqual(popup.rowViewsForTesting.count, originalRows.count)
        XCTAssertTrue(popup.rowViewsForTesting[0] === originalRows[0])
    }

    func testSlowFetchFromPreviousQueryIsRejected() async throws {
        // Reproduces: continuousCompletionSession rewrites session.sourceText in-place while
        // keeping the same UUID. Without a sourceText snapshot, a slow fetch started for "@a"
        // passes the guard `current.sourceText == currentBlock.text` once the session advances
        // to "@ab" (both sides now equal "@ab"), applying stale suggestions.
        //
        // The test isolates the sourceText-staleness check by using a mutable document store
        // so the block text can be updated to "@ab" and the session.sourceText set to "@ab"
        // without going through requestCompletionSuggestions (which would cancel the in-flight
        // task and mask the bug via Task.isCancelled).
        let provider = QueuedDelayedCompletionProvider()
        let store = MutableCompletionTestStore(blocks: [BlockInputBlock(id: "block", text: "@a")])
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            documentStore: store,
            completionProvider: provider
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)

        // Step 1: trigger fetch for "@a"
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        mounted.view.refreshCompletionSession(item: item, blockID: "block")
        while provider.pendingCount < 1 {
            await Task.yield()
        }
        XCTAssertEqual(provider.callCount, 1)
        let originalSessionID = try XCTUnwrap(mounted.view.completionSession?.id)

        // Step 2: advance both session.sourceText and the document block text to "@ab"
        // WITHOUT cancelling the in-flight task — directly simulating the race window
        // where the session UUID stays the same but the text has advanced.
        store.updateBlock(BlockInputBlock(id: "block", text: "@ab"))
        if var session = mounted.view.completionSession, session.id == originalSessionID {
            session.sourceText = "@ab"
            mounted.view.completionSession = session
        }

        // Step 3: resolve fetch₁ with stale "stale" suggestion.
        // Its capturedSourceText was "@a"; the live sourceText is now "@ab".
        // Without the fix the guard passes (both sides "@ab"); with the fix it rejects.
        provider.resume(at: 0, with: [
            BlockInputCompletionSuggestion(id: "x", title: "stale", insertionText: "stale ", trigger: .mention)
        ])
        await mounted.view.completionRequestTask?.value
        await Task.yield()

        XCTAssertFalse(
            mounted.view.completionSession?.suggestions.contains { $0.title == "stale" } ?? false,
            "Stale suggestions from an earlier fetch must not be applied when the query has advanced"
        )
    }

    func testOverlayPopupShowsLoadingDuringEmptyQueryRefresh() async throws {
        let provider = DelayedRefreshPopupCompletionProvider(initialSuggestions: [])
        let mounted = try await startCompletion(text: "@missing", provider: provider)
        let popup = try XCTUnwrap(mounted.view.completionPopupView)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)

        XCTAssertEqual(mounted.view.completionSession?.isLoading, false)
        XCTAssertTrue(try loadingField(in: popup).isHidden)
        XCTAssertFalse(try emptyField(in: popup).isHidden)

        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        textView.insertText("x", replacementRange: textView.selectedRange())
        while !provider.isWaitingForRefresh {
            await Task.yield()
        }

        XCTAssertEqual(mounted.view.completionSession?.isLoading, true)
        XCTAssertFalse(try loadingField(in: popup).isHidden)
        XCTAssertTrue(try emptyField(in: popup).isHidden)

        provider.resumeRefresh(with: [])
        await mounted.view.completionRequestTask?.value

        XCTAssertEqual(mounted.view.completionSession?.isLoading, false)
        XCTAssertTrue(try loadingField(in: popup).isHidden)
        XCTAssertFalse(try emptyField(in: popup).isHidden)
    }

    private func startCompletion(
        text: String,
        provider: any BlockInputCompletionProvider
    ) async throws -> (view: BlockInputView, window: NSWindow) {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: text)
            ]),
            completionProvider: provider,
            completionPopupPlacement: .overlay
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        mounted.view.refreshCompletionSession(item: item, blockID: "block")
        await mounted.view.completionRequestTask?.value
        mounted.view.layoutSubtreeIfNeeded()
        return mounted
    }

    private func loadingField(in popup: BlockInputCompletionPopupView) throws -> NSTextField {
        try textField("Loading suggestions...", in: popup)
    }

    private func emptyField(in popup: BlockInputCompletionPopupView) throws -> NSTextField {
        try textField("No matches", in: popup)
    }

    private func textField(_ value: String, in popup: BlockInputCompletionPopupView) throws -> NSTextField {
        try XCTUnwrap(popup.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == value })
    }

    private func makePopup(suggestions: [BlockInputCompletionSuggestion]) -> BlockInputCompletionPopupView {
        let popup = BlockInputCompletionPopupView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        popup.configure(
            state: BlockInputCompletionPopupState(
                suggestions: suggestions,
                highlightedIndex: 0,
                isLoading: false,
                sessionID: UUID()
            ),
            style: .default,
            onSelect: { _ in },
            onHighlight: { _ in }
        )
        popup.layoutSubtreeIfNeeded()
        return popup
    }

    private func suggestion(title: String) -> BlockInputCompletionSuggestion {
        .fileLink(
            id: "file:///\(title)",
            label: title,
            fileURL: URL(fileURLWithPath: "/tmp/\(title)")
        )
    }
}
