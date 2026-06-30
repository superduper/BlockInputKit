import Foundation
import XCTest
@testable import BlockInputKit

final class BlockInputStoreInsertionTests: XCTestCase {
    @MainActor
    func testMarkdownInsertionDoesNotFallBackToStaleViewSnapshotWhenStoreMisses() {
        let staleID = BlockInputBlockID(rawValue: "stale")
        let replacementID = BlockInputBlockID(rawValue: "replacement")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: staleID, text: "Old")
        ]))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store))
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: replacementID, text: "New")
        ]))
        store.resetCounts()

        let selection = view.insertMarkdown("Inserted", below: staleID)

        XCTAssertNil(selection)
        XCTAssertEqual(store.document.blocks.map(\.id), [replacementID])
        XCTAssertEqual(store.indexReadIDs, [staleID])
    }

    @MainActor
    func testMarkdownInsertionRefreshesFromStoreBeforeMutating() {
        let staleID = BlockInputBlockID(rawValue: "stale")
        let replacementID = BlockInputBlockID(rawValue: "replacement")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: staleID, text: "Old")
        ]))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store))
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: replacementID, text: "New")
        ]))
        store.resetCounts()

        let selection = view.insertMarkdown("Inserted", below: replacementID)

        XCTAssertEqual(store.document.blocks.map(\.text), ["New", "Inserted"])
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.insertedBlockBatches.count, 1)
        XCTAssertEqual(store.insertedBlockBatches.first?.index, 1)
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: store.document.blocks[1].id, utf16Offset: 0)))
    }

    @MainActor
    func testMarkdownInsertionDowngradesFrontMatterWhenInsertedMidDocument() {
        let blockID = BlockInputBlockID(rawValue: "body")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Body")
        ]))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store))

        _ = view.insertMarkdown("---\ntitle: Demo\n---", below: blockID)

        XCTAssertEqual(store.document.blocks.map(\.kind), [.paragraph, .rawMarkdown])
        XCTAssertEqual(store.document.blocks[1].text, "---\ntitle: Demo\n---")
    }

    @MainActor
    func testMarkdownInsertionPreservesDotClosedFrontMatterWhenDowngradingMidDocument() {
        let blockID = BlockInputBlockID(rawValue: "body")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Body")
        ]))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store))

        _ = view.insertMarkdown("---\ntitle: Demo\n...\n\nTail", below: blockID)

        XCTAssertEqual(store.document.blocks.map(\.kind), [.paragraph, .rawMarkdown, .paragraph])
        XCTAssertEqual(store.document.blocks[1].text, "---\ntitle: Demo\n...\n")
        XCTAssertEqual(store.document.blocks[2].text, "Tail")
    }

    @MainActor
    func testMarkdownInsertionFallsBackToFirstStoreBlockWhenSelectionWasRemoved() {
        let staleID = BlockInputBlockID(rawValue: "stale")
        let replacementID = BlockInputBlockID(rawValue: "replacement")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: staleID, text: "Old")
        ]))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store))
        view.applySelection(.cursor(BlockInputCursor(blockID: staleID, utf16Offset: 0)), notify: false)
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: replacementID, text: "New")
        ]))
        store.resetCounts()

        let selection = view.insertMarkdown("Inserted")

        XCTAssertEqual(store.document.blocks.map(\.text), ["New", "Inserted"])
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.insertedBlockBatches.count, 1)
        XCTAssertEqual(store.insertedBlockBatches.first?.index, 1)
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: store.document.blocks[1].id, utf16Offset: 0)))
    }

    @MainActor
    func testMarkdownInsertionUsesFirstStillValidBlockFromPartiallyStaleBlockSelection() {
        let staleID = BlockInputBlockID(rawValue: "stale")
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: staleID, text: "Old"),
            BlockInputBlock(id: firstID, text: "First")
        ]))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store))
        view.applySelection(.blocks([staleID, secondID]), notify: false)
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ]))
        store.resetCounts()

        let selection = view.insertMarkdown("Inserted")

        XCTAssertEqual(store.document.blocks.map(\.text), ["First", "Second", "Inserted"])
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.insertedBlockBatches.count, 1)
        XCTAssertEqual(store.insertedBlockBatches.first?.index, 2)
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: store.document.blocks[2].id, utf16Offset: 0)))
    }

    @MainActor
    func testFileInsertionDoesNotFallBackToStaleViewSnapshotWhenStoreMisses() {
        let staleID = BlockInputBlockID(rawValue: "stale")
        let replacementID = BlockInputBlockID(rawValue: "replacement")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: staleID, text: "Old")
        ]))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store))
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: replacementID, text: "New")
        ]))
        store.resetCounts()

        let selection = view.insertFileURLs([URL(fileURLWithPath: "/tmp/example.txt")], below: staleID)

        XCTAssertNil(selection)
        XCTAssertEqual(store.document.blocks.map(\.id), [replacementID])
        XCTAssertEqual(store.indexReadIDs, [staleID])
    }

    @MainActor
    func testFileInsertionRefreshesFromStoreBeforeMutating() {
        let staleID = BlockInputBlockID(rawValue: "stale")
        let replacementID = BlockInputBlockID(rawValue: "replacement")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: staleID, text: "Old")
        ]))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store))
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: replacementID, text: "New")
        ]))
        store.resetCounts()

        let selection = view.insertFileURLs([URL(fileURLWithPath: "/tmp/example.txt")], below: replacementID)

        XCTAssertEqual(store.document.blocks.map(\.text), ["New", "[example.txt](<file:///tmp/example.txt>)"])
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.insertedBlockBatches.count, 1)
        XCTAssertEqual(store.insertedBlockBatches.first?.index, 1)
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: store.document.blocks[1].id, utf16Offset: 0)))
    }

    @MainActor
    func testFileInsertionAtStartKeepsStoreFrontMatterLeading() {
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: "front", kind: .frontMatter, text: "title: Demo"),
            BlockInputBlock(id: "body", text: "Body")
        ]))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store))
        store.resetCounts()

        let selection = view.insertFileURLs([URL(fileURLWithPath: "/tmp/example.txt")], at: 0)

        XCTAssertEqual(store.document.blocks.map(\.kind), [.frontMatter, .paragraph, .paragraph])
        XCTAssertEqual(store.document.blocks.map(\.text), ["title: Demo", "[example.txt](<file:///tmp/example.txt>)", "Body"])
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.insertedBlockBatches.count, 1)
        XCTAssertEqual(store.insertedBlockBatches.first?.index, 1)
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: store.document.blocks[1].id, utf16Offset: 0)))
    }

    @MainActor
    func testFileInsertionFallsBackToFirstStoreBlockWhenSelectionWasRemoved() {
        let staleID = BlockInputBlockID(rawValue: "stale")
        let replacementID = BlockInputBlockID(rawValue: "replacement")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: staleID, text: "Old")
        ]))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store))
        view.applySelection(.cursor(BlockInputCursor(blockID: staleID, utf16Offset: 0)), notify: false)
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: replacementID, text: "New")
        ]))
        store.resetCounts()

        let selection = view.insertFileURLs([URL(fileURLWithPath: "/tmp/example.txt")])

        XCTAssertEqual(store.document.blocks.map(\.text), ["New", "[example.txt](<file:///tmp/example.txt>)"])
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.insertedBlockBatches.count, 1)
        XCTAssertEqual(store.insertedBlockBatches.first?.index, 1)
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: store.document.blocks[1].id, utf16Offset: 0)))
    }

    @MainActor
    func testFileInsertionUsesFirstStillValidBlockFromPartiallyStaleBlockSelection() {
        let staleID = BlockInputBlockID(rawValue: "stale")
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: staleID, text: "Old"),
            BlockInputBlock(id: firstID, text: "First")
        ]))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store))
        view.applySelection(.blocks([staleID, secondID]), notify: false)
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ]))
        store.resetCounts()

        let selection = view.insertFileURLs([URL(fileURLWithPath: "/tmp/example.txt")])

        XCTAssertEqual(store.document.blocks.map(\.text), [
            "First",
            "Second",
            "[example.txt](<file:///tmp/example.txt>)"
        ])
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.insertedBlockBatches.count, 1)
        XCTAssertEqual(store.insertedBlockBatches.first?.index, 2)
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: store.document.blocks[2].id, utf16Offset: 0)))
    }
}
