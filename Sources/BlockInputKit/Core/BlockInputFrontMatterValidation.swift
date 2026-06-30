import Foundation

/// A non-blocking frontmatter shape issue detected in a raw YAML body.
public struct BlockInputFrontMatterValidationIssue: Equatable, Codable, Sendable {
    /// The broad validation failure category.
    public enum Kind: String, Equatable, Codable, Sendable {
        /// A top-level mapping line has no key before its colon.
        case emptyKey
        /// A top-level key appears more than once.
        case duplicateKey
        /// A top-level key has no scalar value or indented continuation.
        case emptyValue
        /// A top-level line is neither blank, a comment, nor a simple key/value pair.
        case invalidTopLevelLine
        /// An indented line appears before any top-level key.
        case orphanIndentedLine
        /// A YAML frontmatter delimiter appears inside the delimiter-free body.
        case delimiterInBody
    }

    /// Zero-based line index in the frontmatter body.
    public var lineIndex: Int
    /// Validation issue category for the line.
    public var kind: Kind

    /// Creates a frontmatter validation issue.
    public init(lineIndex: Int, kind: Kind) {
        self.lineIndex = lineIndex
        self.kind = kind
    }
}

public extension BlockInputBlock {
    /// Shape issues in a frontmatter block's raw YAML body.
    ///
    /// Validation is intentionally advisory and dependency-free. It recognizes
    /// only simple top-level key/value structure so hosts can preserve and
    /// interpret the raw YAML source however they need.
    var frontMatterValidationIssues: [BlockInputFrontMatterValidationIssue] {
        guard kind == .frontMatter else {
            return []
        }
        return BlockInputFrontMatterValidator.issues(in: text)
    }
}

/// Bounded frontmatter shape validator for editor hints only.
///
/// This deliberately avoids YAML parsing so raw source formatting and host-owned
/// interpretation stay untouched while obvious line-shape issues can be styled.
enum BlockInputFrontMatterValidator {
    static func issues(in text: String) -> [BlockInputFrontMatterValidationIssue] {
        var issues: [BlockInputFrontMatterValidationIssue] = []
        var seenKeys: Set<String> = []
        var hasCurrentKey = false
        var pendingEmptyValueLineIndex: Int?

        for (lineIndex, line) in BlockInputLineBreaks.lines(in: text).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            if trimmed == "---" || trimmed == "..." {
                appendPendingEmptyValueIssue(&issues, lineIndex: &pendingEmptyValueLineIndex)
                issues.append(BlockInputFrontMatterValidationIssue(lineIndex: lineIndex, kind: .delimiterInBody))
                continue
            }
            if line.first?.isWhitespace == true {
                if !hasCurrentKey {
                    issues.append(BlockInputFrontMatterValidationIssue(lineIndex: lineIndex, kind: .orphanIndentedLine))
                } else {
                    pendingEmptyValueLineIndex = nil
                }
                continue
            }
            appendPendingEmptyValueIssue(&issues, lineIndex: &pendingEmptyValueLineIndex)
            guard let colonIndex = line.firstIndex(of: ":") else {
                hasCurrentKey = false
                issues.append(BlockInputFrontMatterValidationIssue(lineIndex: lineIndex, kind: .invalidTopLevelLine))
                continue
            }
            let key = line[..<colonIndex].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else {
                hasCurrentKey = false
                issues.append(BlockInputFrontMatterValidationIssue(lineIndex: lineIndex, kind: .emptyKey))
                continue
            }
            if seenKeys.contains(key) {
                issues.append(BlockInputFrontMatterValidationIssue(lineIndex: lineIndex, kind: .duplicateKey))
            }
            seenKeys.insert(key)
            let valueStart = line.index(after: colonIndex)
            if line[valueStart...].trimmingCharacters(in: .whitespaces).isEmpty {
                pendingEmptyValueLineIndex = lineIndex
            }
            hasCurrentKey = true
        }
        appendPendingEmptyValueIssue(&issues, lineIndex: &pendingEmptyValueLineIndex)
        return issues
    }

    private static func appendPendingEmptyValueIssue(
        _ issues: inout [BlockInputFrontMatterValidationIssue],
        lineIndex: inout Int?
    ) {
        guard let pendingLineIndex = lineIndex else {
            return
        }
        issues.append(BlockInputFrontMatterValidationIssue(lineIndex: pendingLineIndex, kind: .emptyValue))
        lineIndex = nil
    }
}
