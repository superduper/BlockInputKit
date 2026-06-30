import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputKeyboardShortcutTests: XCTestCase {
    func testReturnShortcutHandledInterceptsTextReturn() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        var contexts: [BlockInputKeyboardShortcutContext] = []
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "First")
            ]),
            keyboardShortcuts: [
                .returnKey: { context in
                    contexts.append(context)
                    return .handled
                }
            ]
        ))
        let textView = try focusedTextView(in: mounted.view, at: 0, selectedRange: NSRange(location: 5, length: 0))

        textView.keyDown(with: try returnKeyEvent())

        XCTAssertEqual(contexts.count, 1)
        XCTAssertEqual(contexts.first?.shortcut, .returnKey)
        XCTAssertEqual(contexts.first?.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 5)))
        XCTAssertEqual(contexts.first?.activeBlock, BlockInputBlock(id: blockID, text: "First"))
        XCTAssertEqual(contexts.first?.focusSource, .blockText)
        XCTAssertFalse(contexts.first?.isRepeat ?? true)
        XCTAssertEqual(mounted.view.document.blocks, [
            BlockInputBlock(id: blockID, text: "First")
        ])
    }

    func testIgnoredReturnPreservesDefaultAndDoesNotDispatchTwice() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        var count = 0
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "First")
            ]),
            keyboardShortcuts: [
                .returnKey: { _ in
                    count += 1
                    return .ignored
                }
            ]
        ))
        let textView = try focusedTextView(in: mounted.view, at: 0, selectedRange: NSRange(location: 5, length: 0))

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(count, 1)
        XCTAssertEqual(mounted.view.document.blocks.count, 2)
        XCTAssertEqual(mounted.view.document.blocks.last?.text, "")
    }

    func testShiftReturnCanPerformPlainReturnDefault() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "First")
            ]),
            keyboardShortcuts: [
                .shiftReturn: { _ in .performDefault(.returnKey) }
            ]
        ))
        let textView = try focusedTextView(in: mounted.view, at: 0, selectedRange: NSRange(location: 5, length: 0))

        textView.keyDown(with: try returnKeyEvent(modifierFlags: .shift))

        XCTAssertEqual(mounted.view.document.blocks.count, 2)
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(
            blockID: mounted.view.document.blocks[1].id,
            utf16Offset: 0
        )))
    }

    func testUnsupportedDefaultFallsBackToOriginalReturn() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "First")
            ]),
            keyboardShortcuts: [
                .returnKey: { _ in .performDefault(BlockInputKeyboardShortcut(key: .character("x"))) }
            ]
        ))
        let textView = try focusedTextView(in: mounted.view, at: 0, selectedRange: NSRange(location: 5, length: 0))

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(mounted.view.document.blocks.count, 2)
    }

    func testOptionReturnAndCharacterShortcutsUseNormalizedEvents() throws {
        var shortcuts: [BlockInputKeyboardShortcut] = []
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "first", text: "First")
            ]),
            keyboardShortcuts: [
                .optionReturn: { context in
                    shortcuts.append(context.shortcut)
                    return .handled
                },
                BlockInputKeyboardShortcut(key: .character("K"), modifiers: .command): { context in
                    shortcuts.append(context.shortcut)
                    return .handled
                }
            ]
        ))
        let textView = try focusedTextView(in: mounted.view, at: 0, selectedRange: NSRange(location: 0, length: 0))

        textView.keyDown(with: try returnKeyEvent(modifierFlags: .option))
        _ = textView.performKeyEquivalent(with: try keyEquivalentEvent(keyCode: 40, characters: "K", modifierFlags: .command))

        XCTAssertEqual(shortcuts, [
            .optionReturn,
            BlockInputKeyboardShortcut(key: .character("k"), modifiers: .command)
        ])
    }

    func testNumericPadEnterMatchesReturnAndRepeatFlag() throws {
        var context: BlockInputKeyboardShortcutContext?
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "first", text: "First")
            ]),
            keyboardShortcuts: [
                .returnKey: {
                    context = $0
                    return .handled
                }
            ]
        ))
        let textView = try focusedTextView(in: mounted.view, at: 0, selectedRange: NSRange(location: 0, length: 0))

        textView.keyDown(with: try keyDownEvent(keyCode: 76, characters: "\r", modifierFlags: .numericPad, isARepeat: true))

        XCTAssertEqual(context?.shortcut, .returnKey)
        XCTAssertEqual(context?.isRepeat, true)
    }

    func testSelectorPathCanInterceptShiftReturn() throws {
        var shortcuts: [BlockInputKeyboardShortcut] = []
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "first", text: "First")
            ]),
            keyboardShortcuts: [
                .shiftReturn: { context in
                    shortcuts.append(context.shortcut)
                    return .handled
                }
            ]
        ))
        let textView = try focusedTextView(in: mounted.view, at: 0, selectedRange: NSRange(location: 0, length: 0))

        textView.doCommand(by: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)))

        XCTAssertEqual(shortcuts, [.shiftReturn])
    }

    func testSelectorPathCanInterceptOptionShiftWordSelection() throws {
        let shortcut = BlockInputKeyboardShortcut(key: .rightArrow, modifiers: [.option, .shift])
        var shortcuts: [BlockInputKeyboardShortcut] = []
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "first", text: "First")
            ]),
            keyboardShortcuts: [
                shortcut: { context in
                    shortcuts.append(context.shortcut)
                    return .handled
                }
            ]
        ))
        let textView = try focusedTextView(in: mounted.view, at: 0, selectedRange: NSRange(location: 0, length: 0))

        textView.doCommand(by: #selector(NSResponder.moveWordRightAndModifySelection(_:)))

        XCTAssertEqual(shortcuts, [shortcut])
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0))
    }

    func testSelectorPathCanInterceptForwardBackwardShiftSelection() throws {
        let leftShortcut = BlockInputKeyboardShortcut(key: .leftArrow, modifiers: .shift)
        let rightShortcut = BlockInputKeyboardShortcut(key: .rightArrow, modifiers: .shift)
        var shortcuts: [BlockInputKeyboardShortcut] = []
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "first", text: "First")
            ]),
            keyboardShortcuts: [
                leftShortcut: { context in
                    shortcuts.append(context.shortcut)
                    return .handled
                },
                rightShortcut: { context in
                    shortcuts.append(context.shortcut)
                    return .handled
                }
            ]
        ))
        let textView = try focusedTextView(in: mounted.view, at: 0, selectedRange: NSRange(location: 0, length: 0))

        textView.doCommand(by: #selector(NSResponder.moveBackwardAndModifySelection(_:)))
        textView.doCommand(by: #selector(NSResponder.moveForwardAndModifySelection(_:)))

        XCTAssertEqual(shortcuts, [leftShortcut, rightShortcut])
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0))
    }

    func testCommandShiftRightShortcutHandledInterceptsEditorLineBoundarySelection() throws {
        let shortcut = BlockInputKeyboardShortcut(key: .rightArrow, modifiers: [.command, .shift])
        var context: BlockInputKeyboardShortcutContext?
        let mounted = lineBoundaryShortcutMountedView(shortcut: shortcut) {
            context = $0
            return .handled
        }
        let beforeSelection = mounted.view.selection

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandShiftRightEvent()))

        XCTAssertEqual(context?.shortcut, shortcut)
        XCTAssertEqual(context?.focusSource, .blockSelection)
        XCTAssertEqual(mounted.view.selection, beforeSelection)
    }

    func testCommandShiftRightShortcutIgnoredRunsEditorLineBoundaryDefaultOnce() throws {
        let shortcut = BlockInputKeyboardShortcut(key: .rightArrow, modifiers: [.command, .shift])
        var count = 0
        let mounted = lineBoundaryShortcutMountedView(shortcut: shortcut) { _ in
            count += 1
            return .ignored
        }

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandShiftRightEvent()))

        XCTAssertEqual(count, 1)
        XCTAssertEqual(mounted.view.selection, lineBoundaryShortcutDefaultSelection())
    }

    func testCommandShiftRightShortcutCanPerformEditorLineBoundaryDefault() throws {
        let shortcut = BlockInputKeyboardShortcut(key: .rightArrow, modifiers: [.command, .shift])
        let mounted = lineBoundaryShortcutMountedView(shortcut: shortcut) { _ in
            .performDefault(shortcut)
        }

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandShiftRightEvent()))

        XCTAssertEqual(mounted.view.selection, lineBoundaryShortcutDefaultSelection())
    }

    func testRegisteredReturnWorksInTableCells() throws {
        let blockID = BlockInputBlockID(rawValue: "table")
        let table = BlockInputTable.normalized(
            header: ["A", "B"],
            bodyRows: [["one", "two"]],
            alignments: [.left, .left]
        )
        var context: BlockInputKeyboardShortcutContext?
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, kind: .table, text: table.markdown)
            ]),
            keyboardShortcuts: [
                .returnKey: {
                    context = $0
                    return .handled
                }
            ]
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        cell.setSelectedRange(NSRange(location: 1, length: 1))
        let expectedSelection = try XCTUnwrap(table.selection(
            blockID: blockID,
            position: BlockInputTable.CellPosition(row: .body(0), column: 0),
            localRange: NSRange(location: 1, length: 1)
        ))

        cell.keyDown(with: try returnKeyEvent())

        XCTAssertEqual(context?.focusSource, .tableCell)
        XCTAssertEqual(context?.selection, expectedSelection)
        XCTAssertEqual(mounted.view.document.blocks, [
            BlockInputBlock(id: blockID, kind: .table, text: table.markdown)
        ])
    }

    func testRegisteredReturnWorksForEditorSelections() throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let ruleID = BlockInputBlockID(rawValue: "rule")
        var focusSources: [BlockInputKeyboardShortcutFocusSource] = []
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "image.png"))),
                BlockInputBlock(id: ruleID, kind: .horizontalRule)
            ]),
            keyboardShortcuts: [
                .returnKey: {
                    focusSources.append($0.focusSource)
                    return .handled
                }
            ]
        ))

        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: imageID, utf16Offset: 1)), notify: false)
        mounted.view.keyDown(with: try returnKeyEvent())
        mounted.view.applySelection(.blocks([ruleID]), notify: false)
        mounted.view.keyDown(with: try returnKeyEvent())

        XCTAssertEqual(focusSources, [.imageCaret, .blockSelection])
    }

    func testReconfiguringConfigurationUpdatesRegisteredHandlers() throws {
        var firstCount = 0
        var secondCount = 0
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "first", text: "First")
            ]),
            keyboardShortcuts: [
                .returnKey: { _ in
                    firstCount += 1
                    return .handled
                }
            ]
        ))
        mounted.view.configure(BlockInputConfiguration(
            document: mounted.view.document,
            keyboardShortcuts: [
                .returnKey: { _ in
                    secondCount += 1
                    return .handled
                }
            ]
        ))
        let textView = try focusedTextView(in: mounted.view, at: 0, selectedRange: NSRange(location: 0, length: 0))

        textView.keyDown(with: try returnKeyEvent())

        XCTAssertEqual(firstCount, 0)
        XCTAssertEqual(secondCount, 1)
    }
}

