import AppKit
@testable import BlockInputKit

extension BlockInputViewSnapshotTests {
    func makeCustomYellowChipStyleSnapshotView() -> NSView {
        let size = CGSize(width: 620, height: 150)
        let host = NSView(frame: NSRect(origin: .zero, size: size))
        host.appearance = NSAppearance(named: .aqua)
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor(srgbRed: 0.98, green: 0.94, blue: 0.78, alpha: 1).cgColor

        let view = BlockInputView(frame: NSRect(origin: .zero, size: size))
        view.appearance = NSAppearance(named: .aqua)
        host.addSubview(view)

        let yellowFill = NSColor(srgbRed: 0.91, green: 0.70, blue: 0.18, alpha: 0.52)
        let yellowStroke = NSColor(srgbRed: 0.72, green: 0.50, blue: 0.10, alpha: 0.65)
        let chipStyle = BlockInputInlineChipStyle(
            fillColor: yellowFill,
            strokeColor: yellowStroke,
            foregroundColor: .labelColor,
            cornerRadius: 5
        )
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(
                    id: "paragraph",
                    text: "Open [README.md](file:///tmp/README.md), run [/table](host-app://commands/table), or type /review"
                )
            ]),
            allowsBlockReordering: false,
            rawSlashCommandChips: true,
            style: BlockInputStyle(
                editorSurface: BlockInputEditorSurfaceStyle(
                    editorBackgroundColor: nil,
                    scrollBackgroundColor: nil,
                    collectionBackgroundColor: nil
                ),
                fileChip: chipStyle,
                slashCommandChip: chipStyle,
                rawSlashCommandChip: chipStyle
            ),
            slashCommandAvailability: .anywhere
        ))
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        return host
    }
}
