import Foundation

enum GitError: Error, LocalizedError {
    case notAGitRepository(String)
    case gitNotFound
    case commandFailed(String)
    case branchCreationFailed(String)
    case commitFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAGitRepository(let path):
            return "Not a git repository: \(path)"
        case .gitNotFound:
            return "git executable not found"
        case .commandFailed(let message):
            return "Git command failed: \(message)"
        case .branchCreationFailed(let message):
            return "Failed to create branch: \(message)"
        case .commitFailed(let message):
            return "Failed to commit: \(message)"
        }
    }
}

protocol GitOperating: Sendable {
    func runGit(arguments: [String], workingDirectory: String) async throws -> String
}

final class RealGitOperator: GitOperating, @unchecked Sendable {
    private let lock = NSLock()
    private let gitPath: String

    init(gitPath: String = "/usr/bin/git") {
        self.gitPath = gitPath
    }

    func runGit(arguments: [String], workingDirectory: String) async throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: gitPath)
        proc.arguments = arguments
        proc.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            proc.terminationHandler = { process in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: stdout)
                } else {
                    let message = stderr.isEmpty ? stdout : stderr
                    continuation.resume(throwing: GitError.commandFailed(message))
                }
            }

            do {
                try proc.run()
            } catch {
                continuation.resume(throwing: GitError.gitNotFound)
            }
        }
    }
}

final class GitManager {
    private let gitOperator: GitOperating

    init(gitOperator: GitOperating = RealGitOperator()) {
        self.gitOperator = gitOperator
    }

    func currentBranchName(workingDirectory: String) async throws -> String {
        let output = try await gitOperator.runGit(
            arguments: ["rev-parse", "--abbrev-ref", "HEAD"],
            workingDirectory: workingDirectory
        )
        if output.isEmpty {
            throw GitError.commandFailed("Could not determine current branch")
        }
        return output
    }

    func isProtectedBranch(workingDirectory: String) async throws -> Bool {
        let branch = try await currentBranchName(workingDirectory: workingDirectory)
        return branch == "main" || branch == "master"
    }

    func createBranch(name: String, workingDirectory: String) async throws {
        do {
            _ = try await gitOperator.runGit(
                arguments: ["checkout", "-b", name],
                workingDirectory: workingDirectory
            )
        } catch let error as GitError {
            switch error {
            case .commandFailed(let message):
                throw GitError.branchCreationFailed(message)
            default:
                throw error
            }
        }
    }

    func commitAllChanges(message: String, workingDirectory: String) async throws {
        // Stage all changes (tracked and untracked)
        do {
            _ = try await gitOperator.runGit(
                arguments: ["add", "-A"],
                workingDirectory: workingDirectory
            )
        } catch let error as GitError {
            switch error {
            case .commandFailed(let msg):
                throw GitError.commitFailed("Failed to stage changes: \(msg)")
            default:
                throw error
            }
        }

        // Create the commit
        do {
            _ = try await gitOperator.runGit(
                arguments: ["commit", "-m", message],
                workingDirectory: workingDirectory
            )
        } catch let error as GitError {
            switch error {
            case .commandFailed(let msg):
                throw GitError.commitFailed(msg)
            default:
                throw error
            }
        }
    }
}
