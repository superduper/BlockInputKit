import BlockInputKit
import Foundation

extension DemoModel {
    func rawMarkdownBinding(for session: DemoNoteSession) -> BindingBox {
        BindingBox(
            get: { [weak self, id = session.id] in
                self?.sessions[id]?.rawMarkdown ?? ""
            },
            set: { [weak self, id = session.id] value in
                self?.handleRawTextDidChange(value, itemID: id)
            }
        )
    }

    func prepareRenderedView(for session: DemoNoteSession) {
        if session.pendingRawParseTask != nil {
            scheduleRawParse(for: session, delay: 0)
        }
    }

    func prepareRawView(for session: DemoNoteSession) {
        if session.rawViewNeedsReload {
            refreshRawMarkdownFromStore(for: session)
        }
    }

    func handleRenderedMutation(_: BlockInputDocumentChange, itemID: DemoSidebarItemID) {
        guard let session = sessions[itemID] else {
            return
        }
        session.documentRevision += 1
        let saveStatusChanged = markSessionDirty(session, rawEdit: false)
        session.rawViewNeedsReload = true
        session.pendingMarkdownTask?.cancel()
        session.pendingMarkdownTask = nil
        if saveStatusChanged {
            objectWillChange.send()
        }
    }

    func handleRenderedDocumentChange(_ document: BlockInputDocument, itemID: DemoSidebarItemID) {
        guard let session = sessions[itemID] else {
            return
        }
        let revision = session.documentRevision
        session.pendingMarkdownTask?.cancel()
        session.pendingMarkdownTask = Task { [weak self, document, itemID, revision] in
            let markdown = await Task.detached(priority: .utility) {
                document.markdown
            }.value
            self?.applyRenderedMarkdown(markdown, itemID: itemID, revision: revision)
        }
    }

    func applyRenderedMarkdown(_ markdown: String, itemID: DemoSidebarItemID, revision: Int) {
        guard let session = sessions[itemID],
              session.documentRevision == revision else {
            return
        }
        session.rawMarkdown = markdown
        session.rawViewNeedsReload = false
        session.pendingMarkdownTask = nil
        if currentItemID == itemID,
           editorMode == .raw {
            objectWillChange.send()
        }
    }

    func refreshRawMarkdownFromStore(for session: DemoNoteSession) {
        let itemID = session.id
        let revision = session.documentRevision
        let store = session.store
        session.pendingMarkdownTask?.cancel()
        session.pendingMarkdownTask = Task { [weak self, itemID, revision, store] in
            let document: BlockInputDocument
            do {
                document = try await store.completeDocumentSnapshot(limit: DemoData.progressiveLoadBatchLimit)
            } catch {
                return
            }
            let markdown = await Task.detached(priority: .utility) {
                document.markdown
            }.value
            self?.applyRenderedMarkdown(markdown, itemID: itemID, revision: revision)
        }
    }

    func handleRawTextDidChange(_ rawMarkdown: String, itemID: DemoSidebarItemID) {
        guard let session = sessions[itemID],
              session.rawMarkdown != rawMarkdown else {
            return
        }
        session.rawMarkdown = rawMarkdown
        session.rawViewNeedsReload = false
        session.documentRevision += 1
        let saveStatusChanged = markSessionDirty(session, rawEdit: true)
        session.pendingMarkdownTask?.cancel()
        session.pendingMarkdownTask = nil
        scheduleRawParse(for: session, delay: 0.35)
        if saveStatusChanged {
            objectWillChange.send()
        }
    }

    func scheduleRawParse(for session: DemoNoteSession, delay: TimeInterval) {
        let markdown = session.rawMarkdown
        let itemID = session.id
        session.rawParseGeneration += 1
        let generation = session.rawParseGeneration
        session.pendingRawParseTask?.cancel()
        session.pendingRawParseTask = Task { [weak self, markdown, itemID, generation] in
            let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)
            if nanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else {
                return
            }
            let document = await Task.detached(priority: .userInitiated) {
                BlockInputDocument(markdown: markdown)
            }.value
            self?.applyRawDocument(document, itemID: itemID, generation: generation)
        }
    }

    func applyRawDocument(_ document: BlockInputDocument, itemID: DemoSidebarItemID, generation: Int) {
        guard let session = sessions[itemID],
              session.rawParseGeneration == generation else {
            return
        }
        session.pendingRawParseTask = nil
        session.store.replaceDocument(document)
        session.undoController = BlockInputUndoController()
        if currentItemID == itemID,
           editorMode == .rendered {
            objectWillChange.send()
        }
    }
}

struct BindingBox {
    var get: () -> String
    var set: (String) -> Void
}
