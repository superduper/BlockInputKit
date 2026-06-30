import AppKit

extension BlockInputBlockItem {
    func setReorderHandleVisible(_ isVisible: Bool, animated: Bool = true) {
        let alpha: CGFloat = isVisible && handleView.isEnabled ? 1 : 0
        handleView.layer?.removeAllAnimations()
        guard animated else {
            handleView.alphaValue = alpha
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            handleView.animator().alphaValue = alpha
        }
    }
}
