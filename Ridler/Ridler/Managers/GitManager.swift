import Foundation
import os

/// Manages git operations by shelling out to the git command-line tool.
final class GitManager: GitManaging {
    private static let logger = Logger(subsystem: "com.amattn.Ridler", category: "GitManager")
    private static let protectedBranches: Set<String> = ["main", "master"]

    func currentBranch(at directoryURL: URL) throws -> String {
        let result = try runGit(["rev-parse", "--abbrev-ref", "HEAD"], at: directoryURL)
        let branch = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else {
            Self.logger.error("No branch name returned for \(directoryURL.path)")
            throw RidlerError.gitError(
                command: "git rev-parse --abbrev-ref HEAD",
                stderr: "No branch name returned"
            )
        }
        Self.logger.debug("Current branch: \(branch) at \(directoryURL.path)")
        return branch
    }

    func isProtectedBranch(_ branchName: String) -> Bool {
        Self.protectedBranches.contains(branchName)
    }

    func createAndCheckoutBranch(_ branchName: String, at directoryURL: URL) throws {
        Self.logger.info("Creating and checking out branch: \(branchName)")
        _ = try runGit(["checkout", "-b", branchName], at: directoryURL)
    }

    func commitAllChanges(message: String, at directoryURL: URL) throws {
        Self.logger.info("Committing changes: \(message)")
        _ = try runGit(["add", "-A"], at: directoryURL)
        _ = try runGit(["commit", "-m", message], at: directoryURL)
    }

    // MARK: - Private

    private func runGit(_ arguments: [String], at directoryURL: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directoryURL

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        let command = "git " + arguments.joined(separator: " ")

        guard process.terminationStatus == 0 else {
            Self.logger.error("Git command failed: \(command) — \(stderr.prefix(500))")
            throw RidlerError.gitError(command: command, stderr: stderr)
        }

        return stdout
    }
}
