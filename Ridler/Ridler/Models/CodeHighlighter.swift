import SwiftUI

// MARK: - Text Segment

/// Represents a segment of text that is either plain or a code block.
enum TextSegment {
    case plain(String)
    case codeBlock(language: String, code: String)
}

// MARK: - CodeHighlighter

/// Parses markdown code fences from text and produces syntax-highlighted AttributedStrings.
struct CodeHighlighter {

    /// Parses text into segments, splitting on triple-backtick code fences.
    static func parseSegments(_ text: String) -> [TextSegment] {
        var segments: [TextSegment] = []
        let lines = text.components(separatedBy: "\n")
        var currentPlain: [String] = []
        var inCodeBlock = false
        var codeLanguage = ""
        var codeLines: [String] = []

        for line in lines {
            if !inCodeBlock {
                if line.hasPrefix("```") {
                    // Flush any accumulated plain text
                    if !currentPlain.isEmpty {
                        segments.append(.plain(currentPlain.joined(separator: "\n")))
                        currentPlain = []
                    }
                    // Start code block — language is after the ```
                    codeLanguage = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces).lowercased()
                    codeLines = []
                    inCodeBlock = true
                } else {
                    currentPlain.append(line)
                }
            } else {
                if line.hasPrefix("```") {
                    // End code block
                    segments.append(.codeBlock(language: codeLanguage, code: codeLines.joined(separator: "\n")))
                    inCodeBlock = false
                } else {
                    codeLines.append(line)
                }
            }
        }

        // Flush remaining content
        if inCodeBlock {
            // Unclosed code block — treat as code block anyway
            segments.append(.codeBlock(language: codeLanguage, code: codeLines.joined(separator: "\n")))
        } else if !currentPlain.isEmpty {
            segments.append(.plain(currentPlain.joined(separator: "\n")))
        }

