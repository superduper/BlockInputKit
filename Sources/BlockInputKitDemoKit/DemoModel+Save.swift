import BlockInputKit
import Foundation

extension DemoModel {
    func saveSelectedDocument() {
        guard let session = currentSession,
              session.loadingState == .idle,
              session.fileURL != nil else {
            return
        }
        requestSave(for: session, rawEdit: false, immediate: true)
    }

    func saveCurrentSessionAs(_ url: URL) {
        guard let session = currentSession else {
            return
        }
        let hadPendingRawParse = session.pendingRawParseTask != nil
        let fileURL = standardizedFileURL(for: url)
        let targetSession: DemoNoteSession
        if session.fileURL == nil {
            startSaveAsCopy(for: session, to: fileURL, hadPendingRawParse: hadPendingRawParse)
            return
        } else {
            targetSession = session
            retargetFileSession(session, to: fileURL)
        }
        targetSession.isDirty = true
        targetSession.saveGeneration += 1
        if hadPendingRawParse {
            scheduleRawParse(for: targetSession, delay: 0)
        }
        requestSave(for: targetSession, rawEdit: false, immediate: true)
        objectWillChange.send()
    }

    func startSaveAsCopy(for session: DemoNoteSession, to fileURL: URL, hadPendingRawParse: Bool) {
        guard session.activeSaveTask == nil else {
            session.saveQueuedAfterActive = true
            objectWillChange.send()
            return
        }
        let sourceID = session.id
        let store = session.store
        session.saveState = .saving
        objectWillChange.send()
        session.activeSaveTask = Task { [weak self, weak session, sourceID, fileURL, hadPendingRawParse, store] in
            do {
                let document = try await store.completeDocumentSnapshot(limit: DemoData.progressiveLoadBatchLimit)
                guard !Task.isCancelled else {
                    return
                }
                self?.completeSaveAsCopy(
                    sourceID: sourceID,
                    sourceSession: session,
                    fileURL: fileURL,
                    document: document,
                    hadPendingRawParse: hadPendingRawParse
                )
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                self?.completeSaveAsCopyFailure(sourceID: sourceID, sourceSession: session, error: error)
            }
        }
    }

    func completeSaveAsCopy(
        sourceID: DemoSidebarItemID,
        sourceSession: DemoNoteSession?,
        fileURL: URL,
        document: BlockInputDocument,
        hadPendingRawParse: Bool
    ) {
        guard let sourceSession,
              sessions[sourceID] === sourceSession else {
            return
        }
        sourceSession.activeSaveTask = nil
        sourceSession.saveState = .idle
        let targetSession = copySession(sourceSession, to: fileURL, document: document)
        installFileBackedSession(targetSession)
        select(targetSession.id)
        targetSession.isDirty = true
        targetSession.saveGeneration += 1
        if hadPendingRawParse {
            scheduleRawParse(for: targetSession, delay: 0)
        }
        requestSave(for: targetSession, rawEdit: false, immediate: true)
        objectWillChange.send()
    }

    func completeSaveAsCopyFailure(sourceID: DemoSidebarItemID, sourceSession: DemoNoteSession?, error: Error) {
        guard let sourceSession,
              sessions[sourceID] === sourceSession else {
            return
        }
        sourceSession.activeSaveTask = nil
        sourceSession.saveState = .failed("Save failed: \(error.localizedDescription)")
        objectWillChange.send()
    }

    func defaultSaveName(for session: DemoNoteSession) -> String {
        if let fileURL = session.fileURL {
            return fileURL.lastPathComponent
        }
        return "\(session.title).md"
    }

    func saveStatusText(for session: DemoNoteSession) -> String {
        switch session.saveState {
        case .idle:
            if session.fileURL == nil {
                return ""
            }
            return session.isDirty ? "Edited" : "Saved"
        case .saving:
            return "Saving..."
        case .failed(let message):
            return message
        }
    }

    @discardableResult
    func markSessionDirty(_ session: DemoNoteSession, rawEdit: Bool) -> Bool {
        let previousStatus = saveStatusText(for: session)
        guard session.loadingState == .idle else {
            return false
        }
        session.isDirty = true
        session.saveGeneration += 1
        session.saveQueuedRawWrite = rawEdit
        session.saveState = .idle
        if session.fileURL != nil {
            scheduleAutosave(for: session, rawEdit: rawEdit)
        }
        return saveStatusText(for: session) != previousStatus
    }

