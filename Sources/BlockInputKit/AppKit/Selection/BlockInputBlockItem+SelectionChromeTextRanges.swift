import AppKit

struct BlockInputTextSelectionLineFragment {
    var index: Int
    var characterRange: NSRange
    var insertionRange: NSRange
    var lineRect: NSRect
    var usedRect: NSRect
}

extension NSRange {
    func selectionChromeInsertionRange(in text: NSString) -> NSRange {
        var upperBound = min(NSMaxRange(self), text.length)
        while upperBound > location {
            let character = text.character(at: upperBound - 1)
            guard character == 10 || character == 13 else {
                break
            }
            upperBound -= 1
        }
        return NSRange(location: location, length: upperBound - location)
    }

    func selectionChromeContentStart(in text: NSString) -> Int {
        let upperBound = min(NSMaxRange(self), text.length)
        var lowerBound = min(max(location, 0), upperBound)
        while lowerBound < upperBound {
            let character = text.character(at: lowerBound)
            guard character == 10 || character == 13 else {
                break
            }
            lowerBound += 1
        }
        return lowerBound
    }
}

extension NSRect {
    func fallbackExtraLineFragmentRect(
        after fragments: [BlockInputTextSelectionLineFragment],
        in textContainer: NSTextContainer
    ) -> NSRect {
        guard isEmpty else {
            return self
        }
        if let last = fragments.last {
            return NSRect(
                x: last.lineRect.minX,
                y: last.lineRect.maxY,
                width: max(last.lineRect.width, 1),
                height: max(last.lineRect.height, 1)
            )
        }
        return NSRect(x: 0, y: 0, width: max(textContainer.size.width, 1), height: 1)
    }

    func fallbackExtraLineFragmentUsedRect(in lineRect: NSRect) -> NSRect {
        guard !isEmpty else {
            return NSRect(x: lineRect.minX, y: lineRect.minY, width: 12, height: max(lineRect.height, 1))
        }
        return self
    }
}

extension NSString {
    var trailingLineEndingRange: NSRange? {
        guard length > 0 else {
            return nil
        }
        let lastCharacter = character(at: length - 1)
        guard lastCharacter == 10 || lastCharacter == 13 else {
            return nil
        }
        if lastCharacter == 10,
           length > 1,
           character(at: length - 2) == 13 {
            return NSRange(location: length - 2, length: 2)
        }
        return NSRange(location: length - 1, length: 1)
    }
}

extension String {
    func blockInputClampedRange(_ range: NSRange) -> NSRange {
        let text = self as NSString
        let location = min(max(range.location, 0), text.length)
        let length = min(max(range.length, 0), max(text.length - location, 0))
        return NSRange(location: location, length: length)
    }
}
