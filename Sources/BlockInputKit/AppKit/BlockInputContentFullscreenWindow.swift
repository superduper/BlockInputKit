// Sources/BlockInputKit/AppKit/BlockInputContentFullscreenWindow.swift
import AppKit

/// Owns a borderless, screen-covering `NSWindow` that hosts a diagram surface (scaffold or zoom modal) at true
/// fullscreen WITHOUT putting the app's document window into macOS native fullscreen. On `present`, the surface
/// view is reparented into this window's content view (full-bleed) and the window is floated above the menu bar
/// and Dock. On `dismiss`, the surface is restored to its original parent with the full-bleed overlay layout it
/// had before, and the window is ordered out. Both surfaces are full-bleed overlays of `BlockInputView`, so the
/// restore re-adds them via autoresizing (`translatesAutoresizingMaskIntoConstraints = true`, frame = parent
/// bounds, autoresizing both axes) to match how the presenters originally added them.
@MainActor
final class BlockInputContentFullscreenWindow {
    /// Float above the menu bar and Dock so the surface truly covers the screen.
    private static let windowLevel = NSWindow.Level.mainMenu + 1
    /// "Press Esc to exit" toast metrics.
    private static let toastText = "Press Esc to exit full screen"
    private static let toastTopInset: CGFloat = 24
    private static let toastVisibleDuration: TimeInterval = 2.5
    private static let toastFadeDuration: TimeInterval = 0.4
    private static let toastHPadding: CGFloat = 16
    private static let toastVPadding: CGFloat = 8
    private static let toastCornerRadius: CGFloat = 10
    private static let toastBackgroundAlpha: CGFloat = 0.6
    private static let toastFontSize: CGFloat = 13

    private let window: NSWindow
    private weak var presentedSurface: NSView?
    private weak var restoreParent: NSView?
    private var toast: NSView?

    /// Whether a surface is currently hosted in the fullscreen window.
    var isPresented: Bool { presentedSurface != nil }

    init() {
        window = KeyableBorderlessWindow(
            contentRect: NSScreen.main?.frame ?? .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: true
        )
        window.level = Self.windowLevel
        window.isOpaque = true
        window.backgroundColor = .black
        window.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        window.isReleasedWhenClosed = false
    }

    /// Reparents `surface` into the screen-covering window. No-op if a surface is already presented.
    func present(_ surface: NSView, restoringTo parent: NSView) {
        guard !isPresented else { return }
        let screenFrame = surface.window?.screen?.frame ?? NSScreen.main?.frame ?? .zero
        window.setFrame(screenFrame, display: true)
        guard let contentView = window.contentView else { return }

        surface.removeFromSuperview()
        surface.translatesAutoresizingMaskIntoConstraints = true
        surface.frame = contentView.bounds
        surface.autoresizingMask = [.width, .height]
        contentView.addSubview(surface)

        presentedSurface = surface
        restoreParent = parent
        showExitToast(in: contentView)
        window.makeKeyAndOrderFront(nil)
    }

    /// Adds a translucent top-center "Press Esc to exit full screen" toast, then fades it out after a short
    /// visible delay so the keyboard escape hatch is discoverable without lingering over the diagram. The toast
    /// is a rounded background view hosting a white centered label inset by named padding.
    private func showExitToast(in contentView: NSView) {
        removeToast()
        let background = makeToastBackground()
        let label = makeToastLabel()
        background.addSubview(label)
        contentView.addSubview(background, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            background.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            background.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Self.toastTopInset),
            label.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: Self.toastHPadding),
            label.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -Self.toastHPadding),
            label.topAnchor.constraint(equalTo: background.topAnchor, constant: Self.toastVPadding),
            label.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -Self.toastVPadding)
        ])
        toast = background
        scheduleToastFade(background)
    }

    private func makeToastBackground() -> NSView {
        let background = NSView()
        background.translatesAutoresizingMaskIntoConstraints = false
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor.black.withAlphaComponent(Self.toastBackgroundAlpha).cgColor
        background.layer?.cornerRadius = Self.toastCornerRadius
        return background
    }

    private func makeToastLabel() -> NSTextField {
        let label = NSTextField(labelWithString: Self.toastText)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: Self.toastFontSize, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.drawsBackground = false
        return label
    }

    private func scheduleToastFade(_ toastView: NSView) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.toastVisibleDuration) { [weak self, weak toastView] in
            guard let self, let toastView, self.toast === toastView else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = Self.toastFadeDuration
                toastView.animator().alphaValue = 0
            }, completionHandler: { [weak self, weak toastView] in
                MainActor.assumeIsolated {
                    guard let self, let toastView, self.toast === toastView else { return }
                    toastView.removeFromSuperview()
                    self.toast = nil
                }
            })
        }
    }

    private func removeToast() {
        toast?.removeFromSuperview()
        toast = nil
    }

    /// Restores the presented surface to its original parent and orders the window out. No-op if not presented.
    func dismiss() {
        guard let surface = presentedSurface, let parent = restoreParent else { return }
        removeToast()
        surface.removeFromSuperview()
        surface.translatesAutoresizingMaskIntoConstraints = true
        surface.frame = parent.bounds
        surface.autoresizingMask = [.width, .height]
        parent.addSubview(surface, positioned: .above, relativeTo: nil)

        presentedSurface = nil
        restoreParent = nil
        window.orderOut(nil)
    }
}

/// A borderless window that can still become key/main, so the editor surface's text field + AI chat receive
/// keystrokes while fullscreen (a plain `.borderless` window returns `canBecomeKey == false` by default).
private final class KeyableBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
