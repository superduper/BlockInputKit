import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewLineBoundarySelectionTests: XCTestCase {
    func testCommandShiftRightMovesTrailingActiveEdgeToSecondBlockLineEnd() throws {
        let context = try screenshotLikeLineBoundaryContext()
        context.mounted.view.applySelection(.mixed(context.selection), notify: false)
        context.mounted.view.blockSelectionExpansion = BlockInputBlockSelectionExpansion(
            anchorBlockID: context.headingID,
            direction: .downward
        )
        context.mounted.window.makeFirstResponder(context.mounted.view)
        XCTAssertTrue(context.mounted.view.performKeyEquivalent(with: try commandShiftRightEvent()))

        XCTAssertEqual(context.mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [context.paragraphID],
            leadingTextRange: context.selection.leadingTextRange
        )))
        XCTAssertNil(context.paragraphItem.temporarySelectionHighlightRange)
        XCTAssertEqual(context.paragraphItem.testingTextView?.selectedRange().length, 0)
        XCTAssertEqual(context.mounted.window.firstResponder, context.mounted.view)
    }

    func testCommandShiftLeftMovesTrailingActiveEdgeToSecondBlockLineStart() throws {
        let context = try screenshotLikeLineBoundaryContext(trailingLength: 42)
        context.mounted.view.applySelection(.mixed(context.selection), notify: false)
        context.mounted.view.blockSelectionExpansion = BlockInputBlockSelectionExpansion(
            anchorBlockID: context.headingID,
            direction: .downward
        )
        context.mounted.window.makeFirstResponder(context.mounted.view)
        let expectedStart = context.paragraphItem.lineBoundaryUTF16Offset(
            containingUTF16Offset: 42,
            direction: .beginning
        )

        XCTAssertTrue(context.mounted.view.performKeyEquivalent(with: try commandShiftLeftEvent()))

        XCTAssertEqual(expectedStart, 0)
        XCTAssertEqual(context.mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: context.selection.leadingTextRange
        )))
        XCTAssertEqual(context.paragraphItem.temporarySelectionHighlightRange, nil)
        XCTAssertEqual(context.mounted.window.firstResponder, context.mounted.view)
    }

    func testCommandShiftLeftUsesLeadingActiveEdgeWhenSelectionExpandedUpward() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let firstText = "First block"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: firstText),
            BlockInputBlock(id: secondID, text: "Second block")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let leadingRange = BlockInputTextRange(blockID: firstID, range: NSRange(location: 4, length: firstText.count - 4))
        mounted.view.applySelection(.mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: leadingRange,
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 3))
        )), notify: false)
        mounted.view.blockSelectionExpansion = BlockInputBlockSelectionExpansion(anchorBlockID: secondID, direction: .upward)
        mounted.window.makeFirstResponder(mounted.view)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandShiftLeftEvent()))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [firstID],
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 3))
        )))
        XCTAssertEqual(firstItem.temporarySelectionHighlightRange, nil)
    }

    func testShiftLeftContinuesFromCommandShiftRightLineBoundary() throws {
        let context = try screenshotLikeLineBoundaryContext()
        context.mounted.view.applySelection(.mixed(context.selection), notify: false)
        context.mounted.view.blockSelectionExpansion = BlockInputBlockSelectionExpansion(
            anchorBlockID: context.headingID,
            direction: .downward
        )
        context.mounted.window.makeFirstResponder(context.mounted.view)
        let expectedEnd = context.paragraphItem.lineBoundaryUTF16Offset(
            containingUTF16Offset: context.initialTrailingEnd,
            direction: .end
        )

        XCTAssertTrue(context.mounted.view.performKeyEquivalent(with: try commandShiftRightEvent()))
        XCTAssertTrue(context.mounted.view.performKeyEquivalent(with: try shiftLeftEvent()))

        XCTAssertEqual(context.mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: context.selection.leadingTextRange,
            trailingTextRange: BlockInputTextRange(
                blockID: context.paragraphID,
                range: NSRange(location: 0, length: expectedEnd - 1)
            )
        )))
    }

    func testShiftDownContinuesFromCommandShiftRightLineBoundary() throws {
        let headingID = BlockInputBlockID(rawValue: "heading")
        let paragraphID = BlockInputBlockID(rawValue: "paragraph")
        let belowID = BlockInputBlockID(rawValue: "below")
        let headingText = "Headings level 6"
        let paragraphText = "Inline items include bold, italic, underline, and inline code."
        let belowText = "Next line keeps the continuation active edge visible with enough text for a partial endpoint"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: headingID, kind: .heading(level: 6), text: headingText),
            BlockInputBlock(id: paragraphID, text: paragraphText),
            BlockInputBlock(id: belowID, text: belowText)
        ])
        let paragraphItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let belowItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        let expectedParagraphEnd = paragraphItem.lineBoundaryUTF16Offset(containingUTF16Offset: 12, direction: .end)
        let activeX = try XCTUnwrap(paragraphItem.textContainerX(forUTF16Offset: expectedParagraphEnd))
        let expectedBelowOffset = belowItem.utf16Offset(closestToTextContainerX: activeX, linePosition: .first)
        XCTAssertGreaterThan(expectedBelowOffset, 0)
        let leadingStart = (headingText as NSString).range(of: "level").location
        mounted.view.applySelection(.mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(
                blockID: headingID,
                range: NSRange(location: leadingStart, length: (headingText as NSString).length - leadingStart)
            ),
            trailingTextRange: BlockInputTextRange(blockID: paragraphID, range: NSRange(location: 0, length: 12))
        )), notify: false)
        mounted.view.blockSelectionExpansion = BlockInputBlockSelectionExpansion(anchorBlockID: headingID, direction: .downward)
        mounted.window.makeFirstResponder(mounted.view)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandShiftRightEvent()))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftDownEvent()))

        guard case let .mixed(selection) = mounted.view.selection else {
            return XCTFail("Expected mixed selection, got \(String(describing: mounted.view.selection))")
        }
        XCTAssertEqual(selection.blockIDs, [paragraphID])
        XCTAssertEqual(selection.leadingTextRange?.blockID, headingID)
        XCTAssertEqual(selection.trailingTextRange?.blockID, belowID)
        XCTAssertGreaterThan(selection.trailingTextRange?.range.length ?? 0, 0)
    }

    func testShiftDownContinuesFromCommandShiftLeftLineBoundary() throws {
        let headingID = BlockInputBlockID(rawValue: "heading")
        let paragraphID = BlockInputBlockID(rawValue: "paragraph")
        let belowID = BlockInputBlockID(rawValue: "below")
        let headingText = "Headings level 6"
        let paragraphText = "Inline items include bold, italic, underline, and inline code."
        let belowText = "Next line keeps the continuation active edge visible"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: headingID, kind: .heading(level: 6), text: headingText),
            BlockInputBlock(id: paragraphID, text: paragraphText),
            BlockInputBlock(id: belowID, text: belowText)
        ])
        let leadingStart = (headingText as NSString).range(of: "level").location
        mounted.view.applySelection(.mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(
                blockID: headingID,
                range: NSRange(location: leadingStart, length: (headingText as NSString).length - leadingStart)
            ),
            trailingTextRange: BlockInputTextRange(blockID: paragraphID, range: NSRange(location: 0, length: 12))
        )), notify: false)
        mounted.view.blockSelectionExpansion = BlockInputBlockSelectionExpansion(anchorBlockID: headingID, direction: .downward)
        mounted.window.makeFirstResponder(mounted.view)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandShiftLeftEvent()))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftDownEvent()))

        guard case let .mixed(selection) = mounted.view.selection else {
            return XCTFail("Expected mixed selection, got \(String(describing: mounted.view.selection))")
        }
        XCTAssertEqual(selection.blockIDs, [paragraphID, belowID])
        XCTAssertEqual(selection.leadingTextRange?.blockID, headingID)
    }

    func testCommandShiftRightUsesWrappedVisualLineEnd() throws {
        let headingID = BlockInputBlockID(rawValue: "heading")
        let paragraphID = BlockInputBlockID(rawValue: "paragraph")
        let headingText = "Title anchor"
        let paragraphText = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda"
        let leadingStart = 2
        let mounted = makeMountedBlockInputView(
            configuration: BlockInputConfiguration(document: BlockInputDocument(blocks: [
                BlockInputBlock(id: headingID, text: headingText),
                BlockInputBlock(id: paragraphID, text: paragraphText)
            ])),
            size: NSSize(width: 260, height: 220)
        )
        let paragraphItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let initialTrailingEnd = 12
        let expectedEnd = paragraphItem.lineBoundaryUTF16Offset(
            containingUTF16Offset: initialTrailingEnd,
            direction: .end
        )
        XCTAssertGreaterThan(expectedEnd, initialTrailingEnd)
        XCTAssertLessThan(expectedEnd, (paragraphText as NSString).length)
        mounted.view.applySelection(.mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: headingID, range: NSRange(location: leadingStart, length: 5)),
            trailingTextRange: BlockInputTextRange(blockID: paragraphID, range: NSRange(location: 0, length: initialTrailingEnd))
        )), notify: false)
        mounted.view.blockSelectionExpansion = BlockInputBlockSelectionExpansion(anchorBlockID: headingID, direction: .downward)
        mounted.window.makeFirstResponder(mounted.view)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandShiftRightEvent()))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(
                blockID: headingID,
                range: NSRange(location: leadingStart, length: (headingText as NSString).length - leadingStart)
            ),
            trailingTextRange: BlockInputTextRange(blockID: paragraphID, range: NSRange(location: 0, length: expectedEnd))
        )))
    }

    func testCommandShiftRightAtLineEndConsumesNoOpWithoutChangingSelection() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let text = "Already at the end"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: text)
        ])
        let selection = BlockInputSelection.mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: blockID, range: NSRange(location: 0, length: (text as NSString).length))
        ))
        mounted.view.applySelection(selection, notify: false)
        mounted.view.horizontalSelectionExpansion = BlockInputHorizontalSelectionExpansion(
            anchor: BlockInputDocumentTextBoundary(blockID: blockID, utf16Offset: 0)
        )
        mounted.window.makeFirstResponder(mounted.view)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandShiftRightEvent()))
        XCTAssertEqual(mounted.view.selection, selection)
        XCTAssertEqual(mounted.window.firstResponder, mounted.view)
    }

    func testCommandShiftLeftLineBoundaryCanCollapseToCursor() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Single block")
        ])
        mounted.view.applySelection(.mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: blockID, range: NSRange(location: 0, length: 6))
        )), notify: false)
        mounted.view.horizontalSelectionExpansion = BlockInputHorizontalSelectionExpansion(
            anchor: BlockInputDocumentTextBoundary(blockID: blockID, utf16Offset: 0)
        )
        mounted.window.makeFirstResponder(mounted.view)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandShiftLeftEvent()))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))
        XCTAssertEqual(mounted.window.firstResponder, mounted.view.visibleBlockItemForTesting(at: 0)?.testingTextView)
    }

    func testLineBoundarySelectionDirectSelectorUsesEditorSelection() throws {
        let context = try screenshotLikeLineBoundaryContext()
        context.mounted.view.applySelection(.mixed(context.selection), notify: false)
        context.mounted.view.blockSelectionExpansion = BlockInputBlockSelectionExpansion(
            anchorBlockID: context.headingID,
            direction: .downward
        )
        context.mounted.window.makeFirstResponder(context.mounted.view)
        context.mounted.view.doCommand(by: #selector(NSTextView.moveToEndOfLineAndModifySelection(_:)))

        XCTAssertEqual(context.mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [context.paragraphID],
            leadingTextRange: context.selection.leadingTextRange
        )))
    }

    func testRightEndLineBoundaryDirectSelectorUsesEditorSelection() throws {
        let context = try screenshotLikeLineBoundaryContext()
        context.mounted.view.applySelection(.mixed(context.selection), notify: false)
        context.mounted.view.blockSelectionExpansion = BlockInputBlockSelectionExpansion(
            anchorBlockID: context.headingID,
            direction: .downward
        )
        context.mounted.window.makeFirstResponder(context.mounted.view)
        context.mounted.view.doCommand(by: #selector(NSTextView.moveToRightEndOfLineAndModifySelection(_:)))

        XCTAssertEqual(context.mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [context.paragraphID],
            leadingTextRange: context.selection.leadingTextRange
        )))
    }

    func testBeginningLineBoundaryDirectSelectorUsesEditorSelection() throws {
        let context = try screenshotLikeLineBoundaryContext(trailingLength: 42)
        context.mounted.view.applySelection(.mixed(context.selection), notify: false)
        context.mounted.view.blockSelectionExpansion = BlockInputBlockSelectionExpansion(
            anchorBlockID: context.headingID,
            direction: .downward
        )
        context.mounted.window.makeFirstResponder(context.mounted.view)
        context.mounted.view.doCommand(by: #selector(NSTextView.moveToBeginningOfLineAndModifySelection(_:)))

        XCTAssertEqual(context.mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: context.selection.leadingTextRange
        )))
    }

    func testLeftEndLineBoundaryDirectSelectorUsesEditorSelection() throws {
        let context = try screenshotLikeLineBoundaryContext(trailingLength: 42)
        context.mounted.view.applySelection(.mixed(context.selection), notify: false)
        context.mounted.view.blockSelectionExpansion = BlockInputBlockSelectionExpansion(
            anchorBlockID: context.headingID,
            direction: .downward
        )
        context.mounted.window.makeFirstResponder(context.mounted.view)
        context.mounted.view.doCommand(by: #selector(NSTextView.moveToLeftEndOfLineAndModifySelection(_:)))

        XCTAssertEqual(context.mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: context.selection.leadingTextRange
        )))
    }

    func testCommandShiftRightLineBoundarySelectionWorksWhenReadOnly() throws {
        let context = try screenshotLikeLineBoundaryContext(isEditable: false)
        context.mounted.view.applySelection(.mixed(context.selection), notify: false)
        context.mounted.view.blockSelectionExpansion = BlockInputBlockSelectionExpansion(
            anchorBlockID: context.headingID,
            direction: .downward
        )
        context.mounted.window.makeFirstResponder(context.mounted.view)
        XCTAssertTrue(context.mounted.view.performKeyEquivalent(with: try commandShiftRightEvent()))

        XCTAssertEqual(context.mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [context.paragraphID],
            leadingTextRange: context.selection.leadingTextRange
        )))
    }

    func testLineBoundaryFallbackExcludesCRLFSourceLineBreak() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let text = "alpha\r\nbeta gamma\r\ndelta"
        let source = text as NSString
        let lineStart = source.range(of: "beta").location
        let lineEnd = source.range(
            of: "\r\n",
            options: [],
            range: NSRange(location: lineStart, length: source.length - lineStart)
        ).location
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: text)
        ])))
        view.applySelection(.text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: lineStart, length: 4)
        )), notify: false)
        view.horizontalSelectionExpansion = BlockInputHorizontalSelectionExpansion(
            anchor: BlockInputDocumentTextBoundary(blockID: blockID, utf16Offset: lineStart),
            active: BlockInputDocumentTextBoundary(blockID: blockID, utf16Offset: lineStart + 4)
        )

        XCTAssertTrue(view.adjustSelectionToLineBoundary(.end))

        XCTAssertEqual(view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(
                blockID: blockID,
                range: NSRange(location: lineStart, length: lineEnd - lineStart)
            )
        )))
    }

    private func screenshotLikeLineBoundaryContext(
        trailingLength: Int = 12,
        isEditable: Bool = true
    ) throws -> LineBoundaryContext {
        let headingID = BlockInputBlockID(rawValue: "heading")
        let paragraphID = BlockInputBlockID(rawValue: "paragraph")
        let headingText = "Headings level 6"
        let paragraphText = "Inline items include bold, italic, underline, strikethrough, inline code, a normal link, README.md, and /quote."
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: headingID, kind: .heading(level: 6), text: headingText),
                BlockInputBlock(id: paragraphID, text: paragraphText)
            ]),
            isEditable: isEditable
        ))
        let paragraphItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let leadingStart = (headingText as NSString).range(of: "level").location
        let selection = BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(
                blockID: headingID,
                range: NSRange(location: leadingStart, length: (headingText as NSString).length - leadingStart)
            ),
            trailingTextRange: BlockInputTextRange(
                blockID: paragraphID,
                range: NSRange(location: 0, length: trailingLength)
            )
        )
        return LineBoundaryContext(
            mounted: mounted,
            headingID: headingID,
            paragraphID: paragraphID,
            selection: selection,
            paragraphItem: paragraphItem,
            initialTrailingEnd: trailingLength
        )
    }
}

private struct LineBoundaryContext {
    var mounted: (view: BlockInputView, window: NSWindow)
    var headingID: BlockInputBlockID
    var paragraphID: BlockInputBlockID
    var selection: BlockInputMixedSelection
    var paragraphItem: BlockInputBlockItem
    var initialTrailingEnd: Int
}
