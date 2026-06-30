import AppKit

/// Slash-command chip click gesture routed to the host.
public enum BlockInputSlashCommandChipClickKind: Equatable {
    /// A primary mouse click without the Command modifier.
    case plainClick
    /// A primary mouse click with the Command modifier.
    case commandClick
}

/// Host decision for a slash-command chip click.
public enum BlockInputSlashCommandChipClickAction: Equatable {
    /// Open the editor's existing link modal for this chip.
    case showLinkModal
    /// Open the chip URI through the editor URL opener.
    case openURL
    /// The host handled the click and the editor should not perform fallback behavior.
    case hostHandled
    /// Do not consume the click: let the editor place the caret so the link/chip label can be edited inline.
    case placeCaret
}

/// Context sent when a slash-command chip is clicked.
public struct BlockInputSlashCommandChipClickContext {
    /// Visible chip label, including its leading `/`.
    public var label: String
    /// Host-owned slash-command URI.
    public var uri: URL
    /// Block that contains the clicked chip.
    public var blockID: BlockInputBlockID
    /// Full Markdown source range for the clicked chip.
    public var sourceRange: NSRange
    /// Editor view routing the click.
    public var editorView: BlockInputView
    /// Original AppKit mouse event.
    public var event: NSEvent
    /// Normalized click kind.
    public var clickKind: BlockInputSlashCommandChipClickKind

    /// Creates host click context for a slash-command chip.
    public init(
        label: String,
        uri: URL,
        blockID: BlockInputBlockID,
        sourceRange: NSRange,
        editorView: BlockInputView,
        event: NSEvent,
        clickKind: BlockInputSlashCommandChipClickKind
    ) {
        self.label = label
        self.uri = uri
        self.blockID = blockID
        self.sourceRange = sourceRange
        self.editorView = editorView
        self.event = event
        self.clickKind = clickKind
    }
}

/// Runtime options and host integration points for a block input editor.
public struct BlockInputConfiguration {
    /// Default visual horizontal inset for block content.
    public static let defaultEditorHorizontalInset: CGFloat = 20
    /// Default visual vertical inset for the editor content.
    public static let defaultEditorVerticalInset: CGFloat = 8

