import Foundation
import LiquidKit
import os

/// Manages Liquid prompt templates: loading from bundle/project, copying defaults, and rendering.
final class TemplateManager {
    private static let logger = Logger(subsystem: "com.amattn.Ridler", category: "TemplateManager")

    /// Names of agent loop templates used by RalphLoopEngine.buildPrompt
    static let agentTemplateNames = [
        "agent_instructions",
        "story_context",
        "progress_report",
    ]

    /// Names of interactive editing templates used by ClaudeTerminalManager
    static let editingTemplateNames = [
        "edit_file",
        "create_file",
    ]

    /// All template names
    static let allTemplateNames = agentTemplateNames + editingTemplateNames

    /// Error describing a template failure with file context.
    struct TemplateError: LocalizedError {
        let fileName: String
        let message: String

        var errorDescription: String? {
            "Template error in \(fileName): \(message)"
        }
    }

    // MARK: - Template Directory Management

    /// Returns the prompts directory URL for a project: `<projectDir>/prompts/`
    static func promptsDirectory(for projectDirectoryURL: URL) -> URL {
        projectDirectoryURL.appendingPathComponent("prompts")
    }

    /// Ensures all default templates exist in the project's `ridl/prompts/` directory.
    /// Copies any missing templates from the app bundle.
    static func ensureTemplatesExist(in projectDirectoryURL: URL) throws {
        let promptsDir = promptsDirectory(for: projectDirectoryURL)
        let fm = FileManager.default

        // Create prompts directory if needed
        if !fm.fileExists(atPath: promptsDir.path) {
            try fm.createDirectory(at: promptsDir, withIntermediateDirectories: true)
            logger.info("Created prompts directory at \(promptsDir.path)")
        }

        // Copy missing templates from bundle
        for name in allTemplateNames {
            let destURL = promptsDir.appendingPathComponent("\(name).liquid")
            if !fm.fileExists(atPath: destURL.path) {
                guard let bundleURL = Bundle.main.url(forResource: name, withExtension: "liquid") else {
                    throw TemplateError(fileName: "\(name).liquid", message: "Bundled default template not found in app resources")
                }
                try fm.copyItem(at: bundleURL, to: destURL)
                logger.info("Copied default template \(name).liquid to project")
            }
        }
    }

    /// Lists `.liquid` files in the project's prompts directory. Returns empty array if directory doesn't exist.
    static func listTemplateFiles(in projectDirectoryURL: URL) -> [String] {
        let promptsDir = promptsDirectory(for: projectDirectoryURL)
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(atPath: promptsDir.path) else {
            return []
        }

        return contents
            .filter { $0.hasSuffix(".liquid") }
            .sorted()
    }

    // MARK: - Rendering

    /// Loads a template from the project's prompts directory (falling back to bundle) and renders it.
    static func render(
        templateName: String,
        projectDirectoryURL: URL,
        context: [String: Any?]
    ) throws -> String {
        let promptsDir = promptsDirectory(for: projectDirectoryURL)
        let templatePath = promptsDir.appendingPathComponent("\(templateName).liquid").path
        logger.info("Rendering template: \(templateName).liquid from \(templatePath)")
        logger.info("Template context keys: \(formatContextSummary(context))")
        let templateString = try loadTemplate(named: templateName, projectDirectoryURL: projectDirectoryURL)
        let result = try renderString(templateString, fileName: "\(templateName).liquid", context: context)
        logger.info("Template \(templateName).liquid rendered (\(result.count) chars)")
        return result
    }

    /// Formats context dictionary into a human-readable summary for logging.
    private static func formatContextSummary(_ context: [String: Any?]) -> String {
        var parts: [String] = []
        for (key, value) in context.sorted(by: { $0.key < $1.key }) {
            switch value {
            case nil:
                parts.append("\(key)=nil")
            case let dict as [String: Any?]:
                let subkeys = dict.keys.sorted().joined(separator: ", ")
                parts.append("\(key)={\(subkeys)}")
            case let dict as [String: Any]:
                let subkeys = dict.keys.sorted().joined(separator: ", ")
                parts.append("\(key)={\(subkeys)}")
            case let array as [Any]:
                parts.append("\(key)=[\(array.count) items]")
            case let str as String:
                if str.count > 60 {
                    parts.append("\(key)=\"\(str.prefix(57))...\"")
                } else {
                    parts.append("\(key)=\"\(str)\"")
                }
            default:
                parts.append("\(key)=\(value!)")
            }
        }
        return parts.joined(separator: ", ")
    }

    /// Renders a raw template string with the given context.
    static func renderString(_ templateString: String, fileName: String, context: [String: Any?]) throws -> String {
        let lexer = Lexer(templateString: templateString)
        let tokens = lexer.tokenize()
        let tokenValues = context.compactMapValues { convertToTokenValue($0) }
        let liquidContext = Context(dictionary: tokenValues)
        let parser = Parser(tokens: tokens, context: liquidContext)
        let result = parser.parse()
        return result.joined()
    }

