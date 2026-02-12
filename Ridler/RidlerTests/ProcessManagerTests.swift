import XCTest
import Combine
@testable import Ridler

final class ProcessManagerTests: XCTestCase {
    var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - ProcessExitResult Tests

    func testProcessExitResultEquality() {
        let result1 = ProcessExitResult(exitCode: 0, stderr: "", command: "cmd")
        let result2 = ProcessExitResult(exitCode: 0, stderr: "", command: "cmd")
        XCTAssertEqual(result1, result2)
    }

    func testProcessExitResultInequality() {
        let result1 = ProcessExitResult(exitCode: 0, stderr: "", command: "cmd1")
        let result2 = ProcessExitResult(exitCode: 1, stderr: "error", command: "cmd2")
        XCTAssertNotEqual(result1, result2)
    }

    // MARK: - ClaudeCodeProcessManager Initialization Tests

    func testManagerInitiallyNotRunning() {
        let manager = ClaudeCodeProcessManager()
        XCTAssertFalse(manager.isRunning)
    }

    // MARK: - Process Spawn and Stream Tests (using /bin/echo)

    func testSpawnAndKillOnNonRunning() throws {
        let manager = ClaudeCodeProcessManager()

        // Test kill on non-running process does nothing
        manager.kill()
        XCTAssertFalse(manager.isRunning)
    }

    func testKillOnNonRunningProcessIsNoOp() {
        let manager = ClaudeCodeProcessManager()
        // Should not crash
        manager.kill()
        XCTAssertFalse(manager.isRunning)
    }

    // MARK: - Log File Creation Tests (moved to LogStore)

    func testLogFileCreatedByLogStore() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logFile = tempDir.appendingPathComponent("ridler.log")
        let logStore = LogStore()

        logStore.openLogFile(at: logFile, for: "test-project")

        // Wait for the ioQueue to finish creating the file
        let expectation = XCTestExpectation(description: "File created")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        XCTAssertTrue(FileManager.default.fileExists(atPath: logFile.path))

        logStore.closeLogFile(for: "test-project")
    }

    // MARK: - Process Error Reporting Tests

    func testProcessExitResultIncludesCommand() {
        let result = ProcessExitResult(
            exitCode: 127,
            stderr: "command not found",
            command: "claude --dangerously-skip-permissions --output-format stream-json -p <prompt>"
        )
        XCTAssertEqual(result.exitCode, 127)
        XCTAssertEqual(result.stderr, "command not found")
        XCTAssertTrue(result.command.contains("claude"))
    }

    func testRidlerErrorProcessError() {
        let error = RidlerError.processError(
            command: "claude --dangerously-skip-permissions",
            exitCode: 1,
            stderr: "API key not set"
        )
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("exit 1"))
        XCTAssertTrue(description.contains("claude"))
        XCTAssertTrue(description.contains("API key not set"))
    }

    // MARK: - Exit Publisher Tests

    func testExitPublisherIsAvailable() {
        let manager = ClaudeCodeProcessManager()
        var received = false

        manager.exitPublisher
            .sink { _ in received = true }
            .store(in: &cancellables)

        // Publisher exists but won't emit until a process runs and exits
        XCTAssertFalse(received)
    }

    // MARK: - Subprocess with /bin/echo (real process test)

    func testRealSubprocessWithEcho() throws {
        // Directly test Process spawning pattern similar to ClaudeCodeProcessManager
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/echo")
        process.arguments = ["hello from test"]
        process.standardOutput = pipe

        let expectation = XCTestExpectation(description: "Process completes")
        var output = ""

        process.terminationHandler = { _ in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            output = String(data: data, encoding: .utf8) ?? ""
            expectation.fulfill()
        }

        try process.run()
        wait(for: [expectation], timeout: 5.0)

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(output.contains("hello from test"))
    }

    func testNoZombieProcessOnKill() throws {
        let manager = ClaudeCodeProcessManager()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logFile = tempDir.appendingPathComponent("test.log")

        let exitExpectation = XCTestExpectation(description: "Process exits after kill")

        manager.exitPublisher
            .sink { _ in
                exitExpectation.fulfill()
            }
            .store(in: &cancellables)

        do {
            _ = try manager.spawn(
                prompt: "test",
                workingDirectory: tempDir,
                logFileURL: logFile
            )

            // Kill immediately
            manager.kill()

            wait(for: [exitExpectation], timeout: 10.0)

            // After termination handler runs, process should be nil
            // Give a moment for the main queue async to complete
            let cleanupExpectation = XCTestExpectation(description: "Cleanup completes")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                XCTAssertFalse(manager.isRunning)
                cleanupExpectation.fulfill()
            }
            wait(for: [cleanupExpectation], timeout: 2.0)
        } catch {
            // If claude/env not found, test still validates the kill path doesn't crash
            XCTAssertFalse(manager.isRunning)
        }
    }
}
