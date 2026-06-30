import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewReadOnlyTests: XCTestCase {
    func testReadOnlyTextRemainsSelectableButDoesNotAcceptTextMutationCommands() throws {
        let blockID = BlockInputBlockID(rawValue: "paragraph")
        var documentChanges = 0
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "Read only")
            ]),
            isEditable: false,
            disabledCursor: .operationNotAllowed,
            onDocumentChange: { _ in documentChanges += 1 }
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 0, length: 4)
        )), notify: false)
        textView.setSelectedRange(NSRange(location: 0, length: 4))

        XCTAssertFalse(textView.isEditable)
        XCTAssertTrue(textView.isSelectable)
        XCTAssertFalse(item.textView(textView, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementString: "x"))
        XCTAssertFalse(mounted.view.canPerformCommand(.bold))
        XCTAssertEqual(mounted.view.state(for: .bold), .unavailable)
        XCTAssertFalse(mounted.view.performCommand(.bold))
        XCTAssertFalse(mounted.view.performCommand(.cut))
        XCTAssertFalse(mounted.view.performCommand(.paste))
        XCTAssertNil(mounted.view.insertBlockBelowCurrentBlock())

        XCTAssertTrue(mounted.view.canPerformCommand(.copy))
        XCTAssertTrue(mounted.view.performCommand(.copy))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Read")
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["Read only"])
        XCTAssertEqual(documentChanges, 0)
        XCTAssertEqual(mounted.view.disabledCursor, .operationNotAllowed)
        XCTAssertEqual(item.disabledCursor, .operationNotAllowed)
    }

    func testReadOnlyBlocksStructuralAndMediaCommandsAndSuppressesModals() throws {
        let blockID = BlockInputBlockID(rawValue: "paragraph")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "Content")
            ]),
            isEditable: false
        ))
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)), notify: false)

        XCTAssertFalse(mounted.view.performCommand(.insertLink(BlockInputInsertLinkCommand(presentation: .modal))))
        XCTAssertNil(mounted.view.linkModalView)
        XCTAssertFalse(mounted.view.performCommand(.insertImage(BlockInputInsertImageCommand(presentation: .modal))))
        XCTAssertNil(mounted.view.imageModalView)
        XCTAssertFalse(mounted.view.performCommand(.insertTable))
        XCTAssertNil(mounted.view.insertFileURLs([URL(fileURLWithPath: "/tmp/read-only.txt")]))
        XCTAssertNil(mounted.view.insertLocalFileURLs([URL(fileURLWithPath: "/tmp/read-only.png")]))
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["Content"])
    }

    func testReadOnlyBlocksDirectPublicMutationAPIs() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: firstID, text: "First"),
                BlockInputBlock(id: secondID, text: "Second")
            ]),
            isEditable: false
        ))

        XCTAssertNil(mounted.view.insertMarkdown("Inserted", below: firstID))
        XCTAssertNil(mounted.view.mergeBlockIntoPrevious(blockID: secondID))
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["First", "Second"])
    }

    func testReadOnlyKeepsCopyAndSelectionAvailable() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: firstID, text: "First"),
                BlockInputBlock(id: secondID, text: "Second")
            ]),
            isEditable: false
        ))
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: firstID, utf16Offset: 0)), notify: false)

        XCTAssertTrue(mounted.view.selectAllFromActiveSelection())
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: firstID,
            range: NSRange(location: 0, length: 5)
        )))
        XCTAssertTrue(mounted.view.performCommand(.copy))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "First")
    }

    func testReadOnlyDisablesChecklistReorderAndTableMutationControls() throws {
        let checklistID = BlockInputBlockID(rawValue: "check")
        let tableID = BlockInputBlockID(rawValue: "table")
        let table = BlockInputTable.normalized(
            header: ["A", "B"],
            bodyRows: [["1", "2"]],
            alignments: [.left, .left]
        )
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: checklistID, kind: .checklistItem(isChecked: false), text: "Task"),
                BlockInputBlock(id: tableID, kind: .table, text: table.markdown)
            ]),
            isEditable: false
        ))

        let checklistItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        XCTAssertFalse(try XCTUnwrap(checklistItem.testingChecklistButton).isEnabled)
        XCTAssertFalse(try XCTUnwrap(checklistItem.testingHandleView).isEnabled)
        XCTAssertNil(checklistItem.draggingPasteboardItem())
        checklistItem.requestToggleChecklist()
        XCTAssertEqual(mounted.view.document.blocks[0].kind, .checklistItem(isChecked: false))

        let tableItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let tableCell = try XCTUnwrap(tableItem.testingTableCellTextViews.first)
        XCTAssertFalse(tableCell.isEditable)
        XCTAssertTrue(tableCell.isSelectable)
        tableItem.testingTableView.updateAppendControlVisibility(for: NSPoint(x: 100, y: tableItem.testingTableView.bounds.maxY))
        XCTAssertTrue(tableItem.testingAppendTableRowButton.isHidden)
        XCTAssertTrue(tableItem.testingAppendTableColumnButton.isHidden)
        XCTAssertNil(tableItem.testingTableView.accessibilityCustomActions())
        XCTAssertFalse(mounted.view.appendTableBodyRow(blockID: tableID))
        XCTAssertFalse(mounted.view.insertTableColumn(
            blockID: tableID,
            position: BlockInputTable.CellPosition(row: .header, column: 0)
        ))
        XCTAssertEqual(mounted.view.document.blocks[1].text, table.markdown)
    }

    func testSwitchingTableToReadOnlyHidesVisibleAppendControls() throws {
        let tableID = BlockInputBlockID(rawValue: "table")
        let table = BlockInputTable.normalized(
            header: ["A", "B"],
            bodyRows: [["1", "2"]],
            alignments: [.left, .left]
        )
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: tableID, kind: .table, text: table.markdown)
        ])))
        let tableItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let tableView = tableItem.testingTableView
        let tableFrame = tableView.visibleTableFrame
        tableView.updateAppendControlVisibility(for: NSPoint(x: tableFrame.midX, y: tableFrame.maxY))
        XCTAssertFalse(tableItem.testingAppendTableRowButton.isHidden)

        tableView.isEditable = false

        XCTAssertTrue(tableItem.testingAppendTableRowButton.isHidden)
        XCTAssertTrue(tableItem.testingAppendTableColumnButton.isHidden)
    }

    func testReadOnlyAddsDisabledCursorRectsOnlyWhenNonEditable() {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(text: "Read only")
            ]),
            isEditable: false,
            disabledCursor: .operationNotAllowed
        ))
        let readOnlyProbe = CursorRectProbeView(frame: NSRect(x: 0, y: 0, width: 32, height: 12))

        mounted.view.addDisabledCursorRectIfNeeded(to: readOnlyProbe)

        XCTAssertEqual(readOnlyProbe.addedCursorRects.count, 1)
        XCTAssertEqual(readOnlyProbe.addedCursorRects.first?.rect, readOnlyProbe.bounds)
        XCTAssertEqual(readOnlyProbe.addedCursorRects.first?.cursor, .operationNotAllowed)

        mounted.view.configure(BlockInputConfiguration(
            document: mounted.view.document,
            disabledCursor: .operationNotAllowed
        ))
        let editableProbe = CursorRectProbeView(frame: readOnlyProbe.frame)
        mounted.view.addDisabledCursorRectIfNeeded(to: editableProbe)

        XCTAssertTrue(editableProbe.addedCursorRects.isEmpty)
    }

    func testReadOnlyTextViewCursorUpdateUsesDisabledCursor() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(text: "Read only")
            ]),
            isEditable: false,
            disabledCursor: .operationNotAllowed
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let event = try mouseMovedEvent(
            location: textView.convert(NSPoint(x: textView.bounds.midX, y: textView.bounds.midY), to: nil),
            windowNumber: mounted.window.windowNumber
        )

        XCTAssertEqual(textView.readOnlyCursor(for: event), .operationNotAllowed)

        let editableMounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(text: "Editable")
            ]),
            disabledCursor: .operationNotAllowed
        ))
        let editableItem = try XCTUnwrap(editableMounted.view.visibleBlockItemForTesting(at: 0))
        let editableTextView = try XCTUnwrap(editableItem.testingTextView)
        let editableEvent = try mouseMovedEvent(
            location: editableTextView.convert(NSPoint(x: editableTextView.bounds.midX, y: editableTextView.bounds.midY), to: nil),
            windowNumber: editableMounted.window.windowNumber
        )

        XCTAssertNil(editableTextView.readOnlyCursor(for: editableEvent))
    }

    func testReadOnlyTextViewMouseMovedOverridesNativeIBeamCursor() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(text: "Read only")
            ]),
            isEditable: false,
            disabledCursor: .operationNotAllowed
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let event = try mouseMovedEvent(
            location: textView.convert(NSPoint(x: textView.bounds.midX, y: textView.bounds.midY), to: nil),
            windowNumber: mounted.window.windowNumber
        )

        NSCursor.iBeam.set()
        defer {
            NSCursor.arrow.set()
        }
        textView.mouseMoved(with: event)

        XCTAssertEqual(NSCursor.current, .operationNotAllowed)
    }

    func testReadOnlyTextViewCursorKeepsPointingHandOverLinks() throws {
        let text = "Open [docs](https://example.com)"
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(text: text)
            ]),
            isEditable: false,
            disabledCursor: .operationNotAllowed
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let linkRect = item.anchorWindowRect(forUTF16Range: (text as NSString).range(of: "docs"))
        let event = try mouseMovedEvent(
            location: NSPoint(x: linkRect.midX, y: linkRect.midY),
            windowNumber: mounted.window.windowNumber
        )

        XCTAssertEqual(textView.readOnlyCursor(for: event), .pointingHand)
    }

    func testReadOnlyDisablesImageResizeButKeepsImageSelection() throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let image = BlockInputImage(
            source: "file:///tmp/missing-read-only-image.png",
            altText: "Missing",
            width: 120,
            height: 80
        )
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: imageID, kind: .image(image))
            ]),
            isEditable: false,
            disabledCursor: .operationNotAllowed
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let imageView = item.testingImageBlockView

        XCTAssertFalse(imageView.isEditable)
        XCTAssertEqual(imageView.disabledCursor, .operationNotAllowed)
        XCTAssertFalse(imageView.containsResizeHitTarget(NSPoint(x: imageView.bounds.maxX, y: imageView.bounds.midY)))
        imageView.mouseDown(with: try mouseDownEvent(windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(mounted.view.selection, .blocks([imageID]))
    }

    func testSwitchingToReadOnlyDismissesMutationUIAndCompletion() throws {
        let blockID = BlockInputBlockID(rawValue: "paragraph")
        let provider = ReadOnlyCompletionProvider()
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "/")
            ]),
            completionProvider: provider
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        item.setSelectedRange(NSRange(location: 1, length: 0))
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 1)), notify: false)
        mounted.view.refreshCompletionSession(item: item, blockID: blockID)
        XCTAssertNotNil(mounted.view.completionSession)

        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 1)), notify: false)
        XCTAssertTrue(mounted.view.performCommand(.insertLink(BlockInputInsertLinkCommand(presentation: .modal))))
        XCTAssertNotNil(mounted.view.linkModalView)

        mounted.view.configure(BlockInputConfiguration(
            document: mounted.view.document,
            isEditable: false,
            completionProvider: provider
        ))

        XCTAssertNil(mounted.view.completionSession)
        XCTAssertNil(mounted.view.linkModalView)
    }

    func testReadOnlyAppliesSubtleBaseTextStyle() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "paragraph", text: "Dimmed")
            ]),
            isEditable: false
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        let color = try XCTUnwrap(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)

        XCTAssertLessThan(color.alphaComponent, 1)
        XCTAssertGreaterThan(color.alphaComponent, 0.5)
    }

    func testReadOnlyAppliesSubtleFrontMatterStyle() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "front", kind: .frontMatter, text: "title: Demo")
            ]),
            isEditable: false
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        let keyColor = try XCTUnwrap(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        let colonColor = try XCTUnwrap(textStorage.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? NSColor)
        let valueColor = try XCTUnwrap(textStorage.attribute(.foregroundColor, at: 7, effectiveRange: nil) as? NSColor)
        let dividerView = try XCTUnwrap(item.testingFrontMatterDividerView)

        for color in [keyColor, colonColor, valueColor] {
            XCTAssertLessThan(color.alphaComponent, 1)
            XCTAssertGreaterThan(color.alphaComponent, 0.3)
        }
        XCTAssertEqual(dividerView.alphaValue, BlockInputReadOnlyStyle.chromeAlpha, accuracy: 0.01)
    }

    func testReadOnlyAppliesSubtleCodeBlockStyle() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "code", kind: .code(language: "swift"), text: "let value = 1")
            ]),
            isEditable: false
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        let keywordColor = try XCTUnwrap(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        let baseColor = try XCTUnwrap(textStorage.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor)

        for color in [keywordColor, baseColor] {
            XCTAssertLessThan(color.alphaComponent, 1)
            XCTAssertGreaterThan(color.alphaComponent, 0.3)
        }
        XCTAssertEqual(
            item.testingCodeBackgroundView.alphaValue,
            BlockInputReadOnlyStyle.codeBackgroundAlpha,
            accuracy: 0.01
        )
    }

    func testReadOnlyAppliesSubtleRawMarkdownStyle() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "raw", kind: .rawMarkdown, text: "<div>Raw</div>")
            ]),
            isEditable: false
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        let color = try XCTUnwrap(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)

        XCTAssertLessThan(color.alphaComponent, 1)
        XCTAssertGreaterThan(color.alphaComponent, 0.3)
    }

    func testReadOnlyAppliesSubtleTableStyle() throws {
        let table = BlockInputTable.normalized(
            header: ["Name", "Link"],
            bodyRows: [["Value", "[Docs](https://example.com)"]],
            alignments: [.left, .left]
        )
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "table", kind: .table, text: table.markdown)
            ]),
            isEditable: false
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cellTextViews = item.testingTableCellTextViews
        let cellViews = item.testingTableCellViews
        let headerColor = try foregroundColor(at: 0, in: cellTextViews[0])
        let bodyColor = try foregroundColor(at: 0, in: cellTextViews[2])
        let linkColor = try foregroundColor(at: 1, in: cellTextViews[3])

        for color in [headerColor, bodyColor, linkColor] {
            XCTAssertLessThan(color.alphaComponent, 1)
            XCTAssertGreaterThan(color.alphaComponent, 0.3)
        }
        let readOnlyBorderAlpha = try XCTUnwrap(cellViews[0].layer?.borderColor?.alpha)
        let editableMounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: "editable-table", kind: .table, text: table.markdown)
        ])))
        let editableItem = try XCTUnwrap(editableMounted.view.visibleBlockItemForTesting(at: 0))
        let editableBorderAlpha = try XCTUnwrap(editableItem.testingTableCellViews[0].layer?.borderColor?.alpha)
        XCTAssertLessThan(readOnlyBorderAlpha, editableBorderAlpha)
        XCTAssertEqual(readOnlyBorderAlpha, editableBorderAlpha * BlockInputReadOnlyStyle.tableBorderAlpha, accuracy: 0.01)
        XCTAssertLessThan(cellViews[0].layer?.backgroundColor?.alpha ?? 1, 0.08)
    }
}

@MainActor
private func foregroundColor(at offset: Int, in textView: NSTextView) throws -> NSColor {
    let textStorage = try XCTUnwrap(textView.textStorage)
    return try XCTUnwrap(textStorage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor)
}

private final class ReadOnlyCompletionProvider: BlockInputCompletionProvider, @unchecked Sendable {
    func suggestions(for context: BlockInputCompletionContext) async -> [BlockInputCompletionSuggestion] {
        [
            BlockInputCompletionSuggestion(
                id: "command",
                title: "Command",
                insertionText: "/command",
                trigger: .slashCommand
            )
        ]
    }
}

private final class CursorRectProbeView: NSView {
    var addedCursorRects: [(rect: NSRect, cursor: NSCursor)] = []

    override func addCursorRect(_ rect: NSRect, cursor object: NSCursor) {
        addedCursorRects.append((rect, object))
        super.addCursorRect(rect, cursor: object)
    }
}