    /// Recursively converts Any? values to Token.Value, supporting nested dictionaries and arrays.
    private static func convertToTokenValue(_ value: Any?) -> Token.Value {
        switch value {
        case nil:
            return .nil
        case let string as String:
            return .string(string)
        case let int as Int:
            return .integer(int)
        case let bool as Bool:
            return .bool(bool)
        case let double as Double:
            return .decimal(Decimal(floatLiteral: double))
        case let decimal as Decimal:
            return .decimal(decimal)
        case let array as [Any?]:
            return .array(array.map { convertToTokenValue($0) })
        case let array as [String]:
            return .array(array.map { Token.Value.string($0) })
        case let dict as [String: Any?]:
            return .dictionary(dict.compactMapValues { convertToTokenValue($0) })
        case let dict as [String: Any]:
            return .dictionary(dict.mapValues { convertToTokenValue($0) })
        default:
            return .string(String(describing: value!))
        }
    }

    // MARK: - Agent Loop Prompt

    /// Builds the full agent loop prompt by rendering and concatenating the three agent templates.
    static func buildAgentPrompt(
        for story: IterationDefinition,
        project: PRDProject,
        progressContent: String?
    ) throws -> String {
        guard let directoryURL = project.directoryURL else {
            throw TemplateError(fileName: "", message: "Project has no directory URL")
        }

        let context = buildAgentContext(for: story, project: project, progressContent: progressContent)

        var parts: [String] = []
        for name in agentTemplateNames {
            let rendered = try render(templateName: name, projectDirectoryURL: directoryURL, context: context)
            parts.append(rendered)
        }

        return parts.joined()
    }

    /// Builds the Liquid context dictionary for agent loop templates.
    static func buildAgentContext(
        for story: IterationDefinition,
        project: PRDProject,
        progressContent: String?
    ) -> [String: Any?] {
        var storyDict: [String: Any?] = [
            "id": story.id,
            "title": story.userStoryTitle,
            "priority": story.priority,
            "description": story.userStoryDescription,
            "acceptance_criteria": story.acceptanceCriteria,
        ]

        if let refs = story.prdReferences, !refs.isEmpty {
            storyDict["prd_references"] = refs
        }

        var projectDict: [String: Any?] = [:]
        if let ctx = project.universalContext {
            var hasContext = false
            if let nfr = ctx.nonFunctionalRequirements, !nfr.isEmpty {
                projectDict["non_functional_requirements"] = nfr
                hasContext = true
            }
            if let devExp = ctx.developerExperience, !devExp.isEmpty {
                projectDict["developer_experience"] = devExp
                hasContext = true
            }
            if let techArch = ctx.technicalArchitecture, !techArch.isEmpty {
                projectDict["technical_architecture"] = techArch
                hasContext = true
            }
            projectDict["has_universal_context"] = hasContext
        }

        return [
            "story": storyDict,
            "project": projectDict,
            "progress_content": progressContent,
        ]
    }

    // MARK: - Editing Prompts

    /// Builds a prompt for editing an existing file via Claude terminal.
    static func buildEditPrompt(
        filePath: String,
        fileName: String,
        projectDirectoryURL: URL
    ) throws -> String {
        let context: [String: Any?] = [
            "file_path": filePath,
            "file_name": fileName,
            "file_exists": true,
        ]
        return try render(templateName: "edit_file", projectDirectoryURL: projectDirectoryURL, context: context)
    }

    /// Builds a prompt for creating a missing file via Claude terminal.
    static func buildCreatePrompt(
        filePath: String,
        fileName: String,
        projectDirectoryURL: URL
    ) throws -> String {
        let context: [String: Any?] = [
            "file_path": filePath,
            "file_name": fileName,
            "file_exists": false,
        ]
        return try render(templateName: "create_file", projectDirectoryURL: projectDirectoryURL, context: context)
    }

    // MARK: - Validation

    /// Validates a template's syntax. Returns nil if valid, or an error description with line info.
    static func validateTemplate(content: String, fileName: String) -> TemplateError? {
        // Check for unclosed delimiters
        if let error = checkDelimiters(content: content, fileName: fileName) {
            return error
        }

        // Check for balanced block tags
        if let error = checkBalancedTags(content: content, fileName: fileName) {
            return error
        }

        return nil
    }

    /// Validates all templates in a project directory. Returns a dictionary of fileName → error.
    static func validateAllTemplates(in projectDirectoryURL: URL) -> [String: TemplateError] {
        let templates = listTemplateFiles(in: projectDirectoryURL)
        let promptsDir = promptsDirectory(for: projectDirectoryURL)
        var errors: [String: TemplateError] = [:]

        for name in templates {
            let fileURL = promptsDir.appendingPathComponent(name)
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                errors[name] = TemplateError(fileName: name, message: "Cannot read template file")
                continue
            }
            if let error = validateTemplate(content: content, fileName: name) {
                errors[name] = error
            }
        }

