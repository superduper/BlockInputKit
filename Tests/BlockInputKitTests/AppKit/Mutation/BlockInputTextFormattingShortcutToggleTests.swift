import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputFormattingShortcutToggleTests: XCTestCase {
    func testFormattingShortcutsToggleStackedMarkupAroundSameVisibleSelection() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "owns")
        ])
        let textView = try textView(in: mounted.view, at: 0)
        textView.setSelectedRange(NSRange(location: 0, length: 4))

        let steps = [
            FormattingShortcutStep(try commandBEvent(), text: "**owns**", selectedRange: NSRange(location: 2, length: 4)),
            FormattingShortcutStep(try commandIEvent(), text: "**_owns_**", selectedRange: NSRange(location: 3, length: 4)),
            FormattingShortcutStep(try commandShiftXEvent(), text: "**_~~owns~~_**", selectedRange: NSRange(location: 5, length: 4)),
            FormattingShortcutStep(try commandUEvent(), text: "**_~~<u>owns</u>~~_**", selectedRange: NSRange(location: 8, length: 4)),
            FormattingShortcutStep(try commandBEvent(), text: "_~~<u>owns</u>~~_", selectedRange: NSRange(location: 6, length: 4)),
            FormattingShortcutStep(try commandIEvent(), text: "~~<u>owns</u>~~", selectedRange: NSRange(location: 5, length: 4)),
            FormattingShortcutStep(try commandShiftXEvent(), text: "<u>owns</u>", selectedRange: NSRange(location: 3, length: 4)),
            FormattingShortcutStep(try commandUEvent(), text: "owns", selectedRange: NSRange(location: 0, length: 4))
        ]

        for step in steps {
            XCTAssertTrue(textView.performKeyEquivalent(with: step.event))
            assertFormattingState(
                mounted.view,
                textView: textView,
                blockID: blockID,
                text: step.text,
                selectedRange: step.selectedRange
            )
        }
    }

    func testFormattingShortcutsTrimHiddenDelimiterEdgesFromFocusedTextSelection() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "**_~~<u>owns</u>~~_**")
        ])
        let textView = try textView(in: mounted.view, at: 0)
        textView.setSelectedRange(NSRange(location: 5, length: 16))

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandUEvent()))

        assertFormattingState(
            mounted.view,
            textView: textView,
            blockID: blockID,
            text: "**_~~owns~~_**",
            selectedRange: NSRange(location: 5, length: 4)
        )

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandZEvent()))

        assertFormattingState(
            mounted.view,
            textView: textView,
            blockID: blockID,
            text: "**_~~<u>owns</u>~~_**",
            selectedRange: NSRange(location: 8, length: 4)
        )
    }

    func testFormattingShortcutsTrimHiddenDelimiterEdgesBeforeRemovingOuterStyle() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "**_~~<u>owns</u>~~_**")
        ])
        let textView = try textView(in: mounted.view, at: 0)
        textView.setSelectedRange(NSRange(location: 5, length: 16))

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandBEvent()))

        assertFormattingState(
            mounted.view,
            textView: textView,
            blockID: blockID,
            text: "_~~<u>owns</u>~~_",
            selectedRange: NSRange(location: 6, length: 4)
        )
    }

    func testCommandUTogglesEnclosingInsertTagWithoutInvalidSelection() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "<ins>owns</ins>")
        ])
        let textView = try textView(in: mounted.view, at: 0)
        textView.setSelectedRange(NSRange(location: 5, length: 4))

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandUEvent()))

        assertFormattingState(
            mounted.view,
            textView: textView,
            blockID: blockID,
            text: "owns",
            selectedRange: NSRange(location: 0, length: 4)
        )
    }

    func testCommandBTogglesComposedBoldItalicWhilePreservingItalic() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "***owns***")
        ])
        let textView = try textView(in: mounted.view, at: 0)
        textView.setSelectedRange(NSRange(location: 3, length: 4))

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandBEvent()))

        assertFormattingState(
            mounted.view,
            textView: textView,
            blockID: blockID,
            text: "*owns*",
            selectedRange: NSRange(location: 1, length: 4)
        )
    }

    func testCommandITogglesComposedBoldItalicWhilePreservingBold() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "***owns***")
        ])
        let textView = try textView(in: mounted.view, at: 0)
        textView.setSelectedRange(NSRange(location: 3, length: 4))

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandIEvent()))

        assertFormattingState(
            mounted.view,
            textView: textView,
            blockID: blockID,
            text: "**owns**",
            selectedRange: NSRange(location: 2, length: 4)
        )
    }

    func testCommandITogglesSelectionIncludingAsteriskDelimiters() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "*owns*")
        ])
        let textView = try textView(in: mounted.view, at: 0)
        textView.setSelectedRange(NSRange(location: 0, length: 6))

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandIEvent()))

        assertFormattingState(
            mounted.view,
            textView: textView,
            blockID: blockID,
            text: "owns",
            selectedRange: NSRange(location: 0, length: 4)
        )
    }

    func testCommandBTogglesSelectionIncludingComposedBoldItalicDelimiters() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "***owns***")
        ])
        let textView = try textView(in: mounted.view, at: 0)
        textView.setSelectedRange(NSRange(location: 0, length: 10))

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandBEvent()))

        assertFormattingState(
            mounted.view,
            textView: textView,
            blockID: blockID,
            text: "*owns*",
            selectedRange: NSRange(location: 1, length: 4)
        )
    }

    func testCommandUTogglesSelectionIncludingInsertTagDelimiters() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "<ins>owns</ins>")
        ])
        let textView = try textView(in: mounted.view, at: 0)
        textView.setSelectedRange(NSRange(location: 0, length: 15))

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandUEvent()))

        assertFormattingState(
            mounted.view,
            textView: textView,
            blockID: blockID,
            text: "owns",
            selectedRange: NSRange(location: 0, length: 4)
        )
    }

    func testFormattingShortcutsDoNotTreatInlineCodeMarkdownAsHiddenDelimiters() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "`**owns**`")
        ])
        let textView = try textView(in: mounted.view, at: 0)
        textView.setSelectedRange(NSRange(location: 1, length: 8))

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandIEvent()))

        assertFormattingState(
            mounted.view,
            textView: textView,
            blockID: blockID,
            text: "`_**owns**_`",
            selectedRange: NSRange(location: 2, length: 8)
        )
    }

    private func textView(
        in view: BlockInputView,
        at index: Int
    ) throws -> BlockInputTextView {
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: index))
        return try XCTUnwrap(item.testingTextView)
    }

    private func assertFormattingState(
        _ view: BlockInputView,
        textView: BlockInputTextView,
        blockID: BlockInputBlockID,
        text: String,
        selectedRange: NSRange,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(view.document.blocks[0].text, text, file: file, line: line)
        XCTAssertEqual(
            view.selection,
            BlockInputSelection.text(BlockInputTextRange(blockID: blockID, range: selectedRange)),
            file: file,
            line: line
        )
        XCTAssertEqual(textView.string, text, file: file, line: line)
        XCTAssertEqual(textView.selectedRange(), selectedRange, file: file, line: line)
    }
}

private struct FormattingShortcutStep {
    var event: NSEvent
    var text: String
    var selectedRange: NSRange

    init(
        _ event: NSEvent,
        text: String,
        selectedRange: NSRange
    ) {
        self.event = event
        self.text = text
        self.selectedRange = selectedRange
    }
}
