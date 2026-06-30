import AppKit
import BlockInputKit
import SwiftUI

struct DemoShellView: View {
    @ObservedObject var model: DemoModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: selection) {
                Section(DemoSidebarSection.notes.title) {
                    ForEach(model.sidebarItems(in: .notes), id: \.id) { item in
                        Text(item.title)
                            .tag(item.id)
                    }
                }
                Section(DemoSidebarSection.files.title) {
                    ForEach(model.sidebarItems(in: .files), id: \.id) { item in
                        Text(item.title)
                            .tag(item.id)
                            .help(helpText(for: item))
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 176, ideal: 220, max: 280)
        } detail: {
            detailView
        }
    }

    private var selection: Binding<DemoSidebarItemID?> {
        Binding(
            get: { model.selectedItemID },
            set: { itemID in
                guard let itemID else {
                    return
                }
                model.select(itemID)
            }
        )
    }

    @ViewBuilder
    private var detailView: some View {
        if let session = model.currentSession {
            switch session.loadingState {
            case .idle:
                editorView(for: session)
            case .loading:
                LoadingStateView(title: session.title)
            case .failed(let message):
                ErrorStateView(message: message)
            }
        } else {
            LoadingStateView(title: model.currentItemID.title)
        }
    }

    private func editorView(for session: DemoNoteSession) -> some View {
        VStack(spacing: 0) {
            controlStrip(for: session)
            Divider()
            ZStack {
                switch model.editorMode {
                case .rendered:
                    renderedEditor(for: session)
                case .raw:
                    if session.rawViewNeedsReload {
                        LoadingStateView(title: session.title)
                    } else {
                        DemoRawMarkdownEditor(text: Binding(
                            get: { model.rawMarkdownBinding(for: session).get() },
                            set: { model.rawMarkdownBinding(for: session).set($0) }
                        ), isEditable: model.isEditable)
                        .id(session.id)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func renderedEditor(for session: DemoNoteSession) -> some View {
        DemoRenderedEditor(
            configuration: model.editorConfiguration(for: session),
            bind: { model.editorExtension.bind(to: $0) }
        )
        .id(session.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func controlStrip(for session: DemoNoteSession) -> some View {
        // Grouped into labeled sections across rows so the controls don't crowd off-screen.
        VStack(alignment: .leading, spacing: 10) {
            titleRow(for: session)
            Divider()
            controlSection("Editing") { editingControls }
            controlSection("View") { viewControls }
            controlSection("File chips") { fileChipControls }
        }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
    }

    private func titleRow(for session: DemoNoteSession) -> some View {
        HStack(spacing: 12) {
            Text(session.title)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
            Text(model.saveStatusText(for: session))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 16)
        }
    }

    /// A labeled control section: a fixed-width caption followed by its controls.
    private func controlSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            content()
            Spacer(minLength: 8)
        }
    }

    private var editingControls: some View {
        HStack(spacing: 12) {
            Toggle("Read-only", isOn: Binding(
                get: { !model.isEditable },
                set: { model.setIsEditable(!$0) }
            ))
            Toggle("Reordering", isOn: Binding(
                get: { model.allowsReordering },
                set: { model.setAllowsReordering($0) }
            ))
            if let accessories = model.editorExtension.controlStripAccessories(.editing) {
                accessories
                    .disabled(model.editorMode == .raw)
            }
        }
    }

    private var viewControls: some View {
        HStack(spacing: 12) {
            Picker("Mode", selection: Binding(
                get: { model.editorMode },
                set: { model.setEditorMode($0) }
            )) {
                ForEach(DemoEditorMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            Picker("Completion", selection: Binding(
                get: { model.completionPopupPlacement },
                set: { model.setCompletionPopupPlacement($0) }
            )) {
                ForEach(BlockInputCompletionPopupPlacement.allCases, id: \.self) { placement in
                    Text(placement.demoTitle).tag(placement)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            if let accessories = model.editorExtension.controlStripAccessories(.view) {
                accessories
                    .disabled(model.editorMode == .raw)
            }
        }
    }

    private var fileChipControls: some View {
        Picker("Tag style", selection: Binding(
            get: { model.chipTagStyle },
            set: { model.setChipTagStyle($0) }
        )) {
            ForEach(DemoChipTagStyle.allCases, id: \.self) { style in
                Text(style.title).tag(style)
            }
        }
        .labelsHidden()
        .frame(width: 220)
        .help("Preview how file-chip type tags render")
    }

    private func helpText(for item: DemoSidebarItem) -> String {
        guard case .file(let url) = item.id else {
            return item.title
        }
        return url.path
    }
}

enum DemoCompletionOverlayMetrics {
    static let topInset: CGFloat = 12
}

private extension BlockInputCompletionPopupPlacement {
    var demoTitle: String {
        switch self {
        case .caret:
            return "Caret"
        case .overlay:
            return "Overlay"
        }
    }
}

private struct LoadingStateView: View {
    var title: String

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.regular)
            Text("Loading \(title)...")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ErrorStateView: View {
    var message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DemoRawMarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = nsView.documentView as? NSTextView,
              textView.isEditable != isEditable || textView.string != text else {
            return
        }
        context.coordinator.isUpdating = true
        textView.isEditable = isEditable
        textView.isSelectable = true
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.isUpdating = false
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var isUpdating = false

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating,
                  let textView = notification.object as? NSTextView else {
                return
            }
            text.wrappedValue = textView.string
        }
    }
}
