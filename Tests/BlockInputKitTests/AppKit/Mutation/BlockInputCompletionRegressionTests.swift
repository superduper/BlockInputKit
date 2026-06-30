import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputCompletionRegressionTests: XCTestCase {
    func testTypingAfterAcceptedFileCompletionBreaksOutOfLink() async throws {
        let provider = RegressionCompletionProvider(suggestions: [
            .fileLink(label: "default.profraw", fileURL: URL(fileURLWithPath: "/tmp/default.profraw"))
        ])
        let mounted = try await startCompletion(text: "See @default", provider: provider)

        XCTAssertTrue(mounted.view.handleCompletionCommand(#selector(NSResponder.insertNewline(_:))))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        textView.insertText("test", replacementRange: textView.selectedRange())

        let expectedText = "See [default.profraw](file:///tmp/default.profraw) test"
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), [expectedText])
        XCTAssertEqual(textView.string, expectedText)
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(
            blockID: "block",
            utf16Offset: (expectedText as NSString).length
        )))
        XCTAssertNil(textView.textStorage?.attribute(.link, at: (expectedText as NSString).range(of: "test").location, effectiveRange: nil))
    }

    func testTypingAtFileLinkLabelBoundaryBreaksOutOfLinkSource() throws {
        let text = "Open [default.profraw](file:///tmp/default.profraw)"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let textView = try activeTextView(in: mounted, text: text)

        textView.insertText(" test", replacementRange: textView.selectedRange())

        let expectedText = "\(text) test"
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), [expectedText])
        XCTAssertEqual(textView.string, expectedText)
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(
            blockID: "block",
            utf16Offset: (expectedText as NSString).length
        )))
    }

    func testTypingAtSlashCommandChipLabelBoundaryBreaksOutOfLinkSource() throws {
        let text = "Run [/table](host-app://commands/table)"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        let labelEnd = NSMaxRange((text as NSString).range(of: "/table"))
        textView.setSelectedRange(NSRange(location: labelEnd, length: 0))

        textView.insertText(" now", replacementRange: textView.selectedRange())

        let expectedText = "\(text) now"
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), [expectedText])
        XCTAssertEqual(textView.string, expectedText)
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(
            blockID: "block",
            utf16Offset: (expectedText as NSString).length
        )))
    }

    func testReturnAtFileLinkLabelBoundaryBreaksOutOfLinkSource() throws {
        let text = "Open [default.profraw](file:///tmp/default.profraw)"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: text)
        ])
        let textView = try activeTextView(in: mounted, text: text)

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(mounted.view.document.blocks.count, 2)
        XCTAssertEqual(mounted.view.document.blocks[0], BlockInputBlock(id: "block", text: text))
        XCTAssertEqual(mounted.view.document.blocks[1].text, "")
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(
            blockID: mounted.view.document.blocks[1].id,
            utf16Offset: 0
        )))
    }

    func testAcceptedFileCompletionCanBeClickedImmediately() async throws {
        let provider = RegressionCompletionProvider(suggestions: [
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])
        let mounted = try await startCompletion(text: "See @read", provider: provider)

        XCTAssertTrue(mounted.view.handleCompletionCommand(#selector(NSResponder.insertNewline(_:))))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let contentOffset = (textView.string as NSString).range(of: "README.md").location
        let location = try windowLocation(forUTF16Offset: contentOffset, in: textView)
        var openedURLs: [URL] = []
        mounted.view.linkURLOpener = {
            openedURLs.append($0)
            return true
        }

        // Under the shipped interaction model (linkHoverEditAffordance default ON) a single plain click on the freshly
        // accepted file chip only places the caret; opening happens on a cmd-click (or double-click). The regression
        // intent is that the accepted chip is clickable right away (no stale geometry), which the cmd-click open proves.
        textView.mouseDown(with: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber))
        _ = textView.completeTrackedMouseUp(with: try mouseUpEvent(
            location: location,
            windowNumber: mounted.window.windowNumber
        ))

        XCTAssertTrue(openedURLs.isEmpty)
        XCTAssertNil(mounted.view.linkModalView)

        textView.mouseDown(with: try mouseDownEvent(
            location: location,
            windowNumber: mounted.window.windowNumber,
            modifierFlags: .command
        ))

        XCTAssertEqual(openedURLs.map(\.absoluteString), ["file:///tmp/README.md"])
    }

    func testAcceptedLongFileCompletionResizesMountedRow() async throws {
        let longLabel = [
            "Sources/BlockInputKit/AppKit",
            "BlockInputView+BlockItemConfiguration.swift",
            "Sources/BlockInputKit/AppKit",
            "BlockInputBlockItem+InlineChips.swift"
        ].joined(separator: "/")
        let provider = RegressionCompletionProvider(suggestions: [
            .fileLink(label: longLabel, fileURL: URL(fileURLWithPath: "/tmp/\(longLabel)"))
        ])
        let mounted = try await startCompletion(
            blocks: [
                BlockInputBlock(id: "block", text: "See @config"),
                BlockInputBlock(id: "next", text: "Next block")
            ],
            provider: provider
        )
        let initialItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let initialNextItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let initialHeight = initialItem.view.frame.height
        let initialNextMinY = initialNextItem.view.frame.minY

        XCTAssertTrue(mounted.view.handleCompletionCommand(#selector(NSResponder.insertNewline(_:))))
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        let updatedItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let updatedNextItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        XCTAssertGreaterThan(updatedItem.view.frame.height, initialHeight)
        XCTAssertGreaterThan(updatedNextItem.view.frame.minY, initialNextMinY)
        XCTAssertGreaterThanOrEqual(updatedNextItem.view.frame.minY, updatedItem.view.frame.maxY)
    }

    func testPopupMouseMonitorConsumesRowClickUntilMouseUp() async throws {
        let provider = RegressionCompletionProvider(suggestions: [
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])
        let mounted = try await startCompletion(text: "See @read", provider: provider)
        let popup = try XCTUnwrap(mounted.view.completionPopupView)
        let row = try rowView(label: "README.md", in: popup)
        let rowWindowPoint = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)

        let mouseDownResult = mounted.view.handleCompletionPopupMouseEvent(try mouseDownEvent(
            location: rowWindowPoint,
            windowNumber: mounted.window.windowNumber
        ))

        XCTAssertNil(mouseDownResult)
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["See @read"])
        XCTAssertNotNil(mounted.view.completionPopupView)

        let mouseUpResult = mounted.view.handleCompletionPopupMouseEvent(try mouseUpEvent(
            location: rowWindowPoint,
            windowNumber: mounted.window.windowNumber
        ))

        XCTAssertNil(mouseUpResult)
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["See [README.md](file:///tmp/README.md) "])
        XCTAssertNil(mounted.view.completionPopupView)
    }

    func testPopupClickOnUnhighlightedRowAcceptsOnMouseUp() async throws {
        let provider = RegressionCompletionProvider(suggestions: [
            .fileLink(label: "First.md", fileURL: URL(fileURLWithPath: "/tmp/First.md")),
            .fileLink(label: "Second.md", fileURL: URL(fileURLWithPath: "/tmp/Second.md"))
        ])
        let mounted = try await startCompletion(text: "See @read", provider: provider)
        let popup = try XCTUnwrap(mounted.view.completionPopupView)
        let row = try rowView(label: "Second.md", in: popup)
        let rowWindowPoint = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)

        let mouseDownResult = mounted.view.handleCompletionPopupMouseEvent(try mouseDownEvent(
            location: rowWindowPoint,
            windowNumber: mounted.window.windowNumber
        ))

        XCTAssertNil(mouseDownResult)
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["See @read"])
        XCTAssertNotNil(mounted.view.completionPopupView)

        let mouseUpResult = mounted.view.handleCompletionPopupMouseEvent(try mouseUpEvent(
            location: rowWindowPoint,
            windowNumber: mounted.window.windowNumber
        ))

        XCTAssertNil(mouseUpResult)
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["See [Second.md](file:///tmp/Second.md) "])
        XCTAssertNil(mounted.view.completionPopupView)
    }

    func testPopupCaptureViewConsumesRowClickWithoutRetargetingUnderlyingBlocks() async throws {
        let provider = RegressionCompletionProvider(suggestions: [
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])
        let mounted = try await startCompletion(text: "See @read", provider: provider)
        let popup = try XCTUnwrap(mounted.view.completionPopupView)
        let row = try rowView(label: "README.md", in: popup)
        let rowWindowPoint = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
        let captureView = mounted.view.completionPopupEventCaptureView

        XCTAssertTrue(captureView.superview === popup.superview)
        let popupContainer = try XCTUnwrap(popup.superview)
        XCTAssertEqual(captureView.frame, popupContainer.bounds)
        XCTAssertTrue(popupContainer.hitTest(popupContainer.convert(rowWindowPoint, from: nil)) === captureView)

        captureView.mouseDown(with: try mouseDownEvent(
            location: rowWindowPoint,
            windowNumber: mounted.window.windowNumber
        ))
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["See @read"])
        XCTAssertNotNil(mounted.view.completionPopupView)

        captureView.mouseUp(with: try mouseUpEvent(
            location: rowWindowPoint,
            windowNumber: mounted.window.windowNumber
        ))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["See [README.md](file:///tmp/README.md) "])
        XCTAssertNil(mounted.view.completionPopupView)
    }

    func testRightMouseDownInsidePopupDoesNotAcceptCompletion() async throws {
        let provider = RegressionCompletionProvider(suggestions: [
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])
        let mounted = try await startCompletion(text: "See @read", provider: provider)
        let popup = try XCTUnwrap(mounted.view.completionPopupView)
        let row = try rowView(label: "README.md", in: popup)
        let rowWindowPoint = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)

        let mouseDownResult = mounted.view.handleCompletionPopupMouseEvent(try rightMouseDownEvent(
            location: rowWindowPoint,
            windowNumber: mounted.window.windowNumber
        ))

        XCTAssertNil(mouseDownResult)
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["See @read"])
        XCTAssertNotNil(mounted.view.completionPopupView)

        // rightMouseUp must pass through (not be consumed) so the context menu can appear.
        let rightMouseUp = try rightMouseUpEvent(location: rowWindowPoint, windowNumber: mounted.window.windowNumber)
        let mouseUpResult = mounted.view.handleCompletionPopupMouseEvent(rightMouseUp)

        XCTAssertTrue(mouseUpResult === rightMouseUp, "rightMouseUp must not be consumed by the completion popup flag")
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["See @read"])
        XCTAssertNotNil(mounted.view.completionPopupView)
    }

    func testRightMouseUpPassesThroughAfterCompletionPopupMouseDown() async throws {
        // Regression: when completionPopupConsumesNextMouseUp is set by a left- or right-mouseDown
        // on the popup, a subsequent rightMouseUp must not be swallowed. Consuming it would prevent
        // the context menu from appearing.
        let provider = RegressionCompletionProvider(suggestions: [
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])
        let mounted = try await startCompletion(text: "See @read", provider: provider)
        let popup = try XCTUnwrap(mounted.view.completionPopupView)
        let row = try rowView(label: "README.md", in: popup)
        let rowWindowPoint = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)

        // Manually set the flag as the mouse-down path does, simulating a popup click.
        mounted.view.completionPopupConsumesNextMouseUp = true

        // A rightMouseUp should be passed through and must reset the flag.
        let rightMouseUp = try rightMouseUpEvent(location: rowWindowPoint, windowNumber: mounted.window.windowNumber)
        let result = mounted.view.handleCompletionPopupMouseEvent(rightMouseUp)

        XCTAssertTrue(result === rightMouseUp, "rightMouseUp must not be consumed when completionPopupConsumesNextMouseUp is set")
        XCTAssertFalse(mounted.view.completionPopupConsumesNextMouseUp, "flag must be cleared after passing through non-left mouse-up")
    }

    func testPopupMouseMonitorConsumesScrollWheelInsidePopup() async throws {
        let provider = RegressionCompletionProvider(suggestions: (0..<8).map { index in
            .fileLink(label: "File\(index).md", fileURL: URL(fileURLWithPath: "/tmp/File\(index).md"))
        })
        let mounted = try await startCompletion(text: "See @read", provider: provider)
        let popup = try XCTUnwrap(mounted.view.completionPopupView)
        let row = try rowView(label: "File5.md", in: popup)
        let rowWindowPoint = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)

        let result = mounted.view.handleCompletionPopupMouseEvent(TestScrollWheelEvent(
            window: mounted.window,
            location: rowWindowPoint,
            deltaY: -1
        ))

        XCTAssertNil(result)
        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting.first, "File1.md")
    }

    func testPopupMouseMonitorLeavesOutsideScrollWheelAndDoesNotDismiss() async throws {
        let provider = RegressionCompletionProvider(suggestions: [
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])
        let mounted = try await startCompletion(text: "See @read", provider: provider)
        let event = TestScrollWheelEvent(
            window: mounted.window,
            location: NSPoint(x: mounted.view.bounds.maxX + 80, y: mounted.view.bounds.maxY + 80),
            deltaY: -1
        )

        let result = mounted.view.handleCompletionPopupMouseEvent(event)

        XCTAssertTrue(result === event)
        XCTAssertNotNil(mounted.view.completionPopupView)
    }

    private func activeTextView(
        in mounted: (view: BlockInputView, window: NSWindow),
        text: String
    ) throws -> BlockInputTextView {
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        let labelEnd = NSMaxRange((text as NSString).range(of: "default.profraw"))
        textView.setSelectedRange(NSRange(location: labelEnd, length: 0))
        return textView
    }

    private func startCompletion(
        text: String,
        provider: any BlockInputCompletionProvider
    ) async throws -> (view: BlockInputView, window: NSWindow) {
        try await startCompletion(blocks: [
            BlockInputBlock(id: "block", text: text)
        ], provider: provider)
    }

    private func startCompletion(
        blocks: [BlockInputBlock],
        provider: any BlockInputCompletionProvider
    ) async throws -> (view: BlockInputView, window: NSWindow) {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: blocks),
            completionProvider: provider
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let text = blocks[0].text
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        mounted.view.refreshCompletionSession(item: item, blockID: blocks[0].id)
        await mounted.view.completionRequestTask?.value
        mounted.view.layoutSubtreeIfNeeded()
        return mounted
    }

    private func rowView(label: String, in popup: NSView) throws -> NSView {
        try XCTUnwrap(popup.subviews.first { $0.accessibilityLabel() == label })
    }
}

private final class RegressionCompletionProvider: BlockInputCompletionProvider, @unchecked Sendable {
    private let suggestions: [BlockInputCompletionSuggestion]

    init(suggestions: [BlockInputCompletionSuggestion]) {
        self.suggestions = suggestions
    }

    func suggestions(for context: BlockInputCompletionContext) async -> [BlockInputCompletionSuggestion] {
        suggestions
    }
}
