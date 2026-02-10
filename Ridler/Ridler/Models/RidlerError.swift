import Foundation

enum RidlerError: LocalizedError, Equatable {
    case fileNotFound(path: String, filenames: [String])
    case jsonDecoding(file: String, key: String, jsonPath: String, underlyingMessage: String)
    case invalidPRDFormat(details: String)
    case processError(command: String, exitCode: Int32, stderr: String)
    case gitError(command: String, stderr: String)
    case loopError(message: String)
    case claudeConfigNotFound(path: String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path, let filenames):
            let tried = filenames.joined(separator: ", ")
            return "File not found at \(path). Filenames tried: \(tried)"
        case .jsonDecoding(let file, let key, let jsonPath, let underlyingMessage):
            return "\(file): missing or invalid key \"\(key)\" at \(jsonPath). \(underlyingMessage)"
        case .invalidPRDFormat(let details):
            return "Invalid PRD format: \(details)"
        case .processError(let command, let exitCode, let stderr):
            return "Process failed (exit \(exitCode)): \(command)\n\(stderr)"
        case .gitError(let command, let stderr):
            return "Git error: \(command)\n\(stderr)"
        case .loopError(let message):
            return "Loop error: \(message)"
        case .claudeConfigNotFound(let path):
            return "Claude config directory not found at \(path). Please set CLAUDE_CONFIG_DIR in Settings (⌘,)."
        }
    }
}
