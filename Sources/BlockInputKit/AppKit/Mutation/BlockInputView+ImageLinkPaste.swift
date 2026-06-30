import AppKit

extension BlockInputView {
    func pasteURLIntoMarkdownImageDestinationIfNeeded(
        _ urlString: String,
        blockID: BlockInputBlockID?,
        selectedRange: NSRange?
    ) -> Bool {
        // Complete pending image syntax before generic URL paste can wrap the URL as a Markdown link.
        guard imagePresentation == .inlineBlocks,
              let target = linkPasteTarget(blockID: blockID, selectedRangeOverride: selectedRange),
              let block = block(withID: target.blockID),
              block.kind.supportsImageSyntaxSplitting,
              let destinationRange = block.text.blockInputMarkdownImageDestinationRange(containing: target.range) else {
            return false
        }
        let clampedRange = block.text.blockInputLinkClampedRange(target.range)
        guard let replacementRange = markdownImageDestinationReplacementRange(
            selectedRange: clampedRange,
            destinationRange: destinationRange
        ) else {
            return false
        }
        let updatedText = NSMutableString(string: block.text)
        updatedText.replaceCharacters(in: replacementRange, with: urlString)
        let proposedText = updatedText as String
        guard proposedText.blockInputContainsImageSplit(for: block) else {
            return false
        }
        return applyTypingShortcutIfNeeded(
            blockID: target.blockID,
            proposedText: proposedText,
            proposedUTF16Offset: replacementRange.location + (urlString as NSString).length,
            selectionBefore: selection
        ) != nil
    }

    func linkPasteTarget(
        blockID blockIDOverride: BlockInputBlockID? = nil,
        selectedRangeOverride: NSRange?
    ) -> (blockID: BlockInputBlockID, range: NSRange)? {
        if let blockIDOverride,
           let selectedRangeOverride {
            return (blockIDOverride, selectedRangeOverride)
        }
        switch selection {
        case let .cursor(cursor) where blockIDOverride == nil || blockIDOverride == cursor.blockID:
            return (cursor.blockID, selectedRangeOverride ?? NSRange(location: cursor.utf16Offset, length: 0))
        case let .text(textRange) where blockIDOverride == nil || blockIDOverride == textRange.blockID:
            return (textRange.blockID, selectedRangeOverride ?? textRange.range)
        case .blocks, .mixed, .cursor, .text, nil:
            return nil
        }
    }

    private func markdownImageDestinationReplacementRange(
        selectedRange: NSRange,
        destinationRange: NSRange
    ) -> NSRange? {
        if selectedRange.length == 0 {
            return destinationRange.containsOrTouches(selectedRange.location) ? selectedRange : nil
        }
        guard selectedRange.location >= destinationRange.location,
              NSMaxRange(selectedRange) <= NSMaxRange(destinationRange) else {
            return nil
        }
        return selectedRange
    }
}

extension String {
    func blockInputMarkdownImageDestinationRange(containing range: NSRange) -> NSRange? {
        let text = self as NSString
        let clampedRange = blockInputLinkClampedRange(range)
        var location = 0
        while location + 3 < text.length {
            guard text.character(at: location) == markdownImageExclamation,
                  text.character(at: location + 1) == markdownImageOpeningBracket else {
                location += 1
                continue
            }
            guard let labelEnd = markdownImageLabelEnd(in: text, from: location + 2) else {
                location += 2
                continue
            }
            let openingParenthesis = labelEnd + 1
            guard openingParenthesis < text.length,
                  text.character(at: openingParenthesis) == markdownImageOpeningParenthesis else {
                location = labelEnd + 1
                continue
            }
            let destinationStart = openingParenthesis + 1
            // Accept a missing closing parenthesis so URL paste falls back to plain text instead of link wrapping.
            let destinationEnd = markdownImageDestinationEnd(in: text, from: destinationStart)
            let destinationRange = NSRange(location: destinationStart, length: destinationEnd - destinationStart)
            if destinationRange.blockInputContainsOrTouches(clampedRange) {
                return destinationRange
            }
            location = max(destinationEnd + 1, location + 2)
        }
        return nil
    }

    fileprivate func blockInputContainsImageSplit(for block: BlockInputBlock) -> Bool {
        var proposedBlock = block
        proposedBlock.text = self
        return BlockInputMarkdownImporter.imageBlocks(bySplitting: proposedBlock).contains { block in
            if case .image = block.kind {
                return true
            }
            return false
        }
    }

    private func markdownImageLabelEnd(in text: NSString, from start: Int) -> Int? {
        var location = start
        while location < text.length {
            switch text.character(at: location) {
            case markdownImageClosingBracket:
                return location
            case markdownImageLineFeed, markdownImageCarriageReturn:
                return nil
            default:
                location += 1
            }
        }
        return nil
    }

    private func markdownImageDestinationEnd(in text: NSString, from start: Int) -> Int {
        var location = start
        while location < text.length {
            switch text.character(at: location) {
            case markdownImageClosingParenthesis, markdownImageLineFeed, markdownImageCarriageReturn:
                return location
            default:
                location += 1
            }
        }
        return text.length
    }
}

private extension NSRange {
    func blockInputContainsOrTouches(_ range: NSRange) -> Bool {
        if range.length == 0 {
            return containsOrTouches(range.location)
        }
        return intersectionLength(with: range) > 0 ||
            containsOrTouches(range.location) ||
            containsOrTouches(NSMaxRange(range))
    }
}

private let markdownImageExclamation: unichar = 0x21
private let markdownImageOpeningBracket: unichar = 0x5B
private let markdownImageClosingBracket: unichar = 0x5D
private let markdownImageOpeningParenthesis: unichar = 0x28
private let markdownImageClosingParenthesis: unichar = 0x29
private let markdownImageLineFeed: unichar = 0x0A
private let markdownImageCarriageReturn: unichar = 0x0D