private func returnKeyEvent(modifierFlags: NSEvent.ModifierFlags = []) throws -> NSEvent {
    try keyDownEvent(keyCode: 36, characters: "\r", modifierFlags: modifierFlags)
}

@MainActor
private func lineBoundaryShortcutMountedView(
    shortcut: BlockInputKeyboardShortcut,
    handler: @escaping BlockInputKeyboardShortcutHandler
) -> (view: BlockInputView, window: NSWindow) {
    let firstID = BlockInputBlockID(rawValue: "first")
    let secondID = BlockInputBlockID(rawValue: "second")
    let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
        document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ]),
        keyboardShortcuts: [shortcut: handler]
    ))
    mounted.view.applySelection(.mixed(BlockInputMixedSelection(
        blockIDs: [],
        leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 2, length: 3)),
        trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 2))
    )), notify: false)
    mounted.view.blockSelectionExpansion = BlockInputBlockSelectionExpansion(anchorBlockID: firstID, direction: .downward)
    mounted.window.makeFirstResponder(mounted.view)
    return mounted
}

private func lineBoundaryShortcutDefaultSelection() -> BlockInputSelection {
    .mixed(BlockInputMixedSelection(
        blockIDs: [BlockInputBlockID(rawValue: "second")],
        leadingTextRange: BlockInputTextRange(
            blockID: BlockInputBlockID(rawValue: "first"),
            range: NSRange(location: 2, length: 3)
        )
    ))
}

@MainActor
private func focusedTextView(
    in view: BlockInputView,
    at index: Int,
    selectedRange: NSRange
) throws -> BlockInputTextView {
    let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: index))
    let textView = try XCTUnwrap(item.testingTextView)
    textView.setSelectedRange(selectedRange)
    return textView
}
