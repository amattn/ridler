import Foundation

/// Manages git operations by shelling out to the git command-line tool.
final class GitManager: GitManaging {
    private static let protectedBranches: Set<String> = ["main", "master"]

    func currentBranch(at directoryURL: URL) throws -> String {
        let result = try runGit(["rev-parse", "--abbrev-ref", "HEAD"], at: directoryURL)
        let branch = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else {
            throw RidlerError.gitError(
                command: "git rev-parse --abbrev-ref HEAD",
                stderr: "No branch name returned"
            )
        }
        return branch
    }

    func isProtectedBranch(_ branchName: String) -> Bool {
        Self.protectedBranches.contains(branchName)
    }

    func createAndCheckoutBranch(_ branchName: String, at directoryURL: URL) throws {
        _ = try runGit(["checkout", "-b", branchName], at: directoryURL)
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
            throw RidlerError.gitError(command: command, stderr: stderr)
        }

        return stdout
    }
}
