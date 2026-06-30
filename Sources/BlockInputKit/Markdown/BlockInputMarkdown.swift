import Foundation

enum BlockInputMarkdownImporter {
    static func document(
        from markdown: String,
        imageParsingMode: BlockInputMarkdownImageParsingMode = .imageBlocks
    ) -> BlockInputDocument {
        let lines = BlockInputLineBreaks.lines(in: markdown)
        var blocks: [BlockInputBlock] = []
        var index = 0

        while index < lines.count {
            guard let parsed = parseNextBlock(lines: lines, startIndex: index, imageParsingMode: imageParsingMode) else {
                index += 1
                continue
            }
            blocks.append(contentsOf: parsed.blocks)
            index = parsed.nextIndex
        }

        return BlockInputDocument(blocks: blocks)
    }

    private static func parseNextBlock(
        lines: [String],
        startIndex: Int,
        imageParsingMode: BlockInputMarkdownImageParsingMode
    ) -> (blocks: [BlockInputBlock], nextIndex: Int)? {
        let line = lines[startIndex]
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        if let language = codeFenceLanguage(in: line) {
            return parseCodeBlock(lines: lines, startIndex: startIndex, language: language)
        }
        if isFrontMatterOpening(line, index: startIndex),
           let parsed = parseFrontMatter(lines: lines, startIndex: startIndex) {
            return parsed
        }
        if let parsed = parseTable(lines: lines, startIndex: startIndex) {
            return parsed
        }
        if let parsed = parseUnsupportedBlock(lines: lines, startIndex: startIndex, imageParsingMode: imageParsingMode) {
            return parsed
        }
        if line.trimmingCharacters(in: .whitespaces) == "---" {
            return ([BlockInputBlock(kind: .horizontalRule)], startIndex + 1)
        }
        if let heading = parseHeading(line) {
            return (imageBlocks(bySplitting: heading, imageParsingMode: imageParsingMode), startIndex + 1)
        }
        if line.hasPrefix(">") {
            return parseQuote(lines: lines, startIndex: startIndex, imageParsingMode: imageParsingMode)
        }
        if let parsed = parseListLine(lines[startIndex]) {
            return (imageBlocks(bySplitting: parsed, imageParsingMode: imageParsingMode), startIndex + 1)
        }
        return parseParagraph(lines: lines, startIndex: startIndex, imageParsingMode: imageParsingMode)
    }

    static func codeFenceLanguage(in line: String) -> String?? {
        guard let opening = BlockInputCodeParsing.codeFenceOpening(in: line) else {
            return nil
        }
        return .some(opening.language)
    }

