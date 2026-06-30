import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewHorizontalSelectionTests: XCTestCase {
    func testShiftRightFromCollapsedCaretCreatesVisiblePartialSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "One")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 1, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftRightEvent()))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 1, length: 1))
        )))
        XCTAssertEqual(item.temporarySelectionHighlightRange, NSRange(location: 1, length: 1))
        XCTAssertFalse(item.testingSelectionBackgroundView.isHidden)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 1, length: 0))
        XCTAssertEqual(mounted.window.firstResponder, mounted.view)
        XCTAssertEqual(item.testingSelectionBackgroundView.frame.minX, try viewX(forUTF16Offset: 1, item: item), accuracy: 1)
        XCTAssertEqual(item.testingSelectionBackgroundView.frame.maxX, try viewX(forUTF16Offset: 2, item: item), accuracy: 1)
        XCTAssertLessThan(item.testingSelectionBackgroundView.frame.width, 24)
    }

    func testShiftLeftFromCollapsedCaretCreatesVisiblePartialSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "One")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftLeftEvent()))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 1, length: 1))
        )))
        XCTAssertEqual(item.temporarySelectionHighlightRange, NSRange(location: 1, length: 1))
        XCTAssertFalse(item.testingSelectionBackgroundView.isHidden)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 1, length: 0))
        XCTAssertEqual(mounted.window.firstResponder, mounted.view)
    }

    func testShiftRightContinuationAcrossLinkUsesVisibleLabelText() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let text = "Open [docs](https://example.com) trailing"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: text)
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let linkRange = try XCTUnwrap(inlineLinkRange(in: text))
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: linkRange.fullRange.location, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftRightEvent()))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftRightEvent()))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftLeftEvent()))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: blockID, range: NSRange(location: linkRange.contentRange.location, length: 1))
        )))
        XCTAssertEqual(item.temporarySelectionHighlightRange, NSRange(location: linkRange.contentRange.location, length: 1))
    }

    func testShiftDownAfterShiftRightMaintainsAdjustedActiveEdgeX() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(firstItem.testingTextView)
        let activeX = try XCTUnwrap(firstItem.textContainerX(forUTF16Offset: 3))
        let expectedSecondOffset = secondItem.utf16Offset(closestToTextContainerX: activeX, linePosition: .first)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftRightEvent()))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftDownEvent()))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 2, length: 3)),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: expectedSecondOffset))
        )))
    }

    func testShiftUpAfterShiftLeftMaintainsAdjustedActiveEdgeX() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(secondItem.testingTextView)
        let activeX = try XCTUnwrap(secondItem.textContainerX(forUTF16Offset: 2))
        let expectedFirstOffset = firstItem.utf16Offset(closestToTextContainerX: activeX, linePosition: .last)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftLeftEvent()))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftUpEvent()))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(
                blockID: firstID,
                range: NSRange(location: expectedFirstOffset, length: 5 - expectedFirstOffset)
            ),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 3))
        )))
    }

    func testShiftRightFromWholeBlockSelectionSelectsFirstCharacterOfNextBlock() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "One"),
            BlockInputBlock(id: secondID, text: "Two")
        ])
        mounted.view.applySelection(.blocks([firstID]), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftRightEvent()))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [firstID],
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 1))
        )))
    }

    func testShiftRightFromBlockAboveStartsNestedListPartialSelection() throws {
        let headingID = BlockInputBlockID(rawValue: "heading")
        let listID = BlockInputBlockID(rawValue: "list")
        let headingText = "Lists and tasks"
        let listText = "Bulleted list item\nNested bullet item\nDeep nested bullet item"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: headingID, kind: .heading(level: 2), text: headingText),
            BlockInputBlock(id: listID, kind: .bulletedListItem, text: listText, lineIndentationLevels: [0, 1, 2])
        ])
        let headingItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let listItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(headingItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (headingText as NSString).length, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftRightEvent()))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            trailingTextRange: BlockInputTextRange(blockID: listID, range: NSRange(location: 0, length: 1))
        )))
        let markerFrame = try markerLineFrame(in: listItem, lineIndex: 0)
        let segment = try XCTUnwrap(listItem.testingSelectionBackgroundSegmentFrames.first)
        XCTAssertLessThanOrEqual(segment.minX, markerFrame.minX)
        XCTAssertGreaterThanOrEqual(segment.maxX, markerFrame.maxX)
    }

    func testKeyDownShiftRightFromBlockAboveTracesNestedListSelectionBoundary() throws {
        let headingID = BlockInputBlockID(rawValue: "heading")
        let listID = BlockInputBlockID(rawValue: "list")
        let headingText = "Lists and tasks"
        let listText = "Bulleted list item\nNested bullet item\nDeep nested bullet item"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: headingID, kind: .heading(level: 2), text: headingText),
            BlockInputBlock(id: listID, kind: .bulletedListItem, text: listText, lineIndentationLevels: [0, 1, 2])
        ])
        let headingItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let listItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(headingItem.testingTextView)
        let lineStarts = lineStartOffsets(in: listText)
        let nestedLineStart = lineStarts[1]
        let firstLineEnd = nestedLineStart - 1
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (headingText as NSString).length, length: 0))

        var trace: [HorizontalSelectionTraceStep] = []
        textView.keyDown(with: try shiftRightEvent())
        trace.append(horizontalSelectionTraceStep("enter-list", in: mounted, listItem: listItem, listID: listID))

        for _ in 1..<firstLineEnd {
            mounted.view.keyDown(with: try shiftRightEvent())
            trace.append(horizontalSelectionTraceStep("extend-first-line", in: mounted, listItem: listItem, listID: listID))
        }
        mounted.view.keyDown(with: try shiftRightEvent())
        trace.append(horizontalSelectionTraceStep("enter-nested-line", in: mounted, listItem: listItem, listID: listID))

        // Keep this as a timeline assertion so regressions show the full Shift+Right path, not just the final state.
        XCTAssertEqual(
            trace.map(\.rangeSummary),
            (1...firstLineEnd).map { "{0,\($0)}" } + ["{0,\(nestedLineStart + 1)}"],
            traceDescription(trace)
        )
        XCTAssertTrue(trace.allSatisfy(\.firstResponderIsEditor), traceDescription(trace))
        XCTAssertEqual(trace.last?.selectedRange, NSRange(location: 0, length: nestedLineStart + 1))
        XCTAssertEqual(trace.last?.highlightRange, NSRange(location: 0, length: nestedLineStart + 1))

        let firstStep = try XCTUnwrap(trace.first)
        XCTAssertEqual(firstStep.segmentFrames.count, 1, traceDescription(trace))
        XCTAssertEqual(firstStep.segmentFrames[0].maxX, try viewX(forUTF16Offset: 1, item: listItem), accuracy: 1)

        let nestedMarkerFrame = try markerLineFrame(in: listItem, lineIndex: 1)
        let nestedStep = try XCTUnwrap(trace.last)
        XCTAssertTrue(nestedStep.segmentFrames.contains { segment in
            segment.minX <= nestedMarkerFrame.minX && segment.maxX >= nestedMarkerFrame.maxX
        }, traceDescription(trace))
    }

    func testShiftRightFromNestedListLineStartIncludesMarkerBounds() throws {
        let listID = BlockInputBlockID(rawValue: "list")
        let listText = "Bulleted list item\nNested bullet item\nDeep nested bullet item"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: listID, kind: .bulletedListItem, text: listText, lineIndentationLevels: [0, 1, 2])
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let nestedLineStart = lineStartOffsets(in: listText)[1]
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: nestedLineStart, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftRightEvent()))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: listID, range: NSRange(location: nestedLineStart, length: 1))
        )))
        let markerFrame = try markerLineFrame(in: item, lineIndex: 1)
        let segment = try XCTUnwrap(item.testingSelectionBackgroundSegmentFrames.first)
        XCTAssertLessThanOrEqual(segment.minX, markerFrame.minX)
        XCTAssertGreaterThanOrEqual(segment.maxX, markerFrame.maxX)
    }

    func testShiftRightFromNestedListLineEndSelectsNextVisibleListCharacter() throws {
        let listID = BlockInputBlockID(rawValue: "list")
        let listText = "Bulleted list item\nNested bullet item\nDeep nested bullet item"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: listID, kind: .bulletedListItem, text: listText, lineIndentationLevels: [0, 1, 2])
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let nestedLineStart = lineStartOffsets(in: listText)[1]
        let firstLineEnd = nestedLineStart - 1
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: firstLineEnd, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftRightEvent()))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: listID, range: NSRange(location: firstLineEnd, length: 2))
        )))
        let markerFrame = try markerLineFrame(in: item, lineIndex: 1)
        let segments = item.testingSelectionBackgroundSegmentFrames
        XCTAssertTrue(segments.contains { segment in
            segment.minX <= markerFrame.minX && segment.maxX >= markerFrame.maxX
        })
    }

    func testRepeatedShiftRightExtendsTrailingPartialSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "One"),
            BlockInputBlock(id: secondID, text: "Two")
        ])
        mounted.view.applySelection(.blocks([firstID]), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftRightEvent()))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftRightEvent()))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [firstID],
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 2))
        )))
    }

    func testShiftLeftContractsRightwardSelectionBeforeExpandingLeft() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "One"),
            BlockInputBlock(id: secondID, text: "Two")
        ])
        mounted.view.applySelection(.blocks([firstID]), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftRightEvent()))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftLeftEvent()))

        XCTAssertEqual(mounted.view.selection, .blocks([firstID]))
    }

    func testShiftLeftFromWholeBlockSelectionSelectsLastCharacterOfPreviousBlock() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "One"),
            BlockInputBlock(id: secondID, text: "Two")
        ])
        mounted.view.applySelection(.blocks([secondID]), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftLeftEvent()))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [secondID],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 2, length: 1))
        )))
    }

    func testShiftRightFromTextSelectionAtBlockEndSelectsFirstCharacterOfNextBlock() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "One"),
            BlockInputBlock(id: secondID, text: "Two")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(firstItem.testingTextView)
        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: firstID,
            range: NSRange(location: 0, length: 3)
        )), notify: false)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 3))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftRightEvent()))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [firstID],
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 1))
        )))
    }

    func testShiftLeftFromTextSelectionAtBlockStartSelectsLastCharacterOfPreviousBlock() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "One"),
            BlockInputBlock(id: secondID, text: "Two")
        ])
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(secondItem.testingTextView)
        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: secondID,
            range: NSRange(location: 0, length: 3)
        )), notify: false)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 3))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftLeftEvent()))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [secondID],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 2, length: 1))
        )))
    }

    private func viewX(forUTF16Offset offset: Int, item: BlockInputBlockItem) throws -> CGFloat {
        let textView = try XCTUnwrap(item.testingTextView)
        let textContainerX = try XCTUnwrap(item.textContainerX(forUTF16Offset: offset))
        let textContainerOrigin = textView.textContainerOrigin
        return textView.convert(
            NSPoint(x: textContainerOrigin.x + textContainerX, y: textContainerOrigin.y),
            to: item.view
        ).x
    }

    private func markerLineFrame(in item: BlockInputBlockItem, lineIndex: Int) throws -> NSRect {
        let markerView = try XCTUnwrap(item.testingMarkerView)
        let markerFrame = try XCTUnwrap(markerView.markerLineFrame(at: lineIndex))
        return markerView.convert(markerFrame, to: item.view)
    }

    private func lineStartOffsets(in text: String) -> [Int] {
        BlockInputLineBreaks.lineStartOffsets(in: text)
    }

    private func inlineLinkRange(in text: String) -> BlockInputInlineMarkdownRange? {
        BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: text,
            excluding: BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange)
        )
        .first { $0.style == .link }
    }

    private func horizontalSelectionTraceStep(
        _ label: String,
        in mounted: (view: BlockInputView, window: NSWindow),
        listItem: BlockInputBlockItem,
        listID: BlockInputBlockID
    ) -> HorizontalSelectionTraceStep {
        mounted.view.layoutSubtreeIfNeeded()
        listItem.view.layoutSubtreeIfNeeded()
        return HorizontalSelectionTraceStep(
            label: label,
            selectedRange: trailingTextRange(in: mounted.view.selection, blockID: listID)?.range,
            highlightRange: listItem.temporarySelectionHighlightRange,
            segmentFrames: listItem.testingSelectionBackgroundSegmentFrames,
            firstResponderIsEditor: mounted.window.firstResponder === mounted.view,
            selectionDescription: String(describing: mounted.view.selection)
        )
    }

    private func trailingTextRange(
        in selection: BlockInputSelection?,
        blockID: BlockInputBlockID
    ) -> BlockInputTextRange? {
        guard case let .mixed(mixedSelection) = selection,
              mixedSelection.trailingTextRange?.blockID == blockID else {
            return nil
        }
        return mixedSelection.trailingTextRange
    }

    private func traceDescription(_ trace: [HorizontalSelectionTraceStep]) -> String {
        trace.map(\.description).joined(separator: "\n")
    }
}

private struct HorizontalSelectionTraceStep: CustomStringConvertible {
    var label: String
    var selectedRange: NSRange?
    var highlightRange: NSRange?
    var segmentFrames: [NSRect]
    var firstResponderIsEditor: Bool
    var selectionDescription: String

    var rangeSummary: String {
        selectedRange.map { "{\($0.location),\($0.length)}" } ?? "nil"
    }

    var description: String {
        let highlightSummary = highlightRange.map { "{\($0.location),\($0.length)}" } ?? "nil"
        let segmentSummary = segmentFrames.map { frame in
            "{x:\(frame.minX.rounded()),y:\(frame.minY.rounded()),w:\(frame.width.rounded()),h:\(frame.height.rounded())}"
        }
        return [
            label,
            "range=\(rangeSummary)",
            "highlight=\(highlightSummary)",
            "segments=\(segmentSummary)",
            "firstResponder=\(firstResponderIsEditor ? "editor" : "other")",
            "selection=\(selectionDescription)"
        ].joined(separator: " ")
    }
}
