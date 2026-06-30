import Foundation

enum BlockInputStreamingMarkdownImporter {
    static func document<Reader: BlockInputMarkdownLineReader>(
        from reader: inout Reader,
        imageParsingMode: BlockInputMarkdownImageParsingMode = .imageBlocks
    ) async throws -> BlockInputDocument {
        var bufferedReader = BlockInputBufferedMarkdownLineReader(reader: reader)
        defer {
            reader = bufferedReader.reader
        }
        var blocks: [BlockInputBlock] = []
        while let parsedBlocks = try await parseNextBlocks(from: &bufferedReader, imageParsingMode: imageParsingMode) {
            blocks.append(contentsOf: parsedBlocks)
        }
        return BlockInputDocument(blocks: blocks)
    }

    private static func parseNextBlocks<Reader: BlockInputMarkdownLineReader>(
        from reader: inout BlockInputBufferedMarkdownLineReader<Reader>,
        imageParsingMode: BlockInputMarkdownImageParsingMode
    ) async throws -> [BlockInputBlock]? {
        while let line = try await reader.readLine() {
            let lineIndex = reader.consumedLineCount - 1
            guard !isBlank(line) else {
                continue
            }
            if let language = BlockInputMarkdownImporter.codeFenceLanguage(in: line) {
                return [try await parseCodeBlock(startingWith: line, language: language, from: &reader)]
            }
            if lineIndex == 0,
               line.trimmingCharacters(in: .whitespaces) == "---",
               let frontMatter = try await parseFrontMatter(startingWith: line, from: &reader) {
                return [frontMatter]
            }
            if let table = try await parseTable(startingWith: line, from: &reader) {
                return [table]
            }
            if let unsupported = try await parseUnsupportedBlock(
                startingWith: line,
                imageParsingMode: imageParsingMode,
                from: &reader
            ) {
                return [unsupported]
            }
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                return [BlockInputBlock(kind: .horizontalRule)]
            }
            if let heading = BlockInputMarkdownImporter.parseHeading(line) {
                return BlockInputMarkdownImporter.imageBlocks(bySplitting: heading, imageParsingMode: imageParsingMode)
            }
            if line.hasPrefix(">") {
                return BlockInputMarkdownImporter.imageBlocks(
                    bySplitting: try await parseQuote(startingWith: line, from: &reader),
                    imageParsingMode: imageParsingMode
                )
            }
            if let parsed = BlockInputMarkdownImporter.parseListLine(line) {
                return BlockInputMarkdownImporter.imageBlocks(bySplitting: parsed, imageParsingMode: imageParsingMode)
            }
            return BlockInputMarkdownImporter.imageBlocks(
                bySplitting: try await parseParagraph(startingWith: line, from: &reader),
                imageParsingMode: imageParsingMode
            )
        }
        return nil
    }

    private static func parseCodeBlock<Reader: BlockInputMarkdownLineReader>(
        startingWith line: String,
        language: String?,
        from reader: inout BlockInputBufferedMarkdownLineReader<Reader>
    ) async throws -> BlockInputBlock {
        var content: [String] = []
        while let nextLine = try await reader.readLine() {
            if nextLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                return BlockInputBlock(kind: .code(language: language), text: content.joined(separator: "\n"))
            }
            content.append(nextLine)
        }
        return BlockInputBlock(kind: .code(language: language), text: content.joined(separator: "\n"))
    }

    private static func parseFrontMatter<Reader: BlockInputMarkdownLineReader>(
        startingWith line: String,
        from reader: inout BlockInputBufferedMarkdownLineReader<Reader>
    ) async throws -> BlockInputBlock? {
        var rawLines = [line]
        var hasBodyContent = false
        while let nextLine = try await reader.readLine() {
            rawLines.append(nextLine)
            let trimmed = nextLine.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "..." {
                let bodyLines = rawLines.dropFirst().dropLast()
                // Streaming import mirrors snapshot import: keep editor-visible
                // YAML body lines and leave delimiter separator reconstruction to export.
                let body = bodyLines.joined(separator: "\n")
                return BlockInputBlock(kind: .frontMatter, text: body)
            }
            if !trimmed.isEmpty {
                hasBodyContent = true
            }
        }
        if hasBodyContent {
            return try await rawBlock(rawLines, from: &reader)
        }
        reader.pushFront(Array(rawLines.dropFirst()))
        return nil
    }

    private static func parseUnsupportedBlock<Reader: BlockInputMarkdownLineReader>(
        startingWith line: String,
        imageParsingMode: BlockInputMarkdownImageParsingMode,
        from reader: inout BlockInputBufferedMarkdownLineReader<Reader>
    ) async throws -> BlockInputBlock? {
        if let nextLine = try await reader.peekLine(),
           isSetextHeading(contentLine: line, underline: nextLine) {
            _ = try await reader.readLine()
            return try await rawBlock([line, nextLine], from: &reader)
        }
        if let nextLine = try await reader.peekLine(),
           line.contains("|"),
           BlockInputMarkdownImporter.isTableDelimiterLine(nextLine) {
            return try await parseRawRun(startingWith: line, from: &reader) {
                BlockInputMarkdownImporter.isTableContentLine($0)
            }
        }
        if BlockInputMarkdownImporter.isFootnoteDefinition(line) {
            return try await parseFootnoteDefinition(startingWith: line, from: &reader)
        }
        if BlockInputMarkdownImporter.isHTMLBlockOpening(line) {
            return try await parseHTMLBlock(startingWith: line, imageParsingMode: imageParsingMode, from: &reader)
        }
        return nil
    }

    private static func parseTable<Reader: BlockInputMarkdownLineReader>(
        startingWith line: String,
        from reader: inout BlockInputBufferedMarkdownLineReader<Reader>
    ) async throws -> BlockInputBlock? {
        guard !BlockInputMarkdownImporter.isFootnoteDefinition(line),
              !BlockInputMarkdownImporter.isHTMLBlockOpening(line),
              let nextLine = try await reader.peekLine(),
              line.contains("|"),
              BlockInputMarkdownImporter.isTableDelimiterLine(nextLine) else {
            return nil
        }
        var tableLines = [line, try await reader.readLine() ?? nextLine]
        while let bodyLine = try await reader.peekLine(),
              BlockInputTable.isContentLine(bodyLine) {
            tableLines.append(try await reader.readLine() ?? bodyLine)
        }
        guard let table = BlockInputTable(markdown: tableLines.joined(separator: "\n")) else {
            return try await rawBlock(tableLines, from: &reader)
        }
        return BlockInputBlock(kind: .table, text: table.markdown)
    }

    private static func parseRawRun<Reader: BlockInputMarkdownLineReader>(
        startingWith line: String,
        from reader: inout BlockInputBufferedMarkdownLineReader<Reader>,
        while shouldContinue: (String) -> Bool
    ) async throws -> BlockInputBlock {
        var rawLines = [line]
        while let nextLine = try await reader.peekLine(), shouldContinue(nextLine) {
            rawLines.append(try await reader.readLine() ?? nextLine)
        }
        return try await rawBlock(rawLines, from: &reader)
    }

    private static func parseFootnoteDefinition<Reader: BlockInputMarkdownLineReader>(
        startingWith line: String,
        from reader: inout BlockInputBufferedMarkdownLineReader<Reader>
    ) async throws -> BlockInputBlock {
        var rawLines = [line]
        while let nextLine = try await reader.peekLine() {
            if BlockInputMarkdownImporter.isFootnoteDefinition(nextLine) ||
                BlockInputMarkdownImporter.isIndentedFootnoteContinuationLine(nextLine) {
                rawLines.append(try await reader.readLine() ?? nextLine)
                continue
            }
            if isBlank(nextLine) {
                let blankLines = try await reader.readBlankLookahead()
                if let continuationLine = try await reader.peekLine(),
                   BlockInputMarkdownImporter.isIndentedFootnoteContinuationLine(continuationLine) {
                    rawLines.append(contentsOf: blankLines)
                    continue
                }
                reader.pushFront(blankLines)
            }
            break
        }
        return try await rawBlock(rawLines, from: &reader)
    }

    private static func parseHTMLBlock<Reader: BlockInputMarkdownLineReader>(
        startingWith line: String,
        imageParsingMode: BlockInputMarkdownImageParsingMode,
        from reader: inout BlockInputBufferedMarkdownLineReader<Reader>
    ) async throws -> BlockInputBlock {
        if BlockInputImageSyntaxParser.singleHTMLImage(in: line) != nil {
            if imageParsingMode == .imageBlocks,
               let imageBlock = BlockInputMarkdownImporter.imageBlock(fromHTMLLine: line) {
                return imageBlock
            }
            return BlockInputBlock(kind: .paragraph, text: line)
        }
        let opening = line.trimmingCharacters(in: .whitespaces)
        if opening.hasPrefix("<!--") {
            return try await parseDelimitedHTMLBlock(
                startingWith: line,
                opening: opening,
                closingDelimiter: "-->",
                from: &reader
            )
        }
        if opening.hasPrefix("<![CDATA[") {
            return try await parseDelimitedHTMLBlock(
                startingWith: line,
                opening: opening,
                closingDelimiter: "]]>",
                from: &reader
            )
        }
        if opening.hasPrefix("<?") {
            return try await parseDelimitedHTMLBlock(
                startingWith: line,
                opening: opening,
                closingDelimiter: "?>",
                from: &reader
            )
        }
        if opening.hasPrefix("<!") {
            return try await parseDelimitedHTMLBlock(
                startingWith: line,
                opening: opening,
                closingDelimiter: ">",
                from: &reader
            )
        }
        if opening.hasPrefix("</") {
            return try await rawBlock([line], from: &reader)
        }
        guard let tagName = BlockInputMarkdownImporter.htmlBlockOpeningTagName(in: opening) else {
            return try await rawBlock([line], from: &reader)
        }
        return try await parseHTMLTag(startingWith: line, opening: opening, tagName: tagName, from: &reader)
    }

    private static func parseDelimitedHTMLBlock<Reader: BlockInputMarkdownLineReader>(
        startingWith line: String,
        opening: String,
        closingDelimiter: String,
        from reader: inout BlockInputBufferedMarkdownLineReader<Reader>
    ) async throws -> BlockInputBlock {
        if opening.contains(closingDelimiter) {
            return try await rawBlock([line], from: &reader)
        }
        var rawLines = [line]
        while let nextLine = try await reader.readLine() {
            rawLines.append(nextLine)
            if nextLine.contains(closingDelimiter) {
                return try await rawBlock(rawLines, from: &reader)
            }
        }
        return try await rawBlock(rawLines, from: &reader)
    }

    private static func parseHTMLTag<Reader: BlockInputMarkdownLineReader>(
        startingWith line: String,
        opening: String,
        tagName: String,
        from reader: inout BlockInputBufferedMarkdownLineReader<Reader>
    ) async throws -> BlockInputBlock {
        if BlockInputMarkdownImporter.containsHTMLClosingTag(opening, tagName: tagName) ||
            BlockInputMarkdownImporter.isSelfContainedHTMLTag(opening, tagName: tagName) {
            return try await rawBlock([line], from: &reader)
        }
        if BlockInputMarkdownImporter.isDelimitedRawHTMLTagName(tagName) {
            return try await parseDelimitedHTMLTag(startingWith: line, tagName: tagName, from: &reader)
        }
        var rawLines = [line]
        while let nextLine = try await reader.peekLine() {
            if BlockInputMarkdownImporter.containsHTMLClosingTag(nextLine, tagName: tagName) {
                rawLines.append(try await reader.readLine() ?? nextLine)
                return try await rawBlock(rawLines, from: &reader)
            }
            if isBlank(nextLine) {
                return try await rawBlock(rawLines, from: &reader)
            }
            rawLines.append(try await reader.readLine() ?? nextLine)
        }
        return try await rawBlock(rawLines, from: &reader)
    }

    private static func parseDelimitedHTMLTag<Reader: BlockInputMarkdownLineReader>(
        startingWith line: String,
        tagName: String,
        from reader: inout BlockInputBufferedMarkdownLineReader<Reader>
    ) async throws -> BlockInputBlock {
        var rawLines = [line]
        while let nextLine = try await reader.readLine() {
            rawLines.append(nextLine)
            if BlockInputMarkdownImporter.containsHTMLClosingTag(nextLine, tagName: tagName) {
                return try await rawBlock(rawLines, from: &reader)
            }
        }
        return try await rawBlock(rawLines, from: &reader)
    }

    private static func parseQuote<Reader: BlockInputMarkdownLineReader>(
        startingWith line: String,
        from reader: inout BlockInputBufferedMarkdownLineReader<Reader>
    ) async throws -> BlockInputBlock {
        var content = [line.droppingMarkdownPrefix(">").droppingMarkdownPrefix(" ")]
        while let nextLine = try await reader.peekLine(), nextLine.hasPrefix(">") {
            let quoteLine = try await reader.readLine() ?? nextLine
            content.append(quoteLine.droppingMarkdownPrefix(">").droppingMarkdownPrefix(" "))
        }
        return BlockInputBlock(kind: .quote, text: content.joined(separator: "\n"))
    }

    private static func parseParagraph<Reader: BlockInputMarkdownLineReader>(
        startingWith line: String,
        from reader: inout BlockInputBufferedMarkdownLineReader<Reader>
    ) async throws -> BlockInputBlock {
        var content = [line]
        if let nextLine = try await reader.peekLine(),
           isSetextHeading(contentLine: line, underline: nextLine) {
            _ = try await reader.readLine()
            return try await rawBlock([line, nextLine], from: &reader)
        }
        while let nextLine = try await reader.peekLine() {
            if let underline = try await reader.peekLine(ahead: 1),
               isSetextHeading(contentLine: nextLine, underline: underline) {
                _ = try await reader.readLine()
                _ = try await reader.readLine()
                return try await rawBlock(content + [nextLine, underline], from: &reader)
            }
            if try await isParagraphBoundary(nextLine, from: &reader) {
                break
            }
            content.append(try await reader.readLine() ?? nextLine)
        }
        return BlockInputBlock(kind: .paragraph, text: content.joined(separator: "\n"))
    }

    private static func isParagraphBoundary<Reader: BlockInputMarkdownLineReader>(
        _ line: String,
        from reader: inout BlockInputBufferedMarkdownLineReader<Reader>
    ) async throws -> Bool {
        if isBlank(line) ||
            BlockInputMarkdownImporter.codeFenceLanguage(in: line) != nil ||
            line.trimmingCharacters(in: .whitespaces) == "---" ||
            BlockInputMarkdownImporter.parseHeading(line) != nil ||
            line.hasPrefix(">") ||
            BlockInputMarkdownImporter.parseListLine(line) != nil ||
            BlockInputMarkdownImporter.isFootnoteDefinition(line) ||
            BlockInputMarkdownImporter.isHTMLBlockOpening(line) {
            return true
        }
        guard let nextLine = try await reader.peekLine(ahead: 1) else {
            return false
        }
        return line.contains("|") && BlockInputMarkdownImporter.isTableDelimiterLine(nextLine)
    }

    private static func rawBlock<Reader: BlockInputMarkdownLineReader>(
        _ lines: [String],
        from reader: inout BlockInputBufferedMarkdownLineReader<Reader>
    ) async throws -> BlockInputBlock {
        var rawLines = lines
        while let nextLine = try await reader.peekLine(), isBlank(nextLine) {
            rawLines.append(try await reader.readLine() ?? nextLine)
        }
        return BlockInputBlock(kind: .rawMarkdown, text: rawLines.joined(separator: "\n"))
    }

    private static func isSetextHeading(contentLine line: String, underline: String) -> Bool {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        let contentLine = line.trimmingCharacters(in: .whitespaces)
        guard BlockInputMarkdownImporter.codeFenceLanguage(in: line) == nil,
              contentLine != "---",
              BlockInputMarkdownImporter.parseHeading(line) == nil,
              !line.hasPrefix(">"),
              BlockInputMarkdownImporter.parseListLine(line) == nil,
              !BlockInputMarkdownImporter.isFootnoteDefinition(line),
              !BlockInputMarkdownImporter.isHTMLBlockOpening(line) else {
            return false
        }
        let trimmedUnderline = underline.trimmingCharacters(in: .whitespaces)
        guard !trimmedUnderline.isEmpty else {
            return false
        }
        return trimmedUnderline.allSatisfy { $0 == "=" } || trimmedUnderline.allSatisfy { $0 == "-" }
    }

    private static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct BlockInputBufferedMarkdownLineReader<Reader: BlockInputMarkdownLineReader> {
    var reader: Reader
    var consumedLineCount = 0
    private var bufferedLines: [String] = []
    private var bufferedLineOffset = 0

    init(reader: Reader) {
        self.reader = reader
    }

    mutating func readLine() async throws -> String? {
        if bufferedLineOffset < bufferedLines.count {
            let line = bufferedLines[bufferedLineOffset]
            bufferedLineOffset += 1
            compactBufferIfNeeded()
            consumedLineCount += 1
            return line
        }
        guard let line = try await reader.readMarkdownLine() else {
            return nil
        }
        consumedLineCount += 1
        return line
    }

    mutating func peekLine(ahead: Int = 0) async throws -> String? {
        let targetIndex = bufferedLineOffset + ahead
        while bufferedLines.count <= targetIndex {
            guard let line = try await reader.readMarkdownLine() else {
                return nil
            }
            bufferedLines.append(line)
        }
        return bufferedLines[targetIndex]
    }

    mutating func pushFront(_ lines: [String]) {
        guard !lines.isEmpty else {
            return
        }
        consumedLineCount = max(0, consumedLineCount - lines.count)
        let unreadLines = bufferedLineOffset < bufferedLines.count ? Array(bufferedLines[bufferedLineOffset...]) : []
        bufferedLines = lines + unreadLines
        bufferedLineOffset = 0
    }

    mutating func readBlankLookahead() async throws -> [String] {
        var blankLines: [String] = []
        while let nextLine = try await peekLine(),
              nextLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blankLines.append(try await readLine() ?? nextLine)
        }
        return blankLines
    }

    private mutating func compactBufferIfNeeded() {
        guard bufferedLineOffset > 64,
              bufferedLineOffset * 2 >= bufferedLines.count else {
            return
        }
        bufferedLines.removeFirst(bufferedLineOffset)
        bufferedLineOffset = 0
    }
}

private extension String {
    func droppingMarkdownPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
