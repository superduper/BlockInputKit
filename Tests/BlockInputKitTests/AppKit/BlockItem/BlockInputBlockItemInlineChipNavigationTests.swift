import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputInlineChipNavigationTests: XCTestCase {
    func testPlainLeftAtFileLinkChipContentStartExitsLeadingEdge() throws {
        let text = "Open [README.md](file:///tmp/README.md) trailing"
        let textView = try mountedTextView(for: text)
        let linkRange = try XCTUnwrap(inlineLinkRange(in: text))
        textView.setSelectedRange(NSRange(location: linkRange.contentRange.location, length: 0))

        textView.keyDown(with: try plainLeftEvent())

        XCTAssertEqual(textView.selectedRange(), NSRange(location: linkRange.fullRange.location - 1, length: 0))
        XCTAssertEqual(textView.selectionAffinity, .upstream)
        XCTAssertLessThan(try caretRect(in: textView).minX, try chipRect(in: textView, for: linkRange).minX)
    }

    func testPlainLeftAtDocumentStartFileLinkChipContentStartDoesNotJumpToTrailingEdge() throws {
        let text = "[README.md](file:///tmp/README.md) trailing"
        let textView = try mountedTextView(for: text)
        let linkRange = try XCTUnwrap(inlineLinkRange(in: text))
        textView.setSelectedRange(NSRange(location: linkRange.contentRange.location, length: 0))

        textView.keyDown(with: try plainLeftEvent())
        textView.keyDown(with: try plainLeftEvent())

        XCTAssertEqual(textView.selectedRange(), NSRange(location: linkRange.fullRange.location, length: 0))
        try assertCaret(in: textView, isAtLeadingEdgeOfChipFor: linkRange)
    }

    func testPlainLeftAtFileLinkChipContentStartMovesAcrossPrecedingComposedCharacter() throws {
        let text = "👩‍💻 [README.md](file:///tmp/README.md) trailing"
        let textView = try mountedTextView(for: text)
        let linkRange = try XCTUnwrap(inlineLinkRange(in: text))
        textView.setSelectedRange(NSRange(location: linkRange.contentRange.location, length: 0))

        textView.keyDown(with: try plainLeftEvent())

        let expectedRange = (text as NSString).rangeOfComposedCharacterSequence(at: linkRange.fullRange.location - 1)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: expectedRange.location, length: 0))
        XCTAssertLessThan(try caretRect(in: textView).minX, try chipRect(in: textView, for: linkRange).minX)
    }

    func testPlainLeftAtFileLinkChipLeadingEdgeMovesIntoPrecedingText() throws {
        let text = "Open [README.md](file:///tmp/README.md) trailing"
        let textView = try mountedTextView(for: text)
        let linkRange = try XCTUnwrap(inlineLinkRange(in: text))
        setCaret(in: textView, to: linkRange.fullRange.location, affinity: .upstream)

        textView.keyDown(with: try plainLeftEvent())

        XCTAssertEqual(textView.selectedRange(), NSRange(location: linkRange.fullRange.location - 1, length: 0))
        XCTAssertLessThan(try caretRect(in: textView).minX, try chipRect(in: textView, for: linkRange).minX)
    }

    func testRepeatedPlainLeftAtDocumentStartChipLeadingEdgeDoesNotJumpToTrailingEdge() throws {
        let text = "[README.md](file:///tmp/README.md) trailing"
        let textView = try mountedTextView(for: text)
        let linkRange = try XCTUnwrap(inlineLinkRange(in: text))
        setCaret(in: textView, to: linkRange.fullRange.location, affinity: .upstream)

        for _ in 0..<3 {
            textView.keyDown(with: try plainLeftEvent())
        }

        XCTAssertEqual(textView.selectedRange(), NSRange(location: linkRange.fullRange.location, length: 0))
        try assertCaret(in: textView, isAtLeadingEdgeOfChipFor: linkRange)
    }

    func testMoveLeftCommandAtDocumentStartChipLeadingEdgeDoesNotJumpToTrailingEdge() throws {
        let text = "[README.md](file:///tmp/README.md) trailing"
        let textView = try mountedTextView(for: text)
        let linkRange = try XCTUnwrap(inlineLinkRange(in: text))
        setCaret(in: textView, to: linkRange.fullRange.location, affinity: .upstream)

        textView.doCommand(by: #selector(NSResponder.moveLeft(_:)))
        textView.doCommand(by: #selector(NSResponder.moveLeft(_:)))

        XCTAssertEqual(textView.selectedRange(), NSRange(location: linkRange.fullRange.location, length: 0))
        try assertCaret(in: textView, isAtLeadingEdgeOfChipFor: linkRange)
    }

    func testPlainRightAtFileLinkChipContentEndExitsTrailingEdge() throws {
        let text = "Open [README.md](file:///tmp/README.md) trailing"
        let textView = try mountedTextView(for: text)
        let linkRange = try XCTUnwrap(inlineLinkRange(in: text))
        textView.setSelectedRange(NSRange(location: NSMaxRange(linkRange.contentRange), length: 0))

        textView.keyDown(with: try plainRightEvent())

        XCTAssertEqual(textView.selectedRange(), NSRange(location: NSMaxRange(linkRange.fullRange) + 1, length: 0))
        XCTAssertEqual(textView.selectionAffinity, .downstream)
        XCTAssertGreaterThan(try caretRect(in: textView).minX, try chipRect(in: textView, for: linkRange).maxX)
    }

    func testPlainRightAtFileLinkChipTrailingEdgeMovesIntoFollowingText() throws {
        let text = "Open [README.md](file:///tmp/README.md) trailing"
        let textView = try mountedTextView(for: text)
        let linkRange = try XCTUnwrap(inlineLinkRange(in: text))
        setCaret(in: textView, to: NSMaxRange(linkRange.fullRange), affinity: .downstream)

        textView.keyDown(with: try plainRightEvent())

        XCTAssertEqual(textView.selectedRange(), NSRange(location: NSMaxRange(linkRange.fullRange) + 1, length: 0))
        XCTAssertGreaterThan(try caretRect(in: textView).minX, try chipRect(in: textView, for: linkRange).maxX)
    }

    func testPlainRightAtDocumentEndFileLinkChipContentEndDoesNotMovePastDocumentEnd() throws {
        let text = "Open [README.md](file:///tmp/README.md)"
        let textView = try mountedTextView(for: text)
        let linkRange = try XCTUnwrap(inlineLinkRange(in: text))
        textView.setSelectedRange(NSRange(location: NSMaxRange(linkRange.contentRange), length: 0))

        textView.keyDown(with: try plainRightEvent())
        textView.keyDown(with: try plainRightEvent())

        XCTAssertEqual(textView.selectedRange(), NSRange(location: NSMaxRange(linkRange.fullRange), length: 0))
        try assertCaret(in: textView, isAtTrailingEdgeOfChipFor: linkRange)
    }

    func testPlainRightAtFileLinkChipContentEndMovesAcrossFollowingComposedCharacter() throws {
        let text = "Open [README.md](file:///tmp/README.md) 👩‍💻"
        let textView = try mountedTextView(for: text)
        let linkRange = try XCTUnwrap(inlineLinkRange(in: text))
        textView.setSelectedRange(NSRange(location: NSMaxRange(linkRange.contentRange), length: 0))

        textView.keyDown(with: try plainRightEvent())

        let expectedRange = (text as NSString).rangeOfComposedCharacterSequence(at: NSMaxRange(linkRange.fullRange))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: NSMaxRange(expectedRange), length: 0))
        XCTAssertGreaterThan(try caretRect(in: textView).minX, try chipRect(in: textView, for: linkRange).maxX)
    }

    func testMoveLeftCommandAtSlashCommandChipContentStartExitsLeadingEdge() throws {
        let text = "Run [/table](host-app://commands/table) today"
        let textView = try mountedTextView(for: text)
        let linkRange = try XCTUnwrap(inlineLinkRange(in: text))
        textView.setSelectedRange(NSRange(location: linkRange.contentRange.location, length: 0))

        textView.doCommand(by: #selector(NSResponder.moveLeft(_:)))

        XCTAssertEqual(textView.selectedRange(), NSRange(location: linkRange.fullRange.location - 1, length: 0))
        XCTAssertEqual(textView.selectionAffinity, .upstream)
        XCTAssertLessThan(try caretRect(in: textView).minX, try chipRect(in: textView, for: linkRange).minX)
    }

    func testMoveRightCommandAtSlashCommandChipContentEndExitsTrailingEdge() throws {
        let text = "Run [/table](host-app://commands/table) today"
        let textView = try mountedTextView(for: text)
        let linkRange = try XCTUnwrap(inlineLinkRange(in: text))
        textView.setSelectedRange(NSRange(location: NSMaxRange(linkRange.contentRange), length: 0))

        textView.doCommand(by: #selector(NSResponder.moveRight(_:)))

        XCTAssertEqual(textView.selectedRange(), NSRange(location: NSMaxRange(linkRange.fullRange) + 1, length: 0))
        XCTAssertEqual(textView.selectionAffinity, .downstream)
        XCTAssertGreaterThan(try caretRect(in: textView).minX, try chipRect(in: textView, for: linkRange).maxX)
    }

    func testPlainHorizontalMovementInsideFileLinkChipUsesNativeMovement() throws {
        let text = "Open [README.md](file:///tmp/README.md) trailing"
        let textView = try mountedTextView(for: text)
        let linkRange = try XCTUnwrap(inlineLinkRange(in: text))

        textView.setSelectedRange(NSRange(location: linkRange.contentRange.location + 1, length: 0))
        textView.keyDown(with: try plainLeftEvent())
        XCTAssertEqual(textView.selectedRange(), NSRange(location: linkRange.contentRange.location, length: 0))

        textView.setSelectedRange(NSRange(location: NSMaxRange(linkRange.contentRange) - 2, length: 0))
        textView.keyDown(with: try plainRightEvent())
        XCTAssertEqual(textView.selectedRange(), NSRange(location: NSMaxRange(linkRange.contentRange) - 1, length: 0))
    }

    func testOptionRightAtNormalLinkSourceBoundaryMovesToVisibleLabelEnd() throws {
        let text = "Open [docs](https://example.com) trailing"
        let textView = try mountedTextView(for: text)
        let linkRange = try XCTUnwrap(inlineLinkRange(in: text))
        setCaret(in: textView, to: linkRange.fullRange.location, affinity: .upstream)

        textView.keyDown(with: try optionRightEvent())

        XCTAssertEqual(textView.selectedRange(), NSRange(location: NSMaxRange(linkRange.contentRange), length: 0))
    }

    func testOptionRightAtEmojiLinkSourceBoundaryKeepsComposedLabelIntact() throws {
        let text = "Open [👩‍💻](https://example.com) trailing"
        let textView = try mountedTextView(for: text)
        let linkRange = try XCTUnwrap(inlineLinkRange(in: text))
        setCaret(in: textView, to: linkRange.fullRange.location, affinity: .upstream)

        textView.keyDown(with: try optionRightEvent())

        XCTAssertEqual(textView.selectedRange(), NSRange(location: NSMaxRange(linkRange.contentRange), length: 0))
    }

    func testOptionRightKeyEquivalentAtNormalLinkSourceBoundaryMovesToVisibleLabelEnd() throws {
        let text = "Open [docs](https://example.com) trailing"
        let textView = try mountedTextView(for: text)
        let linkRange = try XCTUnwrap(inlineLinkRange(in: text))
        setCaret(in: textView, to: linkRange.fullRange.location, affinity: .upstream)

        XCTAssertTrue(textView.performKeyEquivalent(with: try optionRightEvent()))

        XCTAssertEqual(textView.selectedRange(), NSRange(location: NSMaxRange(linkRange.contentRange), length: 0))
    }

    func testOptionLeftAtNormalLinkTrailingSourceBoundaryMovesToVisibleLabelStart() throws {
        let text = "Open [docs](https://example.com) trailing"
        let textView = try mountedTextView(for: text)
        let linkRange = try XCTUnwrap(inlineLinkRange(in: text))
        setCaret(in: textView, to: NSMaxRange(linkRange.fullRange), affinity: .downstream)

        textView.keyDown(with: try optionLeftEvent())

        XCTAssertEqual(textView.selectedRange(), NSRange(location: linkRange.contentRange.location, length: 0))
    }

    func testMoveWordRightInsideFileChipStopsAtVisibleLabelEnd() throws {
        let text = "Open [README.md](file:///tmp/README.md) trailing"
        let textView = try mountedTextView(for: text)
        let linkRange = try XCTUnwrap(inlineLinkRange(in: text))
        textView.setSelectedRange(NSRange(location: linkRange.contentRange.location, length: 0))

        textView.moveWordRight(nil)

        XCTAssertEqual(textView.selectedRange(), NSRange(location: NSMaxRange(linkRange.contentRange), length: 0))
    }

    func testMoveWordLeftInsideSlashCommandChipStopsAtVisibleLabelStart() throws {
        let text = "Run [/table](host-app://commands/table) today"
        let textView = try mountedTextView(for: text)
        let linkRange = try XCTUnwrap(inlineLinkRange(in: text))
        textView.setSelectedRange(NSRange(location: NSMaxRange(linkRange.contentRange), length: 0))

        textView.moveWordLeft(nil)

        XCTAssertEqual(textView.selectedRange(), NSRange(location: linkRange.contentRange.location, length: 0))
    }

    func testShiftRightAtLinkSourceBoundarySelectsFirstVisibleLabelCharacter() throws {
        let text = "Open [docs](https://example.com) trailing"
        let textView = try mountedTextView(for: text)
        let linkRange = try XCTUnwrap(inlineLinkRange(in: text))
        setCaret(in: textView, to: linkRange.fullRange.location, affinity: .upstream)

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftRightEvent()))

        XCTAssertEqual(
            textView.blockItem?.temporarySelectionHighlightRange,
            NSRange(location: linkRange.contentRange.location, length: 1)
        )
    }

    func testShiftLeftAtLinkTrailingSourceBoundarySelectsLastVisibleLabelCharacter() throws {
        let text = "Open [docs](https://example.com) trailing"
        let textView = try mountedTextView(for: text)
        let linkRange = try XCTUnwrap(inlineLinkRange(in: text))
        setCaret(in: textView, to: NSMaxRange(linkRange.fullRange), affinity: .downstream)

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftLeftEvent()))

        XCTAssertEqual(
            textView.blockItem?.temporarySelectionHighlightRange,
            NSRange(location: NSMaxRange(linkRange.contentRange) - 1, length: 1)
        )
    }

    func testShiftRightSkipsEscapedLinkLabelBackslash() throws {
        let text = "Open [a\\[b\\]c](https://example.com) trailing"
        let textView = try mountedTextView(for: text)
        let escapedOpenBracketRange = (text as NSString).range(of: "\\[")

        textView.setSelectedRange(NSRange(location: escapedOpenBracketRange.location, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftRightEvent()))
        XCTAssertEqual(
            textView.blockItem?.temporarySelectionHighlightRange,
            NSRange(location: escapedOpenBracketRange.location + 1, length: 1)
        )
    }

    func testPlainLeftAtRawSlashCommandChipUsesNativeMovement() throws {
        let text = "Run /table today"
        let textView = try mountedTextView(
            configuration: BlockInputConfiguration(
                document: BlockInputDocument(blocks: [
                    BlockInputBlock(id: "paragraph", kind: .paragraph, text: text)
                ]),
                rawSlashCommandChips: true,
                slashCommandAvailability: .anywhere
            )
        )
        let slashOffset = contentLocation("/table", in: text)
        textView.setSelectedRange(NSRange(location: slashOffset, length: 0))

        textView.keyDown(with: try plainLeftEvent())

        XCTAssertEqual(textView.selectedRange(), NSRange(location: slashOffset - 1, length: 0))
    }

    func testShiftRightAtRawSlashCommandChipUsesNativeSelection() throws {
        let text = "Run /table today"
        let textView = try mountedTextView(
            configuration: BlockInputConfiguration(
                document: BlockInputDocument(blocks: [
                    BlockInputBlock(id: "paragraph", kind: .paragraph, text: text)
                ]),
                rawSlashCommandChips: true,
                slashCommandAvailability: .anywhere
            )
        )
        let slashOffset = contentLocation("/table", in: text)
        textView.setSelectedRange(NSRange(location: slashOffset, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftRightEvent()))

        XCTAssertEqual(textView.blockItem?.temporarySelectionHighlightRange, NSRange(location: slashOffset, length: 1))
    }

    private func mountedTextView(for text: String) throws -> BlockInputTextView {
        try mountedTextView(
            configuration: BlockInputConfiguration(document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "paragraph", kind: .paragraph, text: text)
            ]))
        )
    }

    private func mountedTextView(configuration: BlockInputConfiguration) throws -> BlockInputTextView {
        let mounted = makeMountedBlockInputView(configuration: configuration)
        resizeMountedBlockInputView(mounted, to: NSSize(width: 620, height: 140))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.layoutManager?.ensureLayout(for: try XCTUnwrap(textView.textContainer))
        return textView
    }

    private func setCaret(in textView: BlockInputTextView, to offset: Int, affinity: NSSelectionAffinity) {
        textView.setSelectedRanges([NSValue(range: NSRange(location: offset, length: 0))], affinity: affinity, stillSelecting: false)
    }

    private func inlineLinkRange(in text: String) -> BlockInputInlineMarkdownRange? {
        BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: text,
            excluding: BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange)
        )
        .first { $0.style == .link }
    }

    private func contentLocation(_ content: String, in text: String) -> Int {
        (text as NSString).range(of: content).location
    }

    private func assertCaret(
        in textView: BlockInputTextView,
        isAtLeadingEdgeOfChipFor range: BlockInputInlineMarkdownRange,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let caretRect = try caretRect(in: textView)
        let chipRect = try chipRect(in: textView, for: range)
        XCTAssertLessThanOrEqual(caretRect.minX, chipRect.minX + 3, file: file, line: line)
        XCTAssertLessThan(caretRect.minX, chipRect.midX, file: file, line: line)
    }

    private func assertCaret(
        in textView: BlockInputTextView,
        isAtTrailingEdgeOfChipFor range: BlockInputInlineMarkdownRange,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let caretRect = try caretRect(in: textView)
        let chipRect = try chipRect(in: textView, for: range)
        XCTAssertGreaterThanOrEqual(caretRect.minX, chipRect.maxX - 3, file: file, line: line)
        XCTAssertGreaterThan(caretRect.minX, chipRect.midX, file: file, line: line)
    }

    private func caretRect(in textView: BlockInputTextView) throws -> NSRect {
        let screenRect = textView.firstRect(forCharacterRange: textView.selectedRange(), actualRange: nil)
        guard screenRect != .zero, !screenRect.isNull, !screenRect.isInfinite else {
            return try XCTUnwrap(Optional<NSRect>.none)
        }
        let window = try XCTUnwrap(textView.window)
        let windowPoint = window.convertPoint(fromScreen: screenRect.origin)
        return NSRect(origin: textView.convert(windowPoint, from: nil), size: screenRect.size)
    }

    private func chipRect(in textView: BlockInputTextView, for range: BlockInputInlineMarkdownRange) throws -> NSRect {
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range.contentRange, actualCharacterRange: nil)
        let contentRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            .offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
        return try XCTUnwrap(textView.inlineChipBackgroundRectsForTesting().first { $0.intersects(contentRect) })
    }
}
