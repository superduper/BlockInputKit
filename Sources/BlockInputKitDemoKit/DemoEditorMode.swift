enum DemoEditorMode: Int, CaseIterable, Hashable {
    case raw
    case rendered

    var title: String {
        switch self {
        case .raw:
            "Raw"
        case .rendered:
            "Rendered"
        }
    }
}
