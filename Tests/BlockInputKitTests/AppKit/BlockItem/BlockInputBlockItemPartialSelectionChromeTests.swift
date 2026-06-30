import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputPartialSelectionChromeTests: XCTestCase {
    func testFullRangePartialSelectionChromeIncludesNestedListMarkerLineBounds() throws {
        let block = BlockInputBlock(
            id: "bullets",
            kind: .bulletedListItem,
            text: "Bulleted list item\nNested bullet item\nDeep nested bullet item",
            lineIndentationLevels: [0, 1, 2]
        )
        let item = multilineListItemForSelectionChromeTesting(block: block)
        let markerView = try XCTUnwrap(item.testingMarkerView)

        item.setSelectionHighlightRange(NSRange(location: 0, length: block.utf16Length))
        item.view.layoutSubtreeIfNeeded()

        let deepestMarkerFrame = try markerLineFrame(in: item, markerView: markerView, lineIndex: 2)
        let segments = item.testingSelectionBackgroundSegmentFrames
        XCTAssertEqual(segments.count, 3)
        XCTAssertLessThanOrEqual(segments[2].minX, deepestMarkerFrame.minX)
        XCTAssertGreaterThanOrEqual(segments[2].maxX, deepestMarkerFrame.maxX)
    }

    func testFullRangePartialSelectionChromeIncludesNestedChecklistMarkerLineBounds() throws {
        let block = BlockInputBlock(
            id: "check",
            kind: .checklistItem(isChecked: false),
            text: "Checklist item\nNested checklist item\nDeep nested checklist item",
            lineIndentationLevels: [0, 1, 2]
        )
        let item = multilineListItemForSelectionChromeTesting(block: block)
        let markerView = try XCTUnwrap(item.testingMarkerView)

        item.setSelectionHighlightRange(NSRange(location: 0, length: block.utf16Length))
        item.view.layoutSubtreeIfNeeded()

        let deepestMarkerFrame = try markerLineFrame(in: item, markerView: markerView, lineIndex: 2)
        let segments = item.testingSelectionBackgroundSegmentFrames
        XCTAssertEqual(segments.count, 3)
        XCTAssertLessThanOrEqual(segments[2].minX, deepestMarkerFrame.minX)
        XCTAssertGreaterThanOrEqual(segments[2].maxX, deepestMarkerFrame.maxX)
    }

    func testSelectionChromeFrameMergeDoesNotMergeAdjacentLines() {
        let firstLine = NSRect(x: 10, y: 0, width: 20, height: 10)
        let secondLine = NSRect(x: 10, y: 10, width: 20, height: 10)
        let secondLineMarker = NSRect(x: 0, y: 10, width: 8, height: 10)

        let merged = [firstLine, secondLine].mergingSelectionChromeFrames([secondLineMarker])

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0], firstLine)
        XCTAssertEqual(merged[1], secondLine.union(secondLineMarker))
    }

    private func multilineListItemForSelectionChromeTesting(block: BlockInputBlock) -> BlockInputBlockItem {
        let width: CGFloat = 900
        let textWidth = BlockInputBlockItem.measuredTextWidth(
            for: width,
            block: block,
            allowsReordering: true
        )
        let item = BlockInputBlockItem.configuredForTesting(
            block: block,
            allowsReordering: true,
            delegate: BlockInputView()
        )
        item.view.frame = NSRect(
            x: 0,
            y: 0,
            width: width,
            height: BlockInputBlockItem.height(for: block, textWidth: textWidth)
        )
        item.view.layoutSubtreeIfNeeded()
        return item
    }

    private func markerLineFrame(
        in item: BlockInputBlockItem,
        markerView: BlockInputMarkerView,
        lineIndex: Int
    ) throws -> NSRect {
        let markerFrame = try XCTUnwrap(markerView.markerLineFrame(at: lineIndex))
        return markerView.convert(markerFrame, to: item.view)
    }
}
