import AppKit
import SwiftUI

@MainActor
public final class DemoWindowController: NSWindowController {
    let model: DemoModel

    /// The host supplies the plugin seam (`DemoEditorExtension`); DemoKit knows only the protocol, so the executable
    /// injects `BundledDemoEditorExtension` while a core-only host could inject `NullDemoEditorExtension`.
    public init(editorExtension: DemoEditorExtension) {
        self.model = DemoModel(editorExtension: editorExtension)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "BlockInputKit Demo"
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.toolbarStyle = .unified
        window.center()
        super.init(window: window)

        window.contentViewController = NSHostingController(rootView: DemoShellView(model: model))
        window.minSize = NSSize(width: 860, height: 560)
        window.setContentSize(NSSize(width: 1120, height: 760))
    }

    deinit {
        Task { @MainActor [model] in
            model.cancelPendingWork()
        }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
