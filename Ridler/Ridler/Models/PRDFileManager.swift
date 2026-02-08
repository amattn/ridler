import Foundation

enum PRDFileError: Error, LocalizedError {
    case fileNotFound(String)
    case decodingFailed(String)
    case encodingFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .decodingFailed(let detail):
            return "Failed to decode PRD: \(detail)"
        case .encodingFailed(let detail):
            return "Failed to encode PRD: \(detail)"
        case .writeFailed(let detail):
            return "Failed to write PRD: \(detail)"
        }
    }
}

struct PRDFileManager {
    /// Loads a PRDProject from a ridl.json file at the given path.
    static func load(from path: String) throws -> PRDProject {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PRDFileError.fileNotFound(path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw PRDFileError.fileNotFound(path)
        }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(PRDProject.self, from: data)
        } catch {
            throw PRDFileError.decodingFailed(error.localizedDescription)
        }
    }

    /// Saves a PRDProject to a ridl.json file at the given path.
    static func save(_ project: PRDProject, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(project)
        } catch {
            throw PRDFileError.encodingFailed(error.localizedDescription)
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw PRDFileError.writeFailed(error.localizedDescription)
        }
    }

    /// Given a file path (prd.md or ridl.json), returns the directory containing it.
    static func companionDirectory(for filePath: String) -> String {
        let url = URL(fileURLWithPath: filePath)
        return url.deletingLastPathComponent().path
    }

    /// Locates a companion file (e.g. "ridl.json", "progress.md") in the same directory as the given file.
    /// Returns the full path if the companion file exists, nil otherwise.
    static func companionFilePath(for filePath: String, named fileName: String) -> String? {
        let dir = companionDirectory(for: filePath)
        let companion = (dir as NSString).appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: companion) {
            return companion
        }
        return nil
    }

    /// Loads a PRDProject by locating ridl.json relative to the given file path.
    /// If the given path is already a ridl.json, loads it directly.
    /// If the given path is a prd.md (or any other file), looks for ridl.json in the same directory.
    static func loadFromCompanion(filePath: String) throws -> (project: PRDProject, jsonPath: String) {
        let url = URL(fileURLWithPath: filePath)
        let fileName = url.lastPathComponent

        if fileName.hasSuffix(".json") {
            let project = try load(from: filePath)
            return (project, filePath)
        }

        // Look for ridl.json in the same directory
        let dir = companionDirectory(for: filePath)
        let jsonPath = (dir as NSString).appendingPathComponent("ridl.json")
        if FileManager.default.fileExists(atPath: jsonPath) {
            let project = try load(from: jsonPath)
            return (project, jsonPath)
        }

        // Also try prd.json
        let prdJsonPath = (dir as NSString).appendingPathComponent("prd.json")
        if FileManager.default.fileExists(atPath: prdJsonPath) {
            let project = try load(from: prdJsonPath)
            return (project, prdJsonPath)
        }

        throw PRDFileError.fileNotFound("No JSON file found in \(dir)")
    }
}
