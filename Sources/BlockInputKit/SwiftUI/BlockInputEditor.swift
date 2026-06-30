import AppKit
import SwiftUI

/// SwiftUI wrapper around `BlockInputView`.
public struct BlockInputEditor: NSViewRepresentable {
    private let configuration: BlockInputConfiguration
    private let isFocused: Binding<Bool>?

    /// Creates a SwiftUI editor whose AppKit focus is managed internally.
    public init(configuration: BlockInputConfiguration = BlockInputConfiguration()) {
        self.configuration = configuration
        isFocused = nil
    }

    /// Creates a SwiftUI editor that synchronizes AppKit focus with a SwiftUI binding.
    ///
    /// Setting the binding to `true` focuses the editor and restores the current selection,
    /// including source selections that map into a table cell.
    /// Setting it to `false` resigns editor focus without restoring a previous text selection.
    public init(
        configuration: BlockInputConfiguration = BlockInputConfiguration(),
        isFocused: Binding<Bool>
    ) {
        self.configuration = configuration
        self.isFocused = isFocused
    }

    /// Creates the wrapped AppKit editor view.
    public func makeNSView(context: Context) -> BlockInputView {
        let view = BlockInputView()
        updateView(view)
        return view
    }

    /// Applies the current SwiftUI configuration and focus binding to the wrapped AppKit editor view.
    public func updateNSView(_ nsView: BlockInputView, context: Context) {
        updateView(nsView)
    }

    /// Returns the AppKit editor's preferred rendered height when height sizing is enabled.
    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: BlockInputView, context: Context) -> CGSize? {
        guard nsView.heightSizing != nil else {
            return nil
        }
        guard let width = proposal.width ?? (nsView.bounds.width > 0 ? nsView.bounds.width : nil) else {
            return nil
        }
        let height = nsView.preferredHeight(forWidth: width)
        return CGSize(width: width, height: height)
    }

    func updateView(_ view: BlockInputView) {
        let resolvedConfiguration = resolvedConfiguration()
        if isFocused?.wrappedValue == false {
            view.onFocusChange = resolvedConfiguration.onFocusChange
            _ = view.resignEditorFocus()
            view.configure(resolvedConfiguration, restoresFocus: false)
            if view.isEditorFirstResponder {
                _ = view.resignEditorFocus()
            }
            view.publishFocusChange(false)
            return
        }
        view.configure(
            resolvedConfiguration,
            restoresFocus: isFocused?.wrappedValue ?? true
        )
        updateFocusState(on: view)
    }

    func resolvedConfiguration() -> BlockInputConfiguration {
        guard let isFocused else {
            return configuration
        }
        var configuration = configuration
        let onFocusChange = configuration.onFocusChange
        configuration.onFocusChange = { focused in
            onFocusChange?(focused)
            isFocused.wrappedValue = focused
        }
        return configuration
    }

    func updateFocusState(on view: BlockInputView) {
        guard let isFocused else {
            return
        }
        if isFocused.wrappedValue {
            view.focusEditor()
        } else {
            view.resignEditorFocus()
        }
    }
}
