import AppKit

/// Lightweight regex-based syntax highlighter used by AppKit code surfaces.
@MainActor
enum BlockInputSyntaxHighlighter {
    static let maximumHighlightedUTF16Length = 200_000

    static func highlighted(
        _ source: String,
        language: String?,
        colorScheme: BlockInputSyntaxColorScheme,
        font: NSFont? = nil,
        baseForegroundColor: NSColor? = nil,
        preserveLineNumberPrefixes: Bool = false
    ) -> NSAttributedString {
        let palette = BlockInputSyntaxPalette(colorScheme: colorScheme, baseForegroundColor: baseForegroundColor)
        let baseAttributes = baseAttributes(font: font, foregroundColor: palette.base)
        let attributed = NSMutableAttributedString(string: source, attributes: baseAttributes)
        let normalizedLanguage = normalizedLanguage(language)
        guard !source.isEmpty,
              (source as NSString).length <= maximumHighlightedUTF16Length,
              let spec = languageSpecs[normalizedLanguage] else {
            return attributed
        }

        var protectedRanges: [NSRange] = []
        let protectedMatches = spec.protectedRules(palette: palette)
            .flatMap { matches(for: $0, in: source) }
            .sorted { lhs, rhs in
                if lhs.range.location == rhs.range.location {
                    return lhs.range.length > rhs.range.length
                }
                return lhs.range.location < rhs.range.location
            }

        for match in protectedMatches where !protectedRanges.intersects(match.range) {
            apply(match.color, to: match.range, in: attributed)
            protectedRanges.append(match.range)
        }

        for rule in spec.nonProtectedRules(palette: palette) {
            for match in matches(for: rule, in: source) where !protectedRanges.intersects(match.range) {
                apply(match.color, to: match.range, in: attributed)
            }
        }

        if preserveLineNumberPrefixes {
            applyBaseColorToLeadingLineNumberPrefixes(in: source, palette: palette, attributed: attributed)
        }

        return attributed
    }

    static func normalizedLanguage(_ language: String?) -> String {
        let normalized = (language ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return languageAliases[normalized] ?? normalized
    }

    private static func baseAttributes(font: NSFont?, foregroundColor: NSColor) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: foregroundColor
        ]
        if let font {
            attributes[.font] = font
        }
        return attributes
    }

    private static func matches(for rule: Rule, in source: String) -> [TokenMatch] {
        guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else {
            return []
        }
        let fullRange = NSRange(location: 0, length: (source as NSString).length)
        return regex.matches(in: source, options: [], range: fullRange).map {
            TokenMatch(range: $0.range, color: rule.color)
        }
    }

    private static func apply(_ color: NSColor, to range: NSRange, in attributed: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: attributed.length)
        let clampedRange = NSIntersectionRange(range, fullRange)
        guard clampedRange.length > 0 else {
            return
        }
        attributed.addAttribute(.foregroundColor, value: color, range: clampedRange)
    }

    private static func applyBaseColorToLeadingLineNumberPrefixes(
        in source: String,
        palette: BlockInputSyntaxPalette,
        attributed: NSMutableAttributedString
    ) {
        let fullRange = NSRange(location: 0, length: (source as NSString).length)
        let regex = try? NSRegularExpression(pattern: #"^\s*\d+(\t| +)"#, options: [.anchorsMatchLines])
        regex?.matches(in: source, options: [], range: fullRange).forEach {
            apply(palette.base, to: $0.range, in: attributed)
        }
    }
}

enum BlockInputSyntaxColorScheme {
    case light
    case dark

    init(appearance: NSAppearance) {
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            self = .dark
        default:
            self = .light
        }
    }
}

private struct TokenMatch {
    let range: NSRange
    let color: NSColor
}

private extension BlockInputSyntaxHighlighter {
    struct Rule {
        let pattern: String
        let options: NSRegularExpression.Options
        let color: NSColor
    }

    struct BlockInputSyntaxPalette {
        let base: NSColor
        let keyword: NSColor
        let string: NSColor
        let comment: NSColor
        let number: NSColor
        let symbol: NSColor

