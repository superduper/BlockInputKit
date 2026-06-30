import AppKit

extension BlockInputTextView {
    func performPasteFromEditorCommand() {
        guard blockItem?.isEditable != false else {
            return
        }
        // Registered paste handlers (e.g. images, files, rich text) get first refusal; unclaimed content falls through.
        // Resolution is async, so on decline the editor calls back into `pasteAfterRichContentDeclined` to run the
        // remaining native paste path (URL paste, then AppKit), instead of silently swallowing the paste.
        if blockItem?.requestPasteRichContent(
            atUTF16Offset: blockInputSourceSelectedRange().location,
            onDeclined: { [weak self] in self?.pasteAfterRichContentDeclined() }
        ) == true {
            return
        }
        pasteAfterRichContentDeclined()
    }

    /// The native paste path used when no rich-content handler claims the pasteboard: supported-URL paste, else AppKit.
    func pasteAfterRichContentDeclined() {
        guard blockItem?.isEditable != false else {
            return
        }
        if let urlString = BlockInputLinkURL.supportedURLString(),
           blockItem?.requestPasteURL(urlString, selectedRange: blockInputSourceSelectedRange()) == true {
            return
        }
        super.paste(nil)
    }

    func copySelectedPlainText(allowingEditorRoute: Bool = true) -> Bool {
        let range = selectedRange()
        let copiedText: String?
        if blockItem?.isTableCellTextView(self) == true {
            if allowingEditorRoute, blockItem?.requestCopyActiveSelection() == true {
                return true
            }
            let clampedRange = string.blockInputTextViewClampedRange(range)
            copiedText = BlockInputBlock(text: string).markdownAwareCopiedText(in: clampedRange, fileBaseURL: blockItem?.fileBaseURL)
        } else if var block = blockItem?.renderedBlock {
            block.text = string
            copiedText = block.markdownAwareCopiedText(in: range, fileBaseURL: blockItem?.fileBaseURL)
        } else {
            let clampedRange = string.blockInputTextViewClampedRange(range)
            copiedText = clampedRange.length > 0
                ? (string as NSString).substring(with: clampedRange)
                : nil
        }
        guard let copiedText, !copiedText.isEmpty else {
            return false
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copiedText, forType: .string)
        return true
    }
}
