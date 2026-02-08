import XCTest
@testable import Ridler

// MARK: - Mock Git Operator

final class MockGitOperator: GitOperating, @unchecked Sendable {
    private let lock = NSLock()
    private var _commands: [(arguments: [String], workingDirectory: String)] = []
    private var _responses: [String: String] = [:]
    private var _errors: [String: GitError] = [:]

    var commands: [(arguments: [String], workingDirectory: String)] {
        lock.lock()
        defer { lock.unlock() }
        return _commands
    }

    func setResponse(for command: String, output: String) {
        lock.lock()
        _responses[command] = output
        lock.unlock()
    }

    func setError(for command: String, error: GitError) {
        lock.lock()
        _errors[command] = error
        lock.unlock()
    }

    func runGit(arguments: [String], workingDirectory: String) async throws -> String {
        lock.lock()
        _commands.append((arguments: arguments, workingDirectory: workingDirectory))
        let key = arguments.first ?? ""
        let response = _responses[key]
        let error = _errors[key]
        lock.unlock()

        if let error = error {
            throw error
        }
        return response ?? ""
    }
}

// MARK: - Tests

final class GitManagerTests: XCTestCase {

    // MARK: - Branch Detection Tests

    func testCurrentBranchNameReturnsBranch() async throws {
        let mock = MockGitOperator()
        mock.setResponse(for: "rev-parse", output: "feature/my-branch")

        let manager = GitManager(gitOperator: mock)
        let branch = try await manager.currentBranchName(workingDirectory: "/tmp")

        XCTAssertEqual(branch, "feature/my-branch")
    }

