import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputListSelectionExpansionTests: XCTestCase {
    func testShiftDownSelectsNestedListLinesBeforeWholeBlocks() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let firstText = "Bulleted list item\nNested bullet item\nDeep nested bullet item"
        let secondText = "Numbered list item\nNested numbered item\nDeep nested numbered item"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, kind: .bulletedListItem, text: firstText, lineIndentationLevels: [0, 1, 2]),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 1), text: secondText, lineIndentationLevels: [0, 1, 2])
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        try performShiftDown(in: mounted, textView: textView)
        XCTAssertEqual(mounted.view.selection, .text(textRange(firstID, firstText, lines: 0...0)))

        try performShiftDown(in: mounted, textView: textView)
        XCTAssertEqual(mounted.view.selection, .text(textRange(firstID, firstText, lines: 0...1)))

        try performShiftDown(in: mounted, textView: textView)
        XCTAssertEqual(mounted.view.selection, .blocks([firstID]))

        try performShiftDown(in: mounted, textView: textView)
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [firstID],
            trailingTextRange: textRange(secondID, secondText, lines: 0...0)
        )))

        try performShiftDown(in: mounted, textView: textView)
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [firstID],
            trailingTextRange: textRange(secondID, secondText, lines: 0...1)
        )))

        try performShiftDown(in: mounted, textView: textView)
        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID]))
    }

    func testShiftUpDeselectsNestedListLinesSelectedDownward() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let firstText = "Bulleted list item\nNested bullet item\nDeep nested bullet item"
        let secondText = "Numbered list item\nNested numbered item\nDeep nested numbered item"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, kind: .bulletedListItem, text: firstText, lineIndentationLevels: [0, 1, 2]),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 1), text: secondText, lineIndentationLevels: [0, 1, 2])
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        for _ in 0..<5 {
            try performShiftDown(in: mounted, textView: textView)
        }
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [firstID],
            trailingTextRange: textRange(secondID, secondText, lines: 0...1)
        )))

        try performShiftUp(in: mounted, textView: textView)
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [firstID],
            trailingTextRange: textRange(secondID, secondText, lines: 0...0)
        )))

        try performShiftUp(in: mounted, textView: textView)
        XCTAssertEqual(mounted.view.selection, .blocks([firstID]))

        try performShiftUp(in: mounted, textView: textView)
        XCTAssertEqual(mounted.view.selection, .text(textRange(firstID, firstText, lines: 0...1)))

        try performShiftUp(in: mounted, textView: textView)
        XCTAssertEqual(mounted.view.selection, .text(textRange(firstID, firstText, lines: 0...0)))

        try performShiftUp(in: mounted, textView: textView)
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 0)))
    }

    func testShiftDownFromHeadingCaretStartsWithFirstNestedListLine() throws {
        let headingID = BlockInputBlockID(rawValue: "heading")
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let headingText = "Lists and tasks"
        let firstText = "Bulleted list item\nNested bullet item\nDeep nested bullet item"
        let secondText = "Numbered list item\nNested numbered item\nDeep nested numbered item"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: headingID, kind: .heading(level: 2), text: headingText),
            BlockInputBlock(id: firstID, kind: .bulletedListItem, text: firstText, lineIndentationLevels: [0, 1, 2]),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 1), text: secondText, lineIndentationLevels: [0, 1, 2])
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (headingText as NSString).length, length: 0))

        try performShiftDown(in: mounted, textView: textView)
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            trailingTextRange: textRange(firstID, firstText, lines: 0...0)
        )))

        try performShiftDown(in: mounted, textView: textView)
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            trailingTextRange: textRange(firstID, firstText, lines: 0...1)
        )))

        try performShiftDown(in: mounted, textView: textView)
        XCTAssertEqual(mounted.view.selection, .blocks([firstID]))

        try performShiftDown(in: mounted, textView: textView)
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [firstID],
            trailingTextRange: textRange(secondID, secondText, lines: 0...0)
        )))
    }

    func testShiftUpFromHeadingOriginDeselectsNestedListLinesBeforeReturningToHeadingCaret() throws {
        let headingID = BlockInputBlockID(rawValue: "heading")
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let headingText = "Lists and tasks"
        let firstText = "Bulleted list item\nNested bullet item\nDeep nested bullet item"
        let secondText = "Numbered list item\nNested numbered item\nDeep nested numbered item"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: headingID, kind: .heading(level: 2), text: headingText),
            BlockInputBlock(id: firstID, kind: .bulletedListItem, text: firstText, lineIndentationLevels: [0, 1, 2]),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 1), text: secondText, lineIndentationLevels: [0, 1, 2])
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (headingText as NSString).length, length: 0))
        for _ in 0..<5 {
            try performShiftDown(in: mounted, textView: textView)
        }
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [firstID],
            trailingTextRange: textRange(secondID, secondText, lines: 0...1)
        )))

        // The heading is an excluded anchor, so each reverse key press must shrink the active list edge
        // before the original heading caret is restored.
        try performShiftUp(in: mounted, textView: textView)
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [firstID],
            trailingTextRange: textRange(secondID, secondText, lines: 0...0)
        )))

        try performShiftUp(in: mounted, textView: textView)
        XCTAssertEqual(mounted.view.selection, .blocks([firstID]))

        try performShiftUp(in: mounted, textView: textView)
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            trailingTextRange: textRange(firstID, firstText, lines: 0...1)
        )))

        try performShiftUp(in: mounted, textView: textView)
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            trailingTextRange: textRange(firstID, firstText, lines: 0...0)
        )))

        try performShiftUp(in: mounted, textView: textView)
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(
            blockID: headingID,
            utf16Offset: (headingText as NSString).length
        )))
    }

    func testShiftUpFromHeadingOriginDemotesWholeNestedListBlockBeforeRemovingIt() throws {
        let headingID = BlockInputBlockID(rawValue: "heading")
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let headingText = "Lists and tasks"
        let firstText = "Bulleted list item\nNested bullet item\nDeep nested bullet item"
        let secondText = "Numbered list item\nNested numbered item\nDeep nested numbered item"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: headingID, kind: .heading(level: 2), text: headingText),
            BlockInputBlock(id: firstID, kind: .bulletedListItem, text: firstText, lineIndentationLevels: [0, 1, 2]),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 1), text: secondText, lineIndentationLevels: [0, 1, 2])
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (headingText as NSString).length, length: 0))
        for _ in 0..<6 {
            try performShiftDown(in: mounted, textView: textView)
        }
        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID]))

        try performShiftUp(in: mounted, textView: textView)
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [firstID],
            trailingTextRange: textRange(secondID, secondText, lines: 0...1)
        )))
    }

    private func performShiftDown(
        in mounted: (view: BlockInputView, window: NSWindow),
        textView: BlockInputTextView
    ) throws {
        XCTAssertTrue(performKeyEquivalent(in: mounted, textView: textView, event: try shiftDownEvent()))
    }

    private func performShiftUp(
        in mounted: (view: BlockInputView, window: NSWindow),
        textView: BlockInputTextView
    ) throws {
        XCTAssertTrue(performKeyEquivalent(in: mounted, textView: textView, event: try shiftUpEvent()))
    }

    private func performKeyEquivalent(
        in mounted: (view: BlockInputView, window: NSWindow),
        textView: BlockInputTextView,
        event: NSEvent
    ) -> Bool {
        if mounted.window.firstResponder === mounted.view {
            return mounted.view.performKeyEquivalent(with: event)
        }
        return textView.performKeyEquivalent(with: event)
    }

    private func textRange(_ blockID: BlockInputBlockID, _ text: String, lines: ClosedRange<Int>) -> BlockInputTextRange {
        BlockInputTextRange(blockID: blockID, range: textRange(text, lines: lines))
    }

    private func textRange(_ text: String, lines: ClosedRange<Int>) -> NSRange {
        let lineStarts = BlockInputLineBreaks.lineStartOffsets(in: text)
        let location = lineStarts[lines.lowerBound]
        let end = lineStarts.indices.contains(lines.upperBound + 1)
            ? lineStarts[lines.upperBound + 1]
            : (text as NSString).length
        return NSRange(location: location, length: end - location)
    }
}
