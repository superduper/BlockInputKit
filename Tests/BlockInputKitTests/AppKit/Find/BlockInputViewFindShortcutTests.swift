import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewFindShortcutTests: XCTestCase {
    // MARK: - Fixtures

    private func paragraphBlocks() -> [BlockInputBlock] {
        [
            BlockInputBlock(id: "a", kind: .paragraph, text: "foo alpha"),
            BlockInputBlock(id: "b", kind: .paragraph, text: "beta foo"),
            BlockInputBlock(id: "c", kind: .paragraph, text: "gamma foo delta")
        ]
    }

    private func commandFEvent() throws -> NSEvent {
        try keyEquivalentEvent(keyCode: 3, characters: "f", modifierFlags: .command)
    }

    private func commandGEvent() throws -> NSEvent {
        try keyEquivalentEvent(keyCode: 5, characters: "g", modifierFlags: .command)
    }

    private func commandShiftGEvent() throws -> NSEvent {
        try keyEquivalentEvent(keyCode: 5, characters: "G", modifierFlags: [.command, .shift])
    }

    private func selectedBlockID(_ view: BlockInputView) -> BlockInputBlockID? {
        switch view.selection {
        case let .text(range):
            return range.blockID
        case let .cursor(cursor):
            return cursor.blockID
        default:
            return nil
        }
    }

    // MARK: - 1. Cmd+F opens the find bar

    func testCommandFOpensFindBar() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        XCTAssertNil(view.findBarViewForTesting)
        XCTAssertFalse(view.isFindBarPresented)

        XCTAssertTrue(view.performKeyEquivalent(with: try commandFEvent()))

        XCTAssertTrue(view.isFindBarPresented)
        let bar = try XCTUnwrap(view.findBarViewForTesting)
        XCTAssertTrue(bar.isDescendant(of: view))
    }

    // MARK: - 2. Cmd+G next / Cmd+Shift+G previous

    func testCommandGAdvancesAndCommandShiftGRetreats() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        view.beginFind(initialQuery: "foo")
        XCTAssertEqual(selectedBlockID(view), "a")

        XCTAssertTrue(view.performKeyEquivalent(with: try commandGEvent()))
        XCTAssertEqual(selectedBlockID(view), "b")
        XCTAssertEqual(view.findMatchCount.current, 2)

        XCTAssertTrue(view.performKeyEquivalent(with: try commandGEvent()))
        XCTAssertEqual(selectedBlockID(view), "c")
        XCTAssertEqual(view.findMatchCount.current, 3)

        XCTAssertTrue(view.performKeyEquivalent(with: try commandShiftGEvent()))
        XCTAssertEqual(selectedBlockID(view), "b")
        XCTAssertEqual(view.findMatchCount.current, 2)
    }

    // MARK: - 3. findEnabled = false passes Cmd+F through

    func testCommandFDisabledDoesNotOpenBar() throws {
        let mounted = makeMountedBlockInputView(
            configuration: BlockInputConfiguration(
                document: BlockInputDocument(blocks: paragraphBlocks()),
                findEnabled: false
            )
        )
        let view = mounted.view

        XCTAssertFalse(view.performKeyEquivalent(with: try commandFEvent()))
        XCTAssertFalse(view.isFindBarPresented)
        XCTAssertNil(view.findBarViewForTesting)
    }

    // MARK: - 4. Host keyboardShortcuts Cmd+F wins over the built-in

    func testHostCommandFShortcutTakesPrecedence() throws {
        var hostRan = false
        let mounted = makeMountedBlockInputView(
            configuration: BlockInputConfiguration(
                document: BlockInputDocument(blocks: paragraphBlocks()),
                keyboardShortcuts: [
                    BlockInputKeyboardShortcut(key: .character("f"), modifiers: .command): { _ in
                        hostRan = true
                        return .handled
                    }
                ]
            )
        )
        let view = mounted.view

        XCTAssertTrue(view.performKeyEquivalent(with: try commandFEvent()))
        XCTAssertTrue(hostRan)
        XCTAssertFalse(view.isFindBarPresented)
        XCTAssertNil(view.findBarViewForTesting)
    }

    // MARK: - 5. Find bar interactions: query, Enter, Esc

    func testFindBarQueryEnterAndEscape() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        XCTAssertTrue(view.performKeyEquivalent(with: try commandFEvent()))
        let bar = try XCTUnwrap(view.findBarViewForTesting)

        bar.simulateQueryInputForTesting("foo")
        XCTAssertEqual(view.findMatchCount.total, 3)
        XCTAssertEqual(view.findMatchCount.current, 1)
        XCTAssertEqual(selectedBlockID(view), "a")

        bar.simulateReturnForTesting()
        XCTAssertEqual(view.findMatchCount.current, 2)
        XCTAssertEqual(selectedBlockID(view), "b")

        bar.simulateEscapeForTesting()
        XCTAssertFalse(view.isFindBarPresented)
        XCTAssertNil(view.findBarViewForTesting)
        XCTAssertEqual(view.findMatchCount.total, 0)
    }

    // MARK: - 6. Count label reflects findMatchCount

    func testCountLabelReflectsMatchCount() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        XCTAssertTrue(view.performKeyEquivalent(with: try commandFEvent()))
        let bar = try XCTUnwrap(view.findBarViewForTesting)

        bar.simulateQueryInputForTesting("foo")
        XCTAssertEqual(bar.countLabelTextForTesting, "1/3")

        XCTAssertTrue(view.performKeyEquivalent(with: try commandGEvent()))
        XCTAssertEqual(bar.countLabelTextForTesting, "2/3")

        XCTAssertTrue(view.performKeyEquivalent(with: try commandShiftGEvent()))
        XCTAssertEqual(bar.countLabelTextForTesting, "1/3")

        bar.simulateQueryInputForTesting("zzz-no-match")
        XCTAssertEqual(bar.countLabelTextForTesting, "0/0")
    }

    // MARK: - Cmd+F when bar is already open focuses the field

    func testCommandFWhenBarOpenKeepsSingleBar() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        XCTAssertTrue(view.performKeyEquivalent(with: try commandFEvent()))
        let firstBar = try XCTUnwrap(view.findBarViewForTesting)

        XCTAssertTrue(view.performKeyEquivalent(with: try commandFEvent()))
        let secondBar = try XCTUnwrap(view.findBarViewForTesting)
        XCTAssertTrue(firstBar === secondBar)
    }

    // MARK: - Typing a query keeps the find field focused (no focus steal)

    func testLiveQueryKeepsFindFieldFirstResponder() throws {
        // Regression: typing into the find bar recomputes matches and reveals the active match.
        // Revealing must NOT move first responder to the matched block's text view, otherwise the
        // next keystroke goes to the document and the user cannot finish typing the query.
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        XCTAssertTrue(view.performKeyEquivalent(with: try commandFEvent()))
        let bar = try XCTUnwrap(view.findBarViewForTesting)
        XCTAssertTrue(mounted.window.makeFirstResponder(bar.queryField))

        // Simulate the first character producing a match (live query change).
        bar.simulateQueryInputForTesting("foo")
        XCTAssertEqual(bar.countLabelTextForTesting, "1/3")

        // The find field's field editor must still hold first responder so typing continues.
        let responder = mounted.window.firstResponder
        let fieldEditorOwnsResponder = responder === bar.queryField ||
            (responder as? NSTextView)?.delegate === bar.queryField
        XCTAssertTrue(
            fieldEditorOwnsResponder,
            "find field must keep first responder after a live query; got \(String(describing: responder))"
        )
        XCTAssertFalse(
            responder is BlockInputTextView,
            "revealing the active match must not focus a block text view while typing the query"
        )
    }

    // MARK: - Return / Shift+Return cycle matches while the field keeps focus

    private func assertFindFieldOwnsResponder(
        _ window: NSWindow,
        _ bar: BlockInputFindBarView,
        line: UInt = #line
    ) {
        let responder = window.firstResponder
        let fieldEditorOwnsResponder = responder === bar.queryField ||
            (responder as? NSTextView)?.delegate === bar.queryField
        XCTAssertTrue(
            fieldEditorOwnsResponder,
            "find field must keep first responder; got \(String(describing: responder))",
            line: line
        )
        XCTAssertFalse(
            responder is BlockInputTextView,
            "bar-driven navigation must not focus a block text view",
            line: line
        )
    }

    func testReturnInFindBarAdvancesToNextMatchKeepingFieldFocus() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        XCTAssertTrue(view.performKeyEquivalent(with: try commandFEvent()))
        let bar = try XCTUnwrap(view.findBarViewForTesting)
        XCTAssertTrue(mounted.window.makeFirstResponder(bar.queryField))

        bar.simulateQueryInputForTesting("foo")
        XCTAssertEqual(view.findMatchCount.total, 3)
        XCTAssertEqual(view.findMatchCount.current, 1)
        assertFindFieldOwnsResponder(mounted.window, bar)

        bar.simulateReturnForTesting()
        XCTAssertEqual(view.findMatchCount.current, 2)
        XCTAssertEqual(selectedBlockID(view), "b")
        assertFindFieldOwnsResponder(mounted.window, bar)

        bar.simulateReturnForTesting()
        XCTAssertEqual(view.findMatchCount.current, 3)
        XCTAssertEqual(selectedBlockID(view), "c")
        assertFindFieldOwnsResponder(mounted.window, bar)
    }

    func testReturnViaFieldEditorAdvancesNextKeepingFieldFocus() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        XCTAssertTrue(view.performKeyEquivalent(with: try commandFEvent()))
        let bar = try XCTUnwrap(view.findBarViewForTesting)
        XCTAssertTrue(mounted.window.makeFirstResponder(bar.queryField))
        bar.simulateQueryInputForTesting("foo")
        XCTAssertEqual(view.findMatchCount.current, 1)

        // Drive the actual field-editor command path, not just the closure.
        let fieldEditor = try XCTUnwrap(bar.queryField.currentEditor() as? NSTextView)
        _ = bar.control(bar.queryField, textView: fieldEditor, doCommandBy: #selector(NSTextView.insertNewline(_:)))

        XCTAssertEqual(view.findMatchCount.current, 2)
        XCTAssertEqual(selectedBlockID(view), "b")
        assertFindFieldOwnsResponder(mounted.window, bar)
    }

    func testShiftReturnInFindBarGoesToPreviousMatchKeepingFieldFocus() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        XCTAssertTrue(view.performKeyEquivalent(with: try commandFEvent()))
        let bar = try XCTUnwrap(view.findBarViewForTesting)
        XCTAssertTrue(mounted.window.makeFirstResponder(bar.queryField))

        bar.simulateQueryInputForTesting("foo")
        XCTAssertEqual(view.findMatchCount.current, 1)

        // Previous from the first match wraps to the last.
        bar.simulateShiftReturnForTesting()
        XCTAssertEqual(view.findMatchCount.current, 3)
        XCTAssertEqual(selectedBlockID(view), "c")
        assertFindFieldOwnsResponder(mounted.window, bar)

        bar.simulateShiftReturnForTesting()
        XCTAssertEqual(view.findMatchCount.current, 2)
        XCTAssertEqual(selectedBlockID(view), "b")
        assertFindFieldOwnsResponder(mounted.window, bar)
    }

    // MARK: - Phase 2: Next / Previous buttons cycle matches while the field keeps focus

    func testNextPrevButtonsPresentInBar() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        XCTAssertTrue(view.performKeyEquivalent(with: try commandFEvent()))
        let bar = try XCTUnwrap(view.findBarViewForTesting)

        XCTAssertNotNil(bar.nextButtonForTesting)
        XCTAssertNotNil(bar.previousButtonForTesting)
        XCTAssertEqual(bar.nextButtonForTesting.accessibilityLabel(), "Next Match")
        XCTAssertEqual(bar.previousButtonForTesting.accessibilityLabel(), "Previous Match")
        XCTAssertTrue(bar.nextButtonForTesting.isDescendant(of: bar))
        XCTAssertTrue(bar.previousButtonForTesting.isDescendant(of: bar))
    }

    func testNextButtonAdvancesMatchAndKeepsFieldFocus() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        XCTAssertTrue(view.performKeyEquivalent(with: try commandFEvent()))
        let bar = try XCTUnwrap(view.findBarViewForTesting)
        XCTAssertTrue(mounted.window.makeFirstResponder(bar.queryField))

        bar.simulateQueryInputForTesting("foo")
        XCTAssertEqual(view.findMatchCount.total, 3)
        XCTAssertEqual(view.findMatchCount.current, 1)

        bar.nextButtonForTesting.performClick(nil)
        XCTAssertEqual(view.findMatchCount.current, 2)
        XCTAssertEqual(selectedBlockID(view), "b")
        assertFindFieldOwnsResponder(mounted.window, bar)

        bar.nextButtonForTesting.performClick(nil)
        XCTAssertEqual(view.findMatchCount.current, 3)
        XCTAssertEqual(selectedBlockID(view), "c")
        assertFindFieldOwnsResponder(mounted.window, bar)
    }

    func testPreviousButtonGoesToPreviousMatchWithWrapAndKeepsFieldFocus() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        XCTAssertTrue(view.performKeyEquivalent(with: try commandFEvent()))
        let bar = try XCTUnwrap(view.findBarViewForTesting)
        XCTAssertTrue(mounted.window.makeFirstResponder(bar.queryField))

        bar.simulateQueryInputForTesting("foo")
        XCTAssertEqual(view.findMatchCount.current, 1)

        // Previous from the first match wraps to the last.
        bar.previousButtonForTesting.performClick(nil)
        XCTAssertEqual(view.findMatchCount.current, 3)
        XCTAssertEqual(selectedBlockID(view), "c")
        assertFindFieldOwnsResponder(mounted.window, bar)

        bar.previousButtonForTesting.performClick(nil)
        XCTAssertEqual(view.findMatchCount.current, 2)
        XCTAssertEqual(selectedBlockID(view), "b")
        assertFindFieldOwnsResponder(mounted.window, bar)
    }

    // MARK: - Phase 5: Expandable replace row

    func testReplaceRowCollapsedByDefaultAndTogglesExpanded() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        XCTAssertTrue(view.performKeyEquivalent(with: try commandFEvent()))
        let bar = try XCTUnwrap(view.findBarViewForTesting)

        // Cmd+F opens find-only (collapsed).
        XCTAssertFalse(bar.isReplaceExpandedForTesting)
        let collapsedHeight = bar.desiredHeightForTesting

        bar.toggleReplaceForTesting()
        XCTAssertTrue(bar.isReplaceExpandedForTesting)
        XCTAssertGreaterThan(bar.desiredHeightForTesting, collapsedHeight)
        XCTAssertTrue(bar.replaceButtonForTesting.isDescendant(of: bar))
        XCTAssertTrue(bar.replaceAllButtonForTesting.isDescendant(of: bar))
        XCTAssertTrue(bar.replaceFieldForTesting.isDescendant(of: bar))

        bar.toggleReplaceForTesting()
        XCTAssertFalse(bar.isReplaceExpandedForTesting)
        XCTAssertEqual(bar.desiredHeightForTesting, collapsedHeight)
    }

    func testTogglingReplaceUpdatesInstalledBarHeight() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        XCTAssertTrue(view.performKeyEquivalent(with: try commandFEvent()))
        let bar = try XCTUnwrap(view.findBarViewForTesting)

        let collapsedHeight = view.findBarHeightConstantForTesting
        bar.toggleReplaceForTesting()
        XCTAssertGreaterThan(view.findBarHeightConstantForTesting, collapsedHeight)
        bar.toggleReplaceForTesting()
        XCTAssertEqual(view.findBarHeightConstantForTesting, collapsedHeight)
    }

    func testReplaceViaBarUpdatesDocumentAndKeepsFieldFocus() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        XCTAssertTrue(view.performKeyEquivalent(with: try commandFEvent()))
        let bar = try XCTUnwrap(view.findBarViewForTesting)
        XCTAssertTrue(mounted.window.makeFirstResponder(bar.queryField))

        bar.simulateQueryInputForTesting("foo")
        bar.toggleReplaceForTesting()
        bar.setReplaceTextForTesting("BAR")
        bar.simulateReplaceForTesting()

        XCTAssertEqual(view.document.block(withID: "a")?.text, "BAR alpha")
        assertFindFieldOwnsResponder(mounted.window, bar)
    }

    func testReplaceAllViaBarUpdatesDocument() throws {
        let mounted = makeMountedBlockInputView(blocks: paragraphBlocks())
        let view = mounted.view
        XCTAssertTrue(view.performKeyEquivalent(with: try commandFEvent()))
        let bar = try XCTUnwrap(view.findBarViewForTesting)
        XCTAssertTrue(mounted.window.makeFirstResponder(bar.queryField))

        bar.simulateQueryInputForTesting("foo")
        bar.toggleReplaceForTesting()
        bar.setReplaceTextForTesting("BAR")
        bar.simulateReplaceAllForTesting()

        XCTAssertEqual(view.document.block(withID: "a")?.text, "BAR alpha")
        XCTAssertEqual(view.document.block(withID: "b")?.text, "beta BAR")
        XCTAssertEqual(view.document.block(withID: "c")?.text, "gamma BAR delta")
        XCTAssertEqual(view.findMatchCount.total, 0)
    }

}
