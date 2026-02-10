import Foundation

/// Protocol defining the interface for git operations, enabling test mocking.
protocol GitManaging {
    /// Returns the name of the current git branch at the given directory.
    func currentBranch(at directoryURL: URL) throws -> String

    /// Returns true if the branch is a protected branch (main or master).
    func isProtectedBranch(_ branchName: String) -> Bool

    /// Creates and checks out a new branch with the given name.
    func createAndCheckoutBranch(_ branchName: String, at directoryURL: URL) throws

    /// Stages all changes and creates a commit with the given message.
    func commitAllChanges(message: String, at directoryURL: URL) throws
}