        return segments
    }

    /// Returns true if the text contains any code fences.
    static func containsCodeBlock(_ text: String) -> Bool {
        text.contains("```")
    }

    /// Highlights code using keyword-based regex coloring, returning an AttributedString.
    static func highlight(code: String, language: String) -> AttributedString {
        var result = AttributedString(code)
        result.font = .system(.caption, design: .monospaced)

        let keywords = keywords(for: language)
        let nsCode = code as NSString

        // Highlight string literals (double-quoted and single-quoted)
        applyPattern("\"(?:[^\"\\\\]|\\\\.)*\"", to: &result, nsString: nsCode, color: .highlightString)
        applyPattern("'(?:[^'\\\\]|\\\\.)*'", to: &result, nsString: nsCode, color: .highlightString)

        // Highlight single-line comments
        let commentPattern = language == "python" || language == "py" ? "#[^\n]*" : "//[^\n]*"
        applyPattern(commentPattern, to: &result, nsString: nsCode, color: .highlightComment)

        // Highlight numbers
        applyPattern("\\b\\d+(?:\\.\\d+)?\\b", to: &result, nsString: nsCode, color: .highlightNumber)

        // Highlight keywords
        for keyword in keywords {
            applyPattern("\\b\(keyword)\\b", to: &result, nsString: nsCode, color: .highlightKeyword)
        }

        // Highlight type-like identifiers (capitalized words) for some languages
        if ["swift", "typescript", "ts", "java", "kotlin", "go"].contains(language) {
            applyPattern("\\b[A-Z][A-Za-z0-9]+\\b", to: &result, nsString: nsCode, color: .highlightType)
        }

        return result
    }

    // MARK: - Private

    private static func applyPattern(_ pattern: String, to result: inout AttributedString, nsString: NSString, color: Color) {
        let sourceString = nsString as String
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let matches = regex.matches(in: sourceString, range: NSRange(location: 0, length: nsString.length))
        for match in matches {
            guard let swiftRange = Range(match.range, in: sourceString) else { continue }
            // Convert String range to AttributedString range by counting character offsets
            let startOffset = sourceString.distance(from: sourceString.startIndex, to: swiftRange.lowerBound)
            let endOffset = sourceString.distance(from: sourceString.startIndex, to: swiftRange.upperBound)
            let attrStart = result.characters.index(result.startIndex, offsetBy: startOffset)
            let attrEnd = result.characters.index(result.startIndex, offsetBy: endOffset)
            result[attrStart..<attrEnd].foregroundColor = color
        }
    }

    private static func keywords(for language: String) -> [String] {
        switch language {
        case "swift":
            return ["import", "func", "var", "let", "class", "struct", "enum", "protocol", "extension",
                    "if", "else", "guard", "switch", "case", "default", "for", "while", "repeat",
                    "return", "throw", "throws", "try", "catch", "do", "async", "await",
                    "private", "public", "internal", "fileprivate", "open", "static", "override",
                    "self", "Self", "nil", "true", "false", "init", "deinit", "where",
                    "associatedtype", "typealias", "some", "any", "in", "is", "as"]
        case "typescript", "ts", "javascript", "js":
            return ["import", "export", "from", "function", "const", "let", "var", "class",
                    "interface", "type", "enum", "if", "else", "switch", "case", "default",
                    "for", "while", "do", "return", "throw", "try", "catch", "finally",
                    "async", "await", "new", "this", "super", "extends", "implements",
                    "true", "false", "null", "undefined", "void", "typeof", "instanceof",
                    "private", "public", "protected", "static", "readonly", "abstract"]
        case "python", "py":
            return ["import", "from", "def", "class", "if", "elif", "else", "for", "while",
                    "return", "yield", "raise", "try", "except", "finally", "with", "as",
                    "pass", "break", "continue", "lambda", "and", "or", "not", "in", "is",
                    "True", "False", "None", "self", "async", "await", "global", "nonlocal"]
        case "json":
            return [] // JSON only has strings, numbers, booleans, null
        case "go":
            return ["package", "import", "func", "var", "const", "type", "struct", "interface",
                    "map", "chan", "if", "else", "switch", "case", "default", "for", "range",
                    "return", "go", "defer", "select", "break", "continue", "fallthrough",
                    "true", "false", "nil", "make", "new", "len", "cap", "append", "delete"]
        case "java", "kotlin":
            return ["import", "package", "class", "interface", "enum", "abstract", "final",
                    "public", "private", "protected", "static", "void", "int", "long", "double",
                    "float", "boolean", "char", "byte", "short", "if", "else", "switch", "case",
                    "default", "for", "while", "do", "return", "throw", "throws", "try", "catch",
                    "finally", "new", "this", "super", "extends", "implements", "true", "false",
                    "null", "instanceof", "val", "var", "fun", "override", "when", "object"]
        case "rust":
            return ["use", "mod", "fn", "let", "mut", "const", "struct", "enum", "trait", "impl",
                    "pub", "crate", "self", "super", "if", "else", "match", "for", "while", "loop",
                    "return", "break", "continue", "async", "await", "move", "ref", "where",
                    "type", "as", "in", "true", "false", "Some", "None", "Ok", "Err", "unsafe"]
        case "bash", "sh", "shell", "zsh":
            return ["if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case",
                    "esac", "function", "return", "exit", "echo", "export", "local", "set",
                    "unset", "readonly", "shift", "source", "true", "false", "in"]
        default:
            // Generic fallback — common keywords across languages
            return ["import", "export", "from", "function", "func", "def", "class", "struct",
                    "if", "else", "for", "while", "return", "var", "let", "const", "true", "false",
                    "null", "nil", "None", "try", "catch", "throw", "new", "this", "self"]
        }
    }
}

// MARK: - Highlight Colors

private extension Color {
    static let highlightKeyword = Color.purple
    static let highlightString = Color.red
    static let highlightComment = Color.gray
    static let highlightNumber = Color.cyan
    static let highlightType = Color.green
}
