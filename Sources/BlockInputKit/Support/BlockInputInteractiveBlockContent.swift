import AppKit

/// Generic interactive-editing + AI seam for a rendered ` ```foo ` block.
///
/// A plugin supplies a `View` (and optionally an `AIBackend`) keyed by the block's `contentIdentifier`;
/// core hosts the view and persists edited source. Diagrams/Mermaid are one consumer — core knows no
/// content grammar. A ` ```toc `, ` ```chart `, or any future fence plugin uses the same seam (or only
/// the subset it needs). The render seam (`BlockInputBlockContentRendering`) handles display; this seam
/// handles interactive editing on top of it.
public enum BlockInputInteractiveBlockContent {
    /// Host hook that builds a plugin-owned interactive view for a content block, keyed by its
    /// `contentIdentifier`. Returns nil when no plugin handles that content.
    public typealias Provider = @MainActor (Context) -> (any View)?

    /// Outcome of validating candidate source: a rendered image, or a failure with a message a plugin's
    /// AI agent can feed back into its next attempt.
    public enum Validation: Sendable {
        case valid(BlockInputRenderedImage)
        case invalid(message: String)
    }

    /// A turn of agent progress, surfaced to the plugin's chat UI.
    public enum AIEvent: Sendable {
        case status(String)            // "rendering…", "attempt 2/4"
        case assistantMessage(String)  // chat text from the agent
        case candidate(String)         // a source the agent is trying (optional, for live code peek)
    }

    /// Author of an ``AIMessage`` turn.
    public enum AIMessageRole: Sendable { case user, assistant }

    /// One turn of an authoring conversation, surfaced to the plugin's chat UI. Editor-session state the host
    /// cannot reconstruct; supplied to `AIBackend.converse`.
    public struct AIMessage: Sendable {
        public let role: AIMessageRole
        public let text: String
        public init(role: AIMessageRole, text: String) {
            self.role = role
            self.text = text
        }
    }

    /// The outcome the agent returns for a turn. The editor renders each differently (a chat question vs. a
    /// diagram to validate+apply) — a display distinction, not agent machinery.
    public enum AITurn: Sendable {
        case question(String)
        case candidate(String)
    }

    /// Host-supplied AI backend (the LLM/agent) for an interactive content plugin. Renderer-agnostic: the
    /// PLUGIN owns the AI-fix UI and drives this backend; the host implements only the model call. The
    /// backend is a rewrite contract a plugin consumes (not core UI).
    public protocol AIBackend: Sendable {
        /// Rewrite `source` per `instruction`. The PLUGIN validates the returned source by rendering it
        /// in-page; the backend is a pure model call. `onEvent` streams progress into the plugin's chat UI.
        func rewrite(
            source: String,
            instruction: String,
            contentIdentifier: String,
            onEvent: @Sendable @MainActor (AIEvent) -> Void
        ) async -> Result<String, Error>

        /// Multi-turn authoring: given the current `source` and the full `messages` conversation (incl. the
        /// latest user turn), the host agent returns either a clarifying `.question` or a diagram `.candidate`.
        /// The PLUGIN validates a candidate by rendering. `onEvent` streams status/assistant text. Has a
        /// default that adapts `rewrite`, so backends implementing only `rewrite` keep working.
        func converse(
            contentIdentifier: String,
            blockID: BlockInputBlockID,
            source: String,
            messages: [AIMessage],
            onEvent: @Sendable @MainActor (AIEvent) -> Void
        ) async -> Result<AITurn, Error>
    }

    /// Everything a plugin needs to build an interactive content view: the content id, the current source,
    /// the renderer `validate` oracle (for live preview / a fix loop), and the optional host AI backend.
    public struct Context: Sendable {
        public var contentIdentifier: String
        public var source: String
        public var validate: @Sendable (String) async -> Validation
        public var aiBackend: (any AIBackend)?
        /// When true (the "Fix with AI" entry point on a failed render), the view should open straight into
        /// AI mode and auto-run a fix against the current render error — exactly as if the user clicked it.
        public var autoFix: Bool

        public init(
            contentIdentifier: String,
            source: String,
            validate: @escaping @Sendable (String) async -> Validation,
            aiBackend: (any AIBackend)? = nil,
            autoFix: Bool = false
        ) {
            self.contentIdentifier = contentIdentifier
            self.source = source
            self.validate = validate
            self.aiBackend = aiBackend
            self.autoFix = autoFix
        }
    }

    /// A plugin-supplied interactive content surface. The plugin owns everything inside `nsView` — render,
    /// zoom, pan, minimap, and (if it wants) its own AI-fix UI driving `context.aiBackend`. Core only hosts
    /// the view, reads `currentSource`, and is notified via `onCommitSource` when the plugin wants the edited
    /// source persisted to the document.
    @MainActor
    public protocol View: AnyObject {
        /// The view to host (fills the surface the host provides).
        var nsView: NSView { get }
        /// The current edited source, read by the host to commit on close.
        var currentSource: String { get }
        /// Set by the host; the plugin calls it when the edited source should be written back to the document.
        var onCommitSource: ((String) -> Void)? { get set }
        /// Called when the host tears the surface down, so the plugin can release resources (web views, etc.).
        func tearDown()
        /// Whether the scaffold should show the fullscreen button in the chrome. Defaults to `true`.
        /// A config-panel surface (e.g. a TOC options panel) returns `false` to suppress the button.
        var showsFullscreen: Bool { get }
        /// When non-nil, the scaffold sizes its card to (roughly) this content size and centers it, instead of
        /// filling the surface. Small config-panel surfaces (e.g. the TOC options panel) return a size so they
        /// hug their content; large canvases (diagrams) return `nil` to fill. Defaults to `nil`.
        var preferredContentSize: CGSize? { get }
    }
}

public extension BlockInputInteractiveBlockContent.View {
    /// Default: fullscreen chrome is shown. Existing conformers need not implement this property.
    var showsFullscreen: Bool { true }
    /// Default: the surface fills the scaffold (no content-hugging). Existing conformers need not implement this.
    var preferredContentSize: CGSize? { nil }
}

public extension BlockInputInteractiveBlockContent.AIBackend {
    /// Default `converse`: use the latest user message as the `rewrite` instruction and wrap the result as a
    /// `.candidate`. Lets `rewrite`-only backends (e.g. "Fix with AI") participate without change.
    func converse(
        contentIdentifier: String,
        blockID: BlockInputBlockID,
        source: String,
        messages: [BlockInputInteractiveBlockContent.AIMessage],
        onEvent: @Sendable @MainActor (BlockInputInteractiveBlockContent.AIEvent) -> Void
    ) async -> Result<BlockInputInteractiveBlockContent.AITurn, Error> {
        let instruction = messages.last(where: { $0.role == .user })?.text ?? ""
        // blockID is not forwarded: the one-shot rewrite contract has no block context.
        return await rewrite(source: source, instruction: instruction,
                             contentIdentifier: contentIdentifier, onEvent: onEvent)
            .map { .candidate($0) }
    }
}