    private static func parseCodeBlock(
        lines: [String],
        startIndex: Int,
        language: String?
    ) -> (blocks: [BlockInputBlock], nextIndex: Int) {
        var content: [String] = []
        var index = startIndex + 1
        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                return ([BlockInputBlock(kind: .code(language: language), text: content.joined(separator: "\n"))], index + 1)
            }
            content.append(lines[index])
            index += 1
        }
        return ([BlockInputBlock(kind: .code(language: language), text: content.joined(separator: "\n"))], index)
    }

    private static func parseQuote(
        lines: [String],
        startIndex: Int,
        imageParsingMode: BlockInputMarkdownImageParsingMode
    ) -> (blocks: [BlockInputBlock], nextIndex: Int) {
        var content: [String] = []
        var index = startIndex
        while index < lines.count, lines[index].hasPrefix(">") {
            content.append(lines[index].droppingPrefix(">").droppingPrefix(" "))
            index += 1
        }
        return (
            imageBlocks(
                bySplitting: BlockInputBlock(kind: .quote, text: content.joined(separator: "\n")),
                imageParsingMode: imageParsingMode
            ),
            index
        )
    }

    private static func parseUnsupportedBlock(
        lines: [String],
        startIndex: Int,
        imageParsingMode: BlockInputMarkdownImageParsingMode
    ) -> (blocks: [BlockInputBlock], nextIndex: Int)? {
        if isSetextHeading(lines: lines, startIndex: startIndex) {
            return rawBlock(lines: lines, range: startIndex..<(startIndex + 2))
        }
        if isTable(lines: lines, startIndex: startIndex) {
            return parseRawRun(lines: lines, startIndex: startIndex, while: isTableContentLine)
        }
        if isFootnoteDefinition(lines[startIndex]) {
            return parseFootnoteDefinition(lines: lines, startIndex: startIndex)
        }
        if isHTMLBlockOpening(lines[startIndex]) {
            return parseHTMLBlock(lines: lines, startIndex: startIndex, imageParsingMode: imageParsingMode)
        }
        return nil
    }

    private static func parseTable(
        lines: [String],
        startIndex: Int
    ) -> (blocks: [BlockInputBlock], nextIndex: Int)? {
        let line = lines[startIndex]
        guard !isFootnoteDefinition(line),
              !isHTMLBlockOpening(line),
              let parsed = BlockInputTable.parse(lines: lines, startIndex: startIndex) else {
            return nil
        }
        return ([BlockInputBlock(kind: .table, text: parsed.table.markdown)], parsed.nextIndex)
    }

    private static func parseFrontMatter(
        lines: [String],
        startIndex: Int
    ) -> (blocks: [BlockInputBlock], nextIndex: Int)? {
        var hasBodyContent = false
        var index = startIndex + 1
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "..." {
                let bodyLines = lines[(startIndex + 1)..<index]
                // Keep only editor-visible YAML body lines. Export recreates the
                // required line break before the closing delimiter so ordinary file
                // loads do not display a synthetic blank line in the editor.
                let body = bodyLines.joined(separator: "\n")
                return ([BlockInputBlock(kind: .frontMatter, text: body)], index + 1)
            }
            if !trimmed.isEmpty {
                hasBodyContent = true
            }
            index += 1
        }
        if hasBodyContent {
            return rawBlock(lines: lines, range: startIndex..<lines.count)
        }
        return nil
    }

    private static func parseFootnoteDefinition(
        lines: [String],
        startIndex: Int
    ) -> (blocks: [BlockInputBlock], nextIndex: Int) {
        var index = startIndex
        while index < lines.count {
            let line = lines[index]
            if isFootnoteDefinition(line) || isIndentedFootnoteContinuationLine(line) {
                index += 1
                continue
            }
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let continuationIndex = nextIndentedFootnoteContinuationIndex(lines: lines, startIndex: index) {
                index = continuationIndex
                continue
            }
            break
        }
        return rawBlock(lines: lines, range: startIndex..<index)
    }

    private static func parseRawRun(
        lines: [String],
        startIndex: Int,
        while shouldContinue: (String) -> Bool
    ) -> (blocks: [BlockInputBlock], nextIndex: Int) {
        var index = startIndex
        while index < lines.count, shouldContinue(lines[index]) {
            index += 1
        }
        return rawBlock(lines: lines, range: startIndex..<index)
    }

    static func rawBlock(
        lines: [String],
        range: Range<Int>
    ) -> (blocks: [BlockInputBlock], nextIndex: Int) {
        var upperBound = range.upperBound
        while upperBound < lines.count, lines[upperBound].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            upperBound += 1
        }
        let source = lines[range.lowerBound..<upperBound].joined(separator: "\n")
        return ([BlockInputBlock(kind: .rawMarkdown, text: source)], upperBound)
    }

    private static func parseParagraph(
        lines: [String],
        startIndex: Int,
        imageParsingMode: BlockInputMarkdownImageParsingMode
    ) -> (blocks: [BlockInputBlock], nextIndex: Int) {
        var content: [String] = []
        var index = startIndex
        while index < lines.count {
            let line = lines[index]
            if isSetextHeading(lines: lines, startIndex: index) {
                return rawBlock(lines: lines, range: startIndex..<(index + 2))
            }
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                codeFenceLanguage(in: line) != nil ||
                parseUnsupportedBlock(lines: lines, startIndex: index, imageParsingMode: imageParsingMode) != nil ||
                line.trimmingCharacters(in: .whitespaces) == "---" ||
                parseHeading(line) != nil ||
                line.hasPrefix(">") ||
                parseListLine(line) != nil {
                break
            }
            content.append(line)
            index += 1
        }
        return (
            imageBlocks(
                bySplitting: BlockInputBlock(kind: .paragraph, text: content.joined(separator: "\n")),
                imageParsingMode: imageParsingMode
            ),
            index
        )
    }

    static func parseHeading(_ line: String) -> BlockInputBlock? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let level = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(level),
              trimmed.dropFirst(level).first == " " else {
            return nil
        }
        return BlockInputBlock(kind: .heading(level: level), text: String(trimmed.dropFirst(level + 1)))
    }

    static func parseListLine(_ line: String) -> BlockInputBlock? {
        let leadingSpaceCount = line.prefix { $0 == " " }.count
        let indentationLevel = leadingSpaceCount / 2
        let trimmed = String(line.dropFirst(leadingSpaceCount))

        if trimmed == "- [ ]" || trimmed.hasPrefix("- [ ] ") {
            return BlockInputBlock(
                kind: .checklistItem(isChecked: false),
                text: String(trimmed.dropFirst(min(6, trimmed.count))),
                indentationLevel: indentationLevel
            )
        }
        if trimmed == "- [x]" || trimmed == "- [X]" || trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
            return BlockInputBlock(
                kind: .checklistItem(isChecked: true),
                text: String(trimmed.dropFirst(min(6, trimmed.count))),
                indentationLevel: indentationLevel
            )
        }
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return BlockInputBlock(
                kind: .bulletedListItem,
                text: String(trimmed.dropFirst(2)),
                indentationLevel: indentationLevel
            )
        }
        if let numbered = parseNumberedList(trimmed) {
            return BlockInputBlock(
                kind: .numberedListItem(start: numbered.start),
                text: numbered.text,
                indentationLevel: indentationLevel
            )
        }
        return nil
    }

    private static func parseNumberedList(_ line: String) -> (start: Int, text: String)? {
        var digits = ""
        var cursor = line.startIndex
        while cursor < line.endIndex, line[cursor].isNumber {
            digits.append(line[cursor])
            cursor = line.index(after: cursor)
        }
        guard !digits.isEmpty,
              cursor < line.endIndex,
              line[cursor] == "." else {
            return nil
        }
        cursor = line.index(after: cursor)
        guard cursor < line.endIndex, line[cursor] == " " else {
            return nil
        }
        let textStart = line.index(after: cursor)
        return (Int(digits) ?? 1, String(line[textStart...]))
    }

    private static func isFrontMatterOpening(_ line: String, index: Int) -> Bool {
        index == 0 && line.trimmingCharacters(in: .whitespaces) == "---"
    }

    private static func isSetextHeading(lines: [String], startIndex: Int) -> Bool {
        guard lines.indices.contains(startIndex + 1),
              !lines[startIndex].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        let line = lines[startIndex]
        let contentLine = line.trimmingCharacters(in: .whitespaces)
        guard codeFenceLanguage(in: line) == nil,
              contentLine != "---",
              parseHeading(line) == nil,
              !line.hasPrefix(">"),
              parseListLine(line) == nil,
              !isFootnoteDefinition(line),
              !isHTMLBlockOpening(line) else {
            return false
        }
        let underline = lines[startIndex + 1].trimmingCharacters(in: .whitespaces)
        guard !underline.isEmpty else {
            return false
        }
        return underline.allSatisfy { $0 == "=" } || underline.allSatisfy { $0 == "-" }
    }

    private static func isTable(lines: [String], startIndex: Int) -> Bool {
        guard lines.indices.contains(startIndex + 1),
              lines[startIndex].contains("|") else {
            return false
        }
        return isTableDelimiterLine(lines[startIndex + 1])
    }

    static func isTableDelimiterLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-"),
              trimmed.contains("|") else {
            return false
        }
        return trimmed.allSatisfy { character in
            character == "|" || character == "-" || character == ":" || character.isWhitespace
        }
    }

    static func isTableContentLine(_ line: String) -> Bool {
        !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && line.contains("|")
    }

    static func isFootnoteDefinition(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("[^") && trimmed.contains("]:")
    }

    static func isIndentedFootnoteContinuationLine(_ line: String) -> Bool {
        !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (line.hasPrefix("    ") || line.hasPrefix("\t"))
    }

    private static func nextIndentedFootnoteContinuationIndex(lines: [String], startIndex: Int) -> Int? {
        var index = startIndex + 1
        while index < lines.count {
            let line = lines[index]
            if isIndentedFootnoteContinuationLine(line) {
                return index
            }
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return nil
            }
            index += 1
        }
        return nil
    }

}

