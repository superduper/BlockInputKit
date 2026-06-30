import AppKit

extension BlockInputView {
    /// Returns whether the editor can become the first responder.
    public override var acceptsFirstResponder: Bool { true }

    /// Reapplies appearance-dependent surface colors when AppKit changes the effective appearance.
    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyEditorSurfaceStyle()
        collectionView.visibleItems().forEach { item in
            (item as? BlockInputLoadingItem)?.applySurfaceStyle(style.editorSurface)
        }
        refreshImagePreviewStrip()
    }

    public override func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        updateEditorChromeLayers()
    }
}
