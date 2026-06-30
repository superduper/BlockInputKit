import AppKit

/// Layout-manager delegate that collapses attributed Markdown source delimiters into zero-width glyphs.
///
/// Hidden delimiters (markdown markers, hidden wikilink `target|` sub-ranges) are marked in storage with
/// `.blockInputHiddenDelimiter` and rendered as null glyphs so they keep no advance. The delegate never changes
/// the glyph count, so NSLayoutManager line-fragment generation stays intact.
final class BlockInputDelimiterGlyphs: NSObject, NSLayoutManagerDelegate {
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard glyphRange.length > 0,
              let textStorage = layoutManager.textStorage else {
            return 0
        }
        let glyphBuffer = Array(UnsafeBufferPointer(start: glyphs, count: glyphRange.length))
        var propertyBuffer = Array(UnsafeBufferPointer(start: props, count: glyphRange.length))
        let characterIndexBuffer = Array(UnsafeBufferPointer(start: charIndexes, count: glyphRange.length))
        let didHideDelimiters = hideDelimiterGlyphs(
            textStorage: textStorage,
            properties: &propertyBuffer,
            characterIndexes: characterIndexBuffer
        )
        guard didHideDelimiters else {
            return 0
        }
        var mutableGlyphBuffer = glyphBuffer
        var mutableCharacterIndexBuffer = characterIndexBuffer
        layoutManager.setGlyphs(
            &mutableGlyphBuffer,
            properties: &propertyBuffer,
            characterIndexes: &mutableCharacterIndexBuffer,
            font: font,
            forGlyphRange: glyphRange
        )
        return glyphBuffer.count
    }

    private func hideDelimiterGlyphs(
        textStorage: NSTextStorage,
        properties propertyBuffer: inout [NSLayoutManager.GlyphProperty],
        characterIndexes characterIndexBuffer: [Int]
    ) -> Bool {
        var hasHiddenDelimiter = false
        for index in propertyBuffer.indices {
            let characterIndex = characterIndexBuffer[index]
            guard characterIndex >= 0,
                  characterIndex < textStorage.length,
                  textStorage.attribute(.blockInputHiddenDelimiter, at: characterIndex, effectiveRange: nil) as? Bool == true else {
                continue
            }
            // A hidden chrome character can carry a painted accessory (the link "open" icon, or a file chip's leading or
            // trailing accessory). Keep its glyph and the `.kern`-reserved advance; null-glyphing it collapses the gap.
            let carriesOpenIcon = textStorage.attribute(.blockInputLinkOpenIcon, at: characterIndex, effectiveRange: nil) != nil
            let carriesLeadingChipAccessory =
                textStorage.attribute(.blockInputChipLeadingAccessory, at: characterIndex, effectiveRange: nil) != nil
            let carriesTrailingChipAccessory =
                textStorage.attribute(.blockInputChipTrailingAccessory, at: characterIndex, effectiveRange: nil) != nil
            if carriesOpenIcon || carriesLeadingChipAccessory || carriesTrailingChipAccessory {
                continue
            }
            // Clear foreground hides delimiter drawing, but null glyphs remove
            // their advance so hidden Markdown markers do not read as spaces.
            propertyBuffer[index].insert(.null)
            hasHiddenDelimiter = true
        }
        return hasHiddenDelimiter
    }
}

extension NSAttributedString.Key {
    /// Marks visual inline chip content so adjacent virtual hints can fall back to the normal typing font.
    static let blockInputInlineChip = NSAttributedString.Key("BlockInputInlineChip")
    /// Marks source delimiters/tags that should stay in storage but collapse out of visual layout.
    static let blockInputHiddenDelimiter = NSAttributedString.Key("BlockInputHiddenDelimiter")
}
