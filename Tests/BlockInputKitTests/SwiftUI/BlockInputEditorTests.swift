import SwiftUI
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputEditorTests: XCTestCase {
    func testFocusBindingTracksSelectionChangesAndPreservesSelectionHandler() {
        let blockID = BlockInputBlockID(rawValue: "first")
        var isFocused = false
        var publishedSelections: [BlockInputSelection?] = []
        var publishedFocusValues: [Bool] = []
        let editor = BlockInputEditor(
            configuration: BlockInputConfiguration(
                onSelectionChange: { publishedSelections.append($0) },
                onFocusChange: { publishedFocusValues.append($0) }
            ),
            isFocused: Binding(
                get: { isFocused },
                set: { isFocused = $0 }
            )
        )
        let resolvedConfiguration = editor.resolvedConfiguration()

        resolvedConfiguration.onSelectionChange?(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))
        XCTAssertFalse(isFocused)
        resolvedConfiguration.onSelectionChange?(nil)
        resolvedConfiguration.onFocusChange?(true)
        XCTAssertTrue(isFocused)
        resolvedConfiguration.onFocusChange?(false)

        XCTAssertEqual(publishedSelections, [
            .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)),
            nil
        ])
        XCTAssertEqual(publishedFocusValues, [true, false])
        XCTAssertFalse(isFocused)
    }

    func testHeightSizingContributesSwiftUIFittingHeight() {
        let configuration = BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "first", text: "Short")
            ]),
            heightSizing: BlockInputEditorHeightSizing(defaultVisibleLineCount: 3, maximumVisibleLineCount: 6)
        )
        let host = NSHostingView(rootView: BlockInputEditor(configuration: configuration).frame(width: 360))
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 200)

        host.layoutSubtreeIfNeeded()

        let rowHeight = BlockInputBlockItem.height(
            for: BlockInputBlock(id: "expected", text: "x"),
            textWidth: 10_000
        )
        let expectedHeight = ceil((rowHeight * 3) + (BlockInputConfiguration.defaultEditorVerticalInset * 2))
        XCTAssertEqual(host.fittingSize.height, expectedHeight, accuracy: 1)
    }

    func testResolvedConfigurationPreservesPlaceholder() {
        let editor = BlockInputEditor(configuration: BlockInputConfiguration(placeholder: "Ask anything"))

        XCTAssertEqual(editor.resolvedConfiguration().placeholder, "Ask anything")
    }

    func testResolvedConfigurationPreservesReadOnlyOptions() {
        let editor = BlockInputEditor(configuration: BlockInputConfiguration(
            isEditable: false,
            disabledCursor: .operationNotAllowed
        ))

        XCTAssertFalse(editor.resolvedConfiguration().isEditable)
        XCTAssertEqual(editor.resolvedConfiguration().disabledCursor, .operationNotAllowed)
    }

    func testResolvedConfigurationPreservesInlineHintProvider() {
        let editor = BlockInputEditor(configuration: BlockInputConfiguration(
            inlineHintProvider: { _ in BlockInputInlineHint(text: "hint") }
        ))

        XCTAssertNotNil(editor.resolvedConfiguration().inlineHintProvider)
    }

    func testResolvedConfigurationPreservesRawSlashCommandChips() {
        let editor = BlockInputEditor(configuration: BlockInputConfiguration(rawSlashCommandChips: true))

        XCTAssertTrue(editor.resolvedConfiguration().rawSlashCommandChips)
    }

    func testResolvedConfigurationPreservesSelectAllBehavior() {
        let editor = BlockInputEditor(configuration: BlockInputConfiguration(selectAllBehavior: .document))

        XCTAssertEqual(editor.resolvedConfiguration().selectAllBehavior, .document)
    }

    func testResolvedConfigurationPreservesExpandedStyle() {
        let style = BlockInputStyle(
            editorSurface: BlockInputEditorSurfaceStyle(
                editorBackgroundColor: nil,
                scrollBackgroundColor: nil,
                collectionBackgroundColor: nil
            ),
            fileChip: BlockInputInlineChipStyle(fillColor: nil, strokeColor: nil, foregroundColor: .systemRed),
            slashCommandChip: BlockInputInlineChipStyle(foregroundColor: .systemGreen),
            rawSlashCommandChip: BlockInputInlineChipStyle(foregroundColor: .systemBlue)
        )
        let editor = BlockInputEditor(configuration: BlockInputConfiguration(style: style))
        let resolvedStyle = editor.resolvedConfiguration().style

        XCTAssertNil(resolvedStyle.editorSurface.editorBackgroundColor)
        XCTAssertNil(resolvedStyle.editorSurface.scrollBackgroundColor)
        XCTAssertNil(resolvedStyle.editorSurface.collectionBackgroundColor)
        XCTAssertNil(resolvedStyle.fileChip.fillColor)
        XCTAssertNil(resolvedStyle.fileChip.strokeColor)
        XCTAssertEqual(resolvedStyle.fileChip.foregroundColor, .systemRed)
        XCTAssertEqual(resolvedStyle.slashCommandChip.foregroundColor, .systemGreen)
        XCTAssertEqual(resolvedStyle.rawSlashCommandChip.foregroundColor, .systemBlue)
    }

    func testResolvedConfigurationPreservesCompletionReturnBehavior() {
        let editor = BlockInputEditor(configuration: BlockInputConfiguration(
            completionReturnBehavior: .passthroughExactMatch
        ))

        XCTAssertEqual(editor.resolvedConfiguration().completionReturnBehavior, .passthroughExactMatch)
    }

    func testFocusBindingPreservesKeyboardShortcutHandlers() {
        var isFocused = false
        var handledShortcuts: [BlockInputKeyboardShortcut] = []
        let editor = BlockInputEditor(
            configuration: BlockInputConfiguration(
                keyboardShortcuts: [
                    .returnKey: { context in
                        handledShortcuts.append(context.shortcut)
                        return .handled
                    }
                ]
            ),
            isFocused: Binding(
                get: { isFocused },
                set: { isFocused = $0 }
            )
        )
        let resolvedConfiguration = editor.resolvedConfiguration()
        let handler = resolvedConfiguration.keyboardShortcuts[.returnKey]

        _ = handler?(BlockInputKeyboardShortcutContext(
            shortcut: .returnKey,
            selection: nil,
            activeBlock: nil,
            focusSource: .editor,
            isRepeat: false
        ))

        XCTAssertEqual(handledShortcuts, [.returnKey])
    }

    func testFocusBindingFocusesAndResignsMountedEditor() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        var isFocused = true
        let editor = BlockInputEditor(isFocused: Binding(
            get: { isFocused },
            set: { isFocused = $0 }
        ))
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First")
        ])

        editor.updateFocusState(on: mounted.view)

        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        XCTAssertTrue(mounted.window.firstResponder === item.testingTextView)
        XCTAssertTrue(mounted.view.isEditorFirstResponder)

        isFocused = false
        editor.updateFocusState(on: mounted.view)

        XCTAssertFalse(mounted.view.isEditorFirstResponder)
    }

    func testFocusBindingRestoresTableCellSelection() throws {
        let blockID = BlockInputBlockID(rawValue: "table")
        let table = BlockInputTable.normalized(
            header: ["H1", "H2"],
            bodyRows: [["one", "two"]],
            alignments: [.left, .left]
        )
        let sourceRange = try XCTUnwrap(table.sourceRange(
            forLocalRange: NSRange(location: 1, length: 1),
            in: .init(row: .body(0), column: 0)
        ))
        var isFocused = true
        let editor = BlockInputEditor(isFocused: Binding(
            get: { isFocused },
            set: { isFocused = $0 }
        ))
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, kind: .table, text: table.markdown)
        ])
        mounted.view.applySelection(.text(BlockInputTextRange(blockID: blockID, range: sourceRange)), notify: false)
        mounted.window.makeFirstResponder(nil)

        editor.updateFocusState(on: mounted.view)

        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let bodyCell = try XCTUnwrap(item.testingTableCellTextViews[safe: 2])
        XCTAssertTrue(mounted.window.firstResponder === bodyCell)
        XCTAssertEqual(bodyCell.selectedRange(), NSRange(location: 1, length: 1))
    }

    func testMissingFocusBindingLeavesResponderStateUntouched() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let editor = BlockInputEditor()
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First")
        ])
        mounted.view.focus(blockID: blockID, utf16Offset: 2)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        XCTAssertTrue(mounted.window.firstResponder === item.testingTextView)

        editor.updateFocusState(on: mounted.view)

        XCTAssertTrue(mounted.window.firstResponder === item.testingTextView)
    }

    func testCommandDispatcherBindsToMountedEditor() {
        let blockID = BlockInputBlockID(rawValue: "first")
        let dispatcher = BlockInputEditorCommandDispatcher()
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "First")
            ]),
            commandDispatcher: dispatcher
        ))
        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 0, length: 5)
        )), notify: false)

        XCTAssertTrue(dispatcher.canPerform(.bold))
        XCTAssertTrue(dispatcher.perform(.bold))
        XCTAssertEqual(mounted.view.document.blocks[0].text, "**First**")
        XCTAssertEqual(dispatcher.state(for: .bold), .on)
    }

    func testFalseFocusBindingDoesNotRestoreExistingSelectionDuringUpdate() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        var isFocused = false
        let editor = BlockInputEditor(isFocused: Binding(
            get: { isFocused },
            set: { isFocused = $0 }
        ))
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First")
        ])
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 2)), notify: false)
        mounted.window.makeFirstResponder(nil)

        editor.updateView(mounted.view)

        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        XCTAssertFalse(mounted.window.firstResponder === item.testingTextView)
        XCTAssertFalse(mounted.view.isEditorFirstResponder)
        XCTAssertFalse(isFocused)
    }

    func testFalseFocusBindingCancelsPendingSelectionRestore() async throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        var isFocused = false
        let editor = BlockInputEditor(isFocused: Binding(
            get: { isFocused },
            set: { isFocused = $0 }
        ))
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First")
        ])
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 2)), notify: false)
        mounted.view.reloadDataKeepingFocus()

        editor.updateView(mounted.view)
        await Task.yield()
        await Task.yield()

        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        XCTAssertFalse(mounted.window.firstResponder === item.testingTextView)
        XCTAssertFalse(mounted.view.isEditorFirstResponder)
        XCTAssertFalse(isFocused)
    }

    func testFalseFocusBindingResignsBeforeReconfiguringFocusedEditor() async throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        var isFocused = true
        var focusValues: [Bool] = []
        let lostFocus = expectation(description: "Publishes focus loss")
        let editor = BlockInputEditor(
            configuration: BlockInputConfiguration(
                document: BlockInputDocument(blocks: [
                    BlockInputBlock(id: blockID, text: "First")
                ]),
                onFocusChange: { focused in
                    focusValues.append(focused)
                    if !focused {
                        lostFocus.fulfill()
                    }
                }
            ),
            isFocused: Binding(
                get: { isFocused },
                set: { isFocused = $0 }
            )
        )
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First")
        ])
        mounted.view.configure(editor.resolvedConfiguration())
        mounted.view.focus(blockID: blockID, utf16Offset: 1)
        XCTAssertTrue(mounted.view.isEditorFirstResponder)

        isFocused = false
        editor.updateView(mounted.view)

        await fulfillment(of: [lostFocus], timeout: 1)
        XCTAssertEqual(focusValues, [true, false])
        XCTAssertFalse(isFocused)
    }

    func testFalseFocusBindingPublishesLossThroughCurrentConfiguration() async {
        let blockID = BlockInputBlockID(rawValue: "first")
        var isFocused = true
        var staleFocusValues: [Bool] = []
        var currentFocusValues: [Bool] = []
        let lostFocus = expectation(description: "Publishes focus loss")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First")
        ])
        let staleEditor = BlockInputEditor(
            configuration: BlockInputConfiguration(
                document: BlockInputDocument(blocks: [
                    BlockInputBlock(id: blockID, text: "First")
                ]),
                onFocusChange: { staleFocusValues.append($0) }
            ),
            isFocused: Binding(
                get: { isFocused },
                set: { isFocused = $0 }
            )
        )
        staleEditor.updateView(mounted.view)
        mounted.view.focus(blockID: blockID, utf16Offset: 0)
        XCTAssertTrue(isFocused)

        isFocused = false
        let currentEditor = BlockInputEditor(
            configuration: BlockInputConfiguration(
                document: BlockInputDocument(blocks: [
                    BlockInputBlock(id: blockID, text: "First")
                ]),
                onFocusChange: { focused in
                    currentFocusValues.append(focused)
                    if !focused {
                        lostFocus.fulfill()
                    }
                }
            ),
            isFocused: Binding(
                get: { isFocused },
                set: { isFocused = $0 }
            )
        )

        currentEditor.updateView(mounted.view)

        await fulfillment(of: [lostFocus], timeout: 1)
        XCTAssertEqual(staleFocusValues, [true])
        XCTAssertEqual(currentFocusValues, [false])
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
