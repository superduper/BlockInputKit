import BlockInputKit
import Foundation

extension DemoModel {
    func openMarkdownFile(at url: URL) {
        let fileURL = standardizedFileURL(for: url)
        let itemID = DemoSidebarItemID.file(fileURL)
        if !sidebarItems.contains(where: { $0.id == itemID }) {
            sidebarItems.append(DemoSidebarItem(id: itemID))
        }
        if let session = sessions[itemID] {
            if case .failed = session.loadingState {
                startFileLoad(for: session, url: fileURL)
            }
        } else {
            let session = DemoNoteSession(fileURL: fileURL)
            sessions[itemID] = session
            startFileLoad(for: session, url: fileURL)
        }
        select(itemID)
    }

    func warmRemainingNotesAfterLaunch() {
        for note in DemoNote.all where sessions[.builtIn(note.id)] == nil {
            startWarmTask(for: note.id)
        }
    }

    func startWarmTask(for noteID: DemoNoteID) {
        let itemID = DemoSidebarItemID.builtIn(noteID)
        guard sessions[itemID] == nil,
              warmTasks[noteID] == nil else {
            return
        }
        warmTasks[noteID] = Task { [weak self] in
            let warmState = await Task.detached(priority: .utility) {
                DemoNoteWarmState.make(for: noteID)
            }.value
            guard !Task.isCancelled else {
                return
            }
            self?.installWarmedSession(warmState)
        }
    }

    func installWarmedSession(_ warmState: DemoNoteWarmState) {
        warmTasks[warmState.id] = nil
        let itemID = DemoSidebarItemID.builtIn(warmState.id)
        guard sessions[itemID] == nil else {
            return
        }
        sessions[itemID] = DemoNoteSession(note: DemoNote(id: warmState.id), warmState: warmState)
        if currentItemID == itemID,
           let session = sessions[itemID] {
            prepareVisibleMode(for: session)
        }
        objectWillChange.send()
    }

    func startFileLoad(for session: DemoNoteSession, url: URL) {
        let itemID = session.id
        session.pendingLoadTask?.cancel()
        session.loadingState = .loading
        objectWillChange.send()
        session.pendingLoadTask = Task { [weak self, itemID, url] in
            do {
                let document = try await BlockInputDocument.readingMarkdown(from: url)
                guard !Task.isCancelled else {
                    return
                }
                self?.installLoadedFileDocument(document, itemID: itemID)
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                self?.installFileLoadError(error, itemID: itemID)
            }
        }
    }

    func installLoadedFileDocument(_ document: BlockInputDocument, itemID: DemoSidebarItemID) {
        guard let session = sessions[itemID] else {
            return
        }
        session.pendingLoadTask = nil
        session.loadingState = .idle
        session.store.replaceDocument(document)
        session.undoController = BlockInputUndoController()
        session.rawMarkdown = ""
        session.rawViewNeedsReload = true
        if currentItemID == itemID {
            prepareVisibleMode(for: session)
        }
        objectWillChange.send()
    }

    func installFileLoadError(_ error: Error, itemID: DemoSidebarItemID) {
        guard let session = sessions[itemID] else {
            return
        }
        session.pendingLoadTask = nil
        session.loadingState = .failed("Could not load \(itemID.title): \(error.localizedDescription)")
        objectWillChange.send()
    }
}
