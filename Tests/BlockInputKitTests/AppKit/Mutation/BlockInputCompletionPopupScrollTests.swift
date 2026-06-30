import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputCompletionPopupScrollTests: XCTestCase {
    func testPopupCentersHighlightedSuggestionWhenConfigured() {
        let popup = makePopup(suggestions: popupFileSuggestions(count: 12), highlightedIndex: 7)

        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting, [
            "File4.md",
            "File5.md",
            "File6.md",
            "File7.md",
            "File8.md",
            "File9.md"
        ])
        XCTAssertEqual(popup.visibleSuggestionIndexesForTesting, [4, 5, 6, 7, 8, 9])
    }

    func testPopupSessionChangeResetsVisibleWindowForSameSuggestionIDs() {
        let suggestions = popupFileSuggestions(count: 8)
        let popup = makePopup(suggestions: suggestions, sessionID: UUID())
        XCTAssertTrue(popup.routeScrollWheel(
            at: NSPoint(x: popup.bounds.midX, y: popup.bounds.midY),
            event: TestScrollWheelEvent(deltaY: -1)
        ))
        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting.first, "File1.md")

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

        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting.first, "File0.md")
    }

    func testPointerHoverPreservesVisibleWindowWhenHighlightChanges() throws {
        let suggestions = popupFileSuggestions(count: 10)
        let popup = BlockInputCompletionPopupView(frame: NSRect(x: 0, y: 0, width: 320, height: 256))
        let sessionID = UUID()
        var currentHighlight = 0
        func configurePopup(highlightedIndex: Int) {
            currentHighlight = highlightedIndex
            popup.configure(
                state: BlockInputCompletionPopupState(
                    suggestions: suggestions,
                    highlightedIndex: highlightedIndex,
                    isLoading: false,
                    sessionID: sessionID
                ),
                style: .default,
                onSelect: { _ in },
                onHighlight: { index in configurePopup(highlightedIndex: index) }
            )
            popup.layoutSubtreeIfNeeded()
            popup.layout()
        }
        configurePopup(highlightedIndex: 0)
        scrollPopupDownTwice(popup)
        XCTAssertEqual(popup.visibleSuggestionIndexesForTesting, [2, 3, 4, 5, 6, 7])
        let point = try XCTUnwrap(popup.visibleSuggestionPointForTesting(title: "File7.md"))

        XCTAssertTrue(popup.routeMouseMoved(
            at: point,
            event: try mouseMovedEvent(location: NSPoint(x: point.x + 1, y: point.y), windowNumber: 0)
        ))

        XCTAssertEqual(currentHighlight, 7)
        XCTAssertEqual(popup.visibleSuggestionIndexesForTesting, [2, 3, 4, 5, 6, 7])
    }

    func testMouseDownPreservesVisibleWindowWhenHighlightChanges() throws {
        let suggestions = popupFileSuggestions(count: 10)
        let popup = BlockInputCompletionPopupView(frame: NSRect(x: 0, y: 0, width: 320, height: 256))
        let sessionID = UUID()
        var currentHighlight = 0
        func configurePopup(highlightedIndex: Int) {
            currentHighlight = highlightedIndex
            popup.configure(
                state: BlockInputCompletionPopupState(
                    suggestions: suggestions,
                    highlightedIndex: highlightedIndex,
                    isLoading: false,
                    sessionID: sessionID
                ),
                style: .default,
                onSelect: { _ in },
                onHighlight: { index in configurePopup(highlightedIndex: index) }
            )
            popup.layoutSubtreeIfNeeded()
            popup.layout()
        }
        configurePopup(highlightedIndex: 0)
        scrollPopupDownTwice(popup)
        XCTAssertEqual(popup.visibleSuggestionIndexesForTesting, [2, 3, 4, 5, 6, 7])
        let point = try XCTUnwrap(popup.visibleSuggestionPointForTesting(title: "File6.md"))

        XCTAssertTrue(popup.routeMouseDown(
            at: point,
            event: try mouseDownEvent(location: point, windowNumber: 0)
        ))

        XCTAssertEqual(currentHighlight, 6)
        XCTAssertEqual(popup.visibleSuggestionIndexesForTesting, [2, 3, 4, 5, 6, 7])
    }

    func testPopupRowScrollWheelRoutesToPopup() throws {
        let popup = makePopup(suggestions: popupFileSuggestions(count: 8))
        let row = try rowView(label: "File5.md", in: popup)

        row.scrollWheel(with: TestScrollWheelEvent(deltaY: -1))

        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting.first, "File1.md")
    }

    func testPopupScrollReusesVisibleRowViews() {
        let popup = makePopup(suggestions: popupFileSuggestions(count: 8))
        let originalRows = popup.rowViewsForTesting

        XCTAssertTrue(popup.routeScrollWheel(
            at: NSPoint(x: popup.bounds.midX, y: popup.bounds.midY),
            event: TestScrollWheelEvent(deltaY: -1)
        ))

        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting.first, "File1.md")
        XCTAssertEqual(popup.rowViewsForTesting.count, originalRows.count)
        for (row, originalRow) in zip(popup.rowViewsForTesting, originalRows) {
            XCTAssertTrue(row === originalRow)
        }
    }

    func testPopupChromeScrollWheelRoutesToPopup() {
        let popup = makePopup(suggestions: popupFileSuggestions(count: 8))

        popup.scrollWheel(with: TestScrollWheelEvent(deltaY: -1))

        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting.first, "File1.md")
    }

    func testPopupConsumesBoundaryAndHorizontalWheelEvents() {
        let popup = makePopup(
            suggestions: popupFileSuggestions(count: 8),
            onHighlight: { _ in XCTFail("Boundary wheel should not change highlight") }
        )

        XCTAssertTrue(popup.routeScrollWheel(
            at: NSPoint(x: popup.bounds.midX, y: popup.bounds.midY),
            event: TestScrollWheelEvent(deltaY: 1)
        ))
        XCTAssertTrue(popup.routeScrollWheel(
            at: NSPoint(x: popup.bounds.midX, y: popup.bounds.midY),
            event: TestScrollWheelEvent(deltaY: 0, deltaX: 8)
        ))
        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting.first, "File0.md")
    }

    func testPopupConsumesWheelEventsWhenNotScrollable() {
        let popup = makePopup(suggestions: popupFileSuggestions(count: 2))
        XCTAssertTrue(popup.routeScrollWheel(
            at: NSPoint(x: popup.bounds.midX, y: popup.bounds.midY),
            event: TestScrollWheelEvent(deltaY: -1)
        ))
        XCTAssertTrue(popup.routeScrollWheel(
            at: NSPoint(x: popup.bounds.midX, y: popup.bounds.midY),
            event: TestScrollWheelEvent(deltaY: 0)
        ))

        popup.configure(
            state: BlockInputCompletionPopupState(suggestions: [], highlightedIndex: 0, isLoading: false),
            style: .default,
            onSelect: { _ in },
            onHighlight: { _ in }
        )
        XCTAssertTrue(popup.routeScrollWheel(
            at: NSPoint(x: popup.bounds.midX, y: popup.bounds.midY),
            event: TestScrollWheelEvent(deltaY: -1)
        ))

        popup.configure(
            state: BlockInputCompletionPopupState(suggestions: [], highlightedIndex: 0, isLoading: true),
            style: .default,
            onSelect: { _ in },
            onHighlight: { _ in }
        )
        XCTAssertTrue(popup.routeScrollWheel(
            at: NSPoint(x: popup.bounds.midX, y: popup.bounds.midY),
            event: TestScrollWheelEvent(deltaY: -1)
        ))
        popup.layoutSubtreeIfNeeded()
        popup.layout()
    }

    func testPopupUsesDeltaYFallbackForWheelDirection() {
        let popup = makePopup(suggestions: popupFileSuggestions(count: 8))

        XCTAssertTrue(popup.routeScrollWheel(
            at: NSPoint(x: popup.bounds.midX, y: popup.bounds.midY),
            event: TestScrollWheelEvent(deltaY: 0, fallbackDeltaY: -1)
        ))

        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting.first, "File1.md")
    }

    func testInitialStationaryHoverDoesNotSelectBottomRowWhenLoadingResolves() throws {
        let window = CompletionPopupMouseLocationWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 256),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        let popup = BlockInputCompletionPopupView(frame: NSRect(x: 0, y: 0, width: 320, height: 256))
        window.contentView = popup
        let sessionID = UUID()
        popup.configure(
            state: BlockInputCompletionPopupState(suggestions: [], highlightedIndex: 0, isLoading: true, sessionID: sessionID),
            style: .default,
            onSelect: { _ in },
            onHighlight: { _ in }
        )
        let bottomRowWindowPoint = NSPoint(x: 80, y: 28)
        window.testMouseLocationOutsideOfEventStream = bottomRowWindowPoint

        popup.configure(
            state: BlockInputCompletionPopupState(
                suggestions: popupFileSuggestions(count: 8),
                highlightedIndex: 0,
                isLoading: false,
                sessionID: sessionID
            ),
            style: .default,
            onSelect: { _ in },
            onHighlight: { _ in XCTFail("Stationary hover should not update highlight") }
        )
        popup.layoutSubtreeIfNeeded()
        let bottomRow = try rowView(label: "File5.md", in: popup)
        bottomRow.mouseEntered(with: try mouseMovedEvent(location: bottomRowWindowPoint, windowNumber: window.windowNumber))
    }

    func testPopupMouseMonitorConsumesScrollWheelInsidePopup() async throws {
        let mounted = try await startCompletion()
        let popup = try XCTUnwrap(mounted.view.completionPopupView)
        let row = try rowView(label: "File5.md", in: popup)
        let rowWindowPoint = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
        let initialScrollOrigin = mounted.view.scrollView.contentView.bounds.origin

        let result = mounted.view.handleCompletionPopupMouseEvent(TestScrollWheelEvent(
            window: mounted.window,
            location: rowWindowPoint,
            deltaY: -1
        ))

        XCTAssertNil(result)
        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting.first, "File1.md")
        XCTAssertEqual(mounted.view.scrollView.contentView.bounds.origin, initialScrollOrigin)
    }

    func testPopupMouseMonitorConsumesBoundaryScrollWheelInsidePopup() async throws {
        let mounted = try await startCompletion()
        let popup = try XCTUnwrap(mounted.view.completionPopupView)
        let row = try rowView(label: "File0.md", in: popup)
        let rowWindowPoint = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
        let initialScrollOrigin = mounted.view.scrollView.contentView.bounds.origin

        let result = mounted.view.handleCompletionPopupMouseEvent(TestScrollWheelEvent(
            window: mounted.window,
            location: rowWindowPoint,
            deltaY: 1
        ))

        XCTAssertNil(result)
        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting.first, "File0.md")
        XCTAssertEqual(mounted.view.scrollView.contentView.bounds.origin, initialScrollOrigin)
    }

    func testPopupMouseMonitorConsumesScrollWheelInsideOverlayPopup() async throws {
        let mounted = try await startCompletion(placement: .overlay)
        let popup = try XCTUnwrap(mounted.view.completionPopupView)
        let row = try rowView(label: "File5.md", in: popup)
        let rowWindowPoint = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
        let initialScrollOrigin = mounted.view.scrollView.contentView.bounds.origin

        let result = mounted.view.handleCompletionPopupMouseEvent(TestScrollWheelEvent(
            window: mounted.window,
            location: rowWindowPoint,
            deltaY: -1
        ))

        XCTAssertNil(result)
        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting.first, "File1.md")
        XCTAssertEqual(mounted.view.scrollView.contentView.bounds.origin, initialScrollOrigin)
    }

    func testPopupCaptureViewConsumesOverlayScrollWheelInsidePopup() async throws {
        let mounted = try await startCompletion(placement: .overlay)
        let popup = try XCTUnwrap(mounted.view.completionPopupView)
        let row = try rowView(label: "File5.md", in: popup)
        let rowWindowPoint = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
        let initialScrollOrigin = mounted.view.scrollView.contentView.bounds.origin

        mounted.view.completionPopupEventCaptureView.scrollWheel(with: TestScrollWheelEvent(
            window: mounted.window,
            location: rowWindowPoint,
            deltaY: -1
        ))

        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting.first, "File1.md")
        XCTAssertEqual(mounted.view.scrollView.contentView.bounds.origin, initialScrollOrigin)
    }

    func testPopupMouseMonitorLeavesOutsideScrollWheelAndDoesNotDismiss() async throws {
        let mounted = try await startCompletion(suggestionCount: 1)
        let event = TestScrollWheelEvent(
            window: mounted.window,
            location: NSPoint(x: mounted.view.bounds.maxX + 80, y: mounted.view.bounds.maxY + 80),
            deltaY: -1
        )

        let result = mounted.view.handleCompletionPopupMouseEvent(event)

        XCTAssertTrue(result === event)
        XCTAssertNotNil(mounted.view.completionPopupView)
    }

    func testPopupMouseMonitorDoesNotUseLiveMouseLocationForScrollWheel() async throws {
        let window = CompletionPopupMouseLocationWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 720, height: 480)),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let mounted = try await startCompletion(window: window)
        let popup = try XCTUnwrap(mounted.view.completionPopupView)
        let row = try rowView(label: "File5.md", in: popup)
        let livePoint = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
        let outsidePoint = NSPoint(x: mounted.view.bounds.maxX + 80, y: mounted.view.bounds.maxY + 80)
        let initialScrollOrigin = mounted.view.scrollView.contentView.bounds.origin
        window.testMouseLocationOutsideOfEventStream = livePoint

        let result = mounted.view.handleCompletionPopupMouseEvent(TestScrollWheelEvent(
            window: mounted.window,
            location: outsidePoint,
            deltaY: -1
        ))

        XCTAssertNotNil(result)
        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting.first, "File0.md")
        XCTAssertEqual(mounted.view.scrollView.contentView.bounds.origin, initialScrollOrigin)
    }

    private func makePopup(
        suggestions: [BlockInputCompletionSuggestion],
        highlightedIndex: Int = 0,
        sessionID: UUID = UUID(),
        onHighlight: @escaping (Int) -> Void = { _ in }
    ) -> BlockInputCompletionPopupView {
        let popup = BlockInputCompletionPopupView(frame: NSRect(x: 0, y: 0, width: 320, height: 256))
        popup.configure(
            state: BlockInputCompletionPopupState(
                suggestions: suggestions,
                highlightedIndex: highlightedIndex,
                isLoading: false,
                sessionID: sessionID
            ),
            style: .default,
            onSelect: { _ in },
            onHighlight: onHighlight
        )
        popup.layoutSubtreeIfNeeded()
        return popup
    }

    private func startCompletion(
        suggestionCount: Int = 8,
        window customWindow: NSWindow? = nil,
        placement: BlockInputCompletionPopupPlacement = .caret
    ) async throws -> (view: BlockInputView, window: NSWindow) {
        let configuration = BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: "@read")
            ]),
            completionProvider: PopupCompletionProvider(suggestions: popupFileSuggestions(count: suggestionCount)),
            completionPopupPlacement: placement
        )
        let mounted: (view: BlockInputView, window: NSWindow)
        if let customWindow {
            let view = BlockInputView(frame: customWindow.contentView?.bounds ?? customWindow.frame)
            customWindow.contentView = view
            view.configure(configuration)
            view.layoutSubtreeIfNeeded()
            view.collectionView.layoutSubtreeIfNeeded()
            mounted = (view, customWindow)
        } else {
            mounted = makeMountedBlockInputView(configuration: configuration)
        }
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: ("@read" as NSString).length, length: 0))
        mounted.view.refreshCompletionSession(item: item, blockID: "block")
        await mounted.view.completionRequestTask?.value
        mounted.view.layoutSubtreeIfNeeded()
        return mounted
    }

    private func rowView(label: String, in popup: NSView) throws -> NSView {
        try XCTUnwrap(popup.subviews.first { $0.accessibilityLabel() == label })
    }

    private func scrollPopupDownTwice(_ popup: BlockInputCompletionPopupView) {
        XCTAssertTrue(popup.routeScrollWheel(
            at: NSPoint(x: popup.bounds.midX, y: popup.bounds.midY),
            event: TestScrollWheelEvent(deltaY: -1)
        ))
        XCTAssertTrue(popup.routeScrollWheel(
            at: NSPoint(x: popup.bounds.midX, y: popup.bounds.midY),
            event: TestScrollWheelEvent(deltaY: -1)
        ))
    }

    private func popupFileSuggestions(count: Int) -> [BlockInputCompletionSuggestion] {
        (0..<count).map { index in
            .fileLink(label: "File\(index).md", fileURL: URL(fileURLWithPath: "/tmp/File\(index).md"))
        }
    }
}
