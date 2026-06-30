import AppKit

extension BlockInputTextView {
    /// Keeps plain left/right movement aligned with the visible link/chip boundary, not hidden Markdown source bytes.
    func handleLinkBoundaryMovementCommand(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(moveLeft(_:)):
            return collapseSelectedChip(.leftward) || moveAcrossHiddenLinkBoundary(.leftward)
        case #selector(moveRight(_:)):
            return collapseSelectedChip(.rightward) || moveAcrossHiddenLinkBoundary(.rightward)
        default:
            return false
        }
    }

    func handleLinkBoundaryMovementShortcut(_ event: NSEvent) -> Bool {
        guard let direction = event.plainHorizontalMovementDirection else {
            return false
        }
        return moveAcrossHiddenLinkBoundary(direction)
    }

    private func moveAcrossHiddenLinkBoundary(_ direction: BlockInputHorizontalMovementDirection) -> Bool {
        let selectedRange = selectedRange()
        guard selectedRange.length == 0,
              supportsInlineLinkNavigation,
              let target = inlineLinkNavigation().characterBoundaryTarget(
                from: selectedRange.location,
                direction: direction
              ) else {
            return false
        }
        setSelectedRanges([NSValue(range: target.range)], affinity: target.affinity, stillSelecting: false)
        scrollRangeToVisible(target.range)
        blockItem?.updateSelectionDependentAttributesForCurrentSelection()
        return true
    }

    func moveWordAcrossInlineLinkSource(_ direction: BlockInputWordMovementDirection) -> Bool {
        let selectedRange = selectedRange()
        guard selectedRange.length == 0,
              supportsInlineLinkNavigation,
              let target = inlineLinkNavigation().wordBoundaryTarget(
                from: selectedRange.location,
                direction: direction
              ) else {
            return false
        }
        setSelectedRange(target.range)
        scrollRangeToVisible(target.range)
        blockItem?.updateSelectionDependentAttributesForCurrentSelection()
        return true
    }

    func modifyWordSelectionAcrossInlineLinkSource(
        _ direction: BlockInputWordMovementDirection,
        previousRange: NSRange
    ) -> Bool {
        guard supportsInlineLinkNavigation,
              let target = inlineLinkNavigation().wordBoundaryTarget(
                from: previousRange.activeWordSelectionOffset(for: direction),
                direction: direction
              ) else {
            return false
        }
        let anchor = previousRange.wordSelectionAnchor(for: direction)
        let range = NSRange(
            location: min(anchor, target.range.location),
            length: abs(target.range.location - anchor)
        )
        setSelectedRange(range)
        scrollRangeToVisible(range)
        if blockItem?.isTableCellTextView(self) != true {
            requestWordSelectionAdjustmentFromOwningBlock(
                direction,
                previousSelectedRange: previousRange,
                selectedRange: range
            )
        }
        blockItem?.updateSelectionDependentAttributesForCurrentSelection()
        return true
    }

    func inlineLinkNavigation() -> BlockInputInlineLinkNavigation {
        BlockInputInlineLinkNavigation(text: string, fileBaseURL: blockItem?.fileBaseURL)
    }

    var supportsInlineLinkNavigation: Bool {
        blockItem?.supportsInlineMarkdownLinkRendering(for: self) == true
    }
}

struct BlockInputInlineLinkNavigation {
    private let sourceText: String
    private let text: NSString
    private let visibleText: String
    private let linkRanges: [BlockInputInlineMarkdownRange]
    private let hiddenOffsets: [Bool]
    private let sourceToVisibleOffsets: [Int]
    private let visibleToSourceBeforeNext: [Int]
    private let visibleToSourceAfterPrevious: [Int]

