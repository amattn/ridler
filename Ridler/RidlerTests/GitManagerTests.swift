import XCTest
@testable import Ridler

final class GitManagerTests: XCTestCase {

    private var tempDir: URL!
    private let gitManager = GitManager()

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitManagerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Integration Tests with real git repos

    func testCurrentBranchInNewRepo() throws {
        try initGitRepo(at: tempDir, defaultBranch: "main")
        let branch = try gitManager.currentBranch(at: tempDir)
        XCTAssertEqual(branch, "main")
    }

    func testCurrentBranchAfterCheckout() throws {
        try initGitRepo(at: tempDir, defaultBranch: "main")
        try runGit(["checkout", "-b", "feature/test"], at: tempDir)
        let branch = try gitManager.currentBranch(at: tempDir)
        XCTAssertEqual(branch, "feature/test")
    }

    func testCurrentBranchInNonGitDir() {
        XCTAssertThrowsError(try gitManager.currentBranch(at: tempDir)) { error in
            guard case RidlerError.gitError(let command, _) = error else {
                XCTFail("Expected RidlerError.gitError, got \(error)")
                return
            }
            XCTAssertTrue(command.contains("rev-parse"))
        }
    }

    func testIsProtectedBranchMain() {
        XCTAssertTrue(gitManager.isProtectedBranch("main"))
    }

    func testIsProtectedBranchMaster() {
        XCTAssertTrue(gitManager.isProtectedBranch("master"))
    }

    func testIsProtectedBranchFeature() {
        XCTAssertFalse(gitManager.isProtectedBranch("feature/my-feature"))
    }

    func testIsProtectedBranchDevelop() {
        XCTAssertFalse(gitManager.isProtectedBranch("develop"))
    }

    func testCreateAndCheckoutBranch() throws {
        try initGitRepo(at: tempDir, defaultBranch: "main")
        try gitManager.createAndCheckoutBranch("ridler/test-prd", at: tempDir)
        let branch = try gitManager.currentBranch(at: tempDir)
        XCTAssertEqual(branch, "ridler/test-prd")
    }

    func testCreateBranchThatAlreadyExists() throws {
        try initGitRepo(at: tempDir, defaultBranch: "main")
        try runGit(["checkout", "-b", "existing-branch"], at: tempDir)
        try runGit(["checkout", "main"], at: tempDir)
        XCTAssertThrowsError(try gitManager.createAndCheckoutBranch("existing-branch", at: tempDir)) { error in
            guard case RidlerError.gitError(let command, let stderr) = error else {
                XCTFail("Expected RidlerError.gitError, got \(error)")
                return
            }
            XCTAssertTrue(command.contains("checkout"))
            XCTAssertFalse(stderr.isEmpty)
        }
    }

    func testGitErrorIncludesCommandAndStderr() {
        do {
            _ = try gitManager.currentBranch(at: tempDir)
            XCTFail("Expected error")
        } catch let error as RidlerError {
            let description = error.errorDescription ?? ""
            XCTAssertTrue(description.contains("git"), "Error should mention git command")
        } catch {
            XCTFail("Expected RidlerError, got \(type(of: error))")
        }
    }

    func testProtectedBranchDetectionIntegration() throws {
        // Create repo on main branch
        try initGitRepo(at: tempDir, defaultBranch: "main")
        let branch = try gitManager.currentBranch(at: tempDir)
        XCTAssertTrue(gitManager.isProtectedBranch(branch))

        // Switch to non-protected branch
        try gitManager.createAndCheckoutBranch("ridler/my-prd", at: tempDir)
        let newBranch = try gitManager.currentBranch(at: tempDir)
        XCTAssertFalse(gitManager.isProtectedBranch(newBranch))
    }

    // MARK: - Helpers

    private func initGitRepo(at url: URL, defaultBranch: String = "main") throws {
        try runGit(["init", "--initial-branch", defaultBranch], at: url)
        // Create initial commit so HEAD exists
        let dummyFile = url.appendingPathComponent("README.md")
        try "# Test".write(to: dummyFile, atomically: true, encoding: .utf8)
        try runGit(["add", "."], at: url)
        try runGit(["-c", "user.name=Test", "-c", "user.email=test@test.com", "commit", "-m", "Initial commit"], at: url)
    }

    @discardableResult
    private func runGit(_ arguments: [String], at url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = url

        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "GitTest", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: stderr])
        }

        return output
    }
}
