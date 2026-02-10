import Foundation
import Combine
import os

/// Parses Claude Code's streaming JSON output (one JSON object per line) into structured LogEntry values.
///
/// Claude Code with `--output-format stream-json` outputs newline-delimited JSON objects.
/// Each object has a `type` field indicating the message type:
/// - `assistant`: text content from Claude
/// - `tool_use`: a tool invocation (Read, Edit, Write, Bash, etc.)
/// - `tool_result`: the result of a tool invocation
/// - `result`: the final result of the session
/// - Other types are treated as system messages
final class StreamingJSONParser {
    private static let logger = Logger(subsystem: "com.amattn.Ridler", category: "StreamingJSONParser")

    private let entrySubject = PassthroughSubject<LogEntry, Never>()
    private let completionSubject = PassthroughSubject<Void, Never>()

    /// Publisher that emits parsed log entries.
    var entryPublisher: AnyPublisher<LogEntry, Never> {
        entrySubject.eraseToAnyPublisher()
    }

    /// Publisher that emits when the ridler-complete signal is detected.
    var completionPublisher: AnyPublisher<Void, Never> {
        completionSubject.eraseToAnyPublisher()
    }

    /// Parse a single line of streaming JSON output from Claude Code.
    /// Returns the parsed LogEntry, or nil if the line could not be parsed.
    @discardableResult
    func parseLine(_ line: String) -> LogEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Check for ridler-complete signal in raw text
        if trimmed.contains("<ridler-complete/>") {
            completionSubject.send()
        }

        guard let data = trimmed.data(using: .utf8) else {
            Self.logger.warning("StreamingJSONParser: Could not convert line to UTF-8 data")
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Self.logger.warning("StreamingJSONParser: Malformed JSON line: \(trimmed.prefix(200))")
            return nil
        }

        let entry = parseJSON(json)

        // Also check for ridler-complete signal in parsed content
        if entry.content.contains("<ridler-complete/>") {
            completionSubject.send()
        }

        entrySubject.send(entry)
        return entry
    }

    /// Subscribe to a line publisher (e.g., from ClaudeCodeProcessManager) and parse each line.
    /// Returns a cancellable subscription.
    func subscribe(to linePublisher: AnyPublisher<String, Never>) -> AnyCancellable {
        linePublisher
            .sink { [weak self] line in
                self?.parseLine(line)
            }
    }

    // MARK: - Private

    private func parseJSON(_ json: [String: Any]) -> LogEntry {
        let type = json["type"] as? String ?? ""

        switch type {
        case "assistant":
            return parseAssistantMessage(json)
        case "tool_use":
            return parseToolUse(json)
        case "tool_result":
            return parseToolResult(json)
        case "result":
            return parseResult(json)
        case "error":
            return parseError(json)
        default:
            return parseSystemMessage(json, type: type)
        }
    }

    private func parseAssistantMessage(_ json: [String: Any]) -> LogEntry {
        let content: String
        if let message = json["content"] as? String {
            content = message
        } else if let contentArray = json["content"] as? [[String: Any]] {
            // Content can be an array of content blocks
            content = contentArray.compactMap { block -> String? in
                if block["type"] as? String == "text" {
                    return block["text"] as? String
                }
                return nil
            }.joined(separator: "\n")
        } else if let message = json["message"] as? String {
            content = message
        } else {
            content = extractFallbackContent(from: json)
        }
        return LogEntry(type: .assistantText, content: content)
    }

    private func parseToolUse(_ json: [String: Any]) -> LogEntry {
        let toolName = json["tool"] as? String
            ?? json["name"] as? String
            ?? "unknown"

        var content = "Tool: \(toolName)"

        if let input = json["input"] as? [String: Any] {
            // Show a compact representation of the tool input
            if let command = input["command"] as? String {
                content += "\n$ \(command)"
            } else if let filePath = input["file_path"] as? String {
                content += "\n\(filePath)"
            } else if let pattern = input["pattern"] as? String {
                content += "\nPattern: \(pattern)"
            }
        }

        return LogEntry(type: .toolUse, content: content)
    }

    private func parseToolResult(_ json: [String: Any]) -> LogEntry {
        let content: String
        if let output = json["output"] as? String {
            content = output
        } else if let contentArray = json["content"] as? [[String: Any]] {
            content = contentArray.compactMap { block -> String? in
                if block["type"] as? String == "text" {
                    return block["text"] as? String
                }
                return nil
            }.joined(separator: "\n")
        } else {
            content = extractFallbackContent(from: json)
        }
        return LogEntry(type: .toolResult, content: content)
    }

    private func parseResult(_ json: [String: Any]) -> LogEntry {
        let content: String
        if let result = json["result"] as? String {
            content = result
        } else if let text = json["text"] as? String {
            content = text
        } else {
            content = extractFallbackContent(from: json)
        }

        // Check for completion signal in result
        if content.contains("<ridler-complete/>") {
            completionSubject.send()
        }

        return LogEntry(type: .assistantText, content: content)
    }

    private func parseError(_ json: [String: Any]) -> LogEntry {
        let content: String
        if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Unknown error"
            let errorType = error["type"] as? String ?? ""
            content = errorType.isEmpty ? message : "[\(errorType)] \(message)"
        } else if let message = json["message"] as? String {
            content = message
        } else if let error = json["error"] as? String {
            content = error
        } else {
            content = extractFallbackContent(from: json)
        }
        return LogEntry(type: .error, content: content)
    }

    private func parseSystemMessage(_ json: [String: Any], type: String) -> LogEntry {
        let content: String
        if let message = json["message"] as? String {
            content = "[\(type)] \(message)"
        } else {
            content = "[\(type)] \(extractFallbackContent(from: json))"
        }
        return LogEntry(type: .system, content: content)
    }

    private func extractFallbackContent(from json: [String: Any]) -> String {
        // Attempt to serialize back to a compact JSON string for display
        if let data = try? JSONSerialization.data(withJSONObject: json, options: []),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "<unparseable>"
    }
}
