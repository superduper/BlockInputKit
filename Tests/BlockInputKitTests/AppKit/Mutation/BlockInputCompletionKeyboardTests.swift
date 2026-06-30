import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputCompletionKeyboardTests: XCTestCase {
    func testKeyboardHighlightDoesNotJumpBackToStationaryHoveredRow() async throws {
        let provider = PopupCompletionProvider(suggestions: popupNavigationSuggestions())
        let mounted = try await startCompletion(provider: provider)
        let popup = try XCTUnwrap(mounted.view.completionPopupView)
        let thirdRow = try rowView(label: "Third.md", in: popup)
        let thirdRowPoint = NSPoint(x: thirdRow.frame.midX, y: thirdRow.frame.midY)
        let thirdWindowPoint = thirdRow.convert(NSPoint(x: thirdRow.bounds.midX, y: thirdRow.bounds.midY), to: nil)

        XCTAssertTrue(popup.routeMouseMoved(
            at: thirdRowPoint,
            event: try mouseMovedEvent(location: thirdWindowPoint, windowNumber: mounted.window.windowNumber)
        ))
        XCTAssertEqual(mounted.view.completionSession?.highlightedIndex, 2)

        XCTAssertTrue(mounted.view.handleCompletionCommand(#selector(NSResponder.moveUp(_:))))
        XCTAssertEqual(mounted.view.completionSession?.highlightedIndex, 1)
        popup.layoutSubtreeIfNeeded()

        let rebuiltThirdRow = try rowView(label: "Third.md", in: popup)
        rebuiltThirdRow.mouseEntered(with: try mouseMovedEvent(
            location: thirdWindowPoint,
            windowNumber: mounted.window.windowNumber
        ))

        XCTAssertEqual(mounted.view.completionSession?.highlightedIndex, 1)
    }

    func testMouseMovementAfterKeyboardHighlightUpdatesHoveredRow() async throws {
        let provider = PopupCompletionProvider(suggestions: popupNavigationSuggestions())
        let mounted = try await startCompletion(provider: provider)
        let popup = try XCTUnwrap(mounted.view.completionPopupView)
        let thirdRow = try rowView(label: "Third.md", in: popup)
        let thirdWindowPoint = thirdRow.convert(NSPoint(x: thirdRow.bounds.midX, y: thirdRow.bounds.midY), to: nil)

        XCTAssertTrue(popup.routeMouseMoved(
            at: NSPoint(x: thirdRow.frame.midX, y: thirdRow.frame.midY),
            event: try mouseMovedEvent(location: thirdWindowPoint, windowNumber: mounted.window.windowNumber)
        ))
        XCTAssertTrue(mounted.view.handleCompletionCommand(#selector(NSResponder.moveUp(_:))))
        XCTAssertEqual(mounted.view.completionSession?.highlightedIndex, 1)
        popup.layoutSubtreeIfNeeded()

        let firstRow = try rowView(label: "First.md", in: popup)
        let firstWindowPoint = firstRow.convert(NSPoint(x: firstRow.bounds.midX, y: firstRow.bounds.midY), to: nil)

        XCTAssertTrue(popup.routeMouseMoved(
            at: NSPoint(x: firstRow.frame.midX, y: firstRow.frame.midY),
            event: try mouseMovedEvent(location: firstWindowPoint, windowNumber: mounted.window.windowNumber)
        ))

        XCTAssertEqual(mounted.view.completionSession?.highlightedIndex, 0)
    }

    private func startCompletion(
        provider: any BlockInputCompletionProvider
    ) async throws -> (view: BlockInputView, window: NSWindow) {
        let text = "@read"
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: text)
            ]),
            completionProvider: provider
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        mounted.view.refreshCompletionSession(item: item, blockID: "block")
        await mounted.view.completionRequestTask?.value
        mounted.view.layoutSubtreeIfNeeded()
        return mounted
    }

    private func rowView(label: String, in popup: NSView) throws -> NSView {
        try XCTUnwrap(popup.subviews.first { $0.accessibilityLabel() == label })
    }

    private func popupNavigationSuggestions() -> [BlockInputCompletionSuggestion] {
        [
            .fileLink(label: "First.md", fileURL: URL(fileURLWithPath: "/tmp/First.md")),
            .fileLink(label: "Second.md", fileURL: URL(fileURLWithPath: "/tmp/Second.md")),
            .fileLink(label: "Third.md", fileURL: URL(fileURLWithPath: "/tmp/Third.md"))
        ]
    }
}
