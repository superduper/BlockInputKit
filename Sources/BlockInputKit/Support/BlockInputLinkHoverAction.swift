import Foundation

/// A host-supplied extra button shown in the inline-link hover affordance (e.g. "Show in Finder" for a file chip).
///
/// Core renders the title and runs `perform` when the button is clicked; the action policy stays in the host.
public struct BlockInputLinkHoverAction {
    /// Button title.
    public var title: String
    /// Action to run when the button is clicked.
    public var perform: @MainActor () -> Void

    /// Creates a hover action.
    public init(title: String, perform: @escaping @MainActor () -> Void) {
        self.title = title
        self.perform = perform
    }
}

/// Context describing the hovered inline link an action list is requested for.
public struct BlockInputLinkHoverActionContext {
    /// The hovered link's resolved destination URL.
    public var destination: URL
    /// Block that owns the hovered link.
    public var blockID: BlockInputBlockID
    /// Classified link kind (e.g. `.fileChip`).
    public var kind: BlockInputInlineLinkKind

    /// Creates hover-action context.
    public init(destination: URL, blockID: BlockInputBlockID, kind: BlockInputInlineLinkKind) {
        self.destination = destination
        self.blockID = blockID
        self.kind = kind
    }
}
