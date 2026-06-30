import AppKit
import BlockInputKit
import Combine
import SwiftUI

/// The single seam through which host plugins wire themselves into the demo editor.
/// DemoKit (core) knows only this protocol; the plugins repo supplies a conformer
/// that pulls in Vim/Wikilink/Zoom/Paste/WebKit/FormattingMenu.
@MainActor
public protocol DemoEditorExtension: AnyObject {
    /// Lets the extension publish changes (vim mode, zoom level) so SwiftUI re-renders.
    var changePublisher: AnyPublisher<Void, Never> { get }

    /// Optional completion provider that wraps/overrides the demo's file provider.
    /// Return nil to use the file provider alone.
    func makeCompletionProvider(fileProvider: BlockInputCompletionProvider) -> BlockInputCompletionProvider?

    /// Mutate the editor configuration to register plugin seams (markup, paste, renderers, overlays…).
    func registerPlugins(on configuration: inout BlockInputConfiguration, context: DemoExtensionContext)

    /// Called after the editor NSView is created/updated so view-bound adapters (vim, formatting menu) can bind.
    func bind(to view: BlockInputView)

    /// Control-strip accessory views the extension contributes (vim toggle/indicator, zoom buttons…).
    /// Returned as type-erased SwiftUI views grouped by section.
    func controlStripAccessories(_ section: DemoControlStripSection) -> AnyView?

    /// Vim/zoom inputs the configuration needs each build.
    var insertionPointStyleOverride: BlockInputInsertionPointStyle? { get }
    func scaledStyle(_ base: BlockInputStyle) -> BlockInputStyle
}

/// Read-only signals the extension needs when building a configuration.
@MainActor
public struct DemoExtensionContext {
    public var isEditable: Bool
    /// Currently-selected file-chip tag style (toolbar dropdown). The plugin extension turns this into the
    /// Paste-backed `inlineChipAccessoryProvider`, so DemoKit never imports the Paste accessory types.
    public var chipTagStyle: DemoChipTagStyle
    public init(isEditable: Bool, chipTagStyle: DemoChipTagStyle = .iconOnly) {
        self.isEditable = isEditable
        self.chipTagStyle = chipTagStyle
    }
}

public enum DemoControlStripSection {
    case editing
    case view
}

/// No-op extension used by the core-only demo executable (zero plugins).
@MainActor
public final class NullDemoEditorExtension: DemoEditorExtension {
    public init() {}
    public var changePublisher: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    public func makeCompletionProvider(fileProvider: BlockInputCompletionProvider) -> BlockInputCompletionProvider? { nil }
    public func registerPlugins(on configuration: inout BlockInputConfiguration, context: DemoExtensionContext) {}
    public func bind(to view: BlockInputView) {}
    public func controlStripAccessories(_ section: DemoControlStripSection) -> AnyView? { nil }
    public var insertionPointStyleOverride: BlockInputInsertionPointStyle? { nil }
    public func scaledStyle(_ base: BlockInputStyle) -> BlockInputStyle { base }
}
