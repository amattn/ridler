import AppKit

/// Provides syntax highlighting for code blocks found in Claude's output.
/// Parses fenced code blocks (``` markers) and applies keyword-based coloring
/// for common languages (Swift, TypeScript, Python, JavaScript, Go, Rust, etc.).
struct SyntaxHighlighter {

    /// A segment of text content — either plain text or a highlighted code block.
    enum ContentSegment: Equatable {
        case text(String)
        case codeBlock(language: String?, code: String)
    }

    /// Parse content into segments, splitting on fenced code blocks.
    static func parseSegments(_ content: String) -> [ContentSegment] {
        var segments: [ContentSegment] = []
        var currentText = ""
        var inCodeBlock = false
        var codeBlockLanguage: String?
        var codeBlockContent = ""

        let lines = content.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if !inCodeBlock && trimmed.hasPrefix("```") {
                // Start of code block
                if !currentText.isEmpty {
                    segments.append(.text(currentText))
                    currentText = ""
                }
                inCodeBlock = true
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                codeBlockLanguage = lang.isEmpty ? nil : lang.lowercased()
                codeBlockContent = ""
            } else if inCodeBlock && trimmed == "```" {
                // End of code block
                // Remove trailing newline if present
                if codeBlockContent.hasSuffix("\n") {
                    codeBlockContent = String(codeBlockContent.dropLast())
                }
                segments.append(.codeBlock(language: codeBlockLanguage, code: codeBlockContent))
                inCodeBlock = false
                codeBlockLanguage = nil
                codeBlockContent = ""
            } else if inCodeBlock {
                codeBlockContent += line + "\n"
            } else {
                if !currentText.isEmpty || index > 0 {
                    currentText += "\n"
                }
                currentText += line
            }
        }

        // Handle unclosed code block — treat as text
        if inCodeBlock {
            currentText += "\n```"
            if let lang = codeBlockLanguage, !lang.isEmpty {
                currentText += lang
            }
            currentText += "\n" + codeBlockContent
        }

        if !currentText.isEmpty {
            segments.append(.text(currentText))
        }

