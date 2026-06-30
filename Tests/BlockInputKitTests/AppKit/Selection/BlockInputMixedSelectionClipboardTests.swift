import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputMixedSelectionClipboardTests: XCTestCase {
    func testCommandCCopiesMixedFullCodeEndpointWithFence() throws {
        let code = BlockInputBlock(id: "code", kind: .code(language: nil), text: "let one = 1")
        let mounted = makeMountedBlockInputView(blocks: [code])
        mounted.view.applySelection(.mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: code.id, range: NSRange(location: 0, length: code.utf16Length))
        )), notify: false)
        mounted.window.makeFirstResponder(mounted.view)
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandCEvent()))

        XCTAssertEqual(pasteboard.string(forType: .string), BlockInputDocument(blocks: [code]).markdown)
    }

    func testCommandCCopiesMixedPartialCodeEndpointFromStartWithoutFence() throws {
        let code = BlockInputBlock(id: "code", kind: .code(language: nil), text: "let one = 1")
        let mounted = makeMountedBlockInputView(blocks: [code])
        mounted.view.applySelection(.mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: code.id, range: NSRange(location: 0, length: 3))
        )), notify: false)
        mounted.window.makeFirstResponder(mounted.view)
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandCEvent()))

        XCTAssertEqual(pasteboard.string(forType: .string), "let")
    }
}
