import AppKit

extension BlockInputBlockItem {
    func selectedLogicalListLineStartBackgroundFrames(
        for range: NSRange,
        layoutManager: NSLayoutManager
    ) -> [NSRect] {
        // AppKit can fold a selected newline into the previous fragment, which leaves Shift+Right over a nested list
        // boundary with chrome on the old line only. Add a logical-line segment when the first visible list character
        // is selected so the nested marker joins the selection immediately.
        guard !kindLabel.markerLines.isEmpty else {
            return []
        }
        let text = textView.string as NSString
        let lineStarts = BlockInputLineBreaks.lineStartOffsets(in: textView.string)
        let selectedEnd = NSMaxRange(range)
        return lineStarts.enumerated().compactMap { lineIndex, lineStart in
            guard range.location <= lineStart,
                  selectedEnd > lineStart,
                  lineStart < text.length,
                  let markerBounds = selectedMarkerLineBounds(forLineAt: lineIndex) else {
                return nil
            }
            let nextLineStart = lineStarts.indices.contains(lineIndex + 1) ? lineStarts[lineIndex + 1] : text.length
            let lineEnd = max(lineStart, nextLineStart - lineEndingLength(before: nextLineStart, in: text))
            let textEnd = min(max(selectedEnd, lineStart + 1), lineEnd)
            guard textEnd > lineStart else {
                return markerBounds
            }
            return markerBounds.union(logicalListLineTextFrame(
                lineStart: lineStart,
                textEnd: textEnd,
                layoutManager: layoutManager
            ))
        }
    }

    func selectedMarkerLineBounds(forLineAt lineIndex: Int) -> NSRect? {
        guard let markerFrame = kindLabel.markerLineFrame(at: lineIndex) else {
            return nil
        }
        return kindLabel.convert(markerFrame, to: view)
    }

    private func logicalListLineTextFrame(
        lineStart: Int,
        textEnd: Int,
        layoutManager: NSLayoutManager
    ) -> NSRect {
        let textLength = (textView.string as NSString).length
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: min(lineStart, max(textLength - 1, 0)))
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let startX = textContainerX(forUTF16Offset: lineStart) ?? lineRect.minX
        let endX = textContainerX(forUTF16Offset: textEnd) ?? max(startX + 1, lineRect.maxX)
        let textOrigin = textView.textContainerOrigin
        return textView.convert(NSRect(
            x: textOrigin.x + min(startX, endX),
            y: textOrigin.y + lineRect.minY,
            width: max(abs(endX - startX), 1),
            height: max(lineRect.height, 1)
        ), to: view)
    }

    private func lineEndingLength(before lineStart: Int, in text: NSString) -> Int {
        guard lineStart > 0, lineStart <= text.length else {
            return 0
        }
        let previous = text.character(at: lineStart - 1)
        guard previous.isLineEnding else {
            return 0
        }
        if previous.isLineFeed,
           lineStart > 1,
           text.character(at: lineStart - 2).isCarriageReturn {
            return 2
        }
        return 1
    }
}

extension Array where Element == NSRect {
    func mergingSelectionChromeFrames(_ framesToMerge: [NSRect]) -> [NSRect] {
        framesToMerge.reduce(into: self) { frames, frame in
            if let index = frames.firstIndex(where: { $0.verticallyOverlaps(frame) }) {
                frames[index] = frames[index].union(frame)
            } else {
                frames.append(frame)
            }
        }
    }
}

private extension NSRect {
    func verticallyOverlaps(_ other: NSRect) -> Bool {
        min(maxY, other.maxY) > max(minY, other.minY)
    }
}