    init(text: String, fileBaseURL: URL?) {
        sourceText = text
        self.text = text as NSString
        let inlineCodeRanges = BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange)
        let parsedLinkRanges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: text,
            excluding: inlineCodeRanges,
            fileBaseURL: fileBaseURL
        )
        .filter { $0.style == .link }
        linkRanges = parsedLinkRanges

        let textLength = self.text.length
        hiddenOffsets = Self.hiddenOffsets(in: parsedLinkRanges, textLength: textLength)
        let visibleOffsets = Self.visibleOffsetTables(in: self.text, hiddenOffsets: hiddenOffsets)
        sourceToVisibleOffsets = visibleOffsets.sourceToVisibleOffsets
        visibleText = visibleOffsets.visibleText
        visibleToSourceBeforeNext = visibleOffsets.visibleToSourceBeforeNext
        visibleToSourceAfterPrevious = visibleOffsets.visibleToSourceAfterPrevious
    }

    private static func hiddenOffsets(
        in linkRanges: [BlockInputInlineMarkdownRange],
        textLength: Int
    ) -> [Bool] {
        var hiddenOffsets = [Bool](repeating: false, count: textLength)
        for range in linkRanges.flatMap(\.delimiterRanges) {
            let clampedRange = NSIntersectionRange(range, NSRange(location: 0, length: textLength))
            guard clampedRange.length > 0 else {
                continue
            }
            for offset in clampedRange.location..<NSMaxRange(clampedRange) {
                hiddenOffsets[offset] = true
            }
        }
        return hiddenOffsets
    }

    private static func visibleOffsetTables(
        in text: NSString,
        hiddenOffsets: [Bool]
    ) -> BlockInputVisibleLinkOffsetTables {
        let textLength = text.length
        var sourceToVisibleOffsets = [Int](repeating: 0, count: textLength + 1)
        var visibleUTF16Length = 0
        let visibleString = NSMutableString()
        var visibleCharacters: [(sourceRange: NSRange, visibleRange: NSRange)] = []
        var offset = 0
        while offset < textLength {
            let characterRange = text.rangeOfComposedCharacterSequence(at: offset)
            for sourceOffset in characterRange.location..<NSMaxRange(characterRange) {
                sourceToVisibleOffsets[sourceOffset] = visibleUTF16Length
            }
            if !characterRange.intersectsHiddenOffset(in: hiddenOffsets) {
                let visibleRange = NSRange(location: visibleUTF16Length, length: characterRange.length)
                visibleString.append(text.substring(with: characterRange))
                visibleCharacters.append((sourceRange: characterRange, visibleRange: visibleRange))
                visibleUTF16Length += characterRange.length
            }
            offset = NSMaxRange(characterRange)
        }
        sourceToVisibleOffsets[textLength] = visibleUTF16Length

        var visibleToSourceBeforeNext = [Int](repeating: textLength, count: visibleUTF16Length + 1)
        var visibleToSourceAfterPrevious = [Int](repeating: 0, count: visibleUTF16Length + 1)
        for character in visibleCharacters {
            for visibleOffset in character.visibleRange.location..<NSMaxRange(character.visibleRange) {
                visibleToSourceBeforeNext[visibleOffset] = min(
                    visibleToSourceBeforeNext[visibleOffset],
                    character.sourceRange.location
                )
            }
            let visibleEnd = NSMaxRange(character.visibleRange)
            visibleToSourceAfterPrevious[visibleEnd] = NSMaxRange(character.sourceRange)
        }
        visibleToSourceBeforeNext[visibleUTF16Length] = textLength
        visibleToSourceAfterPrevious[0] = 0
        return BlockInputVisibleLinkOffsetTables(
            visibleText: visibleString as String,
            sourceToVisibleOffsets: sourceToVisibleOffsets,
            visibleToSourceBeforeNext: visibleToSourceBeforeNext,
            visibleToSourceAfterPrevious: visibleToSourceAfterPrevious
        )
    }

    func characterBoundaryTarget(
        from offset: Int,
        direction: BlockInputHorizontalMovementDirection
    ) -> HiddenLinkBoundaryTarget? {
        guard !linkRanges.isEmpty,
              characterBoundaryNeedsCustomMovement(from: offset, direction: direction),
              let sourceOffset = characterBoundary(from: offset, direction: direction),
              sourceOffset != offset || characterBoundaryTouchesLinkSourceEdge(from: offset, direction: direction) else {
            return nil
        }
        return HiddenLinkBoundaryTarget(
            range: NSRange(location: sourceOffset, length: 0),
            affinity: direction.selectionAffinity
        )
    }

    func characterBoundaryNeedsCustomMovement(
        from offset: Int,
        direction: BlockInputHorizontalMovementDirection
    ) -> Bool {
        characterBoundaryCrossesHiddenSource(from: offset, direction: direction) ||
            characterBoundaryTouchesLinkSourceEdge(from: offset, direction: direction)
    }

    func characterBoundaryCrossesHiddenSource(
        from offset: Int,
        direction: BlockInputHorizontalMovementDirection
    ) -> Bool {
        let clampedOffset = min(max(offset, 0), text.length)
        switch direction {
        case .leftward:
            guard clampedOffset > 0 else {
                return false
            }
            return hiddenOffsets[clampedOffset - 1]
        case .rightward:
            guard clampedOffset < text.length else {
                return false
            }
            return hiddenOffsets[clampedOffset]
        }
    }

    func characterBoundaryTouchesLinkSourceEdge(
        from offset: Int,
        direction: BlockInputHorizontalMovementDirection
    ) -> Bool {
        let clampedOffset = min(max(offset, 0), text.length)
        switch direction {
        case .leftward:
            return linkRanges.contains { $0.fullRange.location == clampedOffset }
        case .rightward:
            return linkRanges.contains { NSMaxRange($0.fullRange) == clampedOffset }
        }
    }

    func characterBoundary(
        from offset: Int,
        direction: BlockInputHorizontalMovementDirection
    ) -> Int? {
        guard !linkRanges.isEmpty else {
            return nil
        }
        switch direction {
        case .leftward:
            if let range = visibleCharacterRange(before: offset) {
                return range.location
            }
            return characterBoundaryNeedsCustomMovement(from: offset, direction: direction) ? 0 : nil
        case .rightward:
            if let range = visibleCharacterRange(after: offset) {
                return NSMaxRange(range)
            }
            return characterBoundaryNeedsCustomMovement(from: offset, direction: direction) ? text.length : nil
        }
    }

    @MainActor
    func wordBoundaryTarget(
        from offset: Int,
        direction: BlockInputWordMovementDirection
    ) -> HiddenLinkBoundaryTarget? {
        guard !linkRanges.isEmpty,
              !visibleText.isEmpty else {
            return nil
        }
        if let slashCommandTarget = slashCommandChipWordBoundary(from: offset, direction: direction) {
            return HiddenLinkBoundaryTarget(
                range: NSRange(location: slashCommandTarget, length: 0),
                affinity: direction.horizontalMovementDirection.selectionAffinity
            )
        }
        let visibleOffset = visibleOffset(forSourceOffset: offset)
        let targetVisibleOffset = nativeWordBoundary(in: visibleText, from: visibleOffset, direction: direction)
        if targetVisibleOffset == visibleOffset,
           let sourceOffset = linkSourceEdgeWordBoundary(from: offset, direction: direction) {
            return HiddenLinkBoundaryTarget(
                range: NSRange(location: sourceOffset, length: 0),
                affinity: direction.horizontalMovementDirection.selectionAffinity
            )
        }
        guard targetVisibleOffset != visibleOffset else {
            return nil
        }
        let sourceOffset = sourceOffset(forVisibleOffset: targetVisibleOffset, direction: direction)
        if let edgeOffset = linkSourceEdgeWordBoundary(from: offset, direction: direction),
           shouldPreferLinkSourceEdge(edgeOffset, over: sourceOffset, direction: direction) {
            return HiddenLinkBoundaryTarget(
                range: NSRange(location: edgeOffset, length: 0),
                affinity: direction.horizontalMovementDirection.selectionAffinity
            )
        }
        if sourceOffset == offset,
           let sourceOffset = linkSourceEdgeWordBoundary(from: offset, direction: direction) {
            return HiddenLinkBoundaryTarget(
                range: NSRange(location: sourceOffset, length: 0),
                affinity: direction.horizontalMovementDirection.selectionAffinity
            )
        }
        guard sourceOffset != offset else {
            return nil
        }
        return HiddenLinkBoundaryTarget(
            range: NSRange(location: sourceOffset, length: 0),
            affinity: direction.horizontalMovementDirection.selectionAffinity
        )
    }

    func selectionAnchorOffset(
        from offset: Int,
        direction: BlockInputHorizontalMovementDirection
    ) -> Int {
        let visibleOffset = visibleOffset(forSourceOffset: offset)
        switch direction {
        case .leftward:
            return sourceOffsetAfterPreviousVisibleCharacter(forVisibleOffset: visibleOffset)
        case .rightward:
            return sourceOffsetBeforeNextVisibleCharacter(forVisibleOffset: visibleOffset)
        }
    }

    private func visibleCharacterRange(before offset: Int) -> NSRange? {
        var searchOffset = min(max(offset, 0), text.length)
        while searchOffset > 0 {
            let candidate = text.rangeOfComposedCharacterSequence(at: searchOffset - 1)
            if !candidate.intersectsHiddenOffset(in: hiddenOffsets) {
                return candidate
            }
            searchOffset = candidate.location
        }
        return nil
    }

    private func visibleCharacterRange(after offset: Int) -> NSRange? {
        var searchOffset = min(max(offset, 0), text.length)
        while searchOffset < text.length {
            let candidate = text.rangeOfComposedCharacterSequence(at: searchOffset)
            if !candidate.intersectsHiddenOffset(in: hiddenOffsets) {
                return candidate
            }
            searchOffset = NSMaxRange(candidate)
        }
        return nil
    }

    private func slashCommandChipWordBoundary(from offset: Int, direction: BlockInputWordMovementDirection) -> Int? {
        guard let range = linkRanges.first(where: { $0.fullRange.containsOrTouches(offset) }),
              range.inlineChipKind(in: sourceText) == .slashCommand else {
            return nil
        }
        switch direction {
        case .leftward:
            guard offset > range.contentRange.location else {
                return nil
            }
            return range.contentRange.location
        case .rightward:
            guard offset < NSMaxRange(range.contentRange) else {
                return nil
            }
            return NSMaxRange(range.contentRange)
        }
    }

    private func linkSourceEdgeWordBoundary(from offset: Int, direction: BlockInputWordMovementDirection) -> Int? {
        let clampedOffset = min(max(offset, 0), text.length)
        switch direction {
        case .leftward:
            return linkRanges.last {
                NSMaxRange($0.fullRange) == clampedOffset && $0.contentRange.length > 0
            }?.contentRange.location
        case .rightward:
            return linkRanges.first {
                $0.fullRange.location == clampedOffset && $0.contentRange.length > 0
            }.map { NSMaxRange($0.contentRange) }
        }
    }

    private func shouldPreferLinkSourceEdge(
        _ edgeOffset: Int,
        over sourceOffset: Int,
        direction: BlockInputWordMovementDirection
    ) -> Bool {
        switch direction {
        case .leftward:
            return sourceOffset < edgeOffset
        case .rightward:
            return sourceOffset > edgeOffset
        }
    }

    private func visibleOffset(forSourceOffset offset: Int) -> Int {
        sourceToVisibleOffsets[min(max(offset, 0), text.length)]
    }

    private func sourceOffset(forVisibleOffset offset: Int, direction: BlockInputWordMovementDirection) -> Int {
        let visibleOffset = min(max(offset, 0), visibleText.utf16.count)
        switch direction {
        case .leftward:
            return sourceOffsetBeforeNextVisibleCharacter(forVisibleOffset: visibleOffset)
        case .rightward:
            return sourceOffsetAfterPreviousVisibleCharacter(forVisibleOffset: visibleOffset)
        }
    }

    private func sourceOffsetBeforeNextVisibleCharacter(forVisibleOffset offset: Int) -> Int {
        visibleToSourceBeforeNext[min(max(offset, 0), visibleToSourceBeforeNext.count - 1)]
    }

    private func sourceOffsetAfterPreviousVisibleCharacter(forVisibleOffset offset: Int) -> Int {
        visibleToSourceAfterPrevious[min(max(offset, 0), visibleToSourceAfterPrevious.count - 1)]
    }

    @MainActor
    private func nativeWordBoundary(
        in text: String,
        from offset: Int,
        direction: BlockInputWordMovementDirection
    ) -> Int {
        let textView = NSTextView(frame: .zero)
        textView.string = text
        textView.setSelectedRange(NSRange(location: min(max(offset, 0), (text as NSString).length), length: 0))
        switch direction {
        case .leftward:
            textView.moveWordLeft(nil)
        case .rightward:
            textView.moveWordRight(nil)
        }
        return textView.selectedRange().location
    }
}

