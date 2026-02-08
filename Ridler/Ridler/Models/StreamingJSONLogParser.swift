import Foundation

// MARK: - LogEntry

enum LogEntryType: Equatable {
    case assistantText(String)
    case toolUse(toolName: String, input: String)
    case toolResult(output: String)
    case error(String)
    case system(String)
}

struct LogEntry: Identifiable, Equatable {
    let id: UUID
    let type: LogEntryType
    let timestamp: Date

    init(type: LogEntryType, timestamp: Date = Date()) {
        self.id = UUID()
        self.type = type
        self.timestamp = timestamp
    }
}

// MARK: - StreamingJSONLogParser

final class StreamingJSONLogParser {
    private(set) var ridlerCompleteDetected = false

    func parse(line: String) -> LogEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let data = trimmed.data(using: .utf8) else {
            return LogEntry(type: .error("Failed to encode line as UTF-8"))
        }

        let json: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return LogEntry(type: .error("JSON is not a dictionary: \(truncate(trimmed))"))
            }
            json = parsed
        } catch {
            return LogEntry(type: .error("Malformed JSON: \(truncate(trimmed))"))
        }

        guard let type = json["type"] as? String else {
            return LogEntry(type: .error("Missing 'type' field: \(truncate(trimmed))"))
        }

        switch type {
        case "assistant":
            return parseAssistant(json)
        case "tool_use":
            return parseToolUse(json)
        case "tool_result":
            return parseToolResult(json)
        case "error":
            return parseError(json)
        case "system":
            return parseSystem(json)
        case "result":
            return parseResult(json)
        default:
            return LogEntry(type: .system("Unknown event type: \(type)"))
        }
    }

    // MARK: - Private Parsers

    private func parseAssistant(_ json: [String: Any]) -> LogEntry? {
        // Claude stream-json assistant messages have a "message" field with "content" blocks
        if let message = json["message"] as? [String: Any],
           let content = message["content"] as? [[String: Any]] {
            let texts = content.compactMap { block -> String? in
                guard let blockType = block["type"] as? String else { return nil }
                if blockType == "text", let text = block["text"] as? String {
                    checkForRidlerComplete(text)
                    return text
                }
                return nil
            }
            if !texts.isEmpty {
                return LogEntry(type: .assistantText(texts.joined(separator: "\n")))
            }
        }

        // Fallback: direct content_block or text field
        if let content = json["content_block"] as? [String: Any],
           let blockType = content["type"] as? String,
           blockType == "text",
           let text = content["text"] as? String {
            checkForRidlerComplete(text)
            return LogEntry(type: .assistantText(text))
        }

        // content_block_delta with delta.text
        if let delta = json["delta"] as? [String: Any],
           let text = delta["text"] as? String {
            checkForRidlerComplete(text)
            if !text.isEmpty {
                return LogEntry(type: .assistantText(text))
            }
        }

        return nil
    }

    private func parseToolUse(_ json: [String: Any]) -> LogEntry {
        let toolName = json["name"] as? String ?? "unknown"
        let input: String
        if let inputObj = json["input"] {
            if let inputData = try? JSONSerialization.data(withJSONObject: inputObj, options: [.fragmentsAllowed]),
               let inputStr = String(data: inputData, encoding: .utf8) {
                input = truncate(inputStr, maxLength: 500)
            } else {
                input = String(describing: inputObj)
            }
        } else {
            input = ""
        }
        return LogEntry(type: .toolUse(toolName: toolName, input: input))
    }

    private func parseToolResult(_ json: [String: Any]) -> LogEntry {
        let output: String
        if let content = json["content"] as? String {
            output = content
        } else if let content = json["output"] as? String {
            output = content
        } else if let content = json["content"] as? [[String: Any]] {
            let texts = content.compactMap { block -> String? in
                if let text = block["text"] as? String { return text }
                return nil
            }
            output = texts.joined(separator: "\n")
        } else {
            output = ""
        }
        return LogEntry(type: .toolResult(output: output))
    }

    private func parseError(_ json: [String: Any]) -> LogEntry {
        let message: String
        if let error = json["error"] as? [String: Any],
           let msg = error["message"] as? String {
            message = msg
        } else if let msg = json["message"] as? String {
            message = msg
        } else {
            message = "Unknown error"
        }
        return LogEntry(type: .error(message))
    }

    private func parseSystem(_ json: [String: Any]) -> LogEntry {
        let message = json["message"] as? String
            ?? json["subtype"] as? String
            ?? "System event"
        return LogEntry(type: .system(message))
    }

    private func parseResult(_ json: [String: Any]) -> LogEntry? {
        // Final result message — extract any text from the result
        if let result = json["result"] as? String {
            checkForRidlerComplete(result)
            return LogEntry(type: .assistantText(result))
        }
        // Result can also contain a structured message
        if let message = json["message"] as? [String: Any],
           let content = message["content"] as? [[String: Any]] {
            let texts = content.compactMap { block -> String? in
                guard let blockType = block["type"] as? String, blockType == "text",
                      let text = block["text"] as? String else { return nil }
                return text
            }
            if !texts.isEmpty {
                let combined = texts.joined(separator: "\n")
                checkForRidlerComplete(combined)
                return LogEntry(type: .assistantText(combined))
            }
        }
        return LogEntry(type: .system("Result received"))
    }

    // MARK: - Ridler Complete Detection

    private func checkForRidlerComplete(_ text: String) {
        if text.contains("<ridler-complete/>") {
            ridlerCompleteDetected = true
        }
    }

    // MARK: - Helpers

    private func truncate(_ string: String, maxLength: Int = 200) -> String {
        if string.count <= maxLength { return string }
        return String(string.prefix(maxLength)) + "..."
    }
}
