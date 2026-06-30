import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputClipboardStoreTests: XCTestCase {
    func testCopyActionReadsBlockSelectionFromConfiguredStore() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "Stale first"),
            BlockInputBlock(id: secondID, text: "Stale second")
        ]))
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(documentStore: store))
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "Fresh first"),
            BlockInputBlock(id: secondID, text: "Fresh second")
        ]))
        mounted.view.applySelection(.blocks([firstID, secondID]), notify: false)
        mounted.window.makeFirstResponder(mounted.view)
        store.resetCounts()
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        mounted.view.blockInputCopy(nil)

        XCTAssertEqual(pasteboard.string(forType: .string), "Fresh first\n\nFresh second")
        XCTAssertEqual(store.indexReadIDs, [firstID, secondID])
        XCTAssertEqual(store.blockAtReadIndexes, [0, 1])
    }

    func testCopyActionReadsMixedSelectionFromConfiguredStore() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "Stale first"),
            BlockInputBlock(id: secondID, text: "Stale second"),
            BlockInputBlock(id: thirdID, text: "Stale third")
        ]))
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(documentStore: store))
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "Fresh first"),
            BlockInputBlock(id: secondID, text: "Fresh second"),
            BlockInputBlock(id: thirdID, text: "Fresh third")
        ]))
        mounted.view.applySelection(.mixed(BlockInputMixedSelection(
            blockIDs: [secondID],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 6, length: 5)),
            trailingTextRange: BlockInputTextRange(blockID: thirdID, range: NSRange(location: 0, length: 5))
        )), notify: false)
        mounted.window.makeFirstResponder(mounted.view)
        store.resetCounts()
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        mounted.view.blockInputCopy(nil)

        XCTAssertEqual(pasteboard.string(forType: .string), "first\n\nFresh second\n\nFresh")
        XCTAssertEqual(store.indexReadIDs.count, 3)
        XCTAssertEqual(Set(store.indexReadIDs), Set([firstID, secondID, thirdID]))
        XCTAssertEqual(store.blockAtReadIndexes.count, 3)
        XCTAssertEqual(Set(store.blockAtReadIndexes), Set([0, 1, 2]))
    }
}