struct HiddenLinkBoundaryTarget {
    let range: NSRange
    let affinity: NSSelectionAffinity
}

private struct BlockInputVisibleLinkOffsetTables {
    let visibleText: String
    let sourceToVisibleOffsets: [Int]
    let visibleToSourceBeforeNext: [Int]
    let visibleToSourceAfterPrevious: [Int]
}

private extension BlockInputHorizontalMovementDirection {
    var selectionAffinity: NSSelectionAffinity {
        switch self {
        case .leftward:
            return .upstream
        case .rightward:
            return .downstream
        }
    }
}

private extension NSRange {
    func intersectsHiddenOffset(in hiddenOffsets: [Bool]) -> Bool {
        let upperBound = min(NSMaxRange(self), hiddenOffsets.count)
        guard location < upperBound else {
            return false
        }
        return (max(location, 0)..<upperBound).contains { hiddenOffsets[$0] }
    }

    func activeWordSelectionOffset(for direction: BlockInputWordMovementDirection) -> Int {
        switch direction {
        case .leftward:
            return location
        case .rightward:
            return NSMaxRange(self)
        }
    }

    func wordSelectionAnchor(for direction: BlockInputWordMovementDirection) -> Int {
        switch direction {
        case .leftward:
            return NSMaxRange(self)
        case .rightward:
            return location
        }
    }
}
