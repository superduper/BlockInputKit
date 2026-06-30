import Foundation

/// Controls how editor-owned select-all commands expand the active selection.
public enum BlockInputSelectAllBehavior: String, Equatable, Codable, Sendable {
    /// Selects the focused content first, then promotes to the whole document on the next command.
    ///
    /// Empty focused text blocks promote directly to the whole document because there is no focused content to select.
    case focusedContentThenDocument
    /// Selects the whole editor document immediately from any editor-owned focus.
    ///
    /// Focused modal fields, such as link or image editors, keep their native AppKit select-all behavior.
    case document
}
