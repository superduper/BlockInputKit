import Foundation

extension BlockInputInlineMarkdownParsing {
    private static let linkBackslash: unichar = 0x5C
    private static let linkExclamation: unichar = 0x21
    private static let linkOpeningBracket: unichar = 0x5B
    private static let linkClosingBracket: unichar = 0x5D
    private static let linkOpeningParenthesis: unichar = 0x28
    private static let linkClosingParenthesis: unichar = 0x29
    private static let linkOpeningAngle: unichar = 0x3C
    private static let linkClosingAngle: unichar = 0x3E
    private static let linkLineFeed: unichar = 0x0A
    private static let linkCarriageReturn: unichar = 0x0D

    /// Scans inline links without materializing a Markdown AST so mounted rows remain cheap to refresh while typing.
    static func linkRanges(
        in text: NSString,
        excluding excludedRangeLookup: BlockInputExcludedRangeLookup,
        fileBaseURL: URL? = nil
    ) -> [BlockInputInlineMarkdownRange] {
        var ranges: [BlockInputInlineMarkdownRange] = []
        var location = 0
        while location < text.length {
            guard text.character(at: location) == linkOpeningBracket else {
                location += 1
                continue
            }
            if location > 0, text.character(at: location - 1) == linkOpeningBracket {
                location += 1
                continue
            }
            guard !excludedRangeLookup.intersects(NSRange(location: location, length: 1)) else {
                location += 1
                continue
            }
            let linkSearch = linkRange(
                in: text,
                openingBracketLocation: location,
                excluding: excludedRangeLookup,
                fileBaseURL: fileBaseURL
            )
            if let linkRange = linkSearch.range {
                ranges.append(linkRange)
                location = NSMaxRange(linkRange.fullRange)
            } else {
                location = max(location + 1, linkSearch.resumeLocation)
            }
        }
        return ranges
    }

    static func linkSourceRanges(
        in text: String,
        excluding excludedRanges: [NSRange] = []
    ) -> [NSRange] {
        let nsText = text as NSString
        return linkSourceRanges(
            in: nsText,
            excluding: BlockInputExcludedRangeLookup(textLength: nsText.length, ranges: excludedRanges)
        )
    }

    static func linkSourceRanges(
        in text: NSString,
        excluding excludedRangeLookup: BlockInputExcludedRangeLookup
    ) -> [NSRange] {
        var ranges: [NSRange] = []
        var location = 0
        while location < text.length {
            guard text.character(at: location) == linkOpeningBracket else {
                location += 1
                continue
            }
            if location > 0, text.character(at: location - 1) == linkOpeningBracket {
                location += 1
                continue
            }
            if excludedRangeLookup.intersects(NSRange(location: location, length: 1)) {
                location += 1
                continue
            }
            let linkSearch = linkRange(in: text, openingBracketLocation: location, excluding: excludedRangeLookup)
            if let sourceRange = linkSearch.sourceRange {
                ranges.append(sourceRange)
                location = NSMaxRange(sourceRange)
            } else {
                location = max(location + 1, linkSearch.resumeLocation)
            }
        }
        return ranges
    }

    private static func linkRange(
        in text: NSString,
        openingBracketLocation: Int,
        excluding excludedRangeLookup: BlockInputExcludedRangeLookup,
        fileBaseURL: URL? = nil
    ) -> BlockInputLinkSearch {
        let labelSearch = closingLinkLabelLocation(
            in: text,
            from: openingBracketLocation + 1,
            excluding: excludedRangeLookup
        )
        guard let closingBracketLocation = labelSearch.closingLocation,
              closingBracketLocation >= openingBracketLocation + 1,
              closingBracketLocation + 1 < text.length,
              text.character(at: closingBracketLocation + 1) == linkOpeningParenthesis,
              !excludedRangeLookup.intersects(NSRange(location: closingBracketLocation, length: 2)) else {
            return BlockInputLinkSearch(
                range: nil,
                sourceRange: nil,
                resumeLocation: max(openingBracketLocation + 1, labelSearch.resumeLocation)
            )
        }

        let urlStart = closingBracketLocation + 2
        let destinationSearch = closingLinkDestinationLocation(
            in: text,
            from: urlStart,
            excluding: excludedRangeLookup
        )
        guard let closingParenthesisLocation = destinationSearch.closingLocation else {
            return BlockInputLinkSearch(
                range: nil,
                sourceRange: nil,
                resumeLocation: max(openingBracketLocation + 1, destinationSearch.resumeLocation)
            )
        }
        let sourceRanges = BlockInputLinkSourceRanges(
            imageMarkerLocation: imageMarkerLocation(before: openingBracketLocation, in: text),
            openingBracketLocation: openingBracketLocation,
            closingBracketLocation: closingBracketLocation,
            urlStart: urlStart,
            closingParenthesisLocation: closingParenthesisLocation
        )
        let sourceRange = sourceRanges.fullRange
        guard let linkRange = parsedLinkRange(in: text, sourceRanges: sourceRanges, fileBaseURL: fileBaseURL) else {
            return BlockInputLinkSearch(range: nil, sourceRange: sourceRange, resumeLocation: NSMaxRange(sourceRange))
        }
        return BlockInputLinkSearch(range: linkRange, sourceRange: sourceRange, resumeLocation: NSMaxRange(sourceRange))
    }

