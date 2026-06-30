import Foundation

extension BlockInputMarkdownImporter {
    static func parseHTMLBlock(
        lines: [String],
        startIndex: Int,
        imageParsingMode: BlockInputMarkdownImageParsingMode = .imageBlocks
    ) -> (blocks: [BlockInputBlock], nextIndex: Int) {
        let opening = lines[startIndex].trimmingCharacters(in: .whitespaces)
        if BlockInputImageSyntaxParser.singleHTMLImage(in: lines[startIndex]) != nil {
            if imageParsingMode == .imageBlocks,
               let imageBlock = imageBlock(fromHTMLLine: lines[startIndex]) {
                return ([imageBlock], startIndex + 1)
            }
            return ([BlockInputBlock(kind: .paragraph, text: lines[startIndex])], startIndex + 1)
        }
        if let parsed = parseHTMLComment(lines: lines, startIndex: startIndex, opening: opening) {
            return parsed
        }
        if let parsed = parseHTMLCDATA(lines: lines, startIndex: startIndex, opening: opening) {
            return parsed
        }
        if let parsed = parseHTMLDeclarationOrProcessingInstruction(lines: lines, startIndex: startIndex, opening: opening) {
            return parsed
        }
        if opening.hasPrefix("</") {
            return rawBlock(lines: lines, range: startIndex..<(startIndex + 1))
        }
        guard let tagName = htmlBlockOpeningTagName(in: opening) else {
            return rawBlock(lines: lines, range: startIndex..<(startIndex + 1))
        }
        return parseHTMLTag(lines: lines, startIndex: startIndex, opening: opening, tagName: tagName)
    }

    static func isHTMLBlockOpening(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("<!--") ||
            trimmed.hasPrefix("<!") ||
            trimmed.hasPrefix("<?") ||
            trimmed.hasPrefix("</") ||
            htmlBlockOpeningTagName(in: trimmed) != nil
    }

    private static func parseHTMLComment(
        lines: [String],
        startIndex: Int,
        opening: String
    ) -> (blocks: [BlockInputBlock], nextIndex: Int)? {
        guard opening.hasPrefix("<!--") else {
            return nil
        }
        if opening.contains("-->") {
            return rawBlock(lines: lines, range: startIndex..<(startIndex + 1))
        }
        return parseDelimitedHTMLBlock(lines: lines, startIndex: startIndex, closingDelimiter: "-->")
    }

    private static func parseHTMLCDATA(
        lines: [String],
        startIndex: Int,
        opening: String
    ) -> (blocks: [BlockInputBlock], nextIndex: Int)? {
        guard opening.hasPrefix("<![CDATA[") else {
            return nil
        }
        if opening.contains("]]>") {
            return rawBlock(lines: lines, range: startIndex..<(startIndex + 1))
        }
        return parseDelimitedHTMLBlock(lines: lines, startIndex: startIndex, closingDelimiter: "]]>")
    }

    private static func parseDelimitedHTMLBlock(
        lines: [String],
        startIndex: Int,
        closingDelimiter: String
    ) -> (blocks: [BlockInputBlock], nextIndex: Int) {
        var index = startIndex + 1
        while index < lines.count {
            if lines[index].contains(closingDelimiter) {
                return rawBlock(lines: lines, range: startIndex..<(index + 1))
            }
            index += 1
        }
        return rawBlock(lines: lines, range: startIndex..<index)
    }

    private static func parseHTMLDeclarationOrProcessingInstruction(
        lines: [String],
        startIndex: Int,
        opening: String
    ) -> (blocks: [BlockInputBlock], nextIndex: Int)? {
        if opening.hasPrefix("<?") {
            if opening.contains("?>") {
                return rawBlock(lines: lines, range: startIndex..<(startIndex + 1))
            }
            return parseDelimitedHTMLBlock(lines: lines, startIndex: startIndex, closingDelimiter: "?>")
        }
        if opening.hasPrefix("<!") {
            if opening.contains(">") {
                return rawBlock(lines: lines, range: startIndex..<(startIndex + 1))
            }
            return parseDelimitedHTMLBlock(lines: lines, startIndex: startIndex, closingDelimiter: ">")
        }
        return nil
    }

