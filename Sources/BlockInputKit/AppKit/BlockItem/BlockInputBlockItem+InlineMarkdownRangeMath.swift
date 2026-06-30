import Foundation

/// Range math used by the inline-Markdown styling pass: styled-content hit tests plus the sorted
/// inline-code subtraction helpers. Kept file-local to the inline-Markdown styling sources.
extension NSRange {
    func intersectsStyledContent(_ range: NSRange) -> Bool {
        if length == 0 {
            // Insertion immediately before a closing delimiter is still inside
            // the visual span, so typed text should inherit the active style.
            return location >= range.location && location <= NSMaxRange(range)
        }
        return NSIntersectionRange(self, range).length > 0
    }

    func subtractingSorted(_ excludedRanges: [NSRange]) -> [NSRange] {
        // Inline-code ranges are emitted in source order, so binary search can
        // skip non-overlapping code spans before subtracting intersections.
        var remainingRanges = [self]
        let upperBound = NSMaxRange(self)
        var excludedRangeIndex = excludedRanges.firstPossibleIntersectionIndex(with: self)
        while excludedRangeIndex < excludedRanges.count {
            let excludedRange = excludedRanges[excludedRangeIndex]
            if excludedRange.location >= upperBound {
                break
            }
            remainingRanges = remainingRanges.flatMap { $0.subtracting(excludedRange) }
            if remainingRanges.isEmpty {
                break
            }
            excludedRangeIndex += 1
        }
        return remainingRanges
    }

    func subtracting(_ excludedRange: NSRange) -> [NSRange] {
        let intersection = NSIntersectionRange(self, excludedRange)
        guard intersection.length > 0 else {
            return [self]
        }
        var ranges: [NSRange] = []
        if intersection.location > location {
            ranges.append(NSRange(location: location, length: intersection.location - location))
        }
        let intersectionUpperBound = NSMaxRange(intersection)
        if intersectionUpperBound < NSMaxRange(self) {
            ranges.append(NSRange(location: intersectionUpperBound, length: NSMaxRange(self) - intersectionUpperBound))
        }
        return ranges
    }
}

extension [NSRange] {
    func firstPossibleIntersectionIndex(with range: NSRange) -> Int {
        var lowerBound = 0
        var upperBound = count
        while lowerBound < upperBound {
            let middleIndex = (lowerBound + upperBound) / 2
            if NSMaxRange(self[middleIndex]) <= range.location {
                lowerBound = middleIndex + 1
            } else {
                upperBound = middleIndex
            }
        }
        return lowerBound
    }
}
