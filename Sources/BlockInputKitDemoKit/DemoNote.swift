import BlockInputKit
import Foundation

public enum DemoNoteID: String, CaseIterable, Sendable {
    case mixed
    case large

    public var title: String {
        switch self {
        case .mixed:
            "Overview"
        case .large:
            "100K"
        }
    }

    public func makeDocument() -> BlockInputDocument {
        switch self {
        case .mixed:
            DemoData.mixedDocument()
        case .large:
            DemoData.largeDocument()
        }
    }
}

struct DemoNote: Sendable {
    var id: DemoNoteID

    var title: String {
        id.title
    }

    static let all = DemoNoteID.allCases.map(DemoNote.init)
}

enum DemoSidebarItemID: Hashable, Sendable {
    case builtIn(DemoNoteID)
    case file(URL)

    var title: String {
        switch self {
        case .builtIn(let noteID):
            noteID.title
        case .file(let url):
            url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        }
    }
}

struct DemoSidebarItem: Sendable {
    var id: DemoSidebarItemID

    var title: String {
        id.title
    }
}

enum DemoSidebarSection {
    case notes
    case files

    var title: String {
        switch self {
        case .notes:
            "Notes"
        case .files:
            "Files"
        }
    }

    func contains(_ item: DemoSidebarItem) -> Bool {
        switch (self, item.id) {
        case (.notes, .builtIn), (.files, .file):
            true
        case (.notes, .file), (.files, .builtIn):
            false
        }
    }
}

enum DemoNoteLoadingState: Equatable {
    case idle
    case loading
    case failed(String)
}

enum DemoNoteSaveState {
    case idle
    case saving
    case failed(String)
}

struct DemoNoteWarmState: @unchecked Sendable {
    var id: DemoNoteID
    var store: any BlockInputDocumentStore
    var rawMarkdown: String

    static func make(for id: DemoNoteID) -> DemoNoteWarmState {
        switch id {
        case .mixed:
            let document = id.makeDocument()
            return DemoNoteWarmState(
                id: id,
                store: BlockInputMemoryDocumentStore(document: document),
                rawMarkdown: document.markdown
            )
        case .large:
            return DemoNoteWarmState(
                id: id,
                store: DemoGeneratedDocumentStore(
                    count: DemoData.largeDocumentBlockCount,
                    initialLimit: 1_000,
                    blockProvider: DemoData.largeBlock(at:)
                ),
                rawMarkdown: ""
            )
        }
    }
}

final class DemoNoteSession {
    var id: DemoSidebarItemID
    var title: String
    var store: any BlockInputDocumentStore
    var undoController = BlockInputUndoController()
    var rawMarkdown: String
    var loadingState: DemoNoteLoadingState = .idle
    var saveState: DemoNoteSaveState = .idle
    var isDirty = false
    var rawViewNeedsReload = false
    var documentRevision = 0
    var rawParseGeneration = 0
    var saveGeneration = 0
    var saveQueuedAfterActive = false
    var saveQueuedRawWrite = false
    var pendingRawParseTask: Task<Void, Never>?
    var pendingMarkdownTask: Task<Void, Never>?
    var pendingLoadTask: Task<Void, Never>?
    var pendingAutosaveTask: Task<Void, Never>?
    var activeSaveTask: Task<Void, Never>?

    var fileURL: URL? {
        if case .file(let url) = id {
            return url
        }
        return nil
    }

    init(note: DemoNote, document: BlockInputDocument) {
        id = .builtIn(note.id)
        title = note.title
        switch note.id {
        case .mixed:
            store = BlockInputMemoryDocumentStore(document: document)
            rawMarkdown = document.markdown
        case .large:
            store = DemoGeneratedDocumentStore(
                count: DemoData.largeDocumentBlockCount,
                initialLimit: 1_000,
                blockProvider: DemoData.largeBlock(at:)
            )
            rawMarkdown = ""
            rawViewNeedsReload = true
        }
    }

    init(note: DemoNote, warmState: DemoNoteWarmState) {
        id = .builtIn(note.id)
        title = note.title
        store = warmState.store
        rawMarkdown = warmState.rawMarkdown
        if note.id == .large {
            rawViewNeedsReload = true
        }
    }

    init(fileURL: URL) {
        id = .file(fileURL)
        title = fileURL.lastPathComponent.isEmpty ? fileURL.path : fileURL.lastPathComponent
        store = BlockInputMemoryDocumentStore(document: BlockInputDocument())
        rawMarkdown = ""
        loadingState = .loading
    }

    deinit {
        cancelPendingWork()
    }

    func cancelPendingWork() {
        pendingRawParseTask?.cancel()
        pendingRawParseTask = nil
        pendingMarkdownTask?.cancel()
        pendingMarkdownTask = nil
        pendingLoadTask?.cancel()
        pendingLoadTask = nil
        pendingAutosaveTask?.cancel()
        pendingAutosaveTask = nil
        activeSaveTask?.cancel()
        activeSaveTask = nil
    }
}
