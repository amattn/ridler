import Foundation
import Combine
import os

/// Stores log entries per PRD project and supports streaming new entries via Combine.
/// Persists entries to ridler.log as NDJSON and loads them back on project open.
final class LogStore: ObservableObject {
    private static let logger = Logger(subsystem: "com.amattn.Ridler", category: "LogStore")

    @Published private(set) var entries: [String: [LogEntry]] = [:]
    @Published private(set) var loadingProjects: Set<String> = []

    private var fileHandles: [String: FileHandle] = [:]
    private let ioQueue = DispatchQueue(label: "com.amattn.Ridler.LogStore.io", qos: .utility)

    private static let timestampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Returns entries for the given project ID.
    func entries(for projectID: String) -> [LogEntry] {
        entries[projectID] ?? []
    }

    /// Returns entries for the given project filtered by story ID.
    /// When storyID is nil, returns all entries (unfiltered).
    func entries(for projectID: String, storyID: String?) -> [LogEntry] {
        guard let storyID else { return entries(for: projectID) }
        return (entries[projectID] ?? []).filter { $0.storyID == storyID }
    }

    /// Appends a log entry for the given project.
    /// Writes the entry as a JSON line to the project's ridler.log file on the I/O queue.
    func append(_ entry: LogEntry, for projectID: String) {
        // In-memory append on main thread
        if entries[projectID] == nil {
            entries[projectID] = []
        }
        entries[projectID]?.append(entry)

        // Write to disk on I/O queue
        ioQueue.async { [weak self] in
            self?.writeEntry(entry, for: projectID)
        }
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

    // MARK: - File Handle Management

    /// Opens (or creates) the ridler.log file for appending. Call on project open.
    func openLogFile(at url: URL, for projectID: String) {
        ioQueue.async { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            let dirURL = url.deletingLastPathComponent()

            try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
            if !fm.fileExists(atPath: url.path) {
                fm.createFile(atPath: url.path, contents: nil)
            }

            guard let handle = try? FileHandle(forWritingTo: url) else {
                Self.logger.error("Failed to open log file for writing: \(url.path)")
                return
            }
            handle.seekToEndOfFile()
            self.fileHandles[projectID] = handle
            Self.logger.info("Opened log file for \(projectID): \(url.path)")
        }
    }

    /// Closes the ridler.log file handle for a project. Call on project close.
    func closeLogFile(for projectID: String) {
        ioQueue.async { [weak self] in
            guard let self else { return }
            if let handle = self.fileHandles.removeValue(forKey: projectID) {
                handle.closeFile()
                Self.logger.info("Closed log file for \(projectID)")
            }
        }
    }

    // MARK: - Loading

    /// Loads existing log entries from ridler.log on a background thread.
    /// Populates the in-memory store when done.
    func loadEntries(from url: URL, for projectID: String) {
        DispatchQueue.main.async { [weak self] in
            self?.loadingProjects.insert(projectID)
        }

        ioQueue.async { [weak self] in
            guard let self else { return }

            var loaded: [LogEntry] = []

            guard FileManager.default.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url) else {
                DispatchQueue.main.async {
                    self.loadingProjects.remove(projectID)
                }
                return
            }

            guard let contents = String(data: data, encoding: .utf8) else {
                Self.logger.warning("Could not decode log file as UTF-8: \(url.path)")
                DispatchQueue.main.async {
                    self.loadingProjects.remove(projectID)
                }
                return
            }

            let lines = contents.components(separatedBy: "\n")
            for line in lines {
                if let result = StreamingJSONParser.parseLineForLoad(line) {
                    loaded.append(result.entry)
                }
            }

            Self.logger.info("Loaded \(loaded.count) entries from \(url.path)")

            DispatchQueue.main.async {
                // Prepend loaded entries before any that arrived during loading
                let existing = self.entries[projectID] ?? []
                self.entries[projectID] = loaded + existing
                self.loadingProjects.remove(projectID)
            }
        }
    }

    // MARK: - Private

    private func writeEntry(_ entry: LogEntry, for projectID: String) {
        guard let handle = fileHandles[projectID] else { return }

        let timestamp = Self.timestampFormatter.string(from: entry.timestamp)

        let jsonLine: String

        if let rawJSON = entry.rawJSON {
            // Claude Code entry: inject ridler_ fields into the existing JSON
            if let data = rawJSON.data(using: .utf8),
               var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                json["ridler_story_id"] = entry.storyID
                json["ridler_timestamp"] = timestamp
                if let lineData = try? JSONSerialization.data(withJSONObject: json, options: []),
                   let str = String(data: lineData, encoding: .utf8) {
                    jsonLine = str
                } else {
                    return
                }
            } else {
                return
            }
        } else {
            // System-generated entry
            var json: [String: Any] = [
                "ridler_type": "system",
                "ridler_timestamp": timestamp,
                "content": entry.content
            ]
            if let storyID = entry.storyID {
                json["ridler_story_id"] = storyID
            }
            if let lineData = try? JSONSerialization.data(withJSONObject: json, options: []),
               let str = String(data: lineData, encoding: .utf8) {
                jsonLine = str
            } else {
                return
            }
        }

        if let lineData = (jsonLine + "\n").data(using: .utf8) {
            handle.write(lineData)
        }
    }
}