    private static func parsedLinkRange(
        in text: NSString,
        sourceRanges: BlockInputLinkSourceRanges,
        fileBaseURL: URL? = nil
    ) -> BlockInputInlineMarkdownRange? {
        let label = text.substring(with: sourceRanges.labelRange)
        let urlString = normalizedLinkDestination(text.substring(with: sourceRanges.urlRange).blockInputUnescapedLinkDestination)
        let allowsCustomSchemes = label.blockInputUnescapedLinkLabel.hasPrefix("/")
        guard linkLabelIsSupported(label),
              let destination = BlockInputLinkURL.supportedURL(
                from: urlString,
                allowsCustomSchemes: allowsCustomSchemes,
                fileBaseURL: fileBaseURL
              ) else {
            return nil
        }
        return BlockInputInlineMarkdownRange(
            style: .link,
            fullRange: sourceRanges.fullRange,
            contentRange: sourceRanges.labelRange,
            delimiterRanges: linkDelimiterRanges(in: text, sourceRanges: sourceRanges),
            linkDestination: destination,
            linkRawDestination: urlString
        )
    }

    private static func linkDelimiterRanges(
        in text: NSString,
        sourceRanges: BlockInputLinkSourceRanges
    ) -> [NSRange] {
        [
            sourceRanges.openingDelimiterRange,
            NSRange(location: sourceRanges.closingBracketLocation, length: 2),
            sourceRanges.urlRange,
            NSRange(location: sourceRanges.closingParenthesisLocation, length: 1)
        ] + escapedLabelDelimiterRanges(in: text, labelRange: sourceRanges.labelRange)
    }

    private static func imageMarkerLocation(before openingBracketLocation: Int, in text: NSString) -> Int? {
        let markerLocation = openingBracketLocation - 1
        guard markerLocation >= 0,
              text.character(at: markerLocation) == linkExclamation,
              !isEscapedLinkCharacter(at: markerLocation, in: text) else {
            return nil
        }
        return markerLocation
    }

    private static func closingLinkLabelLocation(
        in text: NSString,
        from startLocation: Int,
        excluding excludedRangeLookup: BlockInputExcludedRangeLookup
    ) -> BlockInputLinkClosingSearch {
        var location = startLocation
        while location < text.length {
            let character = text.character(at: location)
            if character == linkLineFeed || character == linkCarriageReturn {
                return BlockInputLinkClosingSearch(closingLocation: nil, resumeLocation: location + 1)
            }
            if character == linkOpeningBracket, !isEscapedLinkCharacter(at: location, in: text) {
                return BlockInputLinkClosingSearch(closingLocation: nil, resumeLocation: location + 1)
            }
            if character == linkClosingBracket,
               !isEscapedLinkCharacter(at: location, in: text),
               !excludedRangeLookup.intersects(NSRange(location: location, length: 1)) {
                return BlockInputLinkClosingSearch(closingLocation: location, resumeLocation: location)
            }
            location += 1
        }
        return BlockInputLinkClosingSearch(closingLocation: nil, resumeLocation: text.length)
    }

    private static func closingLinkDestinationLocation(
        in text: NSString,
        from startLocation: Int,
        excluding excludedRangeLookup: BlockInputExcludedRangeLookup
    ) -> BlockInputLinkClosingSearch {
        if startLocation < text.length,
           text.character(at: startLocation) == linkOpeningAngle {
            return closingAngleLinkDestinationLocation(in: text, from: startLocation, excluding: excludedRangeLookup)
        }
        var location = startLocation
        while location < text.length {
            let character = text.character(at: location)
            if character == linkLineFeed || character == linkCarriageReturn {
                return BlockInputLinkClosingSearch(closingLocation: nil, resumeLocation: location + 1)
            }
            if character == linkOpeningParenthesis, !isEscapedLinkCharacter(at: location, in: text) {
                return BlockInputLinkClosingSearch(closingLocation: nil, resumeLocation: location + 1)
            }
            // Parentheses inside destinations must be escaped so the row-local scanner can stay linear.
            if character == linkClosingParenthesis,
               !isEscapedLinkCharacter(at: location, in: text),
               !excludedRangeLookup.intersects(NSRange(location: location, length: 1)) {
                return BlockInputLinkClosingSearch(closingLocation: location, resumeLocation: location)
            }
            location += 1
        }
        return BlockInputLinkClosingSearch(closingLocation: nil, resumeLocation: text.length)
    }

