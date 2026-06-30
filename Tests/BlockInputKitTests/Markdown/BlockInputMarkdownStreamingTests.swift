import Foundation
import XCTest
@testable import BlockInputKit

final class BlockInputMarkdownStreamingTests: XCTestCase {
    func testStreamingReadMatchesExistingMarkdownImport() async throws {
        let source = """
        ---
        title: Streaming
        ---

        # Heading
        Intro paragraph
        | A | B |
        | - | - |
        | 1 | 2 |
        > Quote
        - Item
        3. Numbered
        - [x] Done
        """
        var reader = ArrayMarkdownLineReader(markdown: source)

        let streamed = try await BlockInputDocument.readingMarkdown(from: &reader)
        let expected = BlockInputDocument(markdown: source)

        XCTAssertBlockDocumentsEqualIgnoringIDs(streamed, expected)
        XCTAssertEqual(streamed.markdown, expected.markdown)
    }

    func testStreamingReadMatchesRawPreservationCases() async throws {
        let sources = [
            "---\ntitle: Demo\n---\n\n# Heading",
            "---\n---\n# Heading",
            "| A | B |\n| - | - |\n| 1 | 2 |",
            "Before\n| A | B |\n| - | - |\n| 1 | 2 |",
            "<section>\nRaw HTML\n</section>\n# Heading",
            "<section>\nRaw HTML\n\n# Heading",
            "<script>\nconst value = \"# not a heading\";\n\n# Still raw\n</script>\n# Heading",
            "<!-- Raw comment -->\n# Heading",
            "<!DOCTYPE html\n  SYSTEM \"about:legacy-compat\">\n# Heading",
            "<?block-input\nmode=\"raw\"?>\n# Heading",
            "<![CDATA[Raw HTML-ish text]]>\n# Heading",
            "<callout-box>\nImportant\n</callout-box>\n# Heading",
            "<SECTION>\nRaw HTML\n</SECTION>\n# Heading",
            "<https://example.com>\n# Heading",
            "<span>Inline HTML</span> text\n# Heading",
            "Setext\n======\n# Heading",
            "First heading line\nsecond heading line\n-------------------\n# Next",
            "# Heading\n---\n- Item\n---",
            "[^note]: First paragraph.\n\n    Continued paragraph.\n# Heading"
        ]

        for source in sources {
            var reader = ArrayMarkdownLineReader(markdown: source)

            let streamed = try await BlockInputDocument.readingMarkdown(from: &reader)
            let expected = BlockInputDocument(markdown: source)

            XCTAssertBlockDocumentsEqualIgnoringIDs(streamed, expected)
            XCTAssertEqual(streamed.markdown, expected.markdown)
        }
    }

    func testStreamingReadMatchesExistingImportAfterUnclosedFrontMatterLookahead() async throws {
        let body = (0..<500)
            .map { "Line \($0)" }
            .joined(separator: "\n")
        let source = "---\n\(body)"
        var reader = ArrayMarkdownLineReader(markdown: source)

        let streamed = try await BlockInputDocument.readingMarkdown(from: &reader)
        let expected = BlockInputDocument(markdown: source)

        XCTAssertBlockDocumentsEqualIgnoringIDs(streamed, expected)
        XCTAssertEqual(streamed.blocks.map(\.kind), [.rawMarkdown])
        XCTAssertEqual(streamed.blocks[0].text, source)
        XCTAssertEqual(streamed.markdown, expected.markdown)
        XCTAssertEqual(streamed.markdown, source)
    }

    func testStreamingReadMatchesExistingImportWhenUnclosedFrontMatterRequiresLargeLookahead() async throws {
        let body = (0..<1_250)
            .map { "Line \($0)" }
            .joined(separator: "\n")
        let source = "---\n\(body)"
        var reader = ArrayMarkdownLineReader(markdown: source)

        let streamed = try await BlockInputDocument.readingMarkdown(from: &reader)
        let expected = BlockInputDocument(markdown: source)

        XCTAssertBlockDocumentsEqualIgnoringIDs(streamed, expected)
        XCTAssertEqual(streamed.blocks.map(\.kind), [.rawMarkdown])
        XCTAssertEqual(streamed.blocks[0].text, source)
        XCTAssertEqual(streamed.markdown, expected.markdown)
        XCTAssertEqual(streamed.markdown, source)
    }

