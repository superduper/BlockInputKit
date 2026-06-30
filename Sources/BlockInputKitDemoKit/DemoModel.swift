import AppKit
import BlockInputKit
import Combine
import Foundation

@MainActor
final class DemoModel: ObservableObject {
    @Published var sidebarItems = DemoNote.all.map { DemoSidebarItem(id: .builtIn($0.id)) }
    @Published var selectedItemID: DemoSidebarItemID? = .builtIn(.mixed)
    @Published var editorMode: DemoEditorMode = .rendered
    @Published var isEditable = true
    @Published var allowsReordering = true
    @Published var completionPopupPlacement = BlockInputCompletionPopupPlacement.caret
    /// Which file-chip tag layout the toolbar dropdown is previewing.
    @Published var chipTagStyle: DemoChipTagStyle = .iconOnly

    /// The single seam through which all plugins wire into the editor. The model holds no plugin types.
    let editorExtension: DemoEditorExtension

    var sessions: [DemoSidebarItemID: DemoNoteSession] = [:]
    var warmTasks: [DemoNoteID: Task<Void, Never>] = [:]
    let fileCompletionProvider = DemoFileCompletionProvider()
    private var editorExtensionCancellable: AnyCancellable?

    var currentItemID: DemoSidebarItemID {
        selectedItemID ?? .builtIn(.mixed)
    }

    var currentSession: DemoNoteSession? {
        sessions[currentItemID]
    }

    init(editorExtension: DemoEditorExtension) {
        self.editorExtension = editorExtension
        sessions[.builtIn(.mixed)] = DemoNoteSession(note: DemoNote(id: .mixed), document: DemoNoteID.mixed.makeDocument())
        warmRemainingNotesAfterLaunch()
        // Forward extension changes (vim mode, zoom level) so SwiftUI re-renders and re-applies the scaled style.
        editorExtensionCancellable = editorExtension.changePublisher.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func cancelPendingWork() {
        warmTasks.values.forEach { $0.cancel() }
        warmTasks.removeAll()
        sessions.values.forEach { $0.cancelPendingWork() }
    }

    func sidebarItems(in section: DemoSidebarSection) -> [DemoSidebarItem] {
        sidebarItems.filter { section.contains($0) }
    }

    func select(_ itemID: DemoSidebarItemID) {
        selectedItemID = itemID
        if case .builtIn(let noteID) = itemID,
           sessions[itemID] == nil {
            startWarmTask(for: noteID)
        }
        if let session = sessions[itemID] {
            prepareVisibleMode(for: session)
        }
    }

    func editorConfiguration(for session: DemoNoteSession) -> BlockInputConfiguration {
        var configuration = BlockInputConfiguration(
            documentStore: session.store,
            allowsBlockReordering: allowsReordering,
            placeholder: "Start writing...",
            isEditable: isEditable,
            insertionPointStyle: editorExtension.insertionPointStyleOverride ?? .bar,
            disabledCursor: .operationNotAllowed,
            inlineHintProvider: { [fileCompletionProvider] context in
                fileCompletionProvider.inlineHint(for: context)
            },
            rawSlashCommandChips: true,
            style: editorExtension.scaledStyle(.default),
            imageBaseURL: Bundle.module.resourceURL,
            undoController: session.undoController,
            completionProvider: editorExtension.makeCompletionProvider(fileProvider: fileCompletionProvider) ?? fileCompletionProvider,
            completionReturnBehavior: .passthroughExactMatch,
            slashCommandAvailability: .anywhere,
            linkHoverEditAffordance: true,
            completionPopupConfiguration: completionPopupConfiguration(),
            onDocumentMutation: { [weak self, itemID = session.id] change in
                Task { @MainActor in
                    self?.handleRenderedMutation(change, itemID: itemID)
                }
            },
            onDocumentChange: { [weak self, itemID = session.id] document in
                Task { @MainActor in
                    self?.handleRenderedDocumentChange(document, itemID: itemID)
                }
            }
        )
        editorExtension.registerPlugins(
            on: &configuration,
            context: DemoExtensionContext(isEditable: isEditable, chipTagStyle: chipTagStyle)
        )
        return configuration
    }

    func setEditorMode(_ mode: DemoEditorMode) {
        guard mode != editorMode else {
            return
        }
        editorMode = mode
        guard let session = currentSession,
              session.loadingState == .idle else {
            return
        }
        prepareVisibleMode(for: session)
    }

    func prepareVisibleMode(for session: DemoNoteSession) {
        guard session.loadingState == .idle else {
            return
        }
        switch editorMode {
        case .raw:
            prepareRawView(for: session)
        case .rendered:
            prepareRenderedView(for: session)
        }
    }

    func setAllowsReordering(_ allowsReordering: Bool) {
        self.allowsReordering = allowsReordering
    }

    func setIsEditable(_ isEditable: Bool) {
        self.isEditable = isEditable
    }

    func setCompletionPopupPlacement(_ placement: BlockInputCompletionPopupPlacement) {
        completionPopupPlacement = placement
    }

    func setChipTagStyle(_ style: DemoChipTagStyle) {
        chipTagStyle = style
    }

    func standardizedFileURL(for url: URL) -> URL {
        URL(fileURLWithPath: url.path).standardizedFileURL
    }

    private func completionPopupConfiguration() -> BlockInputCompletionPopupConfiguration {
        guard completionPopupPlacement == .overlay else {
            return BlockInputCompletionPopupConfiguration(placement: completionPopupPlacement)
        }
        return BlockInputCompletionPopupConfiguration(placement: .overlay) { context in
            let container = context.editorView
            return BlockInputCompletionPopupOverlay(
                container: container,
                frame: Self.overlayCompletionPopupFrame(context: context, in: container)
            )
        }
    }

    private static func overlayCompletionPopupFrame(
        context: BlockInputCompletionPopupOverlayContext,
        in container: NSView
    ) -> NSRect {
        let editorFrame = container.bounds
        let popupHeight = context.popupSize.height
        let popupY = container.isFlipped
            ? editorFrame.minY + DemoCompletionOverlayMetrics.topInset
            : editorFrame.maxY - popupHeight - DemoCompletionOverlayMetrics.topInset
        return NSRect(
            x: editorFrame.minX,
            y: popupY,
            width: editorFrame.width,
            height: popupHeight
        )
    }
}
