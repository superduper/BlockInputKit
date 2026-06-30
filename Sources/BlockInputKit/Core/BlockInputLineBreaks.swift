import Foundation

/// Shared line-break helpers that treat CRLF as one logical line break.
enum BlockInputLineBreaks {
    static func lineCount(in text: String) -> Int {
        lineStartOffsets(in: text).count
    }

    static func lines(in text: String) -> [String] {
        let textStorage = text as NSString
        guard textStorage.length > 0 else {
            return [""]
        }
        var lines: [String] = []
        var offset = 0
        while offset < textStorage.length {
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            textStorage.getLineStart(
                &lineStart,
                end: &lineEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: offset, length: 0)
            )
            lines.append(textStorage.substring(with: NSRange(
                location: lineStart,
                length: contentsEnd - lineStart
            )))
            offset = lineEnd
        }
        if textStorage.character(at: textStorage.length - 1).isLineEnding {
            lines.append("")
        }
        return lines
    }

    static func lineStartOffsets(in text: String) -> [Int] {
        let textStorage = text as NSString
        guard textStorage.length > 0 else {
            return [0]
        }
        var offsets = [0]
        var utf16Index = 0
        while utf16Index < textStorage.length {
            let character = textStorage.character(at: utf16Index)
            if character.isCarriageReturn,
               utf16Index + 1 < textStorage.length,
               textStorage.character(at: utf16Index + 1).isLineFeed {
                offsets.append(utf16Index + 2)
                utf16Index += 2
                continue
            }
            if character.isLineEnding {
                offsets.append(utf16Index + 1)
            }
            utf16Index += 1
        }
        return offsets
    }
}

extension unichar {
    var isLineEnding: Bool {
        isLineFeed || isCarriageReturn
    }

    var isLineFeed: Bool {
        self == 10
    }

    var isCarriageReturn: Bool {
        self == 13
    }
}
