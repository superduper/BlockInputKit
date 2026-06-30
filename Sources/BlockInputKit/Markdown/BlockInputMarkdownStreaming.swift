import Foundation

/// Sequential Markdown line source used by streaming document import.
///
/// Implementations return one logical Markdown line at a time without the
/// trailing line ending. Returning `nil` marks end of input.
public protocol BlockInputMarkdownLineReader {
    /// Returns the next logical line without a trailing line ending, or `nil` at end of input.
    mutating func readMarkdownLine() async throws -> String?
}

/// Sequential Markdown sink used by streaming document export.
///
/// Writers receive Markdown chunks in document order. `BlockInputDocument.writeMarkdown(to:)`
/// writes one block at a time and does not materialize a full-document Markdown string.
public protocol BlockInputMarkdownWriter {
    /// Writes the next Markdown chunk in document order.
    mutating func writeMarkdown(_ chunk: String) async throws
}

public extension BlockInputDocument {
    /// Replaces this document with Markdown read sequentially from `reader`.
    ///
    /// - Parameters:
    ///   - reader: Sequential Markdown line source.
    ///   - imageParsingMode: Import-time image syntax handling. The default
    ///     `.imageBlocks` parses supported images into standalone image blocks.
    mutating func readMarkdown<Reader: BlockInputMarkdownLineReader>(
        from reader: inout Reader,
        imageParsingMode: BlockInputMarkdownImageParsingMode = .imageBlocks
    ) async throws {
        self = try await Self.readingMarkdown(from: &reader, imageParsingMode: imageParsingMode)
    }

    /// Reads Markdown sequentially from `reader` into a new document.
    ///
    /// - Parameters:
    ///   - reader: Sequential Markdown line source.
    ///   - imageParsingMode: Import-time image syntax handling. The default
    ///     `.imageBlocks` parses supported images into standalone image blocks.
    static func readMarkdown<Reader: BlockInputMarkdownLineReader>(
        from reader: inout Reader,
        imageParsingMode: BlockInputMarkdownImageParsingMode = .imageBlocks
    ) async throws -> BlockInputDocument {
        try await readingMarkdown(from: &reader, imageParsingMode: imageParsingMode)
    }

    /// Reads Markdown sequentially from `reader` into a new document.
    ///
    /// - Parameters:
    ///   - reader: Sequential Markdown line source.
    ///   - imageParsingMode: Import-time image syntax handling. The default
    ///     `.imageBlocks` parses supported images into standalone image blocks.
    static func readingMarkdown<Reader: BlockInputMarkdownLineReader>(
        from reader: inout Reader,
        imageParsingMode: BlockInputMarkdownImageParsingMode = .imageBlocks
    ) async throws -> BlockInputDocument {
        try await BlockInputStreamingMarkdownImporter.document(from: &reader, imageParsingMode: imageParsingMode)
    }

    /// Replaces this document with UTF-8 Markdown read sequentially from `url`.
    ///
    /// - Parameters:
    ///   - url: File URL containing UTF-8 Markdown.
    ///   - imageParsingMode: Import-time image syntax handling. The default
    ///     `.imageBlocks` parses supported images into standalone image blocks.
    mutating func readMarkdown(
        from url: URL,
        imageParsingMode: BlockInputMarkdownImageParsingMode = .imageBlocks
    ) async throws {
        self = try await Self.readingMarkdown(from: url, imageParsingMode: imageParsingMode)
    }

    /// Reads UTF-8 Markdown sequentially from `url` into a new document.
    ///
    /// - Parameters:
    ///   - url: File URL containing UTF-8 Markdown.
    ///   - imageParsingMode: Import-time image syntax handling. The default
    ///     `.imageBlocks` parses supported images into standalone image blocks.
    static func readMarkdown(
        from url: URL,
        imageParsingMode: BlockInputMarkdownImageParsingMode = .imageBlocks
    ) async throws -> BlockInputDocument {
        try await readingMarkdown(from: url, imageParsingMode: imageParsingMode)
    }

    /// Reads UTF-8 Markdown sequentially from `url` into a new document.
    ///
    /// - Parameters:
    ///   - url: File URL containing UTF-8 Markdown.
    ///   - imageParsingMode: Import-time image syntax handling. The default
    ///     `.imageBlocks` parses supported images into standalone image blocks.
    static func readingMarkdown(
        from url: URL,
        imageParsingMode: BlockInputMarkdownImageParsingMode = .imageBlocks
    ) async throws -> BlockInputDocument {
        try await Task.detached {
            let reader = try BlockInputMarkdownFileLineReader(url: url)
            var mutableReader = reader
            do {
                let document = try await BlockInputDocument.readingMarkdown(
                    from: &mutableReader,
                    imageParsingMode: imageParsingMode
                )
                try reader.close()
                return document
            } catch {
                try? reader.close()
                throw error
            }
        }.value
    }

    /// Parses Markdown asynchronously from an already-resident string on a background task.
    ///
    /// - Parameters:
    ///   - markdown: Markdown source to parse.
    ///   - imageParsingMode: Import-time image syntax handling. The default
    ///     `.imageBlocks` parses supported images into standalone image blocks.
    static func parsingMarkdown(
        _ markdown: String,
        imageParsingMode: BlockInputMarkdownImageParsingMode = .imageBlocks
    ) async -> BlockInputDocument {
        await Task.detached {
            var reader = BlockInputMarkdownStringLineReader(markdown: markdown)
            do {
                return try await BlockInputDocument.readingMarkdown(from: &reader, imageParsingMode: imageParsingMode)
            } catch {
                return BlockInputDocument(markdown: markdown, imageParsingMode: imageParsingMode)
            }
        }.value
    }

    /// Writes this document as Markdown chunks to `writer` without creating one full-document string.
    func writeMarkdown<Writer: BlockInputMarkdownWriter>(
        to writer: inout Writer
    ) async throws {
        try await BlockInputStreamingMarkdownSerializer.write(self, to: &writer)
    }

    /// Writes this document as UTF-8 Markdown chunks to `url`.
    func writeMarkdown(to url: URL) async throws {
        let document = self
        try await Task.detached {
            let writer = try BlockInputMarkdownFileWriter(url: url)
            var mutableWriter = writer
            do {
                try await BlockInputStreamingMarkdownSerializer.write(document, to: &mutableWriter)
                try writer.close()
            } catch {
                try? writer.closeAfterFailure()
                throw error
            }
        }.value
    }

    /// Produces an asynchronous Markdown snapshot of this document on a background task.
    func markdownSnapshot() async -> String {
        let document = self
        return await Task.detached {
            var writer = BlockInputMarkdownStringWriter()
            do {
                try await BlockInputStreamingMarkdownSerializer.write(document, to: &writer)
                return writer.markdown
            } catch {
                return document.markdown
            }
        }.value
    }
}
