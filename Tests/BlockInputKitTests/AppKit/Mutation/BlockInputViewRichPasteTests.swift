import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewRichPasteTests: XCTestCase {
    /// Test handler that claims a single pasteboard type and returns canned references.
    private struct StubPasteHandler: BlockInputPasteContentHandler {
        var handledTypes: [NSPasteboard.PasteboardType]
        var references: [BlockInputFileDropReference]?
        var onPlacement: (@Sendable (BlockInputFileDropPlacement) -> Void)?

        func references(
            from pasteboard: NSPasteboard,
            type: NSPasteboard.PasteboardType,
            placement: BlockInputFileDropPlacement,
            document: BlockInputDocument
        ) async -> [BlockInputFileDropReference]? {
            onPlacement?(placement)
            return references
        }
    }

    func testPasteInsertsImageBlockFromHandler() async throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: blockID, text: "Before after")]),
            pasteContentHandlers: [
                StubPasteHandler(
                    handledTypes: [.png],
                    references: [BlockInputFileDropReference(kind: .image, source: "assets/Pasted.png", label: "Shot")]
                )
            ]
        ))
        let textView = try textView(in: mounted.view)
        setSelection(in: textView, location: 6)
        writePasteboard { $0.setData(Data([0x89, 0x50]), forType: .png) }

        textView.paste(nil)
        await drainPasteTasks(in: mounted.view)

        XCTAssertEqual(mounted.view.document.blocks.count, 2)
        XCTAssertEqual(
            mounted.view.document.blocks[1].kind,
            .image(BlockInputImage(source: "assets/Pasted.png", altText: "Shot"))
        )
    }

    func testPasteInsertsFileChipInlineAtCaret() async throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: blockID, text: "Open docs")]),
            pasteContentHandlers: [
                StubPasteHandler(
                    handledTypes: [.fileURL],
                    references: [BlockInputFileDropReference(kind: .fileLink, source: "file:///tmp/report.pdf", label: "report.pdf")],
                    onPlacement: { XCTAssertEqual($0, .inline(blockID: blockID, utf16Offset: 5)) }
                )
            ]
        ))
        let textView = try textView(in: mounted.view)
        setSelection(in: textView, location: 5)
        writePasteboard { $0.writeObjects([URL(fileURLWithPath: "/tmp/report.pdf") as NSURL]) }

        textView.paste(nil)
        await drainPasteTasks(in: mounted.view)

        XCTAssertEqual(mounted.view.document.blocks[0].text, "Open [report.pdf](file:///tmp/report.pdf)docs")
    }

    func testPasteFallsThroughToNativeWhenHandlerDeclines() async throws {
        // A handler claims .png but declines (returns nil). Native paste must still run as fallback, inserting the
        // pasteboard's plain text — the paste must not be silently swallowed.
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "block", text: "Hello")]),
            pasteContentHandlers: [StubPasteHandler(handledTypes: [.png], references: nil)]
        ))
        let textView = try textView(in: mounted.view)
        setSelection(in: textView, location: 5)
        writePasteboard {
            $0.setData(Data([0x89]), forType: .png)
            $0.setString("!", forType: .string)
        }

        textView.paste(nil)
        await drainPasteTasks(in: mounted.view)
        // Yield once more so the onDeclined native paste (dispatched after the async decline) applies.
        await Task.yield()

        XCTAssertEqual(mounted.view.document.blocks[0].text, "Hello!")
    }

    func testPasteTriesSecondHandlerWhenFirstDeclines() async throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: blockID, text: "x")]),
            pasteContentHandlers: [
                StubPasteHandler(handledTypes: [.png], references: nil),
                StubPasteHandler(
                    handledTypes: [.png],
                    references: [BlockInputFileDropReference(kind: .image, source: "assets/Second.png", label: "S")]
                )
            ]
        ))
        let textView = try textView(in: mounted.view)
        setSelection(in: textView, location: 1)
        writePasteboard { $0.setData(Data([0x89]), forType: .png) }

        textView.paste(nil)
        await drainPasteTasks(in: mounted.view)

        XCTAssertEqual(mounted.view.document.blocks.count, 2)
        XCTAssertEqual(mounted.view.document.blocks[1].kind, .image(BlockInputImage(source: "assets/Second.png", altText: "S")))
    }

    func testPlainTextPasteIsUnaffectedByEmptyHandlers() async throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "block", text: "Hi")])
        ))
        let textView = try textView(in: mounted.view)
        setSelection(in: textView, location: 2)
        writePasteboard { $0.setString(" there", forType: .string) }

        textView.paste(nil)
        await drainPasteTasks(in: mounted.view)

        XCTAssertEqual(mounted.view.document.blocks[0].text, "Hi there")
    }

    // MARK: - Helpers

    private func textView(in view: BlockInputView) throws -> BlockInputTextView {
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        return try XCTUnwrap(item.testingTextView)
    }

    private func setSelection(in textView: BlockInputTextView, location: Int) {
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: location, length: 0))
    }

    private func writePasteboard(_ write: (NSPasteboard) -> Void) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        write(pasteboard)
    }

    private func drainPasteTasks(in view: BlockInputView) async {
        while !view.pasteContentTasks.isEmpty {
            await Task.yield()
        }
        await Task.yield()
    }
}