        return segments
    }

    /// Apply syntax highlighting to a code string, returning an NSAttributedString.
    static func highlight(code: String, language: String?) -> NSAttributedString {
        let fontSize: CGFloat = 11
        let baseFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let baseColor = NSColor.labelColor

        let result = NSMutableAttributedString(
            string: code,
            attributes: [
                .font: baseFont,
                .foregroundColor: baseColor
            ]
        )

        let keywords = keywords(for: language)
        let nsCode = code as NSString

        // Highlight comments (single-line // and # style)
        highlightPattern(#"//.*$"#, in: result, nsString: nsCode, color: .commentColor)
        if language == "python" || language == "ruby" || language == "bash" || language == "sh" || language == "shell" || language == "zsh" {
            highlightPattern(#"(?m)^[ \t]*#.*$"#, in: result, nsString: nsCode, color: .commentColor)
            highlightPattern(#"(?m)(?<=\s)#.*$"#, in: result, nsString: nsCode, color: .commentColor)
        }

        // Highlight multi-line comments /* ... */
        highlightPattern(#"/\*[\s\S]*?\*/"#, in: result, nsString: nsCode, color: .commentColor)

        // Highlight strings (double-quoted and single-quoted)
        highlightPattern(#""(?:[^"\\]|\\.)*""#, in: result, nsString: nsCode, color: .stringColor)
        highlightPattern(#"'(?:[^'\\]|\\.)*'"#, in: result, nsString: nsCode, color: .stringColor)

        // Highlight template literals for JS/TS
        if language == "javascript" || language == "typescript" || language == "ts" || language == "js" || language == "jsx" || language == "tsx" {
            highlightPattern(#"`(?:[^`\\]|\\.)*`"#, in: result, nsString: nsCode, color: .stringColor)
        }

        // Highlight numbers
        highlightPattern(#"\b\d+\.?\d*\b"#, in: result, nsString: nsCode, color: .numberColor)

        // Highlight keywords
        for keyword in keywords {
            highlightPattern("\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b", in: result, nsString: nsCode, color: .keywordColor)
        }

        // Highlight type names (capitalized identifiers)
        highlightPattern(#"\b[A-Z][a-zA-Z0-9_]*\b"#, in: result, nsString: nsCode, color: .typeColor)

        return result
    }

    // MARK: - Private

    private static func highlightPattern(_ pattern: String, in attrString: NSMutableAttributedString, nsString: NSString, color: NSColor) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
        let range = NSRange(location: 0, length: nsString.length)
        for match in regex.matches(in: nsString as String, range: range) {
            attrString.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }

    private static func keywords(for language: String?) -> [String] {
        switch language {
        case "swift":
            return ["import", "func", "var", "let", "class", "struct", "enum", "protocol", "extension",
                    "if", "else", "guard", "switch", "case", "default", "for", "while", "repeat",
                    "return", "throw", "throws", "try", "catch", "do", "async", "await",
                    "public", "private", "internal", "fileprivate", "open", "static", "override",
                    "self", "Self", "super", "nil", "true", "false", "init", "deinit",
                    "typealias", "associatedtype", "where", "in", "is", "as",
                    "weak", "unowned", "lazy", "mutating", "nonmutating", "some", "any"]

        case "typescript", "ts", "tsx":
            return ["import", "export", "from", "function", "const", "let", "var", "class", "interface",
                    "type", "enum", "if", "else", "switch", "case", "default", "for", "while", "do",
                    "return", "throw", "try", "catch", "finally", "async", "await", "yield",
                    "new", "this", "super", "null", "undefined", "true", "false", "void",
                    "typeof", "instanceof", "in", "of", "as", "extends", "implements",
                    "public", "private", "protected", "static", "readonly", "abstract"]

        case "javascript", "js", "jsx":
            return ["import", "export", "from", "function", "const", "let", "var", "class",
                    "if", "else", "switch", "case", "default", "for", "while", "do",
                    "return", "throw", "try", "catch", "finally", "async", "await", "yield",
                    "new", "this", "super", "null", "undefined", "true", "false", "void",
                    "typeof", "instanceof", "in", "of", "extends"]

        case "python", "py":
            return ["import", "from", "def", "class", "if", "elif", "else", "for", "while",
                    "return", "yield", "raise", "try", "except", "finally", "with", "as",
                    "pass", "break", "continue", "and", "or", "not", "in", "is",
                    "lambda", "global", "nonlocal", "assert", "del",
                    "True", "False", "None", "self", "async", "await"]

        case "go", "golang":
            return ["package", "import", "func", "var", "const", "type", "struct", "interface",
                    "if", "else", "switch", "case", "default", "for", "range", "select",
                    "return", "go", "defer", "chan", "map", "make", "new", "append", "len", "cap",
                    "nil", "true", "false", "break", "continue", "fallthrough"]

        case "rust", "rs":
            return ["use", "mod", "fn", "let", "mut", "const", "struct", "enum", "trait", "impl",
                    "if", "else", "match", "loop", "while", "for", "in",
                    "return", "break", "continue", "move", "ref",
                    "pub", "crate", "super", "self", "Self",
                    "true", "false", "as", "where", "async", "await", "unsafe", "dyn", "type"]

        case "bash", "sh", "shell", "zsh":
            return ["if", "then", "else", "elif", "fi", "for", "while", "do", "done",
                    "case", "esac", "in", "function", "return", "exit",
                    "echo", "export", "local", "readonly", "unset", "set",
                    "true", "false"]

        case "json":
            return [] // JSON has no keywords — just strings, numbers, booleans

        case "html", "xml":
            return [] // HTML/XML highlighting would need tag-aware parsing

        case "css", "scss":
            return ["import", "media", "keyframes", "font-face", "charset"]

        default:
            // Generic keyword set covering common patterns across languages
            return ["import", "export", "from", "function", "func", "def", "class", "struct",
                    "enum", "interface", "type", "var", "let", "const", "mut",
                    "if", "else", "elif", "switch", "case", "default", "match",
                    "for", "while", "do", "loop", "in", "of",
                    "return", "throw", "raise", "yield", "break", "continue",
                    "try", "catch", "except", "finally",
                    "async", "await", "public", "private", "protected", "static",
                    "true", "false", "nil", "null", "None", "undefined", "void",
                    "new", "self", "this", "super"]
        }
    }
}

// MARK: - Syntax Highlighting Colors

private extension NSColor {
    static let keywordColor = NSColor(red: 0.78, green: 0.36, blue: 0.84, alpha: 1.0) // purple
    static let stringColor = NSColor(red: 0.84, green: 0.40, blue: 0.36, alpha: 1.0) // reddish
    static let commentColor = NSColor(red: 0.45, green: 0.52, blue: 0.45, alpha: 1.0) // muted green
    static let numberColor = NSColor(red: 0.84, green: 0.72, blue: 0.36, alpha: 1.0) // gold
    static let typeColor = NSColor(red: 0.36, green: 0.72, blue: 0.84, alpha: 1.0)   // teal/cyan
}