    /// Source of truth for the document shown by the editor.
    public var documentStore: any BlockInputDocumentStore {
        didSet {
            usesDefaultDocumentStore = false
        }
    }
    /// Whether the leading drag handle can reorder blocks.
    public var allowsBlockReordering: Bool
    /// Visual horizontal inset used for block content.
    ///
    /// When reordering is enabled, the drag handle is centered inside this inset when possible
    /// and the gutter grows only when the inset is too small for the handle lane.
    public var editorHorizontalInset: CGFloat
    /// Visual vertical inset used above and below editor content.
    public var editorVerticalInset: CGFloat
    /// Multiplier applied to vertical padding inside rendered block rows.
    ///
    /// A value of `1` preserves built-in block spacing. Values below `1` make block rows denser, values above `1`
    /// increase block row spacing, negative values are clamped to `0`, and non-finite values fall back to `1`.
    /// Horizontal layout and the editor's outer `editorVerticalInset` are not affected.
    public var blockVerticalInsetMultiplier: CGFloat {
        didSet {
            blockVerticalInsetMultiplier = Self.sanitizedBlockVerticalInsetMultiplier(blockVerticalInsetMultiplier)
        }
    }
    /// Subtle text shown when the editor has no meaningful document content.
    ///
    /// The placeholder is visual only. It is not inserted into the document, exported as Markdown, or reported through
    /// document-change callbacks.
    public var placeholder: String?
    /// Whether the editor accepts user-driven document mutations.
    ///
    /// When false, existing content remains selectable, copyable, focusable, and accessible, but typing and editor-owned
    /// mutation commands are disabled.
    public var isEditable: Bool
    /// Shape of the text insertion point inside block text views.
    ///
    /// The default `.bar` uses NSTextView's standard thin vertical I-beam. Use `.block` for a filled
    /// block cursor that covers the glyph at the caret position (suitable for vim normal mode).
    public var insertionPointStyle: BlockInputInsertionPointStyle
    /// Cursor shown over non-editable editor surfaces.
    ///
    /// Link and slash-command chip cursor rects may still take precedence where those interactions remain available.
    public var disabledCursor: NSCursor?
    /// Host hook for visual-only inline hints after the focused caret.
    ///
    /// Hints are never inserted into document text, Markdown export, undo, pasteboard contents, completion ranges, or
    /// accessibility value text.
    public var inlineHintProvider: BlockInputInlineHintProvider?
    /// Whether raw `/command` tokens render as visual slash-command chips.
    ///
    /// Raw slash-command chips remain normal document text for editing, selection, copy, accessibility, and Markdown
    /// export.
    public var rawSlashCommandChips: Bool
    /// Color used for editor accent affordances, including drag insertion and selected horizontal rules.
    public var dropIndicatorColor: NSColor
    /// Visual styling for editor text, code, and selection chrome.
    public var style: BlockInputStyle
    /// Behavior used by editor-owned Cmd+A and select-all commands.
    ///
    /// The default `.focusedContentThenDocument` behavior selects the focused content first and promotes to the whole
    /// document on the next select-all command. Set `.document` when the host wants Cmd+A to select the whole editor
    /// document immediately.
    public var selectAllBehavior: BlockInputSelectAllBehavior
    /// Optional rendered-content height sizing for hosts that want the editor to provide its preferred height.
    ///
    /// When nil, the editor keeps its historical behavior and exposes no intrinsic height. When set, the editor reports a
    /// preferred height that starts at `defaultVisibleLineCount`, grows with rendered content, and caps at
    /// `maximumVisibleLineCount` when provided.
    public var heightSizing: BlockInputEditorHeightSizing?
    /// How images are presented in the editor.
    ///
    /// The default `.inlineBlocks` keeps existing standalone image block behavior. Use `.textLinksWithPreviewStrip`
    /// together with `BlockInputDocument(markdown:imageParsingMode: .preserveSourceText)` when the editor should keep
    /// image syntax editable as text and show extracted image thumbnails in a preview strip.
    public var imagePresentation: BlockInputImagePresentation
    /// Image loader used for image block bytes and natural dimensions.
    public var imageLoader: any BlockInputImageLoading
    /// Host-supplied renderers for renderable block content (e.g. Mermaid diagrams).
    ///
    /// Renderers are resolved per block by ``BlockInputBlock/renderedContentIdentifier``. The
    /// default registry is empty, so renderable code blocks (such as ` ```mermaid `) fall back to
    /// their normal code-text surface until a renderer is registered.
    public var blockContentRenderers: BlockInputBlockContentRendererRegistry
    /// Optional host hook that builds a live interactive view for the rendered-content zoom modal.
    ///
    /// When set, the ⤢ zoom modal shows the rendered image immediately, then swaps in the view this
    /// provider returns (e.g. a live Mermaid `WKWebView` with working links). Return nil to keep the
    /// static image. The editor core never imports WebKit; the host owns the live view.
    public var renderedContentZoomProvider: (@MainActor (BlockInputRenderedContentZoomContext) -> NSView?)?
    /// Host hook that builds a plugin-owned interactive content view (Phase-1 seam). When set, hosts can present
    /// a fully plugin-driven surface (render + zoom + minimap + the plugin's own AI-fix UI). When nil, unused.
    public var interactiveBlockContentProvider: BlockInputInteractiveBlockContent.Provider?
    /// The host's AI backend (LLM) handed to an interactive content plugin via the context. The plugin owns the
    /// AI-fix UI; the host supplies only the model call. When nil, the plugin shows no AI affordance.
    public var blockContentAIBackend: (any BlockInputInteractiveBlockContent.AIBackend)?
    /// Optional disk cache used by the default loader for remote image bytes and dimensions.
    public var imageDiskCache: (any BlockInputImageDiskCaching)?
    /// Base URL used to resolve relative image sources before loading.
    public var imageBaseURL: URL?
    /// Base URL used to resolve relative file-link sources inserted by file drop hooks.
    public var fileBaseURL: URL?
    /// Optional host resolver for a leading accessory (type icon, `PDF`-style pill tag, …) drawn at the start of a file chip.
    ///
    /// Return a `BlockInputChipAccessory` describing the reserved width and a draw closure, or nil for no accessory. The
    /// accessory is painted into a reserved gap and the document source text is never modified; the accessory may also
    /// hide the label's file extension. Core stays policy-free — it reserves space and calls the draw closure.
    public var inlineChipAccessoryProvider: (@MainActor (BlockInputChipContext) -> BlockInputChipAccessory?)?
    /// Whether remote `http` and `https` image URLs should be loaded.
    public var allowsRemoteImageLoading: Bool
    /// Maximum source image payload accepted by the default image loader.
    public var maximumImageSourceBytes: Int
    /// Maximum decoded width or height accepted by the default image loader.
    public var maximumImagePixelDimension: Int
    /// Placeholder aspect ratio used before dimensions are known.
    public var defaultImagePlaceholderAspectRatio: CGFloat
    /// Undo coordinator used by text and structural editor operations.
    ///
    /// When nil, `BlockInputView` uses a view-owned undo controller.
    public var undoController: BlockInputUndoController?
    /// Optional command bridge for hosts without direct access to the mounted AppKit editor.
    public var commandDispatcher: BlockInputEditorCommandDispatcher?
    /// Whether the built-in find bar (Cmd+F / Cmd+G / Cmd+Shift+G) is available.
    ///
    /// When true (the default), Cmd+F opens the find bar, Cmd+G advances to the next match, and Cmd+Shift+G moves to the
    /// previous match. A host `keyboardShortcuts` entry for any of those shortcuts still wins. Set false to disable the
    /// built-in find UI and let those events pass through.
    public var findEnabled: Bool
    /// Whether trackpad pinch magnifies the editor as a zoomable canvas (PDF/Preview style).
    ///
    /// This is canvas zoom: the whole document scales as a unit, text does not reflow, and the user can pan the
    /// magnified canvas. It is independent of font zoom (which changes text size and reflows). Defaults to `true`.
    /// The magnification range is `pinchZoomMinimum`...`pinchZoomMaximum`.
    public var pinchToZoomEnabled: Bool
    /// Smallest canvas magnification reachable by pinch. Clamped to `[0.05, 1]`.
    public var pinchZoomMinimum: CGFloat
    /// Largest canvas magnification reachable by pinch. Clamped to `>= 1`.
    public var pinchZoomMaximum: CGFloat
    /// Registered host keyboard shortcuts to intercept before built-in editor behavior.
    ///
    /// Only shortcuts present in this dictionary are intercepted. Handlers run on the main actor after modal,
    /// completion, and IME priority, but before editor defaults. Return `.ignored` to resume the editor's normal behavior
    /// for the original event, or `.performDefault(.returnKey)` to explicitly run plain Return behavior.
    public var keyboardShortcuts: [BlockInputKeyboardShortcut: BlockInputKeyboardShortcutHandler]
    /// Called for every key-down event reaching a mounted text view, before AppKit processes it.
    /// Return `true` to consume the event; return `false` (or leave nil) to let AppKit handle it normally.
    /// Use this for modal input modes such as vim where the host needs first-class key access.
    public var keyDownHandler: ((NSEvent) -> Bool)?
    /// Host completion source for mentions and slash commands.
    public var completionProvider: (any BlockInputCompletionProvider)?
    /// Optional host hook for resolving local file drops before insertion.
    public var fileDropHandler: BlockInputFileDropHandler?
    /// Ordered handlers consulted on paste before native AppKit insertion.
    ///
    /// On Cmd+V (and right-click Paste), the first handler whose claimed pasteboard type is present and that returns a
    /// non-nil reference list wins; its references are inserted as image blocks / file-link chips in one undo group.
    /// When every handler declines, paste falls through to native text insertion. Empty by default, so paste is
    /// unchanged until a host registers handlers (e.g. via the `BlockInputKitPaste` plugin).
    public var pasteContentHandlers: [any BlockInputPasteContentHandler]
    /// Return-key behavior while the editor-owned completion popup is active.
    public var completionReturnBehavior: BlockInputCompletionReturnBehavior
    /// Where live slash-command completion is allowed to open.
    public var slashCommandAvailability: BlockInputSlashCommandAvailability
    /// Non-deprecated backing storage read and written internally so editor-owned access avoids deprecation warnings.
    var slashCommandChipClickHandlerStorage:
        (@MainActor (BlockInputSlashCommandChipClickContext) -> BlockInputSlashCommandChipClickAction)?
    /// Optional host router for slash-command chip clicks.
    @available(*, deprecated, message: "Use inlineLinkClickHandler; this forwards for the .slashCommand kind.")
    public var slashCommandChipClickHandler:
        (@MainActor (BlockInputSlashCommandChipClickContext) -> BlockInputSlashCommandChipClickAction)? {
        get { slashCommandChipClickHandlerStorage }
        set { slashCommandChipClickHandlerStorage = newValue }
    }
    /// Optional host router for inline-link and chip clicks: `.showLinkModal` keeps the built-in link modal; `.openURL`
    /// opens the destination; `.hostHandled` suppresses fallback.
    public var inlineLinkClickHandler:
        (@MainActor (BlockInputInlineLinkClickContext) -> BlockInputInlineLinkClickAction)?
    /// Optional host provider for extra hover-affordance buttons, inserted between the built-in Open and Edit buttons.
    ///
    /// Use it to add link-kind-specific actions (e.g. "Show in Finder" for file chips) while keeping that policy in the
    /// host; core renders the buttons and runs the actions.
    public var linkHoverActionsProvider:
        (@MainActor (BlockInputLinkHoverActionContext) -> [BlockInputLinkHoverAction])?
    /// Host-registered custom inline markups (detection + styling). Composed BEFORE built-in passes: each provider's
    /// spans are excluded from built-in passes and from later providers, in registration order. Empty by default.
    public var inlineMarkupProviders: [any BlockInputInlineMarkupProvider]
    /// Host-registered completion token triggers (multi-char openers like "[["). Searched before single-char `@`/`/`.
    public var completionTokenTriggers: [BlockInputCompletionTokenTrigger]
    /// Host-registered async source rewriters, keyed by `identifier`. Run off the hot path as one undoable mutation.
    public var inlineMarkupRewriters: [any BlockInputInlineMarkupRewriter]
    /// Whether hovering a link shows an inline edit affordance.
    public var linkHoverEditAffordance: Bool = true
    /// Whether each rendered link/wikilink draws a presentation-only inline "open" icon at its trailing edge (click opens).
    public var showsInlineLinkOpenButton: Bool = true
    /// Optional host override for editor-owned link and image modal presentation.
    ///
    /// Return the parent view and modal frame in that parent's coordinate space, letting hosts rehost modals into another
    /// surface aligned to it. When nil, the editor owns the modal as a direct child and places it in editor bounds.
    public var modalOverlayProvider: (@MainActor (BlockInputModalOverlayContext) -> BlockInputModalOverlay?)?
    /// Optional host-supplied view anchored above the current non-empty text selection.
    ///
    /// When set, the editor positions the returned view centered over the selection (above by default, flipping below
    /// near the top, clamped inside its container), repositions it on scroll/resize, and dismisses it when the
    /// selection collapses, the anchor scrolls out of view, focus is lost, Escape is pressed, or a click lands outside
    /// the overlay. When nil (the default), the feature is off.
    public var selectionOverlayProvider: BlockInputSelectionOverlayProvider?
    /// Built-in completion popup behavior, including caret anchoring and optional overlay hosting.
    public var completionPopupConfiguration: BlockInputCompletionPopupConfiguration
    /// Convenience access to `completionPopupConfiguration.placement`.
    public var completionPopupPlacement: BlockInputCompletionPopupPlacement {
        get { completionPopupConfiguration.placement }
        set { completionPopupConfiguration.placement = newValue }
    }
    /// Called immediately with the granular store mutation applied by the editor.
    ///
    /// Marker-adjusting stores may receive marker-only numbered-list changes instead of a replacement for every
    /// list item whose visible marker changed.
    public var onDocumentMutation: ((BlockInputDocumentChange) -> Void)?
    /// Called with a full document snapshot after editor mutations.
    ///
    /// Large store-backed editors defer and coalesce this callback; use
    /// `onDocumentMutation` for synchronous per-edit updates.
    public var onDocumentChange: ((BlockInputDocument) -> Void)?
    /// Delay used to coalesce full-document snapshots for large store-backed documents.
    public var documentChangeSnapshotDelay: TimeInterval
    /// Called after the editor updates cursor, text, or block selection.
    public var onSelectionChange: ((BlockInputSelection?) -> Void)?
    /// Called when the editor gains or loses AppKit focus.
    public var onFocusChange: ((Bool) -> Void)?
    var usesDefaultDocumentStore: Bool

