import AppKit

@MainActor
public final class DemoAppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: DemoWindowController?
    private let makeEditorExtension: () -> DemoEditorExtension

    /// The host injects the plugin seam factory; DemoKit stays plugin-free. Defaults to the no-op extension so a
    /// core-only host can launch the demo without any plugins.
    public init(makeEditorExtension: @escaping () -> DemoEditorExtension = { NullDemoEditorExtension() }) {
        self.makeEditorExtension = makeEditorExtension
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        let windowController = DemoWindowController(editorExtension: makeEditorExtension())
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
        self.windowController = windowController
        activateDemoApp()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        mainMenu.addItem(fileMenuItem)
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        mainMenu.addItem(editMenuItem)

        let appMenu = NSMenu()
        let quitItem = NSMenuItem(
            title: "Quit \(ProcessInfo.processInfo.processName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = NSApp
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu

        let fileMenu = NSMenu(title: "File")
        let openItem = NSMenuItem(title: "Open...", action: #selector(openDocument(_:)), keyEquivalent: "o")
        openItem.keyEquivalentModifierMask = .command
        openItem.target = self
        fileMenu.addItem(openItem)
        fileMenu.addItem(.separator())
        let saveItem = NSMenuItem(title: "Save", action: #selector(saveDocument(_:)), keyEquivalent: "s")
        saveItem.keyEquivalentModifierMask = .command
        saveItem.target = self
        fileMenu.addItem(saveItem)
        let saveAsItem = NSMenuItem(title: "Save As...", action: #selector(saveDocumentAs(_:)), keyEquivalent: "S")
        saveAsItem.keyEquivalentModifierMask = [.command, .shift]
        saveAsItem.target = self
        fileMenu.addItem(saveAsItem)
        fileMenuItem.submenu = fileMenu

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        NSApp.mainMenu = mainMenu
    }

    @objc private func openDocument(_ sender: Any?) {
        windowController?.openDocument(sender)
    }

    @objc private func saveDocument(_ sender: Any?) {
        windowController?.saveDocument(sender)
    }

    @objc private func saveDocumentAs(_ sender: Any?) {
        windowController?.saveDocumentAs(sender)
    }

    private func activateDemoApp() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