        return errors
    }

    /// Checks for unclosed `{{` or `{%` delimiters.
    private static func checkDelimiters(content: String, fileName: String) -> TemplateError? {
        let lines = content.components(separatedBy: .newlines)
        for (lineIndex, line) in lines.enumerated() {
            let lineNum = lineIndex + 1

            // Check for {{ without }}
            var searchRange = line.startIndex..<line.endIndex
            while let openRange = line.range(of: "{{", range: searchRange) {
                if line.range(of: "}}", range: openRange.upperBound..<line.endIndex) == nil {
                    return TemplateError(fileName: fileName, message: "Line \(lineNum): Unclosed variable tag '{{' — missing '}}'")
                }
                let closeRange = line.range(of: "}}", range: openRange.upperBound..<line.endIndex)!
                searchRange = closeRange.upperBound..<line.endIndex
            }

            // Check for {% without %}
            searchRange = line.startIndex..<line.endIndex
            while let openRange = line.range(of: "{%", range: searchRange) {
                if line.range(of: "%}", range: openRange.upperBound..<line.endIndex) == nil {
                    return TemplateError(fileName: fileName, message: "Line \(lineNum): Unclosed block tag '{%' — missing '%}'")
                }
                let closeRange = line.range(of: "%}", range: openRange.upperBound..<line.endIndex)!
                searchRange = closeRange.upperBound..<line.endIndex
            }
        }
        return nil
    }

    /// Checks for balanced block tags (if/endif, for/endfor, unless/endunless, case/endcase, capture/endcapture).
    private static func checkBalancedTags(content: String, fileName: String) -> TemplateError? {
        let blockPairs: [(open: String, close: String)] = [
            ("if", "endif"),
            ("for", "endfor"),
            ("unless", "endunless"),
            ("case", "endcase"),
            ("capture", "endcapture"),
        ]

        let lines = content.components(separatedBy: .newlines)
        // Track (tagName, lineNumber) for each open tag
        var stack: [(String, Int)] = []

        let tagPattern = try! NSRegularExpression(pattern: #"\{%[-\s]*(\w+)"#)

        for (lineIndex, line) in lines.enumerated() {
            let lineNum = lineIndex + 1
            let nsLine = line as NSString
            let matches = tagPattern.matches(in: line, range: NSRange(location: 0, length: nsLine.length))

            for match in matches {
                let keyword = nsLine.substring(with: match.range(at: 1))

                // Check if it's an opening tag
                if let pair = blockPairs.first(where: { $0.open == keyword }) {
                    stack.append((pair.open, lineNum))
                }
                // Check if it's a closing tag
                else if let pair = blockPairs.first(where: { $0.close == keyword }) {
                    if let last = stack.last, last.0 == pair.open {
                        stack.removeLast()
                    } else if let last = stack.last {
                        return TemplateError(fileName: fileName, message: "Line \(lineNum): Unexpected '{%\(keyword)%}' — expected 'end\(last.0)' to close '{%\(last.0)%}' opened on line \(last.1)")
                    } else {
                        return TemplateError(fileName: fileName, message: "Line \(lineNum): Unexpected '{%\(keyword)%}' — no matching opening tag")
                    }
                }
            }
        }

        if let unclosed = stack.last {
            return TemplateError(fileName: fileName, message: "Line \(unclosed.1): Unclosed '{%\(unclosed.0)%}' — missing '{%end\(unclosed.0)%}'")
        }

        return nil
    }

    // MARK: - Private

    /// Loads a template from the project's prompts directory.
    /// If missing, copies the bundled default first, then reads.
    private static func loadTemplate(named name: String, projectDirectoryURL: URL) throws -> String {
        let promptsDir = promptsDirectory(for: projectDirectoryURL)
        let fileURL = promptsDir.appendingPathComponent("\(name).liquid")
        let fm = FileManager.default

        // If the file doesn't exist, copy from bundle
        if !fm.fileExists(atPath: fileURL.path) {
            // Ensure directory exists
            if !fm.fileExists(atPath: promptsDir.path) {
                try fm.createDirectory(at: promptsDir, withIntermediateDirectories: true)
            }

            guard let bundleURL = Bundle.main.url(forResource: name, withExtension: "liquid") else {
                throw TemplateError(fileName: "\(name).liquid", message: "Bundled default template not found in app resources")
            }
            try fm.copyItem(at: bundleURL, to: fileURL)
            logger.info("Copied missing template \(name).liquid from bundle to project")
        }

        do {
            return try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            throw TemplateError(fileName: "\(name).liquid", message: "Failed to read template: \(error.localizedDescription)")
        }
    }
}
