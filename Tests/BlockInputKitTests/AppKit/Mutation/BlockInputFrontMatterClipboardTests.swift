import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputFrontMatterClipboardTests: XCTestCase {
    func testCommandCCopiesWholeFrontMatterSelectionWithDelimiters() throws {
        let front = BlockInputBlock(id: "front", kind: .frontMatter, text: "title: Demo")
        let mounted = makeMountedBlockInputView(blocks: [front])
        mounted.view.applySelection(.blocks([front.id]), notify: false)
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

        XCTAssertEqual(pasteboard.string(forType: .string), "---\ntitle: Demo\n---")
    }

    func testCommandCCopiesFullBodyFrontMatterTextSelectionWithDelimiters() throws {
        let front = BlockInputBlock(id: "front", kind: .frontMatter, text: "title: Demo")
        let mounted = makeMountedBlockInputView(blocks: [front])
        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: front.id,
            range: NSRange(location: 0, length: front.utf16Length)
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

        XCTAssertEqual(pasteboard.string(forType: .string), "---\ntitle: Demo\n---")
    }

    func testCommandCCopiesPartialFrontMatterSelectionAsRawBodyText() throws {
        let front = BlockInputBlock(id: "front", kind: .frontMatter, text: "title: Demo")
        let mounted = makeMountedBlockInputView(blocks: [front])
        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: front.id,
            range: NSRange(location: 0, length: 5)
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

        mounted.view.blockInputCopy(nil)

        XCTAssertEqual(pasteboard.string(forType: .string), "title")
    }

    func testCutActionCopiesFullBodyFrontMatterTextSelectionWithDelimiters() throws {
        let front = BlockInputBlock(id: "front", kind: .frontMatter, text: "title: Demo")
        let mounted = makeMountedBlockInputView(blocks: [front])
        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: front.id,
            range: NSRange(location: 0, length: front.utf16Length)
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

        mounted.view.blockInputCut(nil)

        XCTAssertEqual(pasteboard.string(forType: .string), "---\ntitle: Demo\n---")
        XCTAssertEqual(mounted.view.document.blocks[0].kind, .frontMatter)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "")
    }

    func testCutMixedSelectionAcrossFrontMatterBoundaryDoesNotMergeBodyIntoMetadata() throws {
        let frontText = "title: Demo\nslug: demo"
        let front = BlockInputBlock(id: "front", kind: .frontMatter, text: frontText)
        let body = BlockInputBlock(id: "body", text: "Body paragraph")
        let mounted = makeMountedBlockInputView(blocks: [front, body])
        mounted.view.applySelection(.mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(
                blockID: front.id,
                range: NSRange(location: 7, length: (frontText as NSString).length - 7)
            ),
            trailingTextRange: BlockInputTextRange(
                blockID: body.id,
                range: NSRange(location: 0, length: 5)
            )
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

        mounted.view.blockInputCut(nil)

        XCTAssertEqual(pasteboard.string(forType: .string), "Demo\nslug: demo\n\nBody ")
        XCTAssertEqual(mounted.view.document.blocks.map(\.kind), [.frontMatter, .paragraph])
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["title: ", "paragraph"])
    }
}
