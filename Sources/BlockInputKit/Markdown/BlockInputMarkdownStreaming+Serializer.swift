import Foundation

enum BlockInputStreamingMarkdownSerializer {
    static func write<Writer: BlockInputMarkdownWriter>(
        _ document: BlockInputDocument,
        to writer: inout Writer
    ) async throws {
        var previousBlock: BlockInputBlock?
        for block in document.blocks {
            if let previousBlock {
                try await writer.writeMarkdown(separator(between: previousBlock, and: block))
            }
            try await writeBlock(block, to: &writer)
            previousBlock = block
        }
    }

    private static func separator(between previousBlock: BlockInputBlock, and block: BlockInputBlock) -> String {
        if previousBlock.kind == .rawMarkdown || block.kind == .rawMarkdown {
            return "\n"
        }
        return previousBlock.kind.isStreamingMarkdownListItem && block.kind.isStreamingMarkdownListItem ? "\n" : "\n\n"
    }

    private static func writeBlock<Writer: BlockInputMarkdownWriter>(
        _ block: BlockInputBlock,
        to writer: inout Writer
    ) async throws {
        if try await writeLiteralBlock(block, to: &writer) {
            return
        }
        switch block.kind {
        case .quote:
            try await writeLines(BlockInputLineBreaks.lines(in: block.text), to: &writer) { _, line in
                "> \(line)"
            }
        case .bulletedListItem:
            try await writeLines(BlockInputLineBreaks.lines(in: block.text), to: &writer) { offset, line in
                "\(indent(for: block, lineOffset: offset))- \(line)"
            }
        case .numberedListItem(let start):
            try await writeNumberedList(block, start: start, to: &writer)
        case .checklistItem(let isChecked):
            try await writeLines(BlockInputLineBreaks.lines(in: block.text), to: &writer) { offset, line in
                "\(indent(for: block, lineOffset: offset))- [\(isChecked ? "x" : " ")] \(line)"
            }
        case .paragraph, .heading, .code, .horizontalRule, .frontMatter, .table, .image, .rawMarkdown:
            break
        }
    }

    private static func writeLiteralBlock<Writer: BlockInputMarkdownWriter>(
        _ block: BlockInputBlock,
        to writer: inout Writer
    ) async throws -> Bool {
        switch block.kind {
        case .paragraph:
            try await writer.writeMarkdown(block.text)
        case .heading(let level):
            let clampedLevel = min(max(level, 1), 6)
            try await writer.writeMarkdown("\(String(repeating: "#", count: clampedLevel)) \(block.text)")
        case .code(let language):
            try await writer.writeMarkdown("```\(language ?? "")\n")
            try await writer.writeMarkdown(block.text)
            try await writer.writeMarkdown("\n```")
        case .horizontalRule:
            try await writer.writeMarkdown("---")
        case .frontMatter:
            try await writer.writeMarkdown(frontMatterMarkdown(block.text))
        case .table, .rawMarkdown:
            try await writer.writeMarkdown(sourceMarkdown(block))
        case .image(let image):
            try await writer.writeMarkdown(BlockInputMarkdownImporter.markdown(for: image))
        case .quote, .bulletedListItem, .numberedListItem, .checklistItem:
            return false
        }
        return true
    }

    private static func sourceMarkdown(_ block: BlockInputBlock) -> String {
        if block.kind == .table {
            return BlockInputTable(markdown: block.text)?.markdown ?? block.text
        }
        return block.text
    }

    private static func writeLines<Writer: BlockInputMarkdownWriter>(
        _ lines: [String],
        to writer: inout Writer,
        transform: (Int, String) -> String
    ) async throws {
        for (offset, line) in lines.enumerated() {
            if offset > 0 {
                try await writer.writeMarkdown("\n")
            }
            try await writer.writeMarkdown(transform(offset, line))
        }
    }

    private static func frontMatterMarkdown(_ body: String) -> String {
        guard !body.isEmpty else {
            return "---\n---"
        }
        // Keep the closing delimiter separator out of editable body text, then
        // recreate it consistently for streaming snapshots and file writes.
        return "---\n\(body)\n---"
    }

    private static func writeNumberedList<Writer: BlockInputMarkdownWriter>(
        _ block: BlockInputBlock,
        start: Int,
        to writer: inout Writer
    ) async throws {
        var countersByLevel: [Int: Int] = [:]
        let baselineIndentationLevel = block.indentationLevel(forLine: 0)
        for (offset, line) in BlockInputLineBreaks.lines(in: block.text).enumerated() {
            if offset > 0 {
                try await writer.writeMarkdown("\n")
            }
            let indentationLevel = block.indentationLevel(forLine: offset)
            countersByLevel = countersByLevel.filter { $0.key <= indentationLevel }
            let counter = countersByLevel[indentationLevel, default: 0]
            countersByLevel[indentationLevel] = counter + 1
            let markerStart = indentationLevel == baselineIndentationLevel ? start + counter : counter + 1
            try await writer.writeMarkdown("\(indent(for: block, lineOffset: offset))\(markerStart). \(line)")
        }
    }

    private static func indent(for block: BlockInputBlock, lineOffset: Int) -> String {
        String(repeating: "  ", count: block.indentationLevel(forLine: lineOffset))
    }
}

private extension BlockInputBlockKind {
    var isStreamingMarkdownListItem: Bool {
        switch self {
        case .bulletedListItem, .numberedListItem, .checklistItem:
            return true
        case .paragraph, .heading, .code, .horizontalRule, .frontMatter, .quote, .table, .image, .rawMarkdown:
            return false
        }
    }
}