    func testCurrentBranchNamePassesCorrectArguments() async throws {
        let mock = MockGitOperator()
        mock.setResponse(for: "rev-parse", output: "main")

        let manager = GitManager(gitOperator: mock)
        _ = try await manager.currentBranchName(workingDirectory: "/some/path")

        let commands = mock.commands
        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands[0].arguments, ["rev-parse", "--abbrev-ref", "HEAD"])
        XCTAssertEqual(commands[0].workingDirectory, "/some/path")
    }

    func testCurrentBranchNameThrowsOnEmptyOutput() async {
        let mock = MockGitOperator()
        mock.setResponse(for: "rev-parse", output: "")

        let manager = GitManager(gitOperator: mock)

        do {
            _ = try await manager.currentBranchName(workingDirectory: "/tmp")
            XCTFail("Expected error to be thrown")
        } catch let error as GitError {
            if case .commandFailed(let msg) = error {
                XCTAssertTrue(msg.contains("Could not determine current branch"))
            } else {
                XCTFail("Expected commandFailed error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testCurrentBranchNamePropagatesGitError() async {
        let mock = MockGitOperator()
        mock.setError(for: "rev-parse", error: .commandFailed("fatal: not a git repository"))

        let manager = GitManager(gitOperator: mock)

        do {
            _ = try await manager.currentBranchName(workingDirectory: "/tmp")
            XCTFail("Expected error to be thrown")
        } catch let error as GitError {
            if case .commandFailed(let msg) = error {
                XCTAssertEqual(msg, "fatal: not a git repository")
            } else {
                XCTFail("Expected commandFailed error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Protected Branch Tests

    func testMainBranchIsProtected() async throws {
        let mock = MockGitOperator()
        mock.setResponse(for: "rev-parse", output: "main")

        let manager = GitManager(gitOperator: mock)
        let isProtected = try await manager.isProtectedBranch(workingDirectory: "/tmp")

        XCTAssertTrue(isProtected)
    }

    func testMasterBranchIsProtected() async throws {
        let mock = MockGitOperator()
        mock.setResponse(for: "rev-parse", output: "master")

        let manager = GitManager(gitOperator: mock)
        let isProtected = try await manager.isProtectedBranch(workingDirectory: "/tmp")

        XCTAssertTrue(isProtected)
    }

    func testFeatureBranchIsNotProtected() async throws {
        let mock = MockGitOperator()
        mock.setResponse(for: "rev-parse", output: "feature/add-login")

        let manager = GitManager(gitOperator: mock)
        let isProtected = try await manager.isProtectedBranch(workingDirectory: "/tmp")

        XCTAssertFalse(isProtected)
    }

    func testRidlerBranchIsNotProtected() async throws {
        let mock = MockGitOperator()
        mock.setResponse(for: "rev-parse", output: "ridler/my-prd")

        let manager = GitManager(gitOperator: mock)
        let isProtected = try await manager.isProtectedBranch(workingDirectory: "/tmp")

        XCTAssertFalse(isProtected)
    }

    // MARK: - Branch Creation Tests

    func testCreateBranchPassesCorrectArguments() async throws {
        let mock = MockGitOperator()
        mock.setResponse(for: "checkout", output: "Switched to a new branch 'ridler/test'")

        let manager = GitManager(gitOperator: mock)
        try await manager.createBranch(name: "ridler/test", workingDirectory: "/my/repo")

        let commands = mock.commands
        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands[0].arguments, ["checkout", "-b", "ridler/test"])
        XCTAssertEqual(commands[0].workingDirectory, "/my/repo")
    }

    func testCreateBranchThrowsBranchCreationFailedOnError() async {
        let mock = MockGitOperator()
        mock.setError(for: "checkout", error: .commandFailed("fatal: A branch named 'ridler/test' already exists"))

        let manager = GitManager(gitOperator: mock)

        do {
            try await manager.createBranch(name: "ridler/test", workingDirectory: "/tmp")
            XCTFail("Expected error to be thrown")
        } catch let error as GitError {
            if case .branchCreationFailed(let msg) = error {
                XCTAssertTrue(msg.contains("already exists"))
            } else {
                XCTFail("Expected branchCreationFailed error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Commit Tests

    func testCommitAllChangesStagesAndCommits() async throws {
        let mock = MockGitOperator()
        mock.setResponse(for: "add", output: "")
        mock.setResponse(for: "commit", output: "[feature abc1234] feat: [US-001] - Story Title")

        let manager = GitManager(gitOperator: mock)
        try await manager.commitAllChanges(
            message: "feat: [US-001] - Story Title",
            workingDirectory: "/my/repo"
        )

        let commands = mock.commands
        XCTAssertEqual(commands.count, 2)

        // First command: stage all changes
        XCTAssertEqual(commands[0].arguments, ["add", "-A"])
        XCTAssertEqual(commands[0].workingDirectory, "/my/repo")

        // Second command: commit
        XCTAssertEqual(commands[1].arguments, ["commit", "-m", "feat: [US-001] - Story Title"])
        XCTAssertEqual(commands[1].workingDirectory, "/my/repo")
    }

    func testCommitFailsOnStagingError() async {
        let mock = MockGitOperator()
        mock.setError(for: "add", error: .commandFailed("fatal: not a git repository"))

        let manager = GitManager(gitOperator: mock)

        do {
            try await manager.commitAllChanges(message: "test", workingDirectory: "/tmp")
            XCTFail("Expected error to be thrown")
        } catch let error as GitError {
            if case .commitFailed(let msg) = error {
                XCTAssertTrue(msg.contains("Failed to stage changes"))
            } else {
                XCTFail("Expected commitFailed error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testCommitFailsOnCommitError() async {
        let mock = MockGitOperator()
        mock.setResponse(for: "add", output: "")
        mock.setError(for: "commit", error: .commandFailed("nothing to commit, working tree clean"))

        let manager = GitManager(gitOperator: mock)

        do {
            try await manager.commitAllChanges(message: "test", workingDirectory: "/tmp")
            XCTFail("Expected error to be thrown")
        } catch let error as GitError {
            if case .commitFailed(let msg) = error {
                XCTAssertEqual(msg, "nothing to commit, working tree clean")
            } else {
                XCTFail("Expected commitFailed error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Error Description Tests

    func testErrorDescriptions() {
        XCTAssertEqual(
            GitError.notAGitRepository("/foo/bar").errorDescription,
            "Not a git repository: /foo/bar"
        )
        XCTAssertEqual(
            GitError.gitNotFound.errorDescription,
            "git executable not found"
        )
        XCTAssertEqual(
            GitError.commandFailed("some error").errorDescription,
            "Git command failed: some error"
        )
        XCTAssertEqual(
            GitError.branchCreationFailed("already exists").errorDescription,
            "Failed to create branch: already exists"
        )
        XCTAssertEqual(
            GitError.commitFailed("nothing to commit").errorDescription,
            "Failed to commit: nothing to commit"
        )
    }
}
