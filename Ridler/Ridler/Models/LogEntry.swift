import Foundation

/// Represents a parsed log entry from Claude Code's streaming JSON output.
struct LogEntry: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let type: LogEntryType
    let content: String
    let storyID: String?
    let rawJSON: String?

    init(id: UUID = UUID(), timestamp: Date = Date(), type: LogEntryType, content: String, storyID: String? = nil, rawJSON: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.content = content
        self.storyID = storyID
        self.rawJSON = rawJSON
    }
}

/// The type of a log entry parsed from Claude Code's stream-json output.
enum LogEntryType: String, Equatable {
    case assistantText
    case toolUse
    case toolResult
    case error
    case system
}
