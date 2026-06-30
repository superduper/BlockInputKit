import AppKit
import BlockInputKit
import SwiftUI

/// NSViewRepresentable that wraps BlockInputView and lets the host extension bind its view-bound adapters
/// (vim, formatting menu) through an opaque `bind` closure, so this file imports no plugin module.
struct DemoRenderedEditor: NSViewRepresentable {
    var configuration: BlockInputConfiguration
    var bind: (BlockInputView) -> Void

    func makeNSView(context: Context) -> BlockInputView {
        let view = BlockInputView()
        view.configure(configuration)
        bind(view)
        return view
    }

    func updateNSView(_ nsView: BlockInputView, context: Context) {
        nsView.configure(configuration)
        bind(nsView)
    }
}
