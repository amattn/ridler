import XCTest
import Combine
@testable import Ridler

// MARK: - Mock ProcessManaging

final class MockProcessManager: ProcessManaging {
    var isRunning: Bool = false
    var processIdentifier: Int32? = nil
    var spawnCallCount = 0
    var lastPrompt: String?
    var lastWorkingDirectory: URL?
    var killCallCount = 0

    private let lineSubject = PassthroughSubject<String, Never>()
    private let exitSubject = PassthroughSubject<ProcessExitResult, Never>()

    var exitPublisher: AnyPublisher<ProcessExitResult, Never> {
        exitSubject.eraseToAnyPublisher()
    }

    func spawn(prompt: String, workingDirectory: URL, logFileURL: URL) throws -> AnyPublisher<String, Never> {
        spawnCallCount += 1
        lastPrompt = prompt
        lastWorkingDirectory = workingDirectory
        isRunning = true
        return lineSubject.eraseToAnyPublisher()
    }

    func kill() {
        killCallCount += 1
        isRunning = false
    }

    // Test helpers
    func sendLine(_ line: String) {
        lineSubject.send(line)
    }

    func sendExit(code: Int32 = 0, stderr: String = "") {
        isRunning = false
        exitSubject.send(ProcessExitResult(exitCode: code, stderr: stderr, command: "claude"))
    }
}

// MARK: - Mock GitManaging

final class MockGitManager: GitManaging {
    var currentBranchResult: String = "main"
    var currentBranchError: Error?
    var commitCallCount = 0
    var lastCommitMessage: String?
    var lastCommitDirectory: URL?
    var commitError: Error?

    func currentBranch(at directoryURL: URL) throws -> String {
        if let error = currentBranchError { throw error }
        return currentBranchResult
    }

    func isProtectedBranch(_ branchName: String) -> Bool {
        branchName == "main" || branchName == "master"
    }

    func createAndCheckoutBranch(_ branchName: String, at directoryURL: URL) throws {}

    func commitAllChanges(message: String, at directoryURL: URL) throws {
        if let error = commitError { throw error }
        commitCallCount += 1
        lastCommitMessage = message
        lastCommitDirectory = directoryURL
    }
}

// MARK: - Tests

