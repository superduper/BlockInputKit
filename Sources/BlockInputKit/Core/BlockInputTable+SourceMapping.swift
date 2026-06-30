import Foundation

extension BlockInputTable {
    /// A stable logical cell address inside a normalized table.
    struct CellPosition: Equatable {
        var row: Row
        var column: Int
    }

    struct FormattingSourceRange {
        var position: CellPosition
        var sourceRange: NSRange
        var localRange: NSRange
    }

    func cell(at position: CellPosition) -> Cell? {
        guard (0..<columnCount).contains(position.column) else {
            return nil
        }
        switch position.row {
        case .header:
            return header[position.column]
        case .body(let rowIndex):
            guard bodyRows.indices.contains(rowIndex) else {
                return nil
            }
            return bodyRows[rowIndex][position.column]
        }
    }

    func sourceRange(forLocalRange localRange: NSRange, in position: CellPosition) -> NSRange? {
        guard let cell = cell(at: position) else {
            return nil
        }
        let clampedRange = cell.text.blockInputTableClampedUTF16Range(localRange)
        let lower = Self.escapedUTF16Offset(forLocalUTF16Offset: clampedRange.location, in: cell.text)
        let upper = Self.escapedUTF16Offset(forLocalUTF16Offset: NSMaxRange(clampedRange), in: cell.text)
        return NSRange(location: cell.sourceRange.location + lower, length: upper - lower)
    }

    func localRange(forSourceRange sourceRange: NSRange, in position: CellPosition) -> NSRange? {
        guard let cell = cell(at: position),
              sourceRange.location >= cell.sourceRange.location,
              NSMaxRange(sourceRange) <= NSMaxRange(cell.sourceRange) else {
            return nil
        }
        let escapedText = (markdown as NSString).substring(with: cell.sourceRange)
        let localLower = Self.localUTF16Offset(
            forEscapedUTF16Offset: sourceRange.location - cell.sourceRange.location,
            in: escapedText
        )
        let localUpper = Self.localUTF16Offset(
            forEscapedUTF16Offset: NSMaxRange(sourceRange) - cell.sourceRange.location,
            in: escapedText
        )
        guard let localLower, let localUpper else {
            return nil
        }
        return NSRange(location: localLower, length: localUpper - localLower)
    }

    func cellPosition(containingSourceRange sourceRange: NSRange) -> CellPosition? {
        for position in cellPositions {
            guard let cell = cell(at: position),
                  sourceRange.location >= cell.sourceRange.location,
                  NSMaxRange(sourceRange) <= NSMaxRange(cell.sourceRange) else {
                continue
            }
            return position
        }
        return nil
    }

    func formattingSourceRange(containing sourceRange: NSRange) -> FormattingSourceRange? {
        guard let position = cellPosition(containingSourceRange: sourceRange),
              let cell = cell(at: position),
              let localRange = localRange(forSourceRange: sourceRange, in: position) else {
            return nil
        }
        let formattedLocalRange = cell.text.blockInputFormattingClampedRange(localRange, trimsHiddenDelimiters: true)
        guard formattedLocalRange.length > 0,
              let formattedSourceRange = self.sourceRange(forLocalRange: formattedLocalRange, in: position) else {
            return nil
        }
        return FormattingSourceRange(position: position, sourceRange: formattedSourceRange, localRange: formattedLocalRange)
    }

    private var cellPositions: [CellPosition] {
        (0..<columnCount).map { CellPosition(row: .header, column: $0) } +
            (0..<bodyRows.count).flatMap { rowIndex in
                (0..<columnCount).map { CellPosition(row: .body(rowIndex), column: $0) }
            }
    }