    func testStreamingReadPreservesLongFrontMatter() async throws {
        let metadata = (0..<1_250).map { "key\($0): value" }
        let source = (["---"] + metadata + ["---", "# Heading"]).joined(separator: "\n")
        var reader = ArrayMarkdownLineReader(markdown: source)

        let streamed = try await BlockInputDocument.readingMarkdown(from: &reader)
        let expected = BlockInputDocument(markdown: source)

        XCTAssertBlockDocumentsEqualIgnoringIDs(streamed, expected)
        XCTAssertEqual(streamed.markdown, expected.markdown)
    }

    func testMutatingStreamingReadReplacesDocument() async throws {
        var reader = ArrayMarkdownLineReader(markdown: """
        # Loaded
        Body
        """)
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(kind: .paragraph, text: "Before")
        ])

        try await document.readMarkdown(from: &reader)

        XCTAssertEqual(document.blocks.map(\.kind), [.heading(level: 1), .paragraph])
        XCTAssertEqual(document.blocks.map(\.text), ["Loaded", "Body"])
    }

    func testStreamingReadPreservesReaderStateAfterReaderFailure() async {
        var reader = ThrowingMarkdownLineReader(lines: ["Paragraph"], throwAtIndex: 1)

        do {
            _ = try await BlockInputDocument.readingMarkdown(from: &reader)
            XCTFail("Expected reader failure to throw")
        } catch TestMarkdownLineReaderError.failure {
            XCTAssertEqual(reader.index, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStreamingWriteMatchesExistingMarkdownExport() async throws {
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(kind: .paragraph, text: "Intro"),
            BlockInputBlock(kind: .heading(level: 2), text: "Heading"),
            BlockInputBlock(kind: .code(language: "swift"), text: "let value = 1"),
            BlockInputBlock(kind: .quote, text: "Quoted\nText"),
            BlockInputBlock(kind: .bulletedListItem, text: "Bullet", indentationLevel: 1),
            BlockInputBlock(kind: .numberedListItem(start: 3), text: "Numbered"),
            BlockInputBlock(kind: .checklistItem(isChecked: false), text: "Todo"),
            BlockInputBlock(kind: .rawMarkdown, text: "| A |\n| - |"),
            BlockInputBlock(kind: .paragraph, text: "After")
        ])
        var writer = RecordingMarkdownWriter()

        try await document.writeMarkdown(to: &writer)

        XCTAssertEqual(writer.markdown, document.markdown)
        XCTAssertGreaterThan(writer.chunks.count, document.blocks.count)
        XCTAssertFalse(writer.chunks.contains(document.markdown))
    }

    func testAsyncConvenienceAPIsMatchExistingMarkdownBehavior() async {
        let source = """
        # Heading
        Paragraph

        [^note]: Raw footnote.
        """

        let parsed = await BlockInputDocument.parsingMarkdown(source)
        let expected = BlockInputDocument(markdown: source)
        let snapshot = await parsed.markdownSnapshot()

        XCTAssertBlockDocumentsEqualIgnoringIDs(parsed, expected)
        XCTAssertEqual(snapshot, expected.markdown)
    }

    func testStreamingMarkdownKeepsInlineStylingMarkersLiteral() async throws {
        let expectedTexts = [
            "*italic text*",
            "_italic text_",
            "**bold text**",
            "***bold and italic***",
            "<u>underlined text</u>",
            "<ins>underlined text</ins>",
            "~~struck text~~",
            "**_bold and italic_**",
            "**<u>bold and underlined</u>**",
            "~~*strikethrough and italic*~~"
        ]
        let source = expectedTexts.joined(separator: "\n\n")
        var reader = ArrayMarkdownLineReader(markdown: source)
        var writer = RecordingMarkdownWriter()

        let document = try await BlockInputDocument.readingMarkdown(from: &reader)
        try await document.writeMarkdown(to: &writer)

        XCTAssertEqual(document.blocks.map(\.text), expectedTexts)
        XCTAssertEqual(writer.markdown, source)
    }

    func testURLReadAndWriteUseStreamingMarkdown() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("document.md")
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(kind: .heading(level: 1), text: "File"),
            BlockInputBlock(kind: .paragraph, text: "Saved"),
            BlockInputBlock(kind: .rawMarkdown, text: "<section>\nRaw\n</section>")
        ])

        try await document.writeMarkdown(to: url)
        let fileContents = try String(contentsOf: url, encoding: .utf8)
        let readDocument = try await BlockInputDocument.readingMarkdown(from: url)
        let aliasReadDocument = try await BlockInputDocument.readMarkdown(from: url)
        var mutatingReadDocument = BlockInputDocument()
        try await mutatingReadDocument.readMarkdown(from: url)

        XCTAssertEqual(fileContents, document.markdown)
        XCTAssertBlockDocumentsEqualIgnoringIDs(readDocument, document)
        XCTAssertBlockDocumentsEqualIgnoringIDs(aliasReadDocument, document)
        XCTAssertBlockDocumentsEqualIgnoringIDs(mutatingReadDocument, document)
    }

    func testURLWriteHandlesLargeRawMarkdownBlock() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("large-raw.md")
        let rawMarkdown = String(repeating: "<div>Large raw block €</div>\n", count: 3_000)
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(kind: .rawMarkdown, text: rawMarkdown)
        ])

        try await document.writeMarkdown(to: url)
        let fileContents = try String(contentsOf: url, encoding: .utf8)

        XCTAssertEqual(fileContents, document.markdown)
    }

    func testURLReadMatchesExistingImportWithCRLFAndTrailingNewline() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("crlf.md")
        let source = "# Heading\nParagraph\n\n- Item\n"
        let crlfData = try XCTUnwrap(source.replacingOccurrences(of: "\n", with: "\r\n").data(using: .utf8))
        try crlfData.write(to: url)

        let streamed = try await BlockInputDocument.readingMarkdown(from: url)
        let expected = BlockInputDocument(markdown: source)

        XCTAssertBlockDocumentsEqualIgnoringIDs(streamed, expected)
        XCTAssertEqual(streamed.markdown, expected.markdown)
    }

    func testURLReadDecodesMultibyteScalarsAcrossChunkBoundary() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("multibyte.md")
        let prefix = String(repeating: "a", count: (64 * 1024) - 1)
        let source = "\(prefix)é\n# Heading"
        let data = try XCTUnwrap(source.data(using: .utf8))
        try data.write(to: url)

        let streamed = try await BlockInputDocument.readingMarkdown(from: url)
        let expected = BlockInputDocument(markdown: source)

        XCTAssertBlockDocumentsEqualIgnoringIDs(streamed, expected)
        XCTAssertEqual(streamed.markdown, expected.markdown)
    }

    func testURLReadRejectsInvalidUTF8() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("invalid.md")
        try Data([0xFF, 0x0A]).write(to: url)

        do {
            _ = try await BlockInputDocument.readingMarkdown(from: url)
            XCTFail("Expected invalid UTF-8 to throw")
        } catch let error as CocoaError {
            XCTAssertEqual(error.code, .fileReadCorruptFile)
        }
    }

    func testURLReadRejectsTrailingPartialUTF8Scalar() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("partial-scalar.md")
        try Data([0xE2, 0x82]).write(to: url)

        do {
            _ = try await BlockInputDocument.readingMarkdown(from: url)
            XCTFail("Expected trailing partial UTF-8 scalar to throw")
        } catch let error as CocoaError {
            XCTAssertEqual(error.code, .fileReadCorruptFile)
        }
    }

    func testFileWriterRejectsWritesAfterClose() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("closed.md")
        let writer = try BlockInputMarkdownFileWriter(url: url)

        try await writer.writeMarkdown("# Heading")
        try writer.close()
        try writer.close()

        do {
            try await writer.writeMarkdown("After close")
            XCTFail("Expected writes after close to throw")
        } catch let error as CocoaError {
            XCTAssertEqual(error.code, .fileWriteUnknown)
        }
    }

    func testFileWriterFailureCloseDiscardsBufferedData() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("discarded.md")
        let writer = try BlockInputMarkdownFileWriter(url: url)

        try await writer.writeMarkdown("Buffered only")
        try writer.closeAfterFailure()

        let fileContents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(fileContents, "")
    }

    func testLargeStreamingWriteDoesNotMaterializeFullDocumentString() async throws {
        let blockCount = 10_000
        let blocks = (0..<blockCount).map { index in
            BlockInputBlock(kind: .paragraph, text: "Block \(index)")
        }
        let document = BlockInputDocument(blocks: blocks)
        let expectedByteCount = blocks
            .map { $0.text.utf8.count }
            .reduce(0, +) + ((blockCount - 1) * 2)
        var writer = CountingMarkdownWriter()

        try await document.writeMarkdown(to: &writer)

        XCTAssertEqual(writer.byteCount, expectedByteCount)
        XCTAssertGreaterThan(writer.writeCount, blockCount)
        XCTAssertLessThan(writer.maxChunkByteCount, 32)
    }
}

