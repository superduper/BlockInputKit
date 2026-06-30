extension BlockInputBlockKind {
    var repeatsPrefixForTextLines: Bool {
        switch self {
        case .quote, .bulletedListItem, .numberedListItem:
            return true
        case .paragraph, .heading, .code, .horizontalRule, .frontMatter, .checklistItem, .table, .image, .rawMarkdown:
            return false
        }
    }
}
