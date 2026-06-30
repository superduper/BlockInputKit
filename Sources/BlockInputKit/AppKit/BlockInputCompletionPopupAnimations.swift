import AppKit
import QuartzCore

@MainActor
func blockInputWithoutCompletionPopupAnimations(_ updates: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    NSAnimationContext.runAnimationGroup { context in
        context.duration = 0
        context.allowsImplicitAnimation = false
        updates()
    }
    CATransaction.commit()
}
