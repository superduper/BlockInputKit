import AppKit

extension BlockInputView {
    var shouldDeferDocumentChangeSnapshot: Bool {
        guard let documentStore else {
            return false
        }
        return !documentStore.isComplete || blockCount > largeDocumentCacheMutationLimit
    }

    func publishDocumentMutation(_ change: BlockInputDocumentChange) {
        onDocumentMutation?(change)
    }

    func cancelPendingDocumentSnapshot() {
        documentSnapshotGeneration += 1
        pendingDocumentSnapshotWorkItem?.cancel()
        pendingDocumentSnapshotWorkItem = nil
    }

    func scheduleDeferredDocumentSnapshot() {
        documentSnapshotGeneration += 1
        let generation = documentSnapshotGeneration
        pendingDocumentSnapshotWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.startDeferredDocumentSnapshot(generation: generation)
            }
        }
        pendingDocumentSnapshotWorkItem = workItem
        let delay = max(0, documentChangeSnapshotDelay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func startDeferredDocumentSnapshot(generation: Int) {
        guard generation == documentSnapshotGeneration,
              onDocumentChange != nil else {
            return
        }
        if let documentStore {
            let snapshotLoadBatchLimit = progressiveLoadBatchLimit
            Task { [weak self, documentStore] in
                let snapshot: BlockInputDocument
                do {
                    snapshot = try await documentStore.completeDocumentSnapshot(limit: snapshotLoadBatchLimit)
                } catch {
                    await MainActor.run { [weak self] in
                        guard let self,
                              generation == self.documentSnapshotGeneration else {
                            return
                        }
                        self.pendingDocumentSnapshotWorkItem = nil
                    }
                    return
                }
                await MainActor.run { [weak self] in
                    guard let self,
                          generation == self.documentSnapshotGeneration else {
                        return
                    }
                    self.pendingDocumentSnapshotWorkItem = nil
                    self.onDocumentChange?(snapshot)
                }
            }
            return
        }
        pendingDocumentSnapshotWorkItem = nil
        onDocumentChange?(document.detachedStorage())
    }
}
