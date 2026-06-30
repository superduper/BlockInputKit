import AppKit
import UniformTypeIdentifiers

extension DemoWindowController {
    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "markdown")
        ].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK,
                  let url = panel.url else {
                return
            }
            Task { @MainActor in
                self?.model.openMarkdownFile(at: url)
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    @objc func saveDocument(_ sender: Any?) {
        guard model.currentSession?.fileURL != nil else {
            saveDocumentAs(sender)
            return
        }
        model.saveSelectedDocument()
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        guard let session = model.currentSession,
              session.loadingState == .idle else {
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "markdown")
        ].compactMap { $0 }
        panel.nameFieldStringValue = model.defaultSaveName(for: session)
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK,
                  let url = panel.url else {
                return
            }
            Task { @MainActor in
                self?.model.saveCurrentSessionAs(url)
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }
}