        init(colorScheme: BlockInputSyntaxColorScheme, baseForegroundColor: NSColor? = nil) {
            base = baseForegroundColor ?? .labelColor
            switch colorScheme {
            case .dark:
                keyword = NSColor(srgbRed: 0.64, green: 0.74, blue: 1.0, alpha: 1)
                string = NSColor(srgbRed: 0.98, green: 0.72, blue: 0.68, alpha: 1)
                comment = NSColor(srgbRed: 0.53, green: 0.57, blue: 0.60, alpha: 1)
                number = NSColor(srgbRed: 0.82, green: 0.82, blue: 0.88, alpha: 1)
                symbol = NSColor(srgbRed: 0.74, green: 0.78, blue: 0.86, alpha: 1)
            case .light:
                keyword = NSColor(srgbRed: 0.64, green: 0.08, blue: 0.50, alpha: 1)
                string = NSColor(srgbRed: 0.77, green: 0.10, blue: 0.10, alpha: 1)
                comment = NSColor(srgbRed: 0.25, green: 0.45, blue: 0.12, alpha: 1)
                number = NSColor(srgbRed: 0.10, green: 0.31, blue: 0.60, alpha: 1)
                symbol = NSColor(srgbRed: 0.33, green: 0.36, blue: 0.42, alpha: 1)
            }
        }
    }

    struct LanguageSpec {
        let commentPatterns: [String]
        let stringPatterns: [String]
        let keywords: [String]
        let annotationPattern: String?
        let extraKeywordPatterns: [String]
        let symbolPatterns: [String]
        let numberPattern: String

        init(
            commentPatterns: [String],
            stringPatterns: [String],
            keywords: [String],
            annotationPattern: String? = nil,
            extraKeywordPatterns: [String] = [],
            symbolPatterns: [String] = [],
            numberPattern: String = #"\b-?\d+(\.\d+)?\b"#
        ) {
            self.commentPatterns = commentPatterns
            self.stringPatterns = stringPatterns
            self.keywords = keywords
            self.annotationPattern = annotationPattern
            self.extraKeywordPatterns = extraKeywordPatterns
            self.symbolPatterns = symbolPatterns
            self.numberPattern = numberPattern
        }

        func protectedRules(palette: BlockInputSyntaxPalette) -> [Rule] {
            stringPatterns.map { Rule(pattern: $0, options: [.anchorsMatchLines], color: palette.string) }
                + commentPatterns.map { Rule(pattern: $0, options: [.anchorsMatchLines], color: palette.comment) }
        }

