import XCTest
@testable import Ridler

// MARK: - Mock Process Spawner

final class MockProcessSpawner: ProcessSpawning, @unchecked Sendable {
    private let lock = NSLock()
    private var _terminated = false
    var terminated: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _terminated
    }

    var exitCode: Int32 = 0
    var outputLines: [String] = []
    var lineDelay: TimeInterval = 0
    var shouldThrow: Error?

    func spawn(
        executablePath: String,
        arguments: [String],
        workingDirectory: String,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws -> ClaudeProcessResult {
        if let error = shouldThrow {
            throw error
        }

        for line in outputLines {
            if terminated { break }

            if lineDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(lineDelay * 1_000_000_000))
            }
            if terminated { break }

            onOutput(line)
        }

        return ClaudeProcessResult(exitCode: exitCode, stderr: "")
    }

    func terminate() {
        lock.lock()
        _terminated = true
        lock.unlock()
    }

    var processIdentifier: Int32? { nil }
}

// MARK: - Tests

final class ClaudeProcessManagerTests: XCTestCase {

    // MARK: - Normal Exit Tests

    func testSuccessfulRunReturnsExitCodeZero() async throws {
        let mock = MockProcessSpawner()
        mock.exitCode = 0
        mock.outputLines = ["{\"type\":\"assistant\",\"text\":\"Hello\"}"]

        let manager = ClaudeProcessManager(spawner: mock)
        let result = try await manager.run(prompt: "test", workingDirectory: "/tmp")

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.success)
    }

    func testNonZeroExitCodeThrowsError() async {
        let mock = MockProcessSpawner()
        mock.exitCode = 1
        mock.outputLines = []

        let manager = ClaudeProcessManager(spawner: mock)

        do {
            _ = try await manager.run(prompt: "test", workingDirectory: "/tmp")
            XCTFail("Expected error to be thrown")
        } catch let error as ClaudeProcessError {
            if case .processFailedWithExitCode(let code, _) = error {
                XCTAssertEqual(code, 1)
            } else {
                XCTFail("Expected processFailedWithExitCode error")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Output Streaming Tests

    func testOutputLinesAreCollected() async throws {
        let mock = MockProcessSpawner()
        mock.exitCode = 0
        mock.outputLines = ["line1", "line2", "line3"]

        let collectedLines = LockIsolated<[String]>([])

        let manager = ClaudeProcessManager(spawner: mock)
        _ = try await manager.run(prompt: "test", workingDirectory: "/tmp") { line in
            collectedLines.withLock { $0.append(line) }
        }

        let lines = collectedLines.withLock { $0 }
        XCTAssertEqual(lines, ["line1", "line2", "line3"])
    }

    func testOutputCallbackReceivesEachLine() async throws {
        let mock = MockProcessSpawner()
        mock.exitCode = 0
        mock.outputLines = ["first", "second"]

        let received = LockIsolated<[String]>([])

        let manager = ClaudeProcessManager(spawner: mock)
        _ = try await manager.run(prompt: "test", workingDirectory: "/tmp") { line in
            received.withLock { $0.append(line) }
        }

        let lines = received.withLock { $0 }
        XCTAssertEqual(lines, ["first", "second"])
    }

    // MARK: - Running State Tests

    func testIsRunningDuringExecution() async throws {
        let mock = MockProcessSpawner()
        mock.exitCode = 0
        mock.outputLines = ["output"]
        mock.lineDelay = 0.1

        let manager = ClaudeProcessManager(spawner: mock)

        let runTask = Task {
            try await manager.run(prompt: "test", workingDirectory: "/tmp")
        }

        // Give the task time to start
        try await Task.sleep(nanoseconds: 50_000_000)

        // Should be running
        await MainActor.run {
            XCTAssertTrue(manager.isRunning)
        }

        _ = try await runTask.value

        // Should not be running after completion
        await MainActor.run {
            XCTAssertFalse(manager.isRunning)
        }
    }

    func testDoubleRunThrowsAlreadyRunning() async throws {
        let mock = MockProcessSpawner()
        mock.exitCode = 0
        mock.outputLines = ["output"]
        mock.lineDelay = 0.5

        let manager = ClaudeProcessManager(spawner: mock)

        let firstTask = Task {
            try await manager.run(prompt: "first", workingDirectory: "/tmp")
        }

        // Give the first task time to start
        try await Task.sleep(nanoseconds: 50_000_000)

        do {
            _ = try await manager.run(prompt: "second", workingDirectory: "/tmp")
            XCTFail("Expected processAlreadyRunning error")
        } catch let error as ClaudeProcessError {
            if case .processAlreadyRunning = error {
                // Expected
            } else {
                XCTFail("Expected processAlreadyRunning, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        _ = try? await firstTask.value
    }

    // MARK: - Cancellation Tests

    func testCancelTerminatesProcess() async throws {
        let mock = MockProcessSpawner()
        mock.exitCode = 0
        mock.outputLines = ["line1", "line2", "line3"]
        mock.lineDelay = 0.2

        let manager = ClaudeProcessManager(spawner: mock)

        let runTask = Task {
            try await manager.run(prompt: "test", workingDirectory: "/tmp")
        }

        // Give the task time to start
        try await Task.sleep(nanoseconds: 50_000_000)

        manager.cancel()

        XCTAssertTrue(mock.terminated)

        _ = try? await runTask.value
    }

    // MARK: - Error Handling Tests

    func testSpawnerErrorPropagates() async {
        let mock = MockProcessSpawner()
        mock.shouldThrow = ClaudeProcessError.executableNotFound("/usr/local/bin/claude")

        let manager = ClaudeProcessManager(spawner: mock)

        do {
            _ = try await manager.run(prompt: "test", workingDirectory: "/tmp")
            XCTFail("Expected error to be thrown")
        } catch let error as ClaudeProcessError {
            if case .executableNotFound = error {
                // Expected
            } else {
                XCTFail("Expected executableNotFound, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        // Should not be running after error
        await MainActor.run {
            XCTAssertFalse(manager.isRunning)
        }
    }

    func testIsNotRunningAfterError() async {
        let mock = MockProcessSpawner()
        mock.exitCode = 1
        mock.outputLines = []

        let manager = ClaudeProcessManager(spawner: mock)

        _ = try? await manager.run(prompt: "test", workingDirectory: "/tmp")

        await MainActor.run {
            XCTAssertFalse(manager.isRunning)
        }
    }

    // MARK: - ClaudeProcessResult Tests

    func testResultSuccessProperty() {
        let success = ClaudeProcessResult(exitCode: 0, stderr: "")
        XCTAssertTrue(success.success)

        let failure = ClaudeProcessResult(exitCode: 1, stderr: "error output")
        XCTAssertFalse(failure.success)
        XCTAssertEqual(failure.stderr, "error output")

        let signaled = ClaudeProcessResult(exitCode: -1, stderr: "")
        XCTAssertFalse(signaled.success)
    }

    // MARK: - Error Description Tests

    func testErrorDescriptions() {
        XCTAssertEqual(
            ClaudeProcessError.processNotRunning.errorDescription,
            "No Claude process is currently running"
        )
        XCTAssertEqual(
            ClaudeProcessError.processAlreadyRunning.errorDescription,
            "A Claude process is already running"
        )
        XCTAssertEqual(
            ClaudeProcessError.processFailedWithExitCode(42, stderr: "").errorDescription,
            "Claude process exited with code 42"
        )
        XCTAssertEqual(
            ClaudeProcessError.processFailedWithExitCode(42, stderr: "something went wrong").errorDescription,
            "Claude process exited with code 42\nsomething went wrong"
        )
        XCTAssertEqual(
            ClaudeProcessError.executableNotFound("/foo/bar").errorDescription,
            "Claude executable not found at: /foo/bar"
        )
    }
}

// MARK: - Thread-Safe Helper

final class LockIsolated<Value>: @unchecked Sendable {
    private var _value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        self._value = value
    }

    func withLock<T>(_ operation: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation(&_value)
    }
}
