import Foundation

/// A normalized keyboard shortcut that a host can intercept before BlockInputKit performs its built-in editor behavior.
///
/// Register shortcuts through `BlockInputConfiguration.keyboardShortcuts`. Matching normalizes equivalent hardware keys
/// into semantic values, such as main Return and keypad Enter both matching `.returnKey`.
public struct BlockInputKeyboardShortcut: Hashable, Sendable {
    /// Plain Return, including the main Return key and numeric keypad Enter.
    public static let returnKey = BlockInputKeyboardShortcut(key: .return)
    /// Shift+Return.
    public static let shiftReturn = BlockInputKeyboardShortcut(key: .return, modifiers: .shift)
    /// Option+Return.
    public static let optionReturn = BlockInputKeyboardShortcut(key: .return, modifiers: .option)

    /// Logical key pressed by the shortcut.
    public var key: BlockInputKeyboardKey
    /// Active semantic modifiers for the shortcut.
    public var modifiers: BlockInputKeyboardModifiers

    /// Creates a shortcut from a logical key and semantic modifiers.
    ///
    /// Character keys are lowercased during initialization so host registrations are case-insensitive for printable
    /// single-character shortcuts.
    public init(
        key: BlockInputKeyboardKey,
        modifiers: BlockInputKeyboardModifiers = []
    ) {
        self.key = key.normalized
        self.modifiers = modifiers
    }
}

/// Logical keys that can be registered as host keyboard shortcuts.
///
/// These values intentionally describe editor-relevant keys rather than raw key codes so the same registration can work
/// across equivalent AppKit event and selector paths.
public enum BlockInputKeyboardKey: Hashable, Sendable {
    /// Return, including numeric keypad Enter.
    case `return`
    /// Up Arrow.
    case upArrow
    /// Down Arrow.
    case downArrow
    /// Left Arrow.
    case leftArrow
    /// Right Arrow.
    case rightArrow
    /// Tab.
    case tab
    /// Escape.
    case escape
    /// A single printable character, normalized to lowercase when created through `BlockInputKeyboardShortcut`.
    case character(String)

    var normalized: Self {
        switch self {
        case .character(let value):
            return .character(value.lowercased())
        case .return, .upArrow, .downArrow, .leftArrow, .rightArrow, .tab, .escape:
            return self
        }
    }
}

/// Semantic modifier keys used when registering host keyboard shortcuts.
///
/// AppKit-only flags that do not affect shortcut meaning, such as numeric pad and caps lock, are ignored before matching.
public struct BlockInputKeyboardModifiers: OptionSet, Hashable, Sendable {
    /// Raw option-set value.
    public let rawValue: Int

    /// Shift.
    public static let shift = BlockInputKeyboardModifiers(rawValue: 1 << 0)
    /// Control.
    public static let control = BlockInputKeyboardModifiers(rawValue: 1 << 1)
    /// Option.
    public static let option = BlockInputKeyboardModifiers(rawValue: 1 << 2)
    /// Command.
    public static let command = BlockInputKeyboardModifiers(rawValue: 1 << 3)

    /// Creates semantic modifier flags from a raw option-set value.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

/// Host decision returned from a registered keyboard shortcut handler.
public enum BlockInputKeyboardShortcutResult: Equatable, Sendable {
    /// Consume the key event without running editor fallback behavior.
    case handled
    /// Continue with the editor's normal behavior for the original event.
    case ignored
    /// Run the editor's normal behavior for another shortcut instead of the original event.
    ///
    /// Supported default targets include `.returnKey` and built-in selection movement shortcuts. Unsupported targets
    /// fall back to the original event's default behavior.
    case performDefault(BlockInputKeyboardShortcut)
}

/// Editor focus surface that received a registered keyboard shortcut.
///
/// Use this to distinguish whether a shortcut came from block text, a table cell, image caret handling, or an editor-level
/// block selection path.
public enum BlockInputKeyboardShortcutFocusSource: String, Equatable, Sendable {
    /// The editor view itself handled the shortcut.
    case editor
    /// A block text view handled the shortcut.
    case blockText
    /// A table cell text view handled the shortcut.
    case tableCell
    /// The image caret handled the shortcut.
    case imageCaret
    /// A whole-block or multi-block selection handled the shortcut.
    case blockSelection
}

/// Context passed to a registered keyboard shortcut handler.
public struct BlockInputKeyboardShortcutContext: Sendable {
    /// Shortcut that matched the host registration.
    public var shortcut: BlockInputKeyboardShortcut
    /// Current editor selection, when available.
    public var selection: BlockInputSelection?
    /// Loaded active block snapshot, when available without requesting a full document snapshot.
    public var activeBlock: BlockInputBlock?
    /// Focus surface that received the shortcut.
    public var focusSource: BlockInputKeyboardShortcutFocusSource
    /// Whether the key event is an AppKit repeat.
    public var isRepeat: Bool

    /// Creates a host keyboard shortcut context.
    ///
    /// Hosts usually receive contexts from `BlockInputConfiguration.keyboardShortcuts`; this initializer exists for tests
    /// and adapter layers that need to invoke a registered handler directly.
    public init(
        shortcut: BlockInputKeyboardShortcut,
        selection: BlockInputSelection?,
        activeBlock: BlockInputBlock?,
        focusSource: BlockInputKeyboardShortcutFocusSource,
        isRepeat: Bool
    ) {
        self.shortcut = shortcut
        self.selection = selection
        self.activeBlock = activeBlock
        self.focusSource = focusSource
        self.isRepeat = isRepeat
    }
}

/// Synchronous main-actor handler for a registered host keyboard shortcut.
///
/// Return promptly from this handler. Start asynchronous host work after returning `.handled` rather than blocking
/// AppKit key dispatch.
public typealias BlockInputKeyboardShortcutHandler =
    @MainActor @Sendable (BlockInputKeyboardShortcutContext) -> BlockInputKeyboardShortcutResult