    private static func parseHTMLTag(
        lines: [String],
        startIndex: Int,
        opening: String,
        tagName: String
    ) -> (blocks: [BlockInputBlock], nextIndex: Int) {
        if containsHTMLClosingTag(opening, tagName: tagName) || isSelfContainedHTMLTag(opening, tagName: tagName) {
            return rawBlock(lines: lines, range: startIndex..<(startIndex + 1))
        }
        if isDelimitedRawHTMLTagName(tagName) {
            return parseDelimitedHTMLTag(lines: lines, startIndex: startIndex, tagName: tagName)
        }
        var index = startIndex + 1
        while index < lines.count {
            if containsHTMLClosingTag(lines[index], tagName: tagName) {
                return rawBlock(lines: lines, range: startIndex..<(index + 1))
            }
            if lines[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return rawBlock(lines: lines, range: startIndex..<index)
            }
            index += 1
        }
        return rawBlock(lines: lines, range: startIndex..<index)
    }

    private static func parseDelimitedHTMLTag(
        lines: [String],
        startIndex: Int,
        tagName: String
    ) -> (blocks: [BlockInputBlock], nextIndex: Int) {
        var index = startIndex + 1
        while index < lines.count {
            if containsHTMLClosingTag(lines[index], tagName: tagName) {
                return rawBlock(lines: lines, range: startIndex..<(index + 1))
            }
            index += 1
        }
        return rawBlock(lines: lines, range: startIndex..<index)
    }

    static func isDelimitedRawHTMLTagName(_ tagName: String) -> Bool {
        ["pre", "script", "style", "textarea"].contains(tagName.lowercased())
    }

    static func isSelfContainedHTMLTag(_ opening: String, tagName: String) -> Bool {
        if opening.hasSuffix("/>") {
            return true
        }
        return [
            "area", "base", "br", "col", "embed", "hr", "img", "input", "link",
            "meta", "param", "source", "track", "wbr"
        ].contains(tagName.lowercased())
    }

    static func htmlBlockOpeningTagName(in line: String) -> String? {
        guard let tagName = htmlOpeningTagName(in: line) else {
            return nil
        }
        if tagName.contains("-") || isBlockHTMLTagName(tagName) || isSelfContainedHTMLTag(line, tagName: tagName) {
            return tagName
        }
        return nil
    }

    static func isBlockHTMLTagName(_ tagName: String) -> Bool {
        [
            "address", "article", "aside", "base", "basefont", "blockquote", "body",
            "caption", "center", "col", "colgroup", "dd", "details", "dialog",
            "dir", "div", "dl", "dt", "fieldset", "figcaption", "figure",
            "footer", "form", "frame", "frameset", "h1", "h2", "h3", "h4",
            "h5", "h6", "head", "header", "hr", "html", "iframe", "legend",
            "li", "link", "main", "menu", "menuitem", "nav", "noframes",
            "ol", "optgroup", "option", "p", "param", "pre", "script",
            "search", "section", "style", "summary", "table", "tbody", "td",
            "textarea", "tfoot", "th", "thead", "title", "tr", "track", "ul"
        ].contains(tagName.lowercased())
    }

    static func containsHTMLClosingTag(_ line: String, tagName: String) -> Bool {
        let lowercasedLine = line.lowercased()
        let needle = "</\(tagName.lowercased())"
        var searchStart = lowercasedLine.startIndex
        while let range = lowercasedLine[searchStart...].range(of: needle) {
            let boundary = range.upperBound
            if boundary == lowercasedLine.endIndex ||
                lowercasedLine[boundary] == ">" ||
                lowercasedLine[boundary].isWhitespace {
                return true
            }
            searchStart = boundary
        }
        return false
    }

    static func htmlOpeningTagName(in line: String) -> String? {
        var cursor = line.startIndex
        guard cursor < line.endIndex, line[cursor] == "<" else {
            return nil
        }
        cursor = line.index(after: cursor)
        guard cursor < line.endIndex, line[cursor].isLetter else {
            return nil
        }
        var tagName = ""
        while cursor < line.endIndex, line[cursor].isLetter || line[cursor].isNumber || line[cursor] == "-" {
            tagName.append(line[cursor].lowercased())
            cursor = line.index(after: cursor)
        }
        if cursor < line.endIndex,
           line[cursor] != ">",
           line[cursor] != "/",
           !line[cursor].isWhitespace {
            return nil
        }
        return tagName.isEmpty ? nil : tagName
    }
}