    private static func escapedUTF16Offset(forLocalUTF16Offset offset: Int, in text: String) -> Int {
        let targetOffset = min(max(offset, 0), (text as NSString).length)
        var localOffset = 0
        var escapedOffset = 0
        var index = text.startIndex
        var codeDelimiterLength = 0
        while index < text.endIndex {
            guard localOffset < targetOffset else {
                return escapedOffset
            }
            let character = text[index]
            if character == "`" {
                let runLength = backtickRunLength(in: text, from: index)
                let runEnd = text.index(index, offsetBy: runLength)
                if targetOffset < localOffset + runLength {
                    return escapedOffset + (targetOffset - localOffset)
                }
                escapedOffset += runLength
                localOffset += runLength
                if codeDelimiterLength == 0 {
                    if hasClosingBacktickRun(in: text, from: runEnd, length: runLength) {
                        codeDelimiterLength = runLength
                    }
                } else if runLength == codeDelimiterLength {
                    codeDelimiterLength = 0
                }
                index = runEnd
                continue
            }
            let localLength = String(character).utf16.count
            let escapedLength = codeDelimiterLength == 0 && isEscapedCellCharacter(character) ? 2 : localLength
            if targetOffset < localOffset + localLength {
                return escapedOffset + min(targetOffset - localOffset, escapedLength)
            }
            escapedOffset += escapedLength
            localOffset += localLength
            index = text.index(after: index)
        }
        return escapedOffset
    }

    private static func localUTF16Offset(forEscapedUTF16Offset offset: Int, in escapedText: String) -> Int? {
        let textLength = (escapedText as NSString).length
        guard offset >= 0, offset <= textLength else {
            return nil
        }
        var sourceOffset = 0
        var localOffset = 0
        var index = escapedText.startIndex
        var codeDelimiterLength = 0
        while index < escapedText.endIndex {
            guard sourceOffset < offset else {
                return localOffset
            }
            let character = escapedText[index]
            if character == "`" {
                let runLength = backtickRunLength(in: escapedText, from: index)
                let runEnd = escapedText.index(index, offsetBy: runLength)
                if offset < sourceOffset + runLength {
                    return localOffset + (offset - sourceOffset)
                }
                sourceOffset += runLength
                localOffset += runLength
                if codeDelimiterLength == 0 {
                    if hasClosingBacktickRun(in: escapedText, from: runEnd, length: runLength) {
                        codeDelimiterLength = runLength
                    }
                } else if runLength == codeDelimiterLength {
                    codeDelimiterLength = 0
                }
                index = runEnd
                continue
            }
            if let escapedEndIndex = escapedSourcePairEndIndex(in: escapedText, at: index, isInCodeSpan: codeDelimiterLength != 0) {
                if offset == sourceOffset + 1 {
                    return nil
                }
                sourceOffset += 2
                localOffset += 1
                index = escapedEndIndex
                continue
            }
            let length = String(character).utf16.count
            sourceOffset += length
            localOffset += length
            index = escapedText.index(after: index)
        }
        return sourceOffset == offset ? localOffset : nil
    }

    private static func isEscapedSourceCharacter(_ character: Character) -> Bool {
        character == "\\" || character == "|"
    }

    private static func escapedSourcePairEndIndex(
        in text: String,
        at index: String.Index,
        isInCodeSpan: Bool
    ) -> String.Index? {
        guard !isInCodeSpan, text[index] == "\\" else {
            return nil
        }
        let nextIndex = text.index(after: index)
        guard nextIndex < text.endIndex, Self.isEscapedSourceCharacter(text[nextIndex]) else {
            return nil
        }
        return text.index(after: nextIndex)
    }

    private static func isEscapedCellCharacter(_ character: Character) -> Bool {
        character == "\\" || character == "|"
    }

    private static func backtickRunLength(in text: String, from index: String.Index) -> Int {
        var length = 0
        var cursor = index
        while cursor < text.endIndex, text[cursor] == "`" {
            length += 1
            cursor = text.index(after: cursor)
        }
        return length
    }

    private static func hasClosingBacktickRun(in text: String, from index: String.Index, length: Int) -> Bool {
        var cursor = index
        while cursor < text.endIndex {
            guard text[cursor] == "`" else {
                cursor = text.index(after: cursor)
                continue
            }
            let runLength = backtickRunLength(in: text, from: cursor)
            if runLength == length {
                return true
            }
            cursor = text.index(cursor, offsetBy: runLength)
        }
        return false
    }
}

private extension String {
    func blockInputTableClampedUTF16Range(_ range: NSRange) -> NSRange {
        let length = (self as NSString).length
        let location = min(max(range.location, 0), length)
        return NSRange(location: location, length: min(max(range.length, 0), length - location))
    }
}
