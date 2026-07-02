import AppKit
import XCTest
@testable import BlockInputKit

/// Scenario tests for vim yank/delete/paste sequences.
///
/// Each test snapshots block kinds AND the Markdown representation before an operation, then diffs after.
/// "Block AST" means: the kind + text of every block in order.
/// "Markdown" means: `document.markdown` — the canonical serialization that must remain round-trippable.
@MainActor
final class DemoVimCopyPasteTests: XCTestCase {

    // MARK: - Block snapshot helpers

    private struct BlockSnapshot: Equatable, CustomStringConvertible {
        let kind: BlockInputBlockKind
        let text: String
        var description: String { "\(kind): \"\(text)\"" }
    }

    private func blockAST(_ view: BlockInputView) -> [BlockSnapshot] {
        view.document.blocks.map { BlockSnapshot(kind: $0.kind, text: $0.text) }
    }

    private func markdown(_ view: BlockInputView) -> String {
        view.document.markdown
    }

    // MARK: - vim dd + p: heading kind must survive round-trip

    func testDDAndPasteHeadingPreservesKindAndMarkdown() throws {
        // Scenario: dd on a heading; p pastes it back using insertBlockBelowWithContent.
        // Both the block AST (kind = .heading(level:2)) and the Markdown ("## Chapter One")
        // must be preserved — not degraded to a paragraph with raw "## text".
        let h2ID = BlockInputBlockID(rawValue: "heading-chapter-one")
        let afterID = BlockInputBlockID(rawValue: "para-below")
        let headingText = "Chapter One"
        let belowText = "paragraph below"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: h2ID, kind: .heading(level: 2), text: headingText),
            BlockInputBlock(id: afterID, text: belowText)
        ])
        let beforeMarkdown = markdown(mounted.view)
        XCTAssertTrue(beforeMarkdown.contains("## Chapter One"),
                      "Markdown must contain '## Chapter One' before any edit")

        // dd: save to register (kind + text), then delete
        let capturedKind = BlockInputBlockKind.heading(level: 2)
        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: h2ID, utf16Offset: 0)))
        mounted.view.performCommand(.selectCurrentBlock)
        mounted.view.performCommand(.cut)

        XCTAssertEqual(mounted.view.document.blocks.count, 1, "heading must be removed after dd")
        XCTAssertFalse(markdown(mounted.view).contains("## Chapter One"),
                       "heading must not appear in Markdown after dd")

        // p: insertBlockBelowWithContent (what the fixed adapter now dispatches)
        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: afterID, utf16Offset: 0)))
        mounted.view.performCommand(.insertBlockBelowWithContent(kind: capturedKind, text: headingText))

        // AST check
        let ast = blockAST(mounted.view)
        XCTAssertEqual(ast.count, 2)
        let pastedBlock = ast.first { if case .heading(level: 2) = $0.kind { true } else { false } }
        XCTAssertNotNil(pastedBlock, "pasted block must be heading(level:2), not a paragraph with raw '##'")
        XCTAssertEqual(pastedBlock?.text, headingText)

        // Markdown check
        XCTAssertTrue(markdown(mounted.view).contains("## \(headingText)"),
                      "Markdown must render heading with ## prefix, not inline '##' text")
    }

    func testDeleteStackAllowsFiveDeletesThenFivePastes() throws {
        // Reproduces: "last headers (3 out of 5) get pasted as bare ## text instead of header".
        // Fix: dd pushes onto a LIFO delete stack; each p pops the top entry so that
        // 5×dd + 5×p restores all 5 blocks — each with its correct kind and Markdown prefix.
        struct HeadingFixture {
            let id: BlockInputBlockID
            let level: Int
            let title: String
            var markdownPrefix: String { String(repeating: "#", count: level) + " " }
        }
        let fixtures: [HeadingFixture] = [
            .init(id: .init(rawValue: "h-alpha"), level: 1, title: "Alpha"),
            .init(id: .init(rawValue: "h-beta"), level: 2, title: "Beta"),
            .init(id: .init(rawValue: "h-gamma"), level: 3, title: "Gamma"),
            .init(id: .init(rawValue: "h-delta"), level: 2, title: "Delta"),
            .init(id: .init(rawValue: "h-epsilon"), level: 1, title: "Epsilon")
        ]
        let anchorID = BlockInputBlockID(rawValue: "anchor-para")
        var blocks = fixtures.map {
            BlockInputBlock(id: $0.id, kind: .heading(level: $0.level), text: $0.title)
        }
        blocks.append(BlockInputBlock(id: anchorID, text: "anchor"))
        let mounted = makeMountedBlockInputView(blocks: blocks)

        // 5×dd: build a local LIFO stack mirroring what the adapter's deleteStack accumulates
        var deleteStack: [(kind: BlockInputBlockKind, text: String)] = []
        for fixture in fixtures {
            mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: fixture.id, utf16Offset: 0)))
            deleteStack.insert((kind: .heading(level: fixture.level), text: fixture.title), at: 0)
            mounted.view.performCommand(.selectCurrentBlock)
            mounted.view.performCommand(.cut)
        }
        XCTAssertEqual(mounted.view.document.blocks.count, 1, "only anchor must remain after 5 dd operations")

        // 5×p: pop from LIFO stack — each p uses insertBlockBelowWithContent (what pasteFromRegister does)
        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: anchorID, utf16Offset: 0)))
        for reg in deleteStack {
            mounted.view.performCommand(.insertBlockBelowWithContent(kind: reg.kind, text: reg.text))
        }

        // AST check: all pasted blocks must be headings — NOT paragraphs with raw "#" text
        let finalAST = blockAST(mounted.view)
        let rawHashParagraphs = finalAST.filter { snap in
            guard case .paragraph = snap.kind else { return false }
            return snap.text.hasPrefix("#")
        }
        XCTAssertTrue(rawHashParagraphs.isEmpty,
                      "No block may be a paragraph with raw '##' text after 5×dd+5×p. Got: \(rawHashParagraphs)")

        // AST check: each heading must be present with its exact kind
        for fixture in fixtures {
            let found = finalAST.first { $0.text == fixture.title }
            XCTAssertNotNil(found, "'\(fixture.title)' must appear in block AST after paste")
            XCTAssertEqual(found?.kind, .heading(level: fixture.level),
                           "'\(fixture.title)' must be heading(level:\(fixture.level)), not \(String(describing: found?.kind))")
        }

        // Markdown check: every heading must render with its ## prefix
        let rendered = markdown(mounted.view)
        for fixture in fixtures {
            let expectedMarkdownLine = fixture.markdownPrefix + fixture.title
            XCTAssertTrue(rendered.contains(expectedMarkdownLine),
                          "Markdown must contain '\(expectedMarkdownLine)' for \(fixture.title)")
        }
    }

    // MARK: - vim yy + p: heading yank must duplicate as heading

    func testYYAndPasteHeadingPreservesKindAndMarkdown() throws {
        // Scenario: yy copies heading into register; p inserts a structural duplicate.
        let hID = BlockInputBlockID(rawValue: "heading-title")
        let afterID = BlockInputBlockID(rawValue: "body-para")
        let headingText = "Title"
        let headingLevel = 1
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: hID, kind: .heading(level: headingLevel), text: headingText),
            BlockInputBlock(id: afterID, text: "body")
        ])
        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: hID, utf16Offset: 0)))

        // yy: capture register, copy to clipboard, don't delete
        let capturedKind = BlockInputBlockKind.heading(level: headingLevel)
        mounted.view.performCommand(.selectCurrentBlock)
        mounted.view.performCommand(.copy)

        // p: paste structural copy below the heading
        mounted.view.performCommand(.insertBlockBelowWithContent(kind: capturedKind, text: headingText))

        // AST check: two heading(level:1) blocks both with "Title"
        let ast = blockAST(mounted.view)
        let h1Blocks = ast.filter { if case .heading(level: 1) = $0.kind { true } else { false } }
        XCTAssertEqual(h1Blocks.count, 2, "yy + p must produce two heading(level:1) blocks")
        XCTAssertTrue(h1Blocks.allSatisfy { $0.text == headingText })

        // Markdown check: "# Title" must appear at least twice
        let rendered = markdown(mounted.view)
        let occurrences = rendered.components(separatedBy: "# \(headingText)").count - 1
        XCTAssertGreaterThanOrEqual(occurrences, 2, "Markdown must contain '# Title' twice after yy+p")
    }

    // MARK: - Paragraph dd + p

    func testDDAndPasteParagraphPreservesKindAndMarkdown() throws {
        // Scenario: dd + p on a paragraph via insertBlockBelowWithContent.
        let pID = BlockInputBlockID(rawValue: "para-first")
        let afterID = BlockInputBlockID(rawValue: "para-second")
        let paraText = "plain text"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: pID, text: paraText),
            BlockInputBlock(id: afterID, text: "second")
        ])
        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: pID, utf16Offset: 0)))

        // dd: capture + cut
        let capturedKind = BlockInputBlockKind.paragraph
        mounted.view.performCommand(.selectCurrentBlock)
        mounted.view.performCommand(.cut)
        XCTAssertEqual(mounted.view.document.blocks.count, 1)

        // p: structural paste
        mounted.view.performCommand(.insertBlockBelowWithContent(kind: capturedKind, text: paraText))

        let ast = blockAST(mounted.view)
        XCTAssertEqual(ast.count, 2)
        XCTAssertTrue(ast.contains { $0.text == paraText && $0.kind == .paragraph },
                      "pasted block must be a paragraph with '\(paraText)'")
        XCTAssertTrue(markdown(mounted.view).contains(paraText),
                      "Markdown must contain '\(paraText)' after dd+p")
    }

    // MARK: - Mixed-kind document integrity

    func testCutDoesNotCorruptOtherBlocksASTOrMarkdown() throws {
        // Scenario: cut the middle block; the surrounding heading blocks must be untouched
        // in both their AST representation and Markdown serialization.
        let h1ID = BlockInputBlockID(rawValue: "h1-heading")
        let paraID = BlockInputBlockID(rawValue: "para-middle")
        let h2ID = BlockInputBlockID(rawValue: "h2-subheading")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: h1ID, kind: .heading(level: 1), text: "Heading"),
            BlockInputBlock(id: paraID, text: "paragraph"),
            BlockInputBlock(id: h2ID, kind: .heading(level: 2), text: "Sub")
        ])
        let beforeAST = blockAST(mounted.view)
        let beforeMarkdown = markdown(mounted.view)

        mounted.view.applySelectionForTesting(.cursor(BlockInputCursor(blockID: paraID, utf16Offset: 0)))
        mounted.view.performCommand(.selectCurrentBlock)
        mounted.view.performCommand(.cut)

        let afterAST = blockAST(mounted.view)
        XCTAssertEqual(afterAST.count, 2)
        XCTAssertEqual(afterAST[0], beforeAST[0], "h1 AST must be untouched")
        XCTAssertEqual(afterAST[1], beforeAST[2], "h2 AST must be untouched")

        let afterMarkdown = markdown(mounted.view)
        XCTAssertTrue(afterMarkdown.contains("# Heading"), "# Heading must remain in Markdown")
        XCTAssertTrue(afterMarkdown.contains("## Sub"), "## Sub must remain in Markdown")
        XCTAssertFalse(afterMarkdown.contains("paragraph"), "cut paragraph must not appear in Markdown")
        _ = beforeMarkdown // silence unused warning
    }

    // MARK: - No accidental character insertion from operator keys

    func testNormalModeOperatorSequencesDontInsertCharacters() throws {
        // Operator keys (d, y, c) intercepted in normal mode must not insert characters as text.
        let blockID = BlockInputBlockID(rawValue: "watched-block")
        let originalText = "watch this text"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: originalText)
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        // dw: extend word right then cut — content changes, but "d" and "w" must not appear
        mounted.view.performCommand(.extendSelectionWordRight)
        mounted.view.performCommand(.cut)

        let afterDW = mounted.view.document.blocks.first?.text ?? ""
        XCTAssertFalse(afterDW.hasPrefix("d"),
                       "'d' must not be inserted as the first character on vim dw")
        XCTAssertFalse(afterDW.hasPrefix("w"),
                       "'w' must not be inserted as the first character on vim dw")
        XCTAssertFalse(afterDW.hasPrefix("dw"),
                       "literal 'dw' must not appear after vim dw")

        // yw: extend word right then copy — no text mutation
        let beforeYW = blockAST(mounted.view)
        mounted.view.performCommand(.extendSelectionWordRight)
        mounted.view.performCommand(.copy)
        mounted.view.performCommand(.moveLeft)

        XCTAssertEqual(blockAST(mounted.view).map(\.text), beforeYW.map(\.text),
                       "yw must not insert 'y' or 'w' characters into block text")
    }
}
