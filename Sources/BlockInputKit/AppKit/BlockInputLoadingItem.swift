import AppKit

/// Collection item used as the visible sentinel for progressive loading.
final class BlockInputLoadingItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("BlockInputLoadingItem")

    private let progress = NSProgressIndicator()
    private let label = NSTextField(labelWithString: "Loading...")

    override func loadView() {
        let view = NSView()
        view.wantsLayer = true

        progress.style = .spinning
        progress.controlSize = .small
        progress.startAnimation(nil)
        progress.translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [progress, label])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        self.view = view
    }

    func configure(error: String?, surfaceStyle: BlockInputEditorSurfaceStyle) {
        applySurfaceStyle(surfaceStyle)
        if let error {
            progress.stopAnimation(nil)
            progress.isHidden = true
            label.stringValue = "Could not load more blocks: \(error)"
        } else {
            progress.isHidden = false
            progress.startAnimation(nil)
            label.stringValue = "Loading..."
        }
    }

    func applySurfaceStyle(_ surfaceStyle: BlockInputEditorSurfaceStyle) {
        view.wantsLayer = true
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = surfaceStyle.collectionBackgroundColor?.cgColor
        }
    }
}
