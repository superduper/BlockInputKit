import Foundation

public extension BlockInputView {
    /// Parses Markdown into blocks and inserts them below a block, or below the active block by default.
    ///
    /// If the document only contains the default empty paragraph, the parsed blocks replace
    /// that placeholder. The edit is recorded on the structural undo stack.
    @discardableResult
    func insertMarkdown(
        _ markdown: String,
        below blockID: BlockInputBlockID? = nil
    ) -> BlockInputSelection? {
        guard isEditable else {
            return nil
        }
        let trimmedMarkdown = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMarkdown.isEmpty else {
            return nil
        }

        let parsedBlocks = BlockInputDocument(markdown: markdown, imageParsingMode: markdownInsertionImageParsingMode).blocks
        let targetBlockID = blockID ?? activeBlockID
        if let targetBlockID, index(of: targetBlockID) == nil {
            return nil
        }

        let result = performStructuralEdit(
            named: "Insert Markdown",
            storeSyncAction: { beforeDocument, _, _ in
                if beforeDocument.blocks.count == 1,
                   beforeDocument.blocks[0].kind == .paragraph,
                   beforeDocument.blocks[0].isEmpty {
                    return .replaceDocument
                }
                let insertionIndex = markdownInsertionIndex(below: targetBlockID, in: beforeDocument)
                    ?? beforeDocument.blocks.count
                let insertedBlocks = frontMatterDowngradedBlocks(parsedBlocks, sourceMarkdown: markdown)
                return .insertBlocks(insertedBlocks, insertionIndex: insertionIndex)
            },
            edit: { document in
                if document.blocks.count == 1,
                   document.blocks[0].kind == .paragraph,
                   document.blocks[0].isEmpty {
                    document.blocks = parsedBlocks
                    guard let firstBlock = parsedBlocks.first else {
                        return nil
                    }
                    return .cursor(BlockInputCursor(blockID: firstBlock.id, utf16Offset: 0))
                }

                guard let insertionIndex = markdownInsertionIndex(below: targetBlockID, in: document) else {
                    return nil
                }
                let insertedBlocks = frontMatterDowngradedBlocks(parsedBlocks, sourceMarkdown: markdown)
                return document.insertBlocks(insertedBlocks, at: insertionIndex)
            }
        )
        scrollActiveTextSelectionToVisibleIfNeeded()
        return result
    }

    private func markdownInsertionIndex(
        below targetBlockID: BlockInputBlockID?,
        in document: BlockInputDocument
    ) -> Int? {
        if let targetBlockID {
            return document.index(of: targetBlockID).map { $0 + 1 }
        }
        return document.blocks.count
    }

    private var markdownInsertionImageParsingMode: BlockInputMarkdownImageParsingMode {
        imagePresentation == .textLinksWithPreviewStrip ? .preserveSourceText : .imageBlocks
    }
}

private func frontMatterDowngradedBlocks(_ blocks: [BlockInputBlock], sourceMarkdown: String) -> [BlockInputBlock] {
    let frontMatterSource = leadingFrontMatterSource(in: sourceMarkdown)
    return blocks.map { block in
        guard block.kind == .frontMatter else {
            return block
        }
        // Frontmatter is meaningful only at document start; pasted mid-document
        // source stays editable and round-trippable as raw Markdown. Use the
        // original source slice so delimiter style, including `...`, survives.
        return BlockInputBlock(
            id: block.id,
            kind: .rawMarkdown,
            text: frontMatterSource ?? BlockInputDocument(blocks: [block]).markdown
        )
    }
}

private func leadingFrontMatterSource(in markdown: String) -> String? {
    let lines = BlockInputLineBreaks.lines(in: markdown)
    guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
        return nil
    }
    for index in lines.indices.dropFirst() {
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        if trimmed == "---" || trimmed == "..." {
            var upperBound = index
            var lookahead = lines.index(after: index)
            while lookahead < lines.endIndex,
                  lines[lookahead].trimmingCharacters(in: .whitespaces).isEmpty {
                upperBound = lookahead
                lookahead = lines.index(after: lookahead)
            }
            return lines[0...upperBound].joined(separator: "\n")
        }
    }
    return nil
}
