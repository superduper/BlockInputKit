import Foundation
import XCTest
@testable import BlockInputKit

final class BlockInputFrontMatterMarkdownTests: XCTestCase {
    func testMarkdownParsesLeadingFrontMatterAsDelimiterFreeBody() {
        let source = """
        ---
        title: Demo
        tags:
          - swift

        # comment
        ---
        # Heading
        """

        let document = BlockInputDocument(markdown: source)

        XCTAssertEqual(document.blocks.map(\.kind), [.frontMatter, .heading(level: 1)])
        XCTAssertEqual(document.blocks[0].text, "title: Demo\ntags:\n  - swift\n\n# comment")
    }

    func testMarkdownRoundTripPreservesFrontMatterBodyFormatting() {
        let body = "title: \"Demo\"\ntags:\n  - swift\npublished: 2026-05-18"
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(kind: .frontMatter, text: body),
            BlockInputBlock(kind: .paragraph, text: "Body")
        ])

        XCTAssertEqual(document.markdown, "---\n\(body)\n---\n\nBody")
        XCTAssertEqual(BlockInputDocument(markdown: document.markdown).blocks[0].text, body)
    }

    func testMarkdownPreservesIntentionalTrailingBlankLineBeforeFrontMatterDelimiter() {
        let source = """
        ---
        title: Demo

        ---

        Body
        """

        let document = BlockInputDocument(markdown: source)

        XCTAssertEqual(document.blocks.map(\.kind), [.frontMatter, .paragraph])
        XCTAssertEqual(document.blocks[0].text, "title: Demo\n")
        XCTAssertEqual(document.markdown, source)
    }

    func testMarkdownParsesEmptyAndDotClosedFrontMatter() {
        let empty = BlockInputDocument(markdown: "---\n---\nBody")
        let dotClosed = BlockInputDocument(markdown: "---\ntitle: Demo\n...\nBody")

        XCTAssertEqual(empty.blocks.map(\.kind), [.frontMatter, .paragraph])
        XCTAssertEqual(empty.blocks[0].text, "")
        XCTAssertEqual(dotClosed.blocks.map(\.kind), [.frontMatter, .paragraph])
        XCTAssertEqual(dotClosed.blocks[0].text, "title: Demo")
    }

    func testMarkdownPreservesUnclosedLeadingFrontMatterAsRawMarkdown() {
        let source = "---\ntitle: Demo\nlist:\n  - swift"

        let document = BlockInputDocument(markdown: source)

        XCTAssertEqual(document.blocks.map(\.kind), [.rawMarkdown])
        XCTAssertEqual(document.blocks[0].text, source)
        XCTAssertEqual(document.markdown, source)
    }

    func testMarkdownKeepsNonLeadingDelimiterRunAsExistingRawMarkdownFallback() {
        let document = BlockInputDocument(markdown: "# Heading\n---\ntitle: Demo\n---")

        XCTAssertEqual(document.blocks.map(\.kind), [
            .heading(level: 1),
            .horizontalRule,
            .rawMarkdown
        ])
    }

    func testStreamingMarkdownSnapshotPreservesFrontMatterFormatting() async throws {
        let body = "title: Demo\nlist:\n  - one"
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(kind: .frontMatter, text: body),
            BlockInputBlock(kind: .heading(level: 2), text: "Heading")
        ])
        var writer = RecordingMarkdownWriter()

        try await document.writeMarkdown(to: &writer)
        let snapshot = await document.markdownSnapshot()

        XCTAssertEqual(snapshot, "---\n\(body)\n---\n\n## Heading")
        XCTAssertEqual(writer.markdown, "---\n\(body)\n---\n\n## Heading")
    }
}

private struct RecordingMarkdownWriter: BlockInputMarkdownWriter {
    var markdown = ""

    mutating func writeMarkdown(_ chunk: String) async throws {
        markdown += chunk
    }
}
