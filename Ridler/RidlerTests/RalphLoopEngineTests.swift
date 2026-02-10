import XCTest
import Combine
@testable import Ridler

// MARK: - Mock ProcessManaging

final class MockProcessManager: ProcessManaging {
    var isRunning: Bool = false
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
}
