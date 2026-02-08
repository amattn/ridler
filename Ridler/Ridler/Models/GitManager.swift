import Foundation

enum GitError: Error, LocalizedError {
    case notAGitRepository(String)
    case gitNotFound
    case commandFailed(command: [String], stderr: String)
    case branchCreationFailed(command: [String], stderr: String)
    case commitFailed(command: [String], stderr: String)

    var errorDescription: String? {
        switch self {
        case .notAGitRepository(let path):
            return "Not a git repository: \(path)"
        case .gitNotFound:
            return "git executable not found"
        case .commandFailed(let command, let stderr):
            let cmdStr = "git " + command.joined(separator: " ")
            if stderr.isEmpty {
                return "Git command failed: \(cmdStr)"
            }
            return "Git command failed: \(cmdStr)\n\(stderr)"
        case .branchCreationFailed(let command, let stderr):
            let cmdStr = "git " + command.joined(separator: " ")
            if stderr.isEmpty {
                return "Failed to create branch: \(cmdStr)"
            }
            return "Failed to create branch: \(cmdStr)\n\(stderr)"
        case .commitFailed(let command, let stderr):
            let cmdStr = "git " + command.joined(separator: " ")
            if stderr.isEmpty {
                return "Failed to commit: \(cmdStr)"
            }
            return "Failed to commit: \(cmdStr)\n\(stderr)"
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

        let args = arguments
        return try await withCheckedThrowingContinuation { continuation in
            proc.terminationHandler = { process in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: stdout)
                } else {
                    let stderrOutput = stderr.isEmpty ? stdout : stderr
                    continuation.resume(throwing: GitError.commandFailed(command: args, stderr: stderrOutput))
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
        let args = ["rev-parse", "--abbrev-ref", "HEAD"]
        let output = try await gitOperator.runGit(
            arguments: args,
            workingDirectory: workingDirectory
        )
        if output.isEmpty {
            throw GitError.commandFailed(command: args, stderr: "Could not determine current branch")
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
            case .commandFailed(let command, let stderr):
                throw GitError.branchCreationFailed(command: command, stderr: stderr)
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
            case .commandFailed(let command, let stderr):
                throw GitError.commitFailed(command: command, stderr: "Failed to stage changes: \(stderr)")
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
            case .commandFailed(let command, let stderr):
                throw GitError.commitFailed(command: command, stderr: stderr)
            default:
                throw error
            }
        }
    }
}