enum BlockInputMarkdownSerializer {
    static func markdown(from document: BlockInputDocument) -> String {
        document.blocks.enumerated().reduce(into: "") { output, element in
            let (index, block) = element
            if index > 0 {
                let previousBlock = document.blocks[index - 1]
                output += separator(between: previousBlock, and: block)
            }
            output += markdownBlock(block)
        }
    }

    private static func separator(between previousBlock: BlockInputBlock, and block: BlockInputBlock) -> String {
        if previousBlock.kind == .rawMarkdown || block.kind == .rawMarkdown {
            return "\n"
        }
        return previousBlock.kind.isMarkdownListItem && block.kind.isMarkdownListItem ? "\n" : "\n\n"
    }

    private static func markdownBlock(_ block: BlockInputBlock) -> String {
        literalMarkdownBlock(block) ?? structuredMarkdownBlock(block)
    }

    private static func literalMarkdownBlock(_ block: BlockInputBlock) -> String? {
        switch block.kind {
        case .paragraph:
            return block.text
        case .heading(let level):
            return "\(String(repeating: "#", count: min(max(level, 1), 6))) \(block.text)"
        case .code(let language):
            let fence = "```" + (language ?? "")
            return "\(fence)\n\(block.text)\n```"
        case .horizontalRule:
            return "---"
        case .frontMatter:
            return frontMatterMarkdown(block.text)
        case .table, .rawMarkdown:
            return sourceMarkdown(block)
        case .image(let image):
            return BlockInputMarkdownImporter.markdown(for: image)
        case .quote, .bulletedListItem, .numberedListItem, .checklistItem:
            return nil
        }
    }