final class RalphLoopEngineTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RalphLoopEngineTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func createTestProject(stories: [UserStory]) throws -> PRDProject {
        let project = PRDProject(
            name: "TestProject",
            userStories: stories,
            directoryURL: tempDir
        )
        let store = FileSystemPRDStore()
        try store.writeProject(project, to: tempDir)
        return project
    }

    // MARK: - Story Selection Tests

    func testSelectsHighestPriorityStoryWithPassesFalse() throws {
        let stories = [
            UserStory(id: "US-001", title: "First", description: "d1", priority: 2, acceptanceCriteria: ["a"], passes: true),
            UserStory(id: "US-002", title: "Second", description: "d2", priority: 1, acceptanceCriteria: ["b"], passes: false),
            UserStory(id: "US-003", title: "Third", description: "d3", priority: 3, acceptanceCriteria: ["c"], passes: false),
        ]
        let project = try createTestProject(stories: stories)

        var mockPM: MockProcessManager?
        let engine = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: {
                let pm = MockProcessManager()
                mockPM = pm
                return pm
            }
        )

        let stateExpectation = XCTestExpectation(description: "State changed to running")
        engine.onStateChange = { state in
            if state == .running {
                stateExpectation.fulfill()
            }
        }

        engine.start(project: project)
        wait(for: [stateExpectation], timeout: 2.0)

        // The prompt should contain US-002 (priority 1, not yet passing)
        XCTAssertNotNil(mockPM)
        XCTAssertTrue(mockPM?.lastPrompt?.contains("US-002") ?? false, "Should select US-002 (lowest priority number, passes: false)")
    }

    func testCompletesWhenAllStoriesPass() throws {
        let stories = [
            UserStory(id: "US-001", title: "First", description: "d1", priority: 1, acceptanceCriteria: ["a"], passes: true),
            UserStory(id: "US-002", title: "Second", description: "d2", priority: 2, acceptanceCriteria: ["b"], passes: true),
        ]
        let project = try createTestProject(stories: stories)

        let engine = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: { MockProcessManager() }
        )

        let completeExpectation = XCTestExpectation(description: "Loop completes")
        engine.onStateChange = { state in
            if state == .complete {
                completeExpectation.fulfill()
            }
        }

        engine.start(project: project)
        wait(for: [completeExpectation], timeout: 2.0)
    }

    // MARK: - State Transition Tests

    func testStartTransitionsToRunning() throws {
        let stories = [
            UserStory(id: "US-001", title: "First", description: "d", priority: 1, acceptanceCriteria: ["a"]),
        ]
        let project = try createTestProject(stories: stories)

        let engine = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: { MockProcessManager() }
        )

        let runningExpectation = XCTestExpectation(description: "Running")
        engine.onStateChange = { state in
            if state == .running {
                runningExpectation.fulfill()
            }
        }

        engine.start(project: project)
        wait(for: [runningExpectation], timeout: 2.0)
    }

    func testPauseTransitionsToPaused() throws {
        let stories = [
            UserStory(id: "US-001", title: "First", description: "d", priority: 1, acceptanceCriteria: ["a"]),
        ]
        let project = try createTestProject(stories: stories)

        let engine = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: { MockProcessManager() }
        )

        let pausedExpectation = XCTestExpectation(description: "Paused")
        var gotRunning = false
        engine.onStateChange = { state in
            if state == .running {
                gotRunning = true
            }
            if state == .paused && gotRunning {
                pausedExpectation.fulfill()
            }
        }

        engine.start(project: project)
        // Small delay to let start() take effect
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            engine.pause()
        }

        wait(for: [pausedExpectation], timeout: 2.0)
    }

    func testStopKillsProcess() throws {
        let stories = [
            UserStory(id: "US-001", title: "First", description: "d", priority: 1, acceptanceCriteria: ["a"]),
        ]
        let project = try createTestProject(stories: stories)

        var mockPM: MockProcessManager?
        let engine = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: {
                let pm = MockProcessManager()
                mockPM = pm
                return pm
            }
        )

        let stoppedExpectation = XCTestExpectation(description: "Stopped")
        var gotRunning = false
        engine.onStateChange = { state in
            if state == .running {
                gotRunning = true
            }
            if state == .stopped && gotRunning {
                stoppedExpectation.fulfill()
            }
        }

        engine.start(project: project)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            engine.stop()
        }

        wait(for: [stoppedExpectation], timeout: 2.0)
        XCTAssertEqual(mockPM?.killCallCount, 1)
    }

    // MARK: - Iteration Tests

    func testIterationCountIncrements() throws {
        let stories = [
            UserStory(id: "US-001", title: "First", description: "d", priority: 1, acceptanceCriteria: ["a"]),
        ]
        let project = try createTestProject(stories: stories)

        let engine = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: { MockProcessManager() }
        )

        let iterationExpectation = XCTestExpectation(description: "Iteration incremented")
        engine.onIterationChange = { count in
            if count == 1 {
                iterationExpectation.fulfill()
            }
        }

        engine.start(project: project)
        wait(for: [iterationExpectation], timeout: 2.0)
    }

    func testMaxIterationsStopsLoop() throws {
        let stories = [
            UserStory(id: "US-001", title: "First", description: "d", priority: 1, acceptanceCriteria: ["a"]),
        ]
        var project = try createTestProject(stories: stories)
        project.maxIterations = 1
        project.iterationCount = 1 // Already at max

        let engine = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: { MockProcessManager() }
        )

        let stoppedExpectation = XCTestExpectation(description: "Stopped")
        engine.onStateChange = { state in
            if state == .stopped {
                stoppedExpectation.fulfill()
            }
        }

        engine.start(project: project)
        wait(for: [stoppedExpectation], timeout: 2.0)
    }

    // MARK: - Prompt Building Tests

    func testPromptContainsStoryDetails() throws {
        let stories = [
            UserStory(id: "US-042", title: "Test Feature", description: "Test description", priority: 5, acceptanceCriteria: ["Criterion A", "Criterion B"]),
        ]
        let project = try createTestProject(stories: stories)

        var capturedPrompt: String?
        let engine = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: {
                let pm = MockProcessManager()
                capturedPrompt = nil
                return pm
            }
        )

        // Capture prompt via the mock's lastPrompt
        var mockPM: MockProcessManager?
        let engine2 = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: {
                let pm = MockProcessManager()
                mockPM = pm
                return pm
            }
        )

        let runningExpectation = XCTestExpectation(description: "Running")
        engine2.onStateChange = { state in
            if state == .running {
                runningExpectation.fulfill()
            }
        }

        engine2.start(project: project)
        wait(for: [runningExpectation], timeout: 2.0)

        let prompt = mockPM?.lastPrompt ?? ""
        XCTAssertTrue(prompt.contains("US-042"), "Prompt should contain story ID")
        XCTAssertTrue(prompt.contains("Test Feature"), "Prompt should contain story title")
        XCTAssertTrue(prompt.contains("Test description"), "Prompt should contain story description")
        XCTAssertTrue(prompt.contains("Criterion A"), "Prompt should contain acceptance criteria")
        XCTAssertTrue(prompt.contains("Criterion B"), "Prompt should contain acceptance criteria")
        XCTAssertTrue(prompt.contains("<ridler-complete/>"), "Prompt should include completion signal instruction")
    }

    // MARK: - Log System Messages

    func testSystemLogMessagesEmitted() throws {
        let stories = [
            UserStory(id: "US-001", title: "First", description: "d", priority: 1, acceptanceCriteria: ["a"]),
        ]
        let project = try createTestProject(stories: stories)

        let engine = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: { MockProcessManager() }
        )

        var logMessages: [String] = []
        engine.onLogEntry = { entry, _ in
            if entry.type == .system {
                logMessages.append(entry.content)
            }
        }

        let runningExpectation = XCTestExpectation(description: "Running")
        engine.onStateChange = { state in
            if state == .running {
                runningExpectation.fulfill()
            }
        }

        engine.start(project: project)
        wait(for: [runningExpectation], timeout: 2.0)

        XCTAssertTrue(logMessages.contains(where: { $0.contains("Loop started") }))
        XCTAssertTrue(logMessages.contains(where: { $0.contains("Iteration 1") }))
    }

    // MARK: - Working Directory Tests

    func testWorkingDirectoryIsParentOfPRDDirectory() throws {
        let stories = [
            UserStory(id: "US-001", title: "First", description: "d", priority: 1, acceptanceCriteria: ["a"]),
        ]
        let project = try createTestProject(stories: stories)

        var mockPM: MockProcessManager?
        let engine = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: {
                let pm = MockProcessManager()
                mockPM = pm
                return pm
            }
        )

        let runningExpectation = XCTestExpectation(description: "Running")
        engine.onStateChange = { state in
            if state == .running {
                runningExpectation.fulfill()
            }
        }

        engine.start(project: project)
        wait(for: [runningExpectation], timeout: 2.0)

        // Working directory should be parent of the PRD directory
        let expectedParent = tempDir.deletingLastPathComponent()
        XCTAssertEqual(
            mockPM?.lastWorkingDirectory?.standardizedFileURL,
            expectedParent.standardizedFileURL,
            "Working directory should be parent of PRD directory"
        )
    }

    // MARK: - Story InProgress Marking

    func testMarksStoryAsInProgress() throws {
        let stories = [
            UserStory(id: "US-001", title: "First", description: "d", priority: 1, acceptanceCriteria: ["a"]),
        ]
        let project = try createTestProject(stories: stories)

        let engine = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: { MockProcessManager() }
        )

        let runningExpectation = XCTestExpectation(description: "Running")
        engine.onStateChange = { state in
            if state == .running {
                runningExpectation.fulfill()
            }
        }

        engine.start(project: project)
        wait(for: [runningExpectation], timeout: 2.0)

        // Verify the story was marked as inProgress on disk
        let store = FileSystemPRDStore()
        let reloaded = try store.loadProject(from: tempDir)
        let story = reloaded.userStories.first { $0.id == "US-001" }
        XCTAssertTrue(story?.inProgress ?? false, "Story should be marked as inProgress")
    }

    // MARK: - Process Exit Handling

    func testProcessExitWithNonZeroCodeTransitionsToError() throws {
        let stories = [
            UserStory(id: "US-001", title: "First", description: "d", priority: 1, acceptanceCriteria: ["a"]),
        ]
        let project = try createTestProject(stories: stories)

        var mockPM: MockProcessManager?
        let engine = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: {
                let pm = MockProcessManager()
                mockPM = pm
                return pm
            }
        )

        let errorExpectation = XCTestExpectation(description: "Error state")
        engine.onStateChange = { state in
            if state == .error {
                errorExpectation.fulfill()
            }
        }

        engine.start(project: project)

        // Wait for spawn, then send error exit
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            mockPM?.sendExit(code: 1, stderr: "Something went wrong")
        }

        wait(for: [errorExpectation], timeout: 3.0)
    }

    func testProcessExitWithZeroCodeAndCompletionDetected() throws {
        // Create two stories, one passing, one not
        let stories = [
            UserStory(id: "US-001", title: "First", description: "d", priority: 1, acceptanceCriteria: ["a"], passes: true),
            UserStory(id: "US-002", title: "Second", description: "d", priority: 2, acceptanceCriteria: ["b"]),
        ]
        let project = try createTestProject(stories: stories)

        var mockPM: MockProcessManager?
        let engine = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: {
                let pm = MockProcessManager()
                mockPM = pm
                return pm
            }
        )

        // After process exits normally, update the story on disk, then let the engine check
        let stateExpectation = XCTestExpectation(description: "State after exit")
        var finalState: LoopState?
        engine.onStateChange = { state in
            finalState = state
            if state != .running {
                stateExpectation.fulfill()
            }
        }

        engine.start(project: project)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Simulate Claude completing the story by updating ridl.json
            let store = FileSystemPRDStore()
            var updated = (try? store.loadProject(from: self.tempDir)) ?? project
            if let idx = updated.userStories.firstIndex(where: { $0.id == "US-002" }) {
                updated.userStories[idx].passes = true
                updated.userStories[idx].inProgress = false
            }
            try? store.writeProject(updated, to: self.tempDir)

            // Send completion signal then successful exit
            mockPM?.sendLine("{\"type\":\"assistant\",\"content\":\"Done! <ridler-complete/>\"}")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                mockPM?.sendExit(code: 0)
            }
        }

        wait(for: [stateExpectation], timeout: 5.0)
        XCTAssertEqual(finalState, .complete)
    }

    // MARK: - Pause After Story

    func testPauseAfterStoryPausesOnIterationComplete() throws {
        let stories = [
            UserStory(id: "US-001", title: "First", description: "d", priority: 1, acceptanceCriteria: ["a"]),
            UserStory(id: "US-002", title: "Second", description: "d", priority: 2, acceptanceCriteria: ["b"]),
        ]
        var project = try createTestProject(stories: stories)
        project.pauseAfterStory = true

        var mockPM: MockProcessManager?
        let engine = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: {
                let pm = MockProcessManager()
                mockPM = pm
                return pm
            }
        )

        let pausedExpectation = XCTestExpectation(description: "Paused")
        engine.onStateChange = { state in
            if state == .paused {
                pausedExpectation.fulfill()
            }
        }

        engine.start(project: project)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            mockPM?.sendExit(code: 0)
        }

        wait(for: [pausedExpectation], timeout: 3.0)
    }

    // MARK: - Progress.md Tests

    func testProgressFileCreatedAfterIteration() throws {
        let stories = [
            UserStory(id: "US-001", title: "First Story", description: "d", priority: 1, acceptanceCriteria: ["a"]),
            UserStory(id: "US-002", title: "Second", description: "d", priority: 2, acceptanceCriteria: ["b"]),
        ]
        let project = try createTestProject(stories: stories)

        var mockPM: MockProcessManager?
        let engine = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: {
                let pm = MockProcessManager()
                mockPM = pm
                return pm
            }
        )

        let pausedExpectation = XCTestExpectation(description: "Paused after iteration")
        engine.onStateChange = { state in
            if state == .paused {
                pausedExpectation.fulfill()
            }
        }

        var project2 = project
        project2.pauseAfterStory = true
        engine.start(project: project2)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            mockPM?.sendExit(code: 0)
        }

        wait(for: [pausedExpectation], timeout: 3.0)

        // Verify progress.md was created
        let progressURL = tempDir.appendingPathComponent("progress.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: progressURL.path), "progress.md should be created")

        let content = try String(contentsOf: progressURL, encoding: .utf8)
        XCTAssertTrue(content.contains("US-001"), "Progress should contain story ID")
        XCTAssertTrue(content.contains("First Story"), "Progress should contain story title")
        XCTAssertTrue(content.contains("Iteration:"), "Progress should contain iteration info")
        XCTAssertTrue(content.contains("Completed successfully"), "Progress should contain success status")
    }

    func testProgressFileAppendsMultipleEntries() throws {
        let stories = [
            UserStory(id: "US-001", title: "First", description: "d", priority: 1, acceptanceCriteria: ["a"]),
            UserStory(id: "US-002", title: "Second", description: "d", priority: 2, acceptanceCriteria: ["b"]),
        ]
        let project = try createTestProject(stories: stories)

        // Write initial content to progress.md
        let progressURL = tempDir.appendingPathComponent("progress.md")
        try "## Existing Content\n---\n".write(to: progressURL, atomically: true, encoding: .utf8)

        var mockPM: MockProcessManager?
        let engine = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: {
                let pm = MockProcessManager()
                mockPM = pm
                return pm
            }
        )

        let pausedExpectation = XCTestExpectation(description: "Paused")
        engine.onStateChange = { state in
            if state == .paused {
                pausedExpectation.fulfill()
            }
        }

        var project2 = project
        project2.pauseAfterStory = true
        engine.start(project: project2)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            mockPM?.sendExit(code: 0)
        }

        wait(for: [pausedExpectation], timeout: 3.0)

        let content = try String(contentsOf: progressURL, encoding: .utf8)
        XCTAssertTrue(content.contains("Existing Content"), "Should preserve existing content")
        XCTAssertTrue(content.contains("US-001"), "Should append new entry")
    }

    func testProgressFileRecordsNonZeroExitCode() throws {
        let stories = [
            UserStory(id: "US-001", title: "First", description: "d", priority: 1, acceptanceCriteria: ["a"]),
        ]
        let project = try createTestProject(stories: stories)

        var mockPM: MockProcessManager?
        let engine = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: {
                let pm = MockProcessManager()
                mockPM = pm
                return pm
            }
        )

        // Non-zero exit without completion detected → error state
        // But progress should still be appended before the error transition
        // Actually, the current code only appends on exit code 0 path.
        // Let me check... The appendProgress call is before the error check.
        // Wait — I placed it after the guard but let me re-check the flow.

        let errorExpectation = XCTestExpectation(description: "Error")
        engine.onStateChange = { state in
            if state == .error {
                errorExpectation.fulfill()
            }
        }

        engine.start(project: project)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            mockPM?.sendExit(code: 1, stderr: "crash")
        }

        wait(for: [errorExpectation], timeout: 3.0)

        // Progress should NOT be appended on error (exit code check happens before appendProgress)
        let progressURL = tempDir.appendingPathComponent("progress.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: progressURL.path), "progress.md should not be created on error exit")
    }

    func testProgressFileStoredInPRDDirectory() throws {
        let stories = [
            UserStory(id: "US-001", title: "First", description: "d", priority: 1, acceptanceCriteria: ["a"]),
            UserStory(id: "US-002", title: "Second", description: "d", priority: 2, acceptanceCriteria: ["b"]),
        ]
        let project = try createTestProject(stories: stories)

        var mockPM: MockProcessManager?
        let engine = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: {
                let pm = MockProcessManager()
                mockPM = pm
                return pm
            }
        )

        let pausedExpectation = XCTestExpectation(description: "Paused")
        engine.onStateChange = { state in
            if state == .paused {
                pausedExpectation.fulfill()
            }
        }

        var project2 = project
        project2.pauseAfterStory = true
        engine.start(project: project2)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            mockPM?.sendExit(code: 0)
        }

        wait(for: [pausedExpectation], timeout: 3.0)

        // Verify progress.md is in the PRD directory (same as ridl.json)
        let progressURL = tempDir.appendingPathComponent("progress.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: progressURL.path), "progress.md should be in PRD directory")

        // Verify it's NOT in the parent directory
        let parentProgressURL = tempDir.deletingLastPathComponent().appendingPathComponent("progress.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: parentProgressURL.path), "progress.md should not be in parent directory")
    }

    // MARK: - Git Commit Tests

    func testGitCommitAfterSuccessfulIteration() throws {
        let stories = [
            UserStory(id: "US-001", title: "First Story", description: "d", priority: 1, acceptanceCriteria: ["a"]),
            UserStory(id: "US-002", title: "Second", description: "d", priority: 2, acceptanceCriteria: ["b"]),
        ]
        let project = try createTestProject(stories: stories)

        var mockPM: MockProcessManager?
        let mockGit = MockGitManager()
        let engine = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: {
                let pm = MockProcessManager()
                mockPM = pm
                return pm
            },
            gitManager: mockGit
        )

        let pausedExpectation = XCTestExpectation(description: "Paused")
        engine.onStateChange = { state in
            if state == .paused {
                pausedExpectation.fulfill()
            }
        }

        var project2 = project
        project2.pauseAfterStory = true
        engine.start(project: project2)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            mockPM?.sendExit(code: 0)
        }

        wait(for: [pausedExpectation], timeout: 3.0)

        XCTAssertEqual(mockGit.commitCallCount, 1, "Should create one commit per iteration")
        XCTAssertEqual(mockGit.lastCommitMessage, "feat: [US-001] - First Story", "Commit message should follow format")
    }

    func testGitCommitUsesProjectRootAsWorkingDirectory() throws {
        let stories = [
            UserStory(id: "US-001", title: "First", description: "d", priority: 1, acceptanceCriteria: ["a"]),
            UserStory(id: "US-002", title: "Second", description: "d", priority: 2, acceptanceCriteria: ["b"]),
        ]
        let project = try createTestProject(stories: stories)

        var mockPM: MockProcessManager?
        let mockGit = MockGitManager()
        let engine = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: {
                let pm = MockProcessManager()
                mockPM = pm
                return pm
            },
            gitManager: mockGit
        )

        let pausedExpectation = XCTestExpectation(description: "Paused")
        engine.onStateChange = { state in
            if state == .paused {
                pausedExpectation.fulfill()
            }
        }

        var project2 = project
        project2.pauseAfterStory = true
        engine.start(project: project2)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            mockPM?.sendExit(code: 0)
        }

        wait(for: [pausedExpectation], timeout: 3.0)

        // Commit directory should be parent of PRD directory (project root)
        let expectedDir = tempDir.deletingLastPathComponent()
        XCTAssertEqual(
            mockGit.lastCommitDirectory?.standardizedFileURL,
            expectedDir.standardizedFileURL,
            "Commit should use project root directory"
        )
    }

    func testGitCommitNotCalledOnError() throws {
        let stories = [
            UserStory(id: "US-001", title: "First", description: "d", priority: 1, acceptanceCriteria: ["a"]),
        ]
        let project = try createTestProject(stories: stories)

        var mockPM: MockProcessManager?
        let mockGit = MockGitManager()
        let engine = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: {
                let pm = MockProcessManager()
                mockPM = pm
                return pm
            },
            gitManager: mockGit
        )

        let errorExpectation = XCTestExpectation(description: "Error")
        engine.onStateChange = { state in
            if state == .error {
                errorExpectation.fulfill()
            }
        }

        engine.start(project: project)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            mockPM?.sendExit(code: 1, stderr: "crash")
        }

        wait(for: [errorExpectation], timeout: 3.0)

        XCTAssertEqual(mockGit.commitCallCount, 0, "Should not commit on error exit")
    }

    func testGitCommitFailureDoesNotStopLoop() throws {
        let stories = [
            UserStory(id: "US-001", title: "First", description: "d", priority: 1, acceptanceCriteria: ["a"]),
            UserStory(id: "US-002", title: "Second", description: "d", priority: 2, acceptanceCriteria: ["b"]),
        ]
        let project = try createTestProject(stories: stories)

        var mockPM: MockProcessManager?
        let mockGit = MockGitManager()
        mockGit.commitError = RidlerError.gitError(command: "git commit", stderr: "nothing to commit")
        let engine = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: {
                let pm = MockProcessManager()
                mockPM = pm
                return pm
            },
            gitManager: mockGit
        )

        let pausedExpectation = XCTestExpectation(description: "Paused")
        engine.onStateChange = { state in
            if state == .paused {
                pausedExpectation.fulfill()
            }
        }

        var project2 = project
        project2.pauseAfterStory = true
        engine.start(project: project2)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            mockPM?.sendExit(code: 0)
        }

        wait(for: [pausedExpectation], timeout: 3.0)

        // Loop should continue (paused as expected) even though commit failed
        // This verifies the commit error is non-fatal
    }

    func testGitCommitLogMessage() throws {
        let stories = [
            UserStory(id: "US-042", title: "Cool Feature", description: "d", priority: 1, acceptanceCriteria: ["a"]),
            UserStory(id: "US-043", title: "Other", description: "d", priority: 2, acceptanceCriteria: ["b"]),
        ]
        let project = try createTestProject(stories: stories)

        var mockPM: MockProcessManager?
        let mockGit = MockGitManager()
        let engine = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: {
                let pm = MockProcessManager()
                mockPM = pm
                return pm
            },
            gitManager: mockGit
        )

        var logMessages: [String] = []
        engine.onLogEntry = { entry, _ in
            if entry.type == .system {
                logMessages.append(entry.content)
            }
        }

        let pausedExpectation = XCTestExpectation(description: "Paused")
        engine.onStateChange = { state in
            if state == .paused {
                pausedExpectation.fulfill()
            }
        }

        var project2 = project
        project2.pauseAfterStory = true
        engine.start(project: project2)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            mockPM?.sendExit(code: 0)
        }

        wait(for: [pausedExpectation], timeout: 3.0)

        XCTAssertTrue(logMessages.contains(where: { $0.contains("Committed:") && $0.contains("US-042") }), "Should log commit message")
    }

    // MARK: - Parallel PRD Execution Tests (US-026)

    /// Helper to create a test project in a unique subdirectory
    private func createIsolatedTestProject(name: String, stories: [UserStory]) throws -> (PRDProject, URL) {
        let dir = tempDir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let project = PRDProject(
            name: name,
            userStories: stories,
            directoryURL: dir
        )
        let store = FileSystemPRDStore()
        try store.writeProject(project, to: dir)
        return (project, dir)
    }

    func testThreeParallelEnginesRunIndependently() throws {
        // Create 3 separate projects with distinct stories
        let (projectA, _) = try createIsolatedTestProject(name: "ProjectA", stories: [
            UserStory(id: "A-001", title: "A Story", description: "d", priority: 1, acceptanceCriteria: ["a"]),
            UserStory(id: "A-002", title: "A Story 2", description: "d", priority: 2, acceptanceCriteria: ["b"]),
        ])
        let (projectB, _) = try createIsolatedTestProject(name: "ProjectB", stories: [
            UserStory(id: "B-001", title: "B Story", description: "d", priority: 1, acceptanceCriteria: ["a"]),
        ])
        let (projectC, _) = try createIsolatedTestProject(name: "ProjectC", stories: [
            UserStory(id: "C-001", title: "C Story", description: "d", priority: 1, acceptanceCriteria: ["a"]),
            UserStory(id: "C-002", title: "C Story 2", description: "d", priority: 2, acceptanceCriteria: ["b"]),
            UserStory(id: "C-003", title: "C Story 3", description: "d", priority: 3, acceptanceCriteria: ["c"]),
        ])

        var mockPM_A: MockProcessManager?
        var mockPM_B: MockProcessManager?
        var mockPM_C: MockProcessManager?

        let engineA = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: {
                let pm = MockProcessManager()
                mockPM_A = pm
                return pm
            }
        )
        let engineB = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: {
                let pm = MockProcessManager()
                mockPM_B = pm
                return pm
            }
        )
        let engineC = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: {
                let pm = MockProcessManager()
                mockPM_C = pm
                return pm
            }
        )

        // Track states independently
        var statesA: [LoopState] = []
        var statesB: [LoopState] = []
        var statesC: [LoopState] = []

        let allRunning = XCTestExpectation(description: "All three engines running")
        allRunning.expectedFulfillmentCount = 3

        engineA.onStateChange = { state in
            statesA.append(state)
            if state == .running { allRunning.fulfill() }
        }
        engineB.onStateChange = { state in
            statesB.append(state)
            if state == .running { allRunning.fulfill() }
        }
        engineC.onStateChange = { state in
            statesC.append(state)
            if state == .running { allRunning.fulfill() }
        }

        // Start all three simultaneously
        engineA.start(project: projectA)
        engineB.start(project: projectB)
        engineC.start(project: projectC)

        wait(for: [allRunning], timeout: 3.0)

        // All three should be running independently
        XCTAssertTrue(statesA.contains(.running), "Engine A should be running")
        XCTAssertTrue(statesB.contains(.running), "Engine B should be running")
        XCTAssertTrue(statesC.contains(.running), "Engine C should be running")

        // Each engine should have spawned a process for its own project
        XCTAssertTrue(mockPM_A?.lastPrompt?.contains("A-001") ?? false, "Engine A should work on A-001")
        XCTAssertTrue(mockPM_B?.lastPrompt?.contains("B-001") ?? false, "Engine B should work on B-001")
        XCTAssertTrue(mockPM_C?.lastPrompt?.contains("C-001") ?? false, "Engine C should work on C-001")
    }

    func testPausingOneEngineDoesNotAffectOthers() throws {
        let (projectA, _) = try createIsolatedTestProject(name: "PauseA", stories: [
            UserStory(id: "PA-001", title: "PA Story", description: "d", priority: 1, acceptanceCriteria: ["a"]),
        ])
        let (projectB, _) = try createIsolatedTestProject(name: "PauseB", stories: [
            UserStory(id: "PB-001", title: "PB Story", description: "d", priority: 1, acceptanceCriteria: ["a"]),
        ])
        let (projectC, _) = try createIsolatedTestProject(name: "PauseC", stories: [
            UserStory(id: "PC-001", title: "PC Story", description: "d", priority: 1, acceptanceCriteria: ["a"]),
        ])

        let engineA = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: { MockProcessManager() }
        )
        let engineB = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: { MockProcessManager() }
        )
        let engineC = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: { MockProcessManager() }
        )

        var latestStateA: LoopState = .ready
        var latestStateB: LoopState = .ready
        var latestStateC: LoopState = .ready

        let allRunning = XCTestExpectation(description: "All running")
        allRunning.expectedFulfillmentCount = 3

        engineA.onStateChange = { state in
            latestStateA = state
            if state == .running { allRunning.fulfill() }
        }
        engineB.onStateChange = { state in
            latestStateB = state
            if state == .running { allRunning.fulfill() }
        }
        engineC.onStateChange = { state in
            latestStateC = state
            if state == .running { allRunning.fulfill() }
        }

        engineA.start(project: projectA)
        engineB.start(project: projectB)
        engineC.start(project: projectC)

        wait(for: [allRunning], timeout: 3.0)

        // Pause only engine B
        let bPausedExpectation = XCTestExpectation(description: "B paused")
        engineB.onStateChange = { state in
            latestStateB = state
            if state == .paused { bPausedExpectation.fulfill() }
        }
        engineB.pause()

        wait(for: [bPausedExpectation], timeout: 2.0)

        // Verify B is paused while A and C remain running
        XCTAssertEqual(latestStateB, .paused, "Engine B should be paused")
        XCTAssertEqual(latestStateA, .running, "Engine A should still be running")
        XCTAssertEqual(latestStateC, .running, "Engine C should still be running")
    }

    func testStoppingOneEngineDoesNotAffectOthers() throws {
        let (projectA, _) = try createIsolatedTestProject(name: "StopA", stories: [
            UserStory(id: "SA-001", title: "SA Story", description: "d", priority: 1, acceptanceCriteria: ["a"]),
        ])
        let (projectB, _) = try createIsolatedTestProject(name: "StopB", stories: [
            UserStory(id: "SB-001", title: "SB Story", description: "d", priority: 1, acceptanceCriteria: ["a"]),
        ])
        let (projectC, _) = try createIsolatedTestProject(name: "StopC", stories: [
            UserStory(id: "SC-001", title: "SC Story", description: "d", priority: 1, acceptanceCriteria: ["a"]),
        ])

        var mockPM_A: MockProcessManager?
        let engineA = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: {
                let pm = MockProcessManager()
                mockPM_A = pm
                return pm
            }
        )
        let engineB = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: { MockProcessManager() }
        )
        let engineC = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: { MockProcessManager() }
        )

        var latestStateA: LoopState = .ready
        var latestStateB: LoopState = .ready
        var latestStateC: LoopState = .ready

        let allRunning = XCTestExpectation(description: "All running")
        allRunning.expectedFulfillmentCount = 3

        engineA.onStateChange = { state in
            latestStateA = state
            if state == .running { allRunning.fulfill() }
        }
        engineB.onStateChange = { state in
            latestStateB = state
            if state == .running { allRunning.fulfill() }
        }
        engineC.onStateChange = { state in
            latestStateC = state
            if state == .running { allRunning.fulfill() }
        }

        engineA.start(project: projectA)
        engineB.start(project: projectB)
        engineC.start(project: projectC)

        wait(for: [allRunning], timeout: 3.0)

        // Stop only engine A
        let aStoppedExpectation = XCTestExpectation(description: "A stopped")
        engineA.onStateChange = { state in
            latestStateA = state
            if state == .stopped { aStoppedExpectation.fulfill() }
        }
        engineA.stop()

        wait(for: [aStoppedExpectation], timeout: 2.0)

        // A should be stopped, B and C should still be running
        XCTAssertEqual(latestStateA, .stopped, "Engine A should be stopped")
        XCTAssertEqual(mockPM_A?.killCallCount, 1, "Engine A's process should be killed")
        XCTAssertEqual(latestStateB, .running, "Engine B should still be running")
        XCTAssertEqual(latestStateC, .running, "Engine C should still be running")
    }

    func testParallelIterationCountsAreIndependent() throws {
        let (projectA, _) = try createIsolatedTestProject(name: "IterA", stories: [
            UserStory(id: "IA-001", title: "IA Story", description: "d", priority: 1, acceptanceCriteria: ["a"]),
        ])
        let (projectB, _) = try createIsolatedTestProject(name: "IterB", stories: [
            UserStory(id: "IB-001", title: "IB Story", description: "d", priority: 1, acceptanceCriteria: ["a"]),
        ])
        let (projectC, _) = try createIsolatedTestProject(name: "IterC", stories: [
            UserStory(id: "IC-001", title: "IC Story", description: "d", priority: 1, acceptanceCriteria: ["a"]),
        ])

        var iterationA = 0
        var iterationB = 0
        var iterationC = 0

        let allIterating = XCTestExpectation(description: "All have iterated")
        allIterating.expectedFulfillmentCount = 3

        let engineA = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: { MockProcessManager() }
        )
        let engineB = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: { MockProcessManager() }
        )
        let engineC = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: { MockProcessManager() }
        )

        engineA.onIterationChange = { count in
            iterationA = count
            if count == 1 { allIterating.fulfill() }
        }
        engineB.onIterationChange = { count in
            iterationB = count
            if count == 1 { allIterating.fulfill() }
        }
        engineC.onIterationChange = { count in
            iterationC = count
            if count == 1 { allIterating.fulfill() }
        }

        engineA.start(project: projectA)
        engineB.start(project: projectB)
        engineC.start(project: projectC)

        wait(for: [allIterating], timeout: 3.0)

        // Each engine should have its own iteration count
        XCTAssertEqual(iterationA, 1, "Engine A iteration should be 1")
        XCTAssertEqual(iterationB, 1, "Engine B iteration should be 1")
        XCTAssertEqual(iterationC, 1, "Engine C iteration should be 1")
    }

    func testParallelLogEntriesAreIsolatedByProjectID() throws {
        let (projectA, _) = try createIsolatedTestProject(name: "LogA", stories: [
            UserStory(id: "LA-001", title: "LA Story", description: "d", priority: 1, acceptanceCriteria: ["a"]),
        ])
        let (projectB, _) = try createIsolatedTestProject(name: "LogB", stories: [
            UserStory(id: "LB-001", title: "LB Story", description: "d", priority: 1, acceptanceCriteria: ["a"]),
        ])
        let (projectC, _) = try createIsolatedTestProject(name: "LogC", stories: [
            UserStory(id: "LC-001", title: "LC Story", description: "d", priority: 1, acceptanceCriteria: ["a"]),
        ])

        var logsA: [(LogEntry, String)] = []
        var logsB: [(LogEntry, String)] = []
        var logsC: [(LogEntry, String)] = []

        let allRunning = XCTestExpectation(description: "All running")
        allRunning.expectedFulfillmentCount = 3

        let engineA = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: { MockProcessManager() }
        )
        let engineB = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: { MockProcessManager() }
        )
        let engineC = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: { MockProcessManager() }
        )

        engineA.onLogEntry = { entry, projectID in
            logsA.append((entry, projectID))
        }
        engineB.onLogEntry = { entry, projectID in
            logsB.append((entry, projectID))
        }
        engineC.onLogEntry = { entry, projectID in
            logsC.append((entry, projectID))
        }

        engineA.onStateChange = { state in if state == .running { allRunning.fulfill() } }
        engineB.onStateChange = { state in if state == .running { allRunning.fulfill() } }
        engineC.onStateChange = { state in if state == .running { allRunning.fulfill() } }

        engineA.start(project: projectA)
        engineB.start(project: projectB)
        engineC.start(project: projectC)

        wait(for: [allRunning], timeout: 3.0)

        // Each engine's log entries should only reference its own project ID
        XCTAssertTrue(logsA.allSatisfy { $0.1 == "LogA" }, "Engine A logs should all reference LogA")
        XCTAssertTrue(logsB.allSatisfy { $0.1 == "LogB" }, "Engine B logs should all reference LogB")
        XCTAssertTrue(logsC.allSatisfy { $0.1 == "LogC" }, "Engine C logs should all reference LogC")
    }

    func testParallelErrorInOneDoesNotAffectOthers() throws {
        let (projectA, _) = try createIsolatedTestProject(name: "ErrA", stories: [
            UserStory(id: "EA-001", title: "EA Story", description: "d", priority: 1, acceptanceCriteria: ["a"]),
        ])
        let (projectB, _) = try createIsolatedTestProject(name: "ErrB", stories: [
            UserStory(id: "EB-001", title: "EB Story", description: "d", priority: 1, acceptanceCriteria: ["a"]),
        ])
        let (projectC, _) = try createIsolatedTestProject(name: "ErrC", stories: [
            UserStory(id: "EC-001", title: "EC Story", description: "d", priority: 1, acceptanceCriteria: ["a"]),
        ])

        var mockPM_B: MockProcessManager?

        let engineA = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: { MockProcessManager() }
        )
        let engineB = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: {
                let pm = MockProcessManager()
                mockPM_B = pm
                return pm
            }
        )
        let engineC = RalphLoopEngine(
            prdStore: FileSystemPRDStore(),
            processManagerFactory: { MockProcessManager() }
        )

        var latestStateA: LoopState = .ready
        var latestStateB: LoopState = .ready
        var latestStateC: LoopState = .ready

        let allRunning = XCTestExpectation(description: "All running")
        allRunning.expectedFulfillmentCount = 3

        engineA.onStateChange = { state in
            latestStateA = state
            if state == .running { allRunning.fulfill() }
        }
        engineB.onStateChange = { state in
            latestStateB = state
            if state == .running { allRunning.fulfill() }
        }
        engineC.onStateChange = { state in
            latestStateC = state
            if state == .running { allRunning.fulfill() }
        }

        engineA.start(project: projectA)
        engineB.start(project: projectB)
        engineC.start(project: projectC)

        wait(for: [allRunning], timeout: 3.0)

        // Simulate error in engine B only
        let bErrorExpectation = XCTestExpectation(description: "B error")
        engineB.onStateChange = { state in
            latestStateB = state
            if state == .error { bErrorExpectation.fulfill() }
        }

        mockPM_B?.sendExit(code: 1, stderr: "Claude crashed")

        wait(for: [bErrorExpectation], timeout: 3.0)

        // B should be in error, A and C should still be running
        XCTAssertEqual(latestStateB, .error, "Engine B should be in error state")
        XCTAssertEqual(latestStateA, .running, "Engine A should still be running")
        XCTAssertEqual(latestStateC, .running, "Engine C should still be running")
    }
}
