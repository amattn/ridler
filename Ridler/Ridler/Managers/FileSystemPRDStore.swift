import Foundation
import os

struct FileSystemPRDStore: PRDStore {
    private static let logger = Logger(subsystem: "com.amattn.Ridler", category: "PRDStore")

    func loadProject(from directoryURL: URL) throws -> PRDProject {
        let resolvedDir = try resolveDirectory(directoryURL)
        let fileURL = resolvedDir.appendingPathComponent("ridl.json")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            Self.logger.error("File not found: ridl.json at \(resolvedDir.path)")
            throw RidlerError.fileNotFound(
                path: resolvedDir.path,
                filenames: ["ridl.json"]
            )
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            Self.logger.error("Failed to read ridl.json at \(fileURL.path)")
            throw RidlerError.fileNotFound(
                path: fileURL.path,
                filenames: ["ridl.json"]
            )
        }

        let project: PRDProject
        do {
            project = try JSONDecoder().decode(PRDProject.self, from: data)
        } catch let decodingError as DecodingError {
            Self.logger.error("JSON decoding error in ridl.json: \(decodingError.localizedDescription)")
            throw mapDecodingError(decodingError, file: "ridl.json")
        }

        Self.logger.debug("Loaded project \(project.name ?? "unknown") from \(resolvedDir.path)")
        var result = project
        result.directoryURL = resolvedDir
        return result
    }

    func loadMarkdown(filename: String, from directoryURL: URL) throws -> String {
        let resolvedDir = try resolveDirectory(directoryURL)
        let fileURL = resolvedDir.appendingPathComponent(filename)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw RidlerError.fileNotFound(
                path: resolvedDir.path,
                filenames: [filename]
            )
        }

        do {
            return try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            throw RidlerError.fileNotFound(
                path: fileURL.path,
                filenames: [filename]
            )
        }
    }

    func loadMarkdownIfExists(filename: String, from directoryURL: URL) -> String? {
        guard let resolvedDir = try? resolveDirectory(directoryURL) else { return nil }
        let fileURL = resolvedDir.appendingPathComponent(filename)
        return try? String(contentsOf: fileURL, encoding: .utf8)
    }

    func writeProject(_ project: PRDProject, to directoryURL: URL) throws {
        let resolvedDir = try resolveDirectory(directoryURL)
        let fileURL = resolvedDir.appendingPathComponent("ridl.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        try data.write(to: fileURL, options: .atomic)
        Self.logger.debug("Wrote project \(project.name ?? "unknown") to \(fileURL.path)")
    }

    // MARK: - Private

    private func resolveDirectory(_ url: URL) throws -> URL {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

        if exists && isDir.boolValue {
            return url
        }

        if exists && !isDir.boolValue {
            // Given a file — use its parent directory
            return url.deletingLastPathComponent()
        }

        throw RidlerError.fileNotFound(
            path: url.path,
            filenames: ["prd.md", "ridl.md", "ridl.json"]
        )
    }

    private func mapDecodingError(_ error: DecodingError, file: String) -> RidlerError {
        switch error {
        case .keyNotFound(let key, let context):
            let jsonPath = context.codingPath.map(\.stringValue).joined(separator: ".")
            return .jsonDecoding(
                file: file,
                key: key.stringValue,
                jsonPath: jsonPath.isEmpty ? "(root)" : jsonPath,
                underlyingMessage: context.debugDescription
            )
        case .typeMismatch(let type, let context):
            let jsonPath = context.codingPath.map(\.stringValue).joined(separator: ".")
            return .jsonDecoding(
                file: file,
                key: jsonPath.isEmpty ? "(root)" : jsonPath,
                jsonPath: jsonPath.isEmpty ? "(root)" : jsonPath,
                underlyingMessage: "Expected \(type). \(context.debugDescription)"
            )
        case .valueNotFound(let type, let context):
            let jsonPath = context.codingPath.map(\.stringValue).joined(separator: ".")
            return .jsonDecoding(
                file: file,
                key: jsonPath.isEmpty ? "(root)" : jsonPath,
                jsonPath: jsonPath.isEmpty ? "(root)" : jsonPath,
                underlyingMessage: "Expected \(type) but found null. \(context.debugDescription)"
            )
        case .dataCorrupted(let context):
            let jsonPath = context.codingPath.map(\.stringValue).joined(separator: ".")
            return .jsonDecoding(
                file: file,
                key: jsonPath.isEmpty ? "(root)" : jsonPath,
                jsonPath: jsonPath.isEmpty ? "(root)" : jsonPath,
                underlyingMessage: context.debugDescription
            )
        @unknown default:
            return .jsonDecoding(
                file: file,
                key: "(unknown)",
                jsonPath: "(unknown)",
                underlyingMessage: error.localizedDescription
            )
        }
    }
}
