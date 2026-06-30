import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputTextFormattingContextMenuTests: XCTestCase {
    func testTextViewContextMenuShowsFormattingItemsForSelectedText() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: BlockInputBlockID(rawValue: "block"), text: "Format me")
        ])
        let blockTextView = try textView(in: mounted.view, at: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(blockTextView))
        blockTextView.setSelectedRange(NSRange(location: 0, length: 6))

        let menu = try XCTUnwrap(blockTextView.menu(for: try rightMouseDownEvent(windowNumber: mounted.window.windowNumber)))

        XCTAssertEqual(formattingItemTitles(in: menu), Self.formattingTitles)
        XCTAssertFalse(menuContainsSystemFontSubmenu(menu))
        XCTAssertEqual(menu.item(withTitle: "Bold")?.keyEquivalent, "b")
        XCTAssertEqual(menu.item(withTitle: "Strikethrough")?.keyEquivalentModifierMask, NSEvent.ModifierFlags([.command, .shift]))
    }

    func testTextViewContextMenuRemovesSystemFontSubmenu() throws {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Look Up", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let fontItem = NSMenuItem(title: "Police", action: NSSelectorFromString("submenuAction:"), keyEquivalent: "")
        let fontSubmenu = NSMenu(title: "Police")
        fontSubmenu.addItem(NSMenuItem(title: "Afficher les polices", action: NSSelectorFromString("orderFrontFontPanel:"), keyEquivalent: ""))
        fontSubmenu.addItem(NSMenuItem(title: "Gras", action: NSSelectorFromString("addFontTrait:"), keyEquivalent: ""))
        fontSubmenu.addItem(NSMenuItem(title: "Italique", action: NSSelectorFromString("addFontTrait:"), keyEquivalent: ""))
        fontSubmenu.addItem(NSMenuItem(title: "Souligner", action: NSSelectorFromString("underline:"), keyEquivalent: ""))
        fontSubmenu.addItem(NSMenuItem(title: "Couleurs", action: NSSelectorFromString("orderFrontColorPanel:"), keyEquivalent: ""))
        fontItem.submenu = fontSubmenu
        menu.addItem(fontItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Spelling and Grammar", action: nil, keyEquivalent: ""))

        menu.blockInputRemovingSystemFontItems()

        XCTAssertFalse(menu.items.contains { $0 === fontItem })
        XCTAssertNotNil(menu.item(withTitle: "Look Up"))
        XCTAssertNotNil(menu.item(withTitle: "Spelling and Grammar"))
        XCTAssertFalse(menu.items.first?.isSeparatorItem == true)
        XCTAssertFalse(menu.items.last?.isSeparatorItem == true)
        XCTAssertFalse(menuContainsAdjacentSeparators(menu))
    }

    func testTextViewContextMenuItemStateIsOnWhenSelectedTextHasStyle() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: BlockInputBlockID(rawValue: "block"), text: "**word**")
        ])
        let blockTextView = try textView(in: mounted.view, at: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(blockTextView))
        blockTextView.setSelectedRange(NSRange(location: 0, length: 8))

        let menu = try XCTUnwrap(blockTextView.menu(for: try rightMouseDownEvent(windowNumber: mounted.window.windowNumber)))

        XCTAssertEqual(menu.item(withTitle: "Bold")?.state, .on)
        XCTAssertEqual(menu.item(withTitle: "Italic")?.state, .off)
    }

    func testTextViewContextMenuActionTogglesFormattingOff() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "**word**")
        ])
        let blockTextView = try textView(in: mounted.view, at: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(blockTextView))
        blockTextView.setSelectedRange(NSRange(location: 0, length: 8))
        let menu = try XCTUnwrap(blockTextView.menu(for: try rightMouseDownEvent(windowNumber: mounted.window.windowNumber)))

        try performMenuItem(titled: "Bold", in: menu)

        XCTAssertEqual(mounted.view.document.blocks[0].text, "word")
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 0, length: 4)
        )))
    }

    func testTextViewContextMenuActionsUseExpectedDelimiters() throws {
        let cases: [(String, String)] = [
            ("Bold", "**word**"),
            ("Italic", "_word_"),
            ("Underline", "<u>word</u>"),
            ("Strikethrough", "~~word~~")
        ]

        for (title, expectedText) in cases {
            let mounted = makeMountedBlockInputView(blocks: [
                BlockInputBlock(id: BlockInputBlockID(rawValue: title), text: "word")
            ])
            let blockTextView = try textView(in: mounted.view, at: 0)
            XCTAssertTrue(mounted.window.makeFirstResponder(blockTextView))
            blockTextView.setSelectedRange(NSRange(location: 0, length: 4))
            let menu = try XCTUnwrap(blockTextView.menu(for: try rightMouseDownEvent(windowNumber: mounted.window.windowNumber)))

            try performMenuItem(titled: title, in: menu)

            XCTAssertEqual(mounted.view.document.blocks[0].text, expectedText)
        }
    }

    func testTextViewContextMenuDoesNotRetargetSelectedRangeToClickedWord() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "one two")
        ])
        let blockTextView = try textView(in: mounted.view, at: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(blockTextView))
        blockTextView.setSelectedRange(NSRange(location: 0, length: 3))

        let menu = try XCTUnwrap(blockTextView.menu(for: try rightMouseDownEvent(
            location: windowLocation(in: blockTextView, characterRange: NSRange(location: 4, length: 3)),
            windowNumber: mounted.window.windowNumber
        )))

        XCTAssertEqual(blockTextView.selectedRange(), NSRange(location: 0, length: 3))
        try performMenuItem(titled: "Bold", in: menu)

        XCTAssertEqual(mounted.view.document.blocks[0].text, "**one** two")
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 2, length: 3)
        )))
    }

    func testTextViewContextMenuActionNoOpsWhenSelectionChangesBeforeAction() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "word")
        ])
        let blockTextView = try textView(in: mounted.view, at: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(blockTextView))
        blockTextView.setSelectedRange(NSRange(location: 0, length: 4))
        let menu = try XCTUnwrap(blockTextView.menu(for: try rightMouseDownEvent(windowNumber: mounted.window.windowNumber)))

        blockTextView.setSelectedRange(NSRange(location: 0, length: 0))
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)), notify: false)
        try performMenuItem(titled: "Bold", in: menu)

        XCTAssertEqual(mounted.view.document.blocks[0].text, "word")
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))
    }

    func testTextViewContextMenuActionNoOpsWhenFirstResponderChangesBeforeAction() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let firstTextView = try textView(in: mounted.view, at: 0)
        let secondTextView = try textView(in: mounted.view, at: 1)
        XCTAssertTrue(mounted.window.makeFirstResponder(firstTextView))
        firstTextView.setSelectedRange(NSRange(location: 0, length: 5))
        let menu = try XCTUnwrap(firstTextView.menu(for: try rightMouseDownEvent(windowNumber: mounted.window.windowNumber)))

        XCTAssertTrue(mounted.window.makeFirstResponder(secondTextView))
        secondTextView.setSelectedRange(NSRange(location: 0, length: 0))
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: secondID, utf16Offset: 0)), notify: false)
        try performMenuItem(titled: "Bold", in: menu)

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["First", "Second"])
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: secondID, utf16Offset: 0)))
    }

    func testCollectionContextMenuFormatsWholeSelectedBlocks() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        mounted.view.applySelection(.blocks([firstID, secondID]), notify: false)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let menu = try collectionContextMenu(for: item, in: mounted)

        try performMenuItem(titled: "Bold", in: menu)

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["**First**", "**Second**"])
        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID]))
    }

    func testCollectionContextMenuPublishesGranularStoreMutations() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ]))
        var mutations: [BlockInputDocumentChange] = []
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            documentStore: store,
            onDocumentMutation: { mutations.append($0) }
        ))
        mounted.view.applySelection(.blocks([firstID, secondID]), notify: false)
        store.resetCounts()
        mutations.removeAll()
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let menu = try collectionContextMenu(for: item, in: mounted)

        try performMenuItem(titled: "Bold", in: menu)

        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replaceBlockIDs, [firstID, secondID])
        XCTAssertEqual(store.document.blocks.map(\.text), ["**First**", "**Second**"])
        XCTAssertEqual(mutations, [
            .replaceBlock(store.document.blocks[0]),
            .replaceBlock(store.document.blocks[1])
        ])
    }

    func testTextViewContextMenuUsesEditorSelectionForSelectedBlocks() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let blockTextView = try textView(in: mounted.view, at: 1)
        XCTAssertTrue(mounted.window.makeFirstResponder(blockTextView))
        blockTextView.setSelectedRange(NSRange(location: 0, length: 3))
        mounted.view.applySelection(.blocks([firstID, secondID]), notify: false)
        let menu = try XCTUnwrap(blockTextView.menu(for: try rightMouseDownEvent(
            location: blockTextView.convert(NSPoint(x: 10, y: 10), to: nil),
            windowNumber: mounted.window.windowNumber
        )))

        try performMenuItem(titled: "Bold", in: menu)

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["**First**", "**Second**"])
        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID]))
    }

    func testCollectionContextMenuFormatsMixedSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "Alpha"),
            BlockInputBlock(id: secondID, text: "Beta"),
            BlockInputBlock(id: thirdID, text: "Gamma")
        ])
        mounted.view.applySelection(.mixed(BlockInputMixedSelection(
            blockIDs: [secondID],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 2, length: 3)),
            trailingTextRange: BlockInputTextRange(blockID: thirdID, range: NSRange(location: 0, length: 2))
        )), notify: false)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let menu = try contextMenu(for: item, in: mounted.window)

        try performMenuItem(titled: "Italic", in: menu)

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["Al_pha_", "_Beta_", "_Ga_mma"])
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [secondID],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 3, length: 3)),
            trailingTextRange: BlockInputTextRange(blockID: thirdID, range: NSRange(location: 1, length: 2))
        )))
    }

    func testContextMenuItemStateIsOnWhenAllSegmentsHaveStyle() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "**First**"),
            BlockInputBlock(id: secondID, text: "**Second**")
        ])
        mounted.view.applySelection(.blocks([firstID, secondID]), notify: false)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let menu = try contextMenu(for: item, in: mounted.window)

        XCTAssertEqual(menu.item(withTitle: "Bold")?.state, .on)
        XCTAssertEqual(menu.item(withTitle: "Italic")?.state, .off)

        try performMenuItem(titled: "Bold", in: menu)

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["First", "Second"])
        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID]))
    }

    func testContextMenuItemStateIsOffWhenOnlySomeSegmentsHaveStyle() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "**First**"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        mounted.view.applySelection(.blocks([firstID, secondID]), notify: false)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let menu = try contextMenu(for: item, in: mounted.window)

        XCTAssertEqual(menu.item(withTitle: "Bold")?.state, .off)
        try performMenuItem(titled: "Bold", in: menu)

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["**First**", "**Second**"])
        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID]))
    }

    func testContextMenuHidesFormattingItemsForIneligibleSelections() throws {
        let cases: [(BlockInputBlock, BlockInputSelection?)] = [
            (
                BlockInputBlock(id: BlockInputBlockID(rawValue: "paragraph"), text: "Text"),
                .cursor(BlockInputCursor(blockID: BlockInputBlockID(rawValue: "paragraph"), utf16Offset: 2))
            ),
            (
                BlockInputBlock(id: BlockInputBlockID(rawValue: "empty"), text: ""),
                .blocks([BlockInputBlockID(rawValue: "empty")])
            ),
            (
                BlockInputBlock(id: BlockInputBlockID(rawValue: "code"), kind: .code(language: nil), text: "code"),
                .blocks([BlockInputBlockID(rawValue: "code")])
            ),
            (
                BlockInputBlock(id: BlockInputBlockID(rawValue: "rule"), kind: .horizontalRule),
                .blocks([BlockInputBlockID(rawValue: "rule")])
            )
        ]

        for (block, selection) in cases {
            let mounted = makeMountedBlockInputView(blocks: [block])
            if let selection {
                mounted.view.applySelection(selection, notify: false)
            }
            let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
            let menu = item.view.menu(for: try rightMouseDownEvent(
                location: item.view.convert(NSPoint(x: 10, y: 10), to: nil),
                windowNumber: mounted.window.windowNumber
            ))

            XCTAssertTrue(formattingItemTitles(in: menu).isEmpty)
        }
    }

    func testContextMenuHidesFormattingItemsForAllUnsupportedSelection() throws {
        let codeID = BlockInputBlockID(rawValue: "code")
        let ruleID = BlockInputBlockID(rawValue: "rule")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: codeID, kind: .code(language: nil), text: "code"),
            BlockInputBlock(id: ruleID, kind: .horizontalRule)
        ])
        mounted.view.applySelection(.blocks([codeID, ruleID]), notify: false)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let menu = item.view.menu(for: try rightMouseDownEvent(
            location: item.view.convert(NSPoint(x: 10, y: 10), to: nil),
            windowNumber: mounted.window.windowNumber
        ))

        XCTAssertTrue(formattingItemTitles(in: menu).isEmpty)
    }

    func testContextMenuHidesFormattingItemsForUnrelatedClickedBlock() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        mounted.view.applySelection(.blocks([firstID]), notify: false)
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let menu = secondItem.view.menu(for: try rightMouseDownEvent(
            location: secondItem.view.convert(NSPoint(x: 10, y: 10), to: nil),
            windowNumber: mounted.window.windowNumber
        ))

        XCTAssertTrue(formattingItemTitles(in: menu).isEmpty)
    }

    func testTextViewContextMenuHidesFormattingItemsForUnrelatedClickedBlock() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        mounted.view.applySelection(.blocks([firstID]), notify: false)
        let secondTextView = try textView(in: mounted.view, at: 1)
        let menu = secondTextView.menu(for: try rightMouseDownEvent(
            location: secondTextView.convert(NSPoint(x: 10, y: 10), to: nil),
            windowNumber: mounted.window.windowNumber
        ))

        XCTAssertTrue(formattingItemTitles(in: menu).isEmpty)
    }

    private static let formattingTitles = ["Bold", "Italic", "Underline", "Strikethrough"]

    private func formattingItemTitles(in menu: NSMenu?) -> [String] {
        menu?.items.compactMap { item in
            item.representedObject is BlockInputTextFormattingShortcut ? item.title : nil
        } ?? []
    }

    private func menuContainsAdjacentSeparators(_ menu: NSMenu) -> Bool {
        menu.items.indices.dropFirst().contains { index in
            menu.items[index].isSeparatorItem && menu.items[index - 1].isSeparatorItem
        }
    }

    private func menuContainsSystemFontSubmenu(_ menu: NSMenu) -> Bool {
        menu.items.contains { item in
            let submenuActionNames = item.submenu?.items.compactMap { submenuItem in
                submenuItem.action.map(NSStringFromSelector)
            } ?? []
            return submenuActionNames.contains("orderFrontFontPanel:")
                && submenuActionNames.filter { $0 == "addFontTrait:" }.count >= 2
                && submenuActionNames.contains("underline:")
        }
    }

    private func performMenuItem(titled title: String, in menu: NSMenu) throws {
        let item = try XCTUnwrap(menu.item(withTitle: title))
        let action = try XCTUnwrap(item.action)
        XCTAssertTrue(NSApp.sendAction(action, to: item.target, from: item))
    }

    private func windowLocation(
        in textView: NSTextView,
        characterRange: NSRange
    ) throws -> NSPoint {
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
        let boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        return textView.convert(NSPoint(
            x: textView.textContainerOrigin.x + boundingRect.midX,
            y: textView.textContainerOrigin.y + boundingRect.midY
        ), to: nil)
    }

    private func contextMenu(for item: BlockInputBlockItem, in window: NSWindow) throws -> NSMenu {
        try XCTUnwrap(item.view.menu(for: rightMouseDownEvent(
            location: item.view.convert(NSPoint(x: 10, y: 10), to: nil),
            windowNumber: window.windowNumber
        )))
    }

    private func collectionContextMenu(
        for item: BlockInputBlockItem,
        in mounted: (view: BlockInputView, window: NSWindow)
    ) throws -> NSMenu {
        try XCTUnwrap(mounted.view.collectionView.menu(for: rightMouseDownEvent(
            location: item.view.convert(NSPoint(x: 10, y: 10), to: nil),
            windowNumber: mounted.window.windowNumber
        )))
    }

    private func textView(
        in view: BlockInputView,
        at index: Int
    ) throws -> BlockInputTextView {
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: index))
        return try XCTUnwrap(item.testingTextView)
    }
}
