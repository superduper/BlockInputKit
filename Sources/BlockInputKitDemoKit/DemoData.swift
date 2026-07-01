import BlockInputKit
import Foundation

enum DemoData {
    static let largeDocumentBlockCount = 100_000
    static let progressiveLoadBatchLimit = 5_000

    static func mixedDocument() -> BlockInputDocument {
        BlockInputDocument(blocks: overviewIntroBlocks + overviewListBlocks + overviewMediaBlocks)
    }

    static func largeDocument(count: Int = 100_000) -> BlockInputDocument {
        let blocks = (0..<count).map(largeBlock)
        return BlockInputDocument(blocks: blocks)
    }

    static func largeBlock(at index: Int) -> BlockInputBlock {
        let id = BlockInputBlockID(rawValue: "large-\(index)")
        switch index % 8 {
        case 0:
            return BlockInputBlock(id: id, kind: .paragraph, text: "Paragraph block \(index)")
        case 1:
            return BlockInputBlock(id: id, kind: .heading(level: (index % 3) + 1), text: "Heading block \(index)")
        case 2:
            return BlockInputBlock(id: id, kind: .quote, text: "Quote block \(index)")
        case 3:
            return BlockInputBlock(id: id, kind: .bulletedListItem, text: "Bullet block \(index)", indentationLevel: index % 3)
        case 4:
            return BlockInputBlock(id: id, kind: .numberedListItem(start: index + 1), text: "Numbered block \(index)")
        case 5:
            return BlockInputBlock(id: id, kind: .checklistItem(isChecked: index.isMultiple(of: 2)), text: "Checklist block \(index)")
        case 6:
            return BlockInputBlock(id: id, kind: .horizontalRule)
        default:
            return BlockInputBlock(id: id, kind: .code(language: "swift"), text: "let index = \(index)")
        }
    }

