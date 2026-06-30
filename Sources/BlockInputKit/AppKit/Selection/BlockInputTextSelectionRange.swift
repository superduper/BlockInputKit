import Foundation

extension NSRange {
    func shouldPromoteToBlockSelection(in string: String, direction: BlockInputVerticalMovementDirection) -> Bool {
        guard length > 0 else {
            return false
        }
        let textLength = (string as NSString).length
        switch direction {
        case .upward:
            return location <= 0
        case .downward:
            return NSMaxRange(self) >= textLength
        }
    }
}

extension String {
    func expandingLineSelection(_ range: NSRange, direction: BlockInputVerticalMovementDirection) -> NSRange {
        let text = self as NSString
        let length = text.length
        guard length > 0 else {
            return NSRange(location: 0, length: 0)
        }
        let clampedLocation = min(max(range.location, 0), length)
        let clampedEnd = min(max(range.location + range.length, clampedLocation), length)
        switch direction {
        case .upward:
            guard clampedLocation > 0 else {
                return NSRange(location: 0, length: clampedEnd)
            }
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            text.getLineStart(
                &lineStart,
                end: &lineEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: clampedLocation - 1, length: 0)
            )
            return NSRange(location: lineStart, length: clampedEnd - lineStart)
        case .downward:
            guard clampedEnd < length else {
                return NSRange(location: clampedLocation, length: length - clampedLocation)
            }
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            text.getLineStart(
                &lineStart,
                end: &lineEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: clampedEnd, length: 0)
            )
            return NSRange(location: clampedLocation, length: lineEnd - clampedLocation)
        }
    }
}
