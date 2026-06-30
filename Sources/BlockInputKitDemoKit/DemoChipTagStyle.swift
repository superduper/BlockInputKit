/// Demo-selectable file-chip tag styles, so the toolbar dropdown can preview each layout the file-chip accessory
/// supports. This core (plugin-free) part holds only the cases and their titles; the `BlockInputKitPaste`-backed
/// accessory mapping (`typeTagStyle`, `accessoryProvider()`) lives in the demo executable target.
public enum DemoChipTagStyle: CaseIterable, Hashable {
    case iconPillLeading
    case iconPillTrailing
    case iconOnly
    case pillOnly
    case none

    public var title: String {
        switch self {
        case .iconPillLeading: return "Icon + tag (leading)"
        case .iconPillTrailing: return "Icon + tag (trailing)"
        case .iconOnly: return "Icon only"
        case .pillOnly: return "Tag only"
        case .none: return "None"
        }
    }
}