private struct ArrayMarkdownLineReader: BlockInputMarkdownLineReader {
    private let lines: [String]
    private var index = 0

    init(markdown: String) {
        lines = BlockInputLineBreaks.lines(in: markdown)
    }

    mutating func readMarkdownLine() async throws -> String? {
        guard index < lines.count else {
            return nil
        }
        defer {
            index += 1
        }
        return lines[index]
    }
}

private struct ThrowingMarkdownLineReader: BlockInputMarkdownLineReader {
    let lines: [String]
    let throwAtIndex: Int
    private(set) var index = 0

    mutating func readMarkdownLine() async throws -> String? {
        if index == throwAtIndex {
            throw TestMarkdownLineReaderError.failure
        }
        guard index < lines.count else {
            return nil
        }
        defer {
            index += 1
        }
        return lines[index]
    }
}

private enum TestMarkdownLineReaderError: Error {
    case failure
}

private struct RecordingMarkdownWriter: BlockInputMarkdownWriter {
    private(set) var chunks: [String] = []

    var markdown: String {
        chunks.joined()
    }

    mutating func writeMarkdown(_ chunk: String) async throws {
        chunks.append(chunk)
    }
}

private struct CountingMarkdownWriter: BlockInputMarkdownWriter {
    private(set) var byteCount = 0
    private(set) var writeCount = 0
    private(set) var maxChunkByteCount = 0

    mutating func writeMarkdown(_ chunk: String) async throws {
        let chunkByteCount = chunk.utf8.count
        byteCount += chunkByteCount
        writeCount += 1
        maxChunkByteCount = max(maxChunkByteCount, chunkByteCount)
    }
}

private func XCTAssertBlockDocumentsEqualIgnoringIDs(
    _ first: BlockInputDocument,
    _ second: BlockInputDocument,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(first.blocks.map(\.kind), second.blocks.map(\.kind), file: file, line: line)
    XCTAssertEqual(first.blocks.map(\.text), second.blocks.map(\.text), file: file, line: line)
    XCTAssertEqual(first.blocks.map(\.indentationLevel), second.blocks.map(\.indentationLevel), file: file, line: line)
    XCTAssertEqual(first.blocks.map(\.lineIndentationLevels), second.blocks.map(\.lineIndentationLevels), file: file, line: line)
}