    /// Current loaded document snapshot from `documentStore`.
    ///
    /// Progressive stores expose only loaded blocks here; callers that need a complete save snapshot should call
    /// `BlockInputDocumentStore.completeDocumentSnapshot(limit:)`.
    public var document: BlockInputDocument {
        BlockInputDocument(blocks: (0..<documentStore.loadedBlockCount).compactMap { documentStore.block(at: $0) })
    }

    /// Creates configuration. When `documentStore` is supplied, it is the source of truth and `document` is ignored.
    ///
    /// The `selectAllBehavior` parameter controls editor-owned Cmd+A and select-all commands. It does not affect native
    /// AppKit select-all handling inside focused modal fields.
    public init(
        document: BlockInputDocument = BlockInputDocument(),
        documentStore: (any BlockInputDocumentStore)? = nil,
        allowsBlockReordering: Bool = true,
        editorHorizontalInset: CGFloat = BlockInputConfiguration.defaultEditorHorizontalInset,
        editorVerticalInset: CGFloat = BlockInputConfiguration.defaultEditorVerticalInset,
        blockVerticalInsetMultiplier: CGFloat = 1,
        placeholder: String? = nil,
        isEditable: Bool = true,
        insertionPointStyle: BlockInputInsertionPointStyle = .bar,
        disabledCursor: NSCursor? = nil,
        inlineHintProvider: BlockInputInlineHintProvider? = nil,
        rawSlashCommandChips: Bool = false,
        dropIndicatorColor: NSColor = .controlAccentColor,
        style: BlockInputStyle = .default,
        selectAllBehavior: BlockInputSelectAllBehavior = .focusedContentThenDocument,
        heightSizing: BlockInputEditorHeightSizing? = nil,
        imagePresentation: BlockInputImagePresentation = .inlineBlocks,
        imageLoader: any BlockInputImageLoading = BlockInputDefaultImageLoader(),
        blockContentRenderers: BlockInputBlockContentRendererRegistry = BlockInputBlockContentRendererRegistry(),
        renderedContentZoomProvider: (@MainActor (BlockInputRenderedContentZoomContext) -> NSView?)? = nil,
        interactiveBlockContentProvider: BlockInputInteractiveBlockContent.Provider? = nil,
        blockContentAIBackend: (any BlockInputInteractiveBlockContent.AIBackend)? = nil,
        imageDiskCache: (any BlockInputImageDiskCaching)? = BlockInputDefaultImageDiskCache(),
        imageBaseURL: URL? = nil,
        fileBaseURL: URL? = nil,
        allowsRemoteImageLoading: Bool = true,
        maximumImageSourceBytes: Int = 20 * 1024 * 1024,
        maximumImagePixelDimension: Int = 8_192,
        defaultImagePlaceholderAspectRatio: CGFloat = 16.0 / 9.0,
        undoController: BlockInputUndoController? = nil,
        commandDispatcher: BlockInputEditorCommandDispatcher? = nil,
        findEnabled: Bool = true,
        pinchToZoomEnabled: Bool = true,
        pinchZoomMinimum: CGFloat = 1,
        pinchZoomMaximum: CGFloat = 4,
        keyboardShortcuts: [BlockInputKeyboardShortcut: BlockInputKeyboardShortcutHandler] = [:],
        completionProvider: (any BlockInputCompletionProvider)? = nil,
        fileDropHandler: BlockInputFileDropHandler? = nil,
        pasteContentHandlers: [any BlockInputPasteContentHandler] = [],
        inlineChipAccessoryProvider: (@MainActor (BlockInputChipContext) -> BlockInputChipAccessory?)? = nil,
        completionReturnBehavior: BlockInputCompletionReturnBehavior = .acceptHighlightedSuggestion,
        inlineMarkupProviders: [any BlockInputInlineMarkupProvider] = [],
        completionTokenTriggers: [BlockInputCompletionTokenTrigger] = [],
        inlineMarkupRewriters: [any BlockInputInlineMarkupRewriter] = [],
        slashCommandAvailability: BlockInputSlashCommandAvailability = .documentStart,
        slashCommandChipClickHandler:
            (@MainActor (BlockInputSlashCommandChipClickContext) -> BlockInputSlashCommandChipClickAction)? = nil,
        inlineLinkClickHandler:
            (@MainActor (BlockInputInlineLinkClickContext) -> BlockInputInlineLinkClickAction)? = nil,
        linkHoverActionsProvider:
            (@MainActor (BlockInputLinkHoverActionContext) -> [BlockInputLinkHoverAction])? = nil,
        linkHoverEditAffordance: Bool = true,
        showsInlineLinkOpenButton: Bool = true,
        modalOverlayProvider: (@MainActor (BlockInputModalOverlayContext) -> BlockInputModalOverlay?)? = nil,
        selectionOverlayProvider: BlockInputSelectionOverlayProvider? = nil,
        completionPopupPlacement: BlockInputCompletionPopupPlacement = .caret,
        completionPopupConfiguration: BlockInputCompletionPopupConfiguration? = nil,
        onDocumentMutation: ((BlockInputDocumentChange) -> Void)? = nil,
        onDocumentChange: ((BlockInputDocument) -> Void)? = nil,
        documentChangeSnapshotDelay: TimeInterval = 0.25,
        onSelectionChange: ((BlockInputSelection?) -> Void)? = nil,
        onFocusChange: ((Bool) -> Void)? = nil,
        keyDownHandler: ((NSEvent) -> Bool)? = nil
    ) {
        usesDefaultDocumentStore = documentStore == nil
        self.documentStore = documentStore ?? BlockInputMemoryDocumentStore(document: document)
        self.allowsBlockReordering = allowsBlockReordering
        self.editorHorizontalInset = editorHorizontalInset
        self.editorVerticalInset = editorVerticalInset
        self.blockVerticalInsetMultiplier = Self.sanitizedBlockVerticalInsetMultiplier(blockVerticalInsetMultiplier)
        self.placeholder = placeholder
        self.isEditable = isEditable
        self.insertionPointStyle = insertionPointStyle
        self.disabledCursor = disabledCursor
        self.inlineHintProvider = inlineHintProvider
        self.rawSlashCommandChips = rawSlashCommandChips
        self.dropIndicatorColor = dropIndicatorColor
        self.style = style
        self.selectAllBehavior = selectAllBehavior
        self.heightSizing = heightSizing
        (self.imagePresentation, self.imageLoader, self.imageDiskCache) = (imagePresentation, imageLoader, imageDiskCache)
        (self.blockContentRenderers, self.renderedContentZoomProvider) = (blockContentRenderers, renderedContentZoomProvider)
        (self.interactiveBlockContentProvider, self.blockContentAIBackend) = (interactiveBlockContentProvider, blockContentAIBackend)
        (self.imageBaseURL, self.fileBaseURL, self.allowsRemoteImageLoading) = (imageBaseURL, fileBaseURL, allowsRemoteImageLoading)
        (self.maximumImageSourceBytes, self.maximumImagePixelDimension, self.defaultImagePlaceholderAspectRatio) =
            (max(1, maximumImageSourceBytes), max(1, maximumImagePixelDimension), max(0.01, defaultImagePlaceholderAspectRatio))
        (self.undoController, self.commandDispatcher) = (undoController, commandDispatcher)
        (self.findEnabled, self.pinchToZoomEnabled) = (findEnabled, pinchToZoomEnabled)
        self.pinchZoomMinimum = min(max(pinchZoomMinimum, 0.05), 1)
        self.pinchZoomMaximum = max(pinchZoomMaximum, 1)
        self.keyboardShortcuts = keyboardShortcuts
        self.completionProvider = completionProvider
        self.fileDropHandler = fileDropHandler
        (self.pasteContentHandlers, self.inlineChipAccessoryProvider) = (pasteContentHandlers, inlineChipAccessoryProvider)
        self.completionReturnBehavior = completionReturnBehavior
        self.inlineMarkupProviders = inlineMarkupProviders
        self.completionTokenTriggers = completionTokenTriggers
        self.inlineMarkupRewriters = inlineMarkupRewriters
        self.slashCommandAvailability = slashCommandAvailability
        slashCommandChipClickHandlerStorage = slashCommandChipClickHandler
        (self.inlineLinkClickHandler, self.linkHoverActionsProvider) = (inlineLinkClickHandler, linkHoverActionsProvider)
        (self.linkHoverEditAffordance, self.showsInlineLinkOpenButton) = (linkHoverEditAffordance, showsInlineLinkOpenButton)
        self.modalOverlayProvider = modalOverlayProvider
        self.selectionOverlayProvider = selectionOverlayProvider
        self.completionPopupConfiguration = completionPopupConfiguration ?? BlockInputCompletionPopupConfiguration(
            placement: completionPopupPlacement
        )
        self.onDocumentMutation = onDocumentMutation
        self.onDocumentChange = onDocumentChange
        self.documentChangeSnapshotDelay = documentChangeSnapshotDelay
        self.onSelectionChange = onSelectionChange
        self.onFocusChange = onFocusChange
        self.keyDownHandler = keyDownHandler
    }

    static func sanitizedBlockVerticalInsetMultiplier(_ value: CGFloat) -> CGFloat {
        value.isFinite ? max(0, value) : 1
    }
}