        func nonProtectedRules(palette: BlockInputSyntaxPalette) -> [Rule] {
            var rules: [Rule] = []
            if let annotationPattern {
                rules.append(Rule(pattern: annotationPattern, options: [.anchorsMatchLines], color: palette.keyword))
            }
            if !keywords.isEmpty {
                let escapedKeywords = keywords
                    .map(NSRegularExpression.escapedPattern(for:))
                    .joined(separator: "|")
                rules.append(Rule(pattern: #"\b("# + escapedKeywords + #")\b"#, options: [.caseInsensitive], color: palette.keyword))
            }
            for pattern in extraKeywordPatterns {
                rules.append(Rule(pattern: pattern, options: [.anchorsMatchLines, .caseInsensitive], color: palette.keyword))
            }
            for pattern in symbolPatterns {
                rules.append(Rule(pattern: pattern, options: [.anchorsMatchLines], color: palette.symbol))
            }
            rules.append(Rule(pattern: numberPattern, options: [.caseInsensitive], color: palette.number))
            return rules
        }
    }
}

private extension BlockInputSyntaxHighlighter {
    static let asciiDoubleString = #""([^"\\]|\\.)*""#
    static let asciiSingleString = #"'([^'\\]|\\.)*'"#
    static let smartDoubleString = smartQuotedString(open: "\u{201C}", close: "\u{201D}")
    static let smartSingleString = smartQuotedString(open: "\u{2018}", close: "\u{2019}")
    static let stringDoubleSingle = [
        asciiDoubleString,
        smartDoubleString,
        asciiSingleString,
        smartSingleString
    ]
    static let stringDoubleOnly = [asciiDoubleString, smartDoubleString]
    static let cLikeComments = [#"//.*$"#, #"/\*[\s\S]*?\*/"#]
    static let cLikeStrings = stringDoubleSingle + [#"'([^'\\]|\\.)'"#]

    static let swiftKeywords = [
        "func", "var", "let", "if", "else", "for", "while", "guard", "return", "class", "struct", "enum",
        "protocol", "import", "extension", "public", "private", "internal", "static", "final", "override", "init",
        "self", "Self", "throws", "throw", "try", "catch", "do", "in", "as", "is", "nil", "true", "false",
        "where", "case", "switch", "break", "continue", "default", "typealias", "associatedtype", "lazy",
        "weak", "strong", "unowned", "mutating", "nonmutating", "fileprivate", "open", "some", "any", "async",
        "await", "defer", "repeat", "required", "convenience", "inout", "subscript", "operator", "precedencegroup"
    ]

    static let pythonKeywords = [
        "def", "class", "if", "elif", "else", "for", "while", "return", "import", "from", "as", "try",
        "except", "finally", "raise", "with", "in", "is", "not", "and", "or", "True", "False", "None",
        "lambda", "pass", "break", "continue", "yield", "global", "nonlocal", "async", "await", "del", "assert"
    ]

    static let javascriptKeywords = [
        "function", "var", "let", "const", "if", "else", "for", "while", "return", "class", "extends", "import",
        "export", "from", "as", "try", "catch", "finally", "throw", "switch", "case", "default", "break",
        "continue", "new", "this", "super", "typeof", "instanceof", "in", "of", "null", "undefined", "true",
        "false", "async", "await", "yield", "interface", "type", "enum", "namespace", "readonly", "public",
        "private", "protected", "static", "abstract"
    ]

    static let bashKeywords = [
        "if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac", "in", "function",
        "return", "exit", "break", "continue", "export", "local", "readonly"
    ]

    static let rubyKeywords = [
        "def", "end", "class", "module", "if", "elsif", "else", "unless", "for", "while", "until", "do",
        "return", "require", "require_relative", "include", "extend", "begin", "rescue", "ensure", "raise",
        "yield", "lambda", "proc", "self", "nil", "true", "false", "and", "or", "not", "in", "when", "case",
        "then", "break", "next", "redo", "retry", "super"
    ]

    static let goKeywords = [
        "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for", "func",
        "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select", "struct",
        "switch", "type", "var", "true", "false", "nil", "iota"
    ]

    static let rustKeywords = [
        "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern", "false",
        "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return",
        "self", "Self", "static", "struct", "super", "trait", "true", "type", "union", "unsafe", "use", "where",
        "while"
    ]

    static let jvmKeywords = [
        "abstract", "as", "break", "case", "catch", "class", "companion", "const", "continue", "crossinline",
        "data", "default", "do", "else", "enum", "extends", "final", "finally", "for", "fun", "if", "implements",
        "import", "in", "infix", "inline", "inner", "interface", "internal", "is", "lateinit", "new", "null",
        "object", "open", "operator", "out", "override", "package", "private", "protected", "public", "reified",
        "return", "sealed", "static", "super", "suspend", "switch", "synchronized", "this", "throw", "throws",
        "transient", "true", "try", "typealias", "val", "var", "void", "volatile", "when", "while", "yield"
    ]

    static let cKeywords = [
        "auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else", "enum", "extern",
        "float", "for", "goto", "if", "inline", "int", "long", "register", "restrict", "return", "short", "signed",
        "sizeof", "static", "struct", "switch", "typedef", "union", "unsigned", "void", "volatile", "while",
        "_Bool", "_Complex", "_Imaginary"
    ]

    static let cppKeywords = cKeywords + [
        "alignas", "alignof", "and", "and_eq", "asm", "bitand", "bitor", "bool", "catch", "char16_t", "char32_t",
        "class", "compl", "concept", "constexpr", "const_cast", "decltype", "delete", "dynamic_cast", "explicit",
        "export", "false", "friend", "mutable", "namespace", "new", "noexcept", "not", "not_eq", "nullptr",
        "operator", "or", "or_eq", "private", "protected", "public", "reinterpret_cast", "requires", "static_assert",
        "static_cast", "template", "this", "thread_local", "throw", "true", "try", "typename", "using", "virtual",
        "xor", "xor_eq"
    ]

    static let objectiveCKeywords = cKeywords + [
        "id", "instancetype", "nil", "Nil", "NULL", "YES", "NO", "self", "super", "atomic", "nonatomic", "strong",
        "weak", "copy", "assign", "readonly", "readwrite", "nullable", "nonnull"
    ]

    static let sqlKeywords = [
        "select", "from", "where", "join", "inner", "left", "right", "full", "outer", "on", "group", "by", "order",
        "having", "limit", "offset", "insert", "into", "values", "update", "set", "delete", "create", "alter",
        "drop", "table", "view", "index", "primary", "key", "foreign", "references", "constraint", "and", "or",
        "not", "null", "is", "in", "exists", "case", "when", "then", "else", "end", "as", "distinct", "union",
        "all", "with", "recursive", "transaction", "begin", "commit", "rollback", "returning", "true", "false"
    ]

    static let languageAliases: [String: String] = [
        "js": "javascript", "mjs": "javascript", "cjs": "javascript",
        "ts": "typescript", "jsx": "jsx", "tsx": "tsx",
        "sh": "bash", "zsh": "bash", "shell": "bash",
        "yml": "yaml",
        "md": "markdown",
        "m": "objectivec", "mm": "objectivec", "objc": "objectivec", "objective-c": "objectivec", "obj-c": "objectivec",
        "c++": "cpp", "cc": "cpp", "cxx": "cpp", "hpp": "cpp", "hxx": "cpp",
        "htm": "html",
        "plist": "xml"
    ]

    static let languageSpecs: [String: LanguageSpec] = [
        "swift": LanguageSpec(
            commentPatterns: cLikeComments,
            stringPatterns: stringDoubleOnly,
            keywords: swiftKeywords,
            annotationPattern: #"@[A-Za-z_][A-Za-z0-9_]*"#
        ),
        "python": LanguageSpec(
            commentPatterns: ["#.*$"],
            stringPatterns: [#"\"\"\"[\s\S]*?\"\"\""#, #"'''[\s\S]*?'''"#, #""([^"\\]|\\.)*""#, #"'([^'\\]|\\.)*'"#],
            keywords: pythonKeywords,
            annotationPattern: #"@[A-Za-z_][A-Za-z0-9_]*"#
        ),
        "javascript": jsSpec(),
        "typescript": jsSpec(),
        "jsx": jsSpec(),
        "tsx": jsSpec(),
        "json": LanguageSpec(
            commentPatterns: [],
            stringPatterns: [#""([^"\\]|\\.)*""#],
            keywords: ["true", "false", "null"],
            extraKeywordPatterns: [#""([^"\\]|\\.)*"\s*(?=:)"#]
        ),
        "bash": LanguageSpec(
            commentPatterns: ["#.*$"],
            stringPatterns: [#""([^"\\]|\\.)*""#, #"'[^']*'"#],
            keywords: bashKeywords,
            extraKeywordPatterns: [#"\$\{[^}]+\}|\$[A-Za-z_][A-Za-z0-9_]*"#]
        ),
        "ruby": LanguageSpec(
            commentPatterns: ["#.*$"],
            stringPatterns: stringDoubleSingle,
            keywords: rubyKeywords,
            extraKeywordPatterns: [#":[A-Za-z_][A-Za-z0-9_]*"#]
        ),
        "go": LanguageSpec(
            commentPatterns: cLikeComments,
            stringPatterns: [#"`[^`]*`"#, #""([^"\\]|\\.)*""#],
            keywords: goKeywords
        ),
        "rust": LanguageSpec(
            commentPatterns: cLikeComments,
            stringPatterns: stringDoubleOnly,
            keywords: rustKeywords,
            annotationPattern: #"#\[[\s\S]*?\]"#
        ),
        "kotlin": jvmSpec(),
        "java": jvmSpec(),
        "yaml": LanguageSpec(
            commentPatterns: ["#.*$"],
            stringPatterns: [#""([^"\\]|\\.)*""#, #"'[^']*'"#],
            keywords: ["true", "false", "null", "~"],
            extraKeywordPatterns: [#"^[\s-]*([A-Za-z_][A-Za-z0-9_-]*)\s*:"#]
        ),
        "c": cSpec(keywords: cKeywords),
        "cpp": cSpec(keywords: cppKeywords),
        "objectivec": cSpec(keywords: objectiveCKeywords, annotationPattern: #"@[A-Za-z_][A-Za-z0-9_]*"#),
        "html": markupSpec(),
        "xml": markupSpec(),
        "css": LanguageSpec(
            commentPatterns: [#"/\*[\s\S]*?\*/"#],
            stringPatterns: stringDoubleSingle,
            keywords: ["important", "inherit", "initial", "unset", "revert"],
            extraKeywordPatterns: [
                #"@[A-Za-z-]+"#,
                #"(^|[;\{\s])[-A-Za-z_][-\w]*\s*(?=:)"#,
                #"#[0-9A-Fa-f]{3,8}\b"#,
                #"\b[-A-Za-z_][-\w]*(?=\()"#
            ],
            symbolPatterns: [#"[{}();:,]"#],
            numberPattern: #"\b-?\d+(\.\d+)?(px|em|rem|vh|vw|%|s|ms|deg)?\b"#
        ),
        "sql": LanguageSpec(
            commentPatterns: [#"--.*$"#, #"/\*[\s\S]*?\*/"#],
            stringPatterns: [#"'([^'\\]|\\.|'')*'"#, #""([^"\\]|\\.)*""#, #"`[^`]*`"#],
            keywords: sqlKeywords,
            extraKeywordPatterns: [#"\b[A-Za-z_][A-Za-z0-9_]*(?=\s*\()"#]
        ),
        "toml": LanguageSpec(
            commentPatterns: ["#.*$"],
            stringPatterns: [#"\"\"\"[\s\S]*?\"\"\""#, #"'''[\s\S]*?'''"#, #""([^"\\]|\\.)*""#, #"'[^']*'"#],
            keywords: ["true", "false"],
            extraKeywordPatterns: [
                #"^\s*\[+[^\]]+\]+"#,
                #"(^|\s)[A-Za-z0-9_.-]+\s*(?==)"#,
                #"\b\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})?)?\b"#
            ]
        ),
        "markdown": LanguageSpec(
            commentPatterns: [],
            stringPatterns: [#"`{1,3}[\s\S]*?`{1,3}"#],
            keywords: [],
            extraKeywordPatterns: [
                #"^\s{0,3}#{1,6}\s+.+"#,
                #"^\s{0,3}>\s?"#,
                #"^\s*([-*+]|\d+\.)\s+"#,
                #"\[[^\]]+\]\([^)]+\)"#,
                #"\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?"#
            ],
            symbolPatterns: [#"[*_~>#|\[\]()`-]"#]
        ),
        "mermaid": LanguageSpec(
            // Mermaid comments are `%% ...`; node/edge label text in brackets reads as strings.
            commentPatterns: [#"%%.*$"#],
            stringPatterns: [
                #"\[[^\]\n]*\]"#, #"\([^)\n]*\)"#, #"\{[^}\n]*\}"#,
                #"\|[^|\n]*\|"#, #""[^"\n]*""#
            ],
            keywords: mermaidKeywords,
            extraKeywordPatterns: [
                // Edge connectors: -->  ---  -.->  ==>  -.-  ===  o--o  x--x  etc.
                #"[ox<]?[-=.]{2,}[->ox]+\|?"#
            ],
            symbolPatterns: [#"[;&:]"#]
        )
    ]

    static let mermaidKeywords = [
        "graph", "flowchart", "subgraph", "end", "direction", "TD", "TB", "BT", "RL", "LR",
        "classDiagram", "sequenceDiagram", "stateDiagram", "stateDiagram-v2", "erDiagram", "gantt",
        "pie", "journey", "gitGraph", "mindmap", "timeline", "participant", "actor", "class", "state",
        "note", "loop", "alt", "opt", "par", "and", "click", "style", "classDef", "linkStyle"
    ]

    static func jsSpec() -> LanguageSpec {
        LanguageSpec(
            commentPatterns: cLikeComments,
            stringPatterns: stringDoubleSingle + [#"`([^`\\]|\\.)*`"#],
            keywords: javascriptKeywords
        )
    }

    static func jvmSpec() -> LanguageSpec {
        LanguageSpec(
            commentPatterns: cLikeComments,
            stringPatterns: stringDoubleOnly,
            keywords: jvmKeywords,
            annotationPattern: #"@[A-Za-z_][A-Za-z0-9_]*"#
        )
    }

    static func cSpec(keywords: [String], annotationPattern: String? = nil) -> LanguageSpec {
        LanguageSpec(
            commentPatterns: cLikeComments,
            stringPatterns: cLikeStrings,
            keywords: keywords,
            annotationPattern: annotationPattern,
            extraKeywordPatterns: [#"^\s*#\s*[A-Za-z_][A-Za-z0-9_]*"#]
        )
    }

    static func markupSpec() -> LanguageSpec {
        LanguageSpec(
            commentPatterns: [#"<!--[\s\S]*?-->"#],
            stringPatterns: stringDoubleSingle,
            keywords: [],
            extraKeywordPatterns: [
                #"</?[A-Za-z_][A-Za-z0-9:._-]*"#,
                #"\s[A-Za-z_:][A-Za-z0-9:._-]*(?=\s*=)"#,
                #"&[A-Za-z0-9#]+;"#,
                #"<!DOCTYPE[\s\S]*?>"#,
                #"<\?xml[\s\S]*?\?>"#
            ],
            symbolPatterns: [#"[<>/=]"#]
        )
    }

    static func smartQuotedString(open: String, close: String) -> String {
        NSRegularExpression.escapedPattern(for: open)
            + #"[\s\S]*?"#
            + NSRegularExpression.escapedPattern(for: close)
    }
}

private extension [NSRange] {
    func intersects(_ range: NSRange) -> Bool {
        contains { NSIntersectionRange($0, range).length > 0 }
    }
}