    private static var overviewIntroBlocks: [BlockInputBlock] {
        [
            BlockInputBlock(kind: .frontMatter, text: "title: BlockInputKit Overview\nstatus: demo"),
            BlockInputBlock(kind: .heading(level: 1), text: "BlockInputKit overview"),
            BlockInputBlock(kind: .paragraph, text: """
            Native AppKit block editing with Markdown import/export, selection, undo, reordering, files, images, and tables.
            """),
            // With the BlockInputKitToc plugin wired (the plugins demo), this ```toc fence renders a live, clickable
            // table of contents of the document's H2–H4 headings. In the core-only demo it shows as a plain code block.
            BlockInputBlock(kind: .code(language: "toc"), text: """
            # minLevel/maxLevel (1-6); include/skip globs
            minLevel: 2
            maxLevel: 4
            """),
            BlockInputBlock(kind: .heading(level: 2), text: "Text blocks"),
            BlockInputBlock(kind: .heading(level: 3), text: "Headings level 3"),
            BlockInputBlock(kind: .heading(level: 4), text: "Headings level 4"),
            BlockInputBlock(kind: .heading(level: 5), text: "Headings level 5"),
            BlockInputBlock(kind: .heading(level: 6), text: "Headings level 6"),
            BlockInputBlock(kind: .paragraph, text: """
            Inline items include **bold**, *italic*, <u>underline</u>, ~~strikethrough~~, `inline code`, \
            [a normal link](https://github.com/afollestad/BlockInputKit), [README.md](file:///tmp/README.md), \
            and [/quote](blockinputkit-demo://commands/quote).
            """),
            BlockInputBlock(kind: .heading(level: 3), text: "Heading anchors"),
            BlockInputBlock(kind: .paragraph, text: """
            Clicking a [#slug](#heading-anchors) link scrolls to the matching heading — no host wiring needed. \
            Try [jump to Diagrams](#diagrams) or [jump to Tables](#tables) to see it in action.
            """),
            BlockInputBlock(kind: .heading(level: 3), text: "Wikilinks"),
            BlockInputBlock(kind: .paragraph, text: """
            Wikilinks show only their title: a bare [[baz/Foo]] resolves to its note title and rewrites itself \
            to the editable alias form, while [[a/B|C]] hides the `a/B|` target and the brackets so it reads `C`. \
            Edit the visible title inline to rename the alias; type `[[` and three or more characters to fuzzy-search \
            notes; click a wikilink to load it, or hover to Open/Edit. \
            A regular [label](https://example.com) link renders collapsed with the hover Edit affordance.
            """),
            BlockInputBlock(kind: .quote, text: "Focus, selection, return, delete, and Cmd+A coordinate across blocks."),
            BlockInputBlock(kind: .code(language: "swift"), text: """
            let editor = BlockInputView()
            editor.configure(BlockInputConfiguration(document: document, placeholder: "Start writing..."))
            editor.focusEditor()
            """),
            BlockInputBlock(kind: .heading(level: 3), text: "Diagrams"),
            BlockInputBlock(kind: .paragraph, text: """
            A ```mermaid code fence renders inline through the host-supplied content renderer. This demo shows a \
            placeholder image (no JavaScript engine bundled); click the diagram to select it, or the ⤢ button to zoom.
            """),
            BlockInputBlock(kind: .code(language: "mermaid"), text: """
            graph TD
                A[Start] --> B{Decision}
                B -->|Yes| C[Render diagram]
                B -->|No| D[Show code]
            """),
            BlockInputBlock(kind: .heading(level: 3), text: "AI / Vibe mode + Fix with AI"),
            BlockInputBlock(kind: .paragraph, text: """
            Click ✏️ on a diagram to open the floating editor, then toggle Code | AI in the header to chat with \
            the host agent (try "make it left to right"). The demo wires a scripted DemoMockDiagramAIProvider — no \
            API key needed. The diagram below is deliberately BROKEN (a dangling edge): open it, and the preview \
            shows Mermaid's real parse error plus a "Fix with AI" button that asks the agent to repair the source. \
            Cmd+Z while the panel is open undoes the last AI edit.
            """),
            BlockInputBlock(kind: .code(language: "mermaid"), text: """
            graph TD
                A -->
            """),
            BlockInputBlock(kind: .horizontalRule)
        ]
    }

    private static var overviewListBlocks: [BlockInputBlock] {
        [
            BlockInputBlock(kind: .heading(level: 2), text: "Lists and tasks"),
            BlockInputBlock(
                kind: .bulletedListItem,
                text: "Bulleted list item\nNested bullet item\nDeep nested bullet item",
                lineIndentationLevels: [0, 1, 2]
            ),
            BlockInputBlock(
                kind: .numberedListItem(start: 1),
                text: "Numbered list item\nNested numbered item\nDeep nested numbered item",
                lineIndentationLevels: [0, 1, 2]
            ),
            BlockInputBlock(kind: .checklistItem(isChecked: false), text: "Unchecked checklist item"),
            BlockInputBlock(kind: .checklistItem(isChecked: true), text: "Checked checklist item"),
            BlockInputBlock(kind: .heading(level: 2), text: "Tables")
        ]
    }

    private static var overviewMediaBlocks: [BlockInputBlock] {
        [
            BlockInputBlock(kind: .table, text: """
            | Feature area | Renderer | Editing behavior | Notes for the demo |
            | --- | :---: | --- | --- |
            | Tables | Structured | Cell text, rows, columns, and selection | Wide content scrolls horizontally inside the editor |
            | Images | Standalone | Resize handles and Markdown export | This demo uses a bundled local resource |
            """),
            BlockInputBlock(kind: .heading(level: 2), text: "Images"),
            BlockInputBlock(kind: .image(BlockInputImage(
                source: "willriver_falls.jpg",
                altText: "Willriver Falls",
                width: 480,
                height: 320
            )))
        ]
    }
}
