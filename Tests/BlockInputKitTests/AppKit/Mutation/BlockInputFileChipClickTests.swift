import AppKit
import XCTest
@testable import BlockInputKit

/// File-chip click routing: a plain click should reach the host handler so it can edit inline (`.showLinkModal`), while a
/// command click should let the host open the file (`.hostHandled`). Mirrors the demo's file-chip handler.
@MainActor
final class BlockInputFileChipClickTests: XCTestCase {
    private let text = "See [README.md](<file:///tmp/README.md>) now"

    private func chipOffset() -> Int {
        (text as NSString).range(of: "README.md").location
    }

    private func makeView(
        handler: @escaping @MainActor (BlockInputInlineLinkClickContext) -> BlockInputInlineLinkClickAction
    ) -> (view: BlockInputView, window: NSWindow) {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "block", text: text)]),
            inlineLinkClickHandler: handler
        ))
        return (mounted.view, mounted.window)
    }

    func testPlainClickReachesHandlerAsFileChip() throws {
        var kinds: [BlockInputInlineLinkKind] = []
        var clickKinds: [BlockInputSlashCommandChipClickKind] = []
        let (view, window) = makeView { context in
            kinds.append(context.kind)
            clickKinds.append(context.clickKind)
            return .showLinkModal
        }
        let textView = try textView(in: view)
        let location = try windowLocation(forUTF16Offset: chipOffset(), in: textView)

        XCTAssertTrue(view.handleLinkClick(
            blockID: "block",
            selectedRange: NSRange(location: chipOffset(), length: 0),
            event: try mouseDownEvent(location: location, windowNumber: window.windowNumber)
        ))
        XCTAssertEqual(kinds.last, .fileChip)
        XCTAssertEqual(clickKinds.last, .plainClick)
    }

    func testCommandClickReportsCommandClickKind() throws {
        var clickKinds: [BlockInputSlashCommandChipClickKind] = []
        let (view, window) = makeView { context in
            clickKinds.append(context.clickKind)
            return context.event.modifierFlags.contains(.command) ? .hostHandled : .showLinkModal
        }
        let textView = try textView(in: view)
        let location = try windowLocation(forUTF16Offset: chipOffset(), in: textView)

        XCTAssertTrue(view.handleLinkClick(
            blockID: "block",
            selectedRange: NSRange(location: chipOffset(), length: 0),
            event: try mouseDownEvent(location: location, windowNumber: window.windowNumber, modifierFlags: .command)
        ))
        XCTAssertEqual(clickKinds.last, .commandClick)
        // hostHandled must NOT open the link modal.
        XCTAssertNil(view.linkModalView)
    }

    func testPlaceCaretActionDoesNotConsumeClick() throws {
        let (view, window) = makeView { _ in .placeCaret }
        let textView = try textView(in: view)
        let location = try windowLocation(forUTF16Offset: chipOffset(), in: textView)

        // `.placeCaret` must NOT consume the click (returns false), so the editor places the caret for inline editing.
        XCTAssertFalse(view.handleLinkClick(
            blockID: "block",
            selectedRange: NSRange(location: chipOffset(), length: 0),
            event: try mouseDownEvent(location: location, windowNumber: window.windowNumber)
        ))
        XCTAssertNil(view.linkModalView, "placeCaret must not open the modal.")
    }

    func testHoverAffordanceIncludesHostActionForFileChip() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "block", text: text)]),
            linkHoverActionsProvider: { context in
                context.kind == .fileChip
                    ? [BlockInputLinkHoverAction(title: "Show in Finder") {}]
                    : []
            }
        ))
        let view = mounted.view
        let chipRange = try XCTUnwrap(
            BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text, excluding: [])
                .first { $0.inlineChipKind(in: text) == .fileLink }
        )
        view.showLinkHoverEditAffordance(
            blockID: "block",
            sourceLinkRange: chipRange,
            windowRects: [NSRect(x: 10, y: 10, width: 40, height: 16)]
        )
        let titles = try XCTUnwrap(view.linkHoverPopover?.buttonTitlesForTesting)
        XCTAssertEqual(titles, ["Open", "Show in Finder", "Edit"])
    }

    func testHoverOpenOpensFileEvenWhenClickHandlerPlacesCaret() throws {
        // The shipped demo returns .placeCaret for plain file-chip clicks; the hover Open button must still open.
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "block", text: text)]),
            inlineLinkClickHandler: { _ in .placeCaret }
        ))
        let view = mounted.view
        var opened: [URL] = []
        view.linkURLOpener = { opened.append($0); return true }
        let chipRange = try XCTUnwrap(
            BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text, excluding: [])
                .first { $0.inlineChipKind(in: text) == .fileLink }
        )
        view.showLinkHoverEditAffordance(
            blockID: "block",
            sourceLinkRange: chipRange,
            windowRects: [NSRect(x: 10, y: 10, width: 40, height: 16)]
        )
        let popover = try XCTUnwrap(view.linkHoverPopover)
        let openIndex = try XCTUnwrap(popover.buttonTitlesForTesting.firstIndex(of: "Open"))
        popover.performButtonForTesting(at: openIndex)
        XCTAssertEqual(opened.map(\.absoluteString), ["file:///tmp/README.md"])
    }

    func testHoverAffordanceSuppressedWhileDiagramSurfacePresented() throws {
        // While a diagram surface is open the underlying document must not show link-hover affordances.
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "block", text: text)])
        ))
        let view = mounted.view
        let chipRange = try XCTUnwrap(
            BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text, excluding: [])
                .first { $0.inlineChipKind(in: text) == .fileLink }
        )
        let rects = [NSRect(x: 10, y: 10, width: 40, height: 16)]

        // Baseline: with no surface presented the popover appears.
        view.showLinkHoverEditAffordance(blockID: "block", sourceLinkRange: chipRange, windowRects: rects)
        XCTAssertNotNil(view.linkHoverPopover, "hover popover shows when no surface is open")

        // With a surface presented the popover is suppressed and any existing one is hidden.
        // isDiagramSurfacePresented is derived from a live surface, so presenting a scaffold makes it true.
        view.interactiveDiagramScaffold = BlockInputDiagramSurfaceScaffold()
        XCTAssertTrue(view.isDiagramSurfacePresented)
        view.showLinkHoverEditAffordance(blockID: "block", sourceLinkRange: chipRange, windowRects: rects)
        XCTAssertNil(view.linkHoverPopover, "hover popover is suppressed while a diagram surface is presented")
    }

    private func textView(in view: BlockInputView) throws -> BlockInputTextView {
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        return try XCTUnwrap(item.testingTextView)
    }
}