    private static func structuredMarkdownBlock(_ block: BlockInputBlock) -> String {
        switch block.kind {
        case .quote:
            return BlockInputLineBreaks.lines(in: block.text).map { "> \($0)" }.joined(separator: "\n")
        case .bulletedListItem:
            return BlockInputLineBreaks.lines(in: block.text).enumerated().map { offset, line in
                "\(indent(for: block, lineOffset: offset))- \(line)"
            }.joined(separator: "\n")
        case .numberedListItem(let start):
            return numberedListMarkdown(block, start: start)
        case .checklistItem(let isChecked):
            return BlockInputLineBreaks.lines(in: block.text).enumerated().map { offset, line in
                "\(indent(for: block, lineOffset: offset))- [\(isChecked ? "x" : " ")] \(line)"
            }.joined(separator: "\n")
        case .paragraph, .heading, .code, .horizontalRule, .frontMatter, .table, .image, .rawMarkdown:
            preconditionFailure("Expected structured Markdown block")
        }
    }

    private static func sourceMarkdown(_ block: BlockInputBlock) -> String {
        if block.kind == .table {
            return BlockInputTable(markdown: block.text)?.markdown ?? block.text
        }
        return block.text
    }

    private static func indent(for block: BlockInputBlock, lineOffset: Int) -> String {
        String(repeating: "  ", count: block.indentationLevel(forLine: lineOffset))
    }

    private static func frontMatterMarkdown(_ body: String) -> String {
        guard !body.isEmpty else {
            return "---\n---"
        }
        // The block owns the raw YAML body; only reconstruct delimiters and
        // the delimiter separator line break that is not shown as editable body text.
        return "---\n\(body)\n---"
    }

    private static func numberedListMarkdown(_ block: BlockInputBlock, start: Int) -> String {
        var countersByLevel: [Int: Int] = [:]
        let baselineIndentationLevel = block.indentationLevel(forLine: 0)
        return BlockInputLineBreaks.lines(in: block.text).enumerated().map { offset, line in
            let indentationLevel = block.indentationLevel(forLine: offset)
            countersByLevel = countersByLevel.filter { $0.key <= indentationLevel }
            let counter = countersByLevel[indentationLevel, default: 0]
            countersByLevel[indentationLevel] = counter + 1
            let markerStart = indentationLevel == baselineIndentationLevel ? start + counter : counter + 1
            return "\(indent(for: block, lineOffset: offset))\(markerStart). \(line)"
        }.joined(separator: "\n")
    }
}

private extension BlockInputBlockKind {
    var isMarkdownListItem: Bool {
        switch self {
        case .bulletedListItem, .numberedListItem, .checklistItem:
            return true
        case .paragraph, .heading, .code, .horizontalRule, .frontMatter, .quote, .table, .image, .rawMarkdown:
            return false
        }
    }
}

private extension String {
    func droppingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