    func scheduleAutosave(for session: DemoNoteSession, rawEdit: Bool) {
        session.pendingAutosaveTask?.cancel()
        let itemID = session.id
        let generation = session.saveGeneration
        session.pendingAutosaveTask = Task { [weak self, itemID, generation, rawEdit] in
            do {
                try await Task.sleep(nanoseconds: 900_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            self?.startAutosave(itemID: itemID, generation: generation, rawEdit: rawEdit)
        }
    }

    func startAutosave(itemID: DemoSidebarItemID, generation: Int, rawEdit: Bool) {
        guard let session = sessions[itemID],
              session.saveGeneration == generation,
              session.isDirty else {
            return
        }
        requestSave(for: session, rawEdit: rawEdit, immediate: false)
    }

    func requestSave(for session: DemoNoteSession, rawEdit: Bool, immediate: Bool) {
        guard let url = session.fileURL else {
            return
        }
        let shouldWriteRaw = session.saveQueuedRawWrite || rawEdit
        if immediate {
            session.pendingAutosaveTask?.cancel()
            session.pendingAutosaveTask = nil
        }
        guard session.activeSaveTask == nil else {
            session.saveQueuedAfterActive = true
            session.saveQueuedRawWrite = shouldWriteRaw
            objectWillChange.send()
            return
        }
        startSave(for: session, to: url, generation: session.saveGeneration, rawEdit: shouldWriteRaw)
    }

    func startSave(for session: DemoNoteSession, to url: URL, generation: Int, rawEdit: Bool) {
        let itemID = session.id
        let rawMarkdown = session.rawMarkdown
        let store = session.store
        session.saveState = .saving
        session.saveQueuedAfterActive = false
        session.saveQueuedRawWrite = false
        objectWillChange.send()
        session.activeSaveTask = Task { [weak self, itemID, url, generation, rawEdit, rawMarkdown, store] in
            do {
                if rawEdit {
                    try await Self.writeRawMarkdown(rawMarkdown, to: url)
                } else {
                    let document = try await store.completeDocumentSnapshot(limit: DemoData.progressiveLoadBatchLimit)
                    try await document.writeMarkdown(to: url)
                }
                guard !Task.isCancelled else {
                    return
                }
                self?.completeSave(itemID: itemID, generation: generation, rawEdit: rawEdit, result: .success(()))
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                self?.completeSave(itemID: itemID, generation: generation, rawEdit: rawEdit, result: .failure(error))
            }
        }
    }

    func completeSave(itemID: DemoSidebarItemID, generation: Int, rawEdit: Bool, result: Result<Void, Error>) {
        guard let session = sessions[itemID] else {
            return
        }
        session.activeSaveTask = nil
        switch result {
        case .success:
            if session.saveGeneration == generation {
                session.isDirty = false
                session.saveState = .idle
            } else {
                session.isDirty = true
                session.saveState = .idle
                requestSave(for: session, rawEdit: false, immediate: true)
                return
            }
        case .failure(let error):
            session.isDirty = true
            guard session.saveGeneration == generation else {
                session.saveState = .idle
                requestSave(for: session, rawEdit: false, immediate: true)
                return
            }
            session.saveQueuedRawWrite = rawEdit
            session.saveState = .failed("Save failed: \(error.localizedDescription)")
        }
        if session.saveQueuedAfterActive,
           session.isDirty {
            requestSave(for: session, rawEdit: false, immediate: true)
            return
        }
        objectWillChange.send()
    }

    func installFileBackedSession(_ session: DemoNoteSession) {
        if let existing = sessions[session.id],
           existing !== session {
            existing.cancelPendingWork()
        }
        sessions[session.id] = session
        if !sidebarItems.contains(where: { $0.id == session.id }) {
            sidebarItems.append(DemoSidebarItem(id: session.id))
        }
    }

    func retargetFileSession(_ session: DemoNoteSession, to url: URL) {
        let oldID = session.id
        let newID = DemoSidebarItemID.file(url)
        guard oldID != newID else {
            return
        }
        session.pendingAutosaveTask?.cancel()
        session.pendingAutosaveTask = nil
        session.activeSaveTask?.cancel()
        session.activeSaveTask = nil
        session.saveQueuedAfterActive = false
        sessions[oldID] = nil
        if let existing = sessions[newID],
           existing !== session {
            existing.cancelPendingWork()
        }
        session.id = newID
        session.title = newID.title
        sessions[newID] = session
        selectedItemID = newID
        let oldRow = sidebarItems.firstIndex(where: { $0.id == oldID })
        let existingRow = sidebarItems.firstIndex(where: { $0.id == newID })
        if let existingRow,
           existingRow != oldRow {
            if let oldRow {
                sidebarItems.remove(at: oldRow)
            }
        } else if let oldRow {
            sidebarItems[oldRow].id = newID
        } else {
            installFileBackedSession(session)
        }
    }

    func copySession(_ session: DemoNoteSession, to url: URL, document: BlockInputDocument) -> DemoNoteSession {
        let copy = DemoNoteSession(fileURL: url)
        copy.loadingState = .idle
        copy.store = BlockInputMemoryDocumentStore(document: document)
        copy.undoController = BlockInputUndoController()
        copy.rawMarkdown = session.rawMarkdown
        copy.documentRevision = session.documentRevision
        copy.rawParseGeneration = session.rawParseGeneration
        copy.saveQueuedRawWrite = session.saveQueuedRawWrite
        copy.rawViewNeedsReload = true
        return copy
    }

    private static func writeRawMarkdown(_ markdown: String, to url: URL) async throws {
        try await Task.detached(priority: .utility) {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
        }.value
    }
}
