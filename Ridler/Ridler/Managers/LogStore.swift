import Foundation
import Combine

/// Stores log entries per PRD project and supports streaming new entries via Combine.
final class LogStore: ObservableObject {
    @Published private(set) var entries: [String: [LogEntry]] = [:]

    /// Returns entries for the given project ID.
    func entries(for projectID: String) -> [LogEntry] {
        entries[projectID] ?? []
    }

    /// Appends a log entry for the given project.
    func append(_ entry: LogEntry, for projectID: String) {
        if entries[projectID] == nil {
            entries[projectID] = []
        }
        entries[projectID]?.append(entry)
    }

    /// Appends a system-level log entry (story transitions, iteration starts, completions).
    func appendSystem(_ message: String, for projectID: String) {
        let entry = LogEntry(type: .system, content: message)
        append(entry, for: projectID)
    }

    /// Clears all entries for the given project.
    func clear(for projectID: String) {
        entries[projectID] = []
    }
}
