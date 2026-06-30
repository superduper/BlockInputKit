import AppKit

private let promisedFileURLPasteboardType = NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")

extension BlockInputTextView {
    func configureFileDropHandling() {
        registerForDraggedTypes([.fileURL])
        fileDropCaretView.wantsLayer = true
        fileDropCaretView.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        fileDropCaretView.layer?.cornerRadius = 1
        fileDropCaretView.isHidden = true
        fileDropCaretView.setAccessibilityElement(false)
        addSubview(fileDropCaretView)
    }

    func hideFileDropCaret() {
        fileDropCaretView.isHidden = true
    }

    func updateFileDropCaretColor(_ color: NSColor) {
        fileDropCaretView.layer?.backgroundColor = color.cgColor
    }

    func handlesFileDropPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        if pasteboard.string(forType: .blockInputBlockID) != nil {
            return true
        }
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: nil) {
            return true
        }
        return pasteboard.types?.contains(promisedFileURLPasteboardType) == true
    }

    func fileDropOperation(_ sender: NSDraggingInfo, _ nativeOperation: @autoclosure () -> NSDragOperation) -> NSDragOperation {
        handlesFileDropPasteboard(sender.draggingPasteboard) ? validateFileDrop(sender) : nativeOperation()
    }

    func prepareFileDropOperation(_ sender: NSDraggingInfo, _ nativePreparation: @autoclosure () -> Bool) -> Bool {
        handlesFileDropPasteboard(sender.draggingPasteboard) ? fileDropTarget(for: sender) != nil : nativePreparation()
    }

    func performFileDropOperation(_ sender: NSDraggingInfo, _ nativeDrop: @autoclosure () -> Bool) -> Bool {
        handlesFileDropPasteboard(sender.draggingPasteboard) ? performFileDrop(sender) : nativeDrop()
    }

    func validateFileDrop(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard blockItem?.isEditable != false,
              let target = fileDropTarget(for: sender) else {
            hideFileDropCaret()
            return []
        }
        showFileDropCaret(atUTF16Offset: target.utf16Offset)
        return .copy
    }

    func performFileDrop(_ sender: NSDraggingInfo) -> Bool {
        defer { hideFileDropCaret() }
        guard let target = fileDropTarget(for: sender) else {
            return false
        }
        return blockItem?.requestInsertFileURLs(target.fileURLs, atUTF16Offset: target.utf16Offset) == true
    }

    func fileDropTarget(for draggingInfo: NSDraggingInfo) -> BlockInputFileDropTarget? {
        guard draggingInfo.draggingPasteboard.string(forType: .blockInputBlockID) == nil,
              let blockItem,
              blockItem.isEditable,
              let block = blockItem.renderedBlock,
              BlockInputBlockItem.supportsInlineMarkdownStyling(block.kind) else {
            return nil
        }
        let fileURLs = BlockInputView.fileURLs(from: draggingInfo.draggingPasteboard)
        guard !fileURLs.isEmpty else {
            return nil
        }
        let localLocation = convert(draggingInfo.draggingLocation, from: nil)
        guard bounds.contains(localLocation) else {
            return nil
        }
        let offset = fileDropUTF16Offset(at: localLocation, in: block.text)
        return BlockInputFileDropTarget(fileURLs: fileURLs, utf16Offset: offset)
    }

    private func fileDropUTF16Offset(at localLocation: NSPoint, in text: String) -> Int {
        let initialOffset = characterIndexForInsertion(at: localLocation)
        let clampedOffset = min(max(initialOffset, 0), (text as NSString).length)
        guard let chipRange = inlineChipRange(containing: clampedOffset, in: text) else {
            return clampedOffset
        }
        let chipMidX = inlineChipMidX(for: chipRange.contentRange) ?? {
            let contentMidpoint = chipRange.contentRange.location + chipRange.contentRange.length / 2
            return clampedOffset <= contentMidpoint ? localLocation.x + 1 : localLocation.x - 1
        }()
        return localLocation.x < chipMidX ? chipRange.fullRange.location : NSMaxRange(chipRange.fullRange)
    }

    private func inlineChipRange(containing offset: Int, in text: String) -> BlockInputInlineMarkdownRange? {
        let inlineCodeRanges = BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange)
        return BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text, excluding: inlineCodeRanges, fileBaseURL: blockItem?.fileBaseURL)
            .first { range in
                range.inlineChipKind(in: text) != nil &&
                    range.fullRange.location <= offset &&
                    offset <= NSMaxRange(range.fullRange)
            }
    }

    private func inlineChipMidX(for contentRange: NSRange) -> CGFloat? {
        guard let layoutManager,
              let textContainer,
              contentRange.length > 0 else {
            return nil
        }
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: contentRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else {
            return nil
        }
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        return rect.midX
    }

    private func showFileDropCaret(atUTF16Offset offset: Int) {
        guard let frame = fileDropCaretFrame(atUTF16Offset: offset) else {
            hideFileDropCaret()
            return
        }
        fileDropCaretView.frame = frame
        fileDropCaretView.isHidden = false
    }

    private func fileDropCaretFrame(atUTF16Offset offset: Int) -> NSRect? {
        guard let window else {
            return nil
        }
        let clampedOffset = min(max(offset, 0), (string as NSString).length)
        let rect = firstRect(forCharacterRange: NSRange(location: clampedOffset, length: 0), actualRange: nil)
        guard rect != .zero, !rect.isNull, !rect.isInfinite else {
            return nil
        }
        let windowPoint = window.convertPoint(fromScreen: NSPoint(x: rect.minX, y: rect.maxY))
        let localPoint = convert(windowPoint, from: nil)
        return NSRect(
            x: localPoint.x,
            y: localPoint.y,
            width: 2,
            height: max(rect.height, font?.boundingRectForFont.height ?? 14)
        )
    }
}

struct BlockInputFileDropTarget {
    var fileURLs: [URL]
    var utf16Offset: Int
}