    private static func closingAngleLinkDestinationLocation(
        in text: NSString,
        from startLocation: Int,
        excluding excludedRangeLookup: BlockInputExcludedRangeLookup
    ) -> BlockInputLinkClosingSearch {
        var location = startLocation + 1
        while location < text.length {
            let character = text.character(at: location)
            if character == linkLineFeed || character == linkCarriageReturn {
                return BlockInputLinkClosingSearch(closingLocation: nil, resumeLocation: location + 1)
            }
            if character == linkClosingAngle,
               !isEscapedLinkCharacter(at: location, in: text) {
                let closingParenthesisLocation = location + 1
                guard closingParenthesisLocation < text.length,
                      text.character(at: closingParenthesisLocation) == linkClosingParenthesis,
                      !isEscapedLinkCharacter(at: closingParenthesisLocation, in: text),
                      !excludedRangeLookup.intersects(NSRange(location: location, length: 2)) else {
                    return BlockInputLinkClosingSearch(closingLocation: nil, resumeLocation: location + 1)
                }
                return BlockInputLinkClosingSearch(closingLocation: closingParenthesisLocation, resumeLocation: closingParenthesisLocation)
            }
            location += 1
        }
        return BlockInputLinkClosingSearch(closingLocation: nil, resumeLocation: text.length)
    }

    private static func linkLabelIsSupported(_ label: String) -> Bool {
        !label.blockInputUnescapedLinkLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func normalizedLinkDestination(_ destination: String) -> String {
        guard destination.hasPrefix("<"),
              destination.hasSuffix(">"),
              destination.count > 2 else {
            return destination
        }
        return String(destination.dropFirst().dropLast())
    }

    private static func escapedLabelDelimiterRanges(in text: NSString, labelRange: NSRange) -> [NSRange] {
        let labelEnd = NSMaxRange(labelRange)
        var ranges: [NSRange] = []
        var location = labelRange.location
        while location + 1 < labelEnd {
            guard text.character(at: location) == linkBackslash else {
                location += 1
                continue
            }
            let escapedCharacter = text.character(at: location + 1)
            if escapedCharacter == linkOpeningBracket || escapedCharacter == linkClosingBracket || escapedCharacter == linkBackslash {
                ranges.append(NSRange(location: location, length: 1))
                location += 2
            } else {
                location += 1
            }
        }
        return ranges
    }

    private static func isEscapedLinkCharacter(at location: Int, in text: NSString) -> Bool {
        guard location > 0 else {
            return false
        }
        var backslashCount = 0
        var cursor = location - 1
        while cursor >= 0, text.character(at: cursor) == linkBackslash {
            backslashCount += 1
            cursor -= 1
        }
        return backslashCount % 2 == 1
    }
}

/// Result of scanning from one `[` candidate, including where the outer scanner should resume.
private struct BlockInputLinkSearch {
    let range: BlockInputInlineMarkdownRange?
    let sourceRange: NSRange?
    let resumeLocation: Int
}

/// Closing delimiter lookup result that lets failed scans skip past malformed candidates.
private struct BlockInputLinkClosingSearch {
    let closingLocation: Int?
    let resumeLocation: Int
}

/// Source offsets for one Markdown link; ranges are derived lazily to keep the scanner allocation-light.
private struct BlockInputLinkSourceRanges {
    let imageMarkerLocation: Int?
    let openingBracketLocation: Int
    let closingBracketLocation: Int
    let urlStart: Int
    let closingParenthesisLocation: Int

    var labelRange: NSRange {
        NSRange(
            location: openingBracketLocation + 1,
            length: closingBracketLocation - openingBracketLocation - 1
        )
    }

    var urlRange: NSRange {
        NSRange(location: urlStart, length: closingParenthesisLocation - urlStart)
    }

    var openingDelimiterRange: NSRange {
        NSRange(location: sourceStartLocation, length: openingBracketLocation - sourceStartLocation + 1)
    }

    var fullRange: NSRange {
        NSRange(
            location: sourceStartLocation,
            length: closingParenthesisLocation - sourceStartLocation + 1
        )
    }

    private var sourceStartLocation: Int {
        imageMarkerLocation ?? openingBracketLocation
    }
}
