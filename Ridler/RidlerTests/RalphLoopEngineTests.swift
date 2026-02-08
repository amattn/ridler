import XCTest
@testable import Ridler

final class RalphLoopEngineTests: XCTestCase {

    // MARK: - Helpers

    private var tempDir: String!

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory() + "RalphLoopEngineTests_\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tempDir)
        super.tearDown()
    }

    private func createPRD(stories: [UserStory]) -> String {
        let prd = PRDProject(
            project: "TestProject",
            description: "Test project",
            userStories: stories
        )
        let path = (tempDir as NSString).appendingPathComponent("prd.json")
        try! PRDFileManager.save(prd, to: path)
        return path
    }

    private func makeStory(
        id: String,
        title: String = "Test Story",
        priority: Int = 1,
        passes: Bool = false,
        inProgress: Bool = false
    ) -> UserStory {
        UserStory(
            id: id,
            title: title,
            description: "A test story",
            acceptanceCriteria: ["Criterion 1", "Criterion 2"],
            priority: priority,
            passes: passes,
            inProgress: inProgress
        )
    }

    // MARK: - Story Selection Tests

    func testSelectNextStoryPicksLowestPriorityNotPassed() {
        let stories = [
            makeStory(id: "US-001", priority: 1, passes: true),
            makeStory(id: "US-002", priority: 2, passes: false),
            makeStory(id: "US-003", priority: 3, passes: false),
        ]
        let prdPath = createPRD(stories: stories)
        let engine = RalphLoopEngine(
            prdFilePath: prdPath,
            workingDirectory: tempDir,
            maxIterations: 10
        )

        let prd = try! PRDFileManager.load(from: prdPath)
        let next = engine.selectNextStory(from: prd)
        XCTAssertEqual(next?.id, "US-002")
    }

    func testSelectNextStoryReturnsNilWhenAllPass() {
        let stories = [
            makeStory(id: "US-001", priority: 1, passes: true),
            makeStory(id: "US-002", priority: 2, passes: true),
        ]
        let prdPath = createPRD(stories: stories)
        let engine = RalphLoopEngine(
            prdFilePath: prdPath,
            workingDirectory: tempDir,
            maxIterations: 10
        )

        let prd = try! PRDFileManager.load(from: prdPath)
        let next = engine.selectNextStory(from: prd)
        XCTAssertNil(next)
    }

    func testSelectNextStorySkipsPassedStories() {
        let stories = [
            makeStory(id: "US-001", priority: 1, passes: true),
            makeStory(id: "US-002", priority: 2, passes: true),
            makeStory(id: "US-003", priority: 3, passes: false),
        ]
        let prdPath = createPRD(stories: stories)
        let engine = RalphLoopEngine(
            prdFilePath: prdPath,
            workingDirectory: tempDir,
            maxIterations: 10
        )

        let prd = try! PRDFileManager.load(from: prdPath)
        let next = engine.selectNextStory(from: prd)
        XCTAssertEqual(next?.id, "US-003")
    }

    // MARK: - Prompt Building Tests

    func testBuildPromptContainsStoryDetails() {
        let story = makeStory(id: "US-042", title: "Add Login")
        let prd = PRDProject(project: "TestProject", description: "Test", userStories: [story])
        let prdPath = createPRD(stories: [story])
        let engine = RalphLoopEngine(
            prdFilePath: prdPath,
            workingDirectory: tempDir,
            maxIterations: 10
        )

        let prompt = engine.buildPrompt(for: story, prd: prd)

        XCTAssertTrue(prompt.contains("US-042"))
        XCTAssertTrue(prompt.contains("Add Login"))
        XCTAssertTrue(prompt.contains("A test story"))
        XCTAssertTrue(prompt.contains("Criterion 1"))
        XCTAssertTrue(prompt.contains("Criterion 2"))
    }

    func testBuildPromptContainsAgentInstructions() {
        let story = makeStory(id: "US-001")
        let prd = PRDProject(project: "TestProject", description: "Test", userStories: [story])
        let prdPath = createPRD(stories: [story])
        let engine = RalphLoopEngine(
            prdFilePath: prdPath,
            workingDirectory: tempDir,
            maxIterations: 10
        )

        let prompt = engine.buildPrompt(for: story, prd: prd)

        XCTAssertTrue(prompt.contains("Chief Agent Instructions"))
        XCTAssertTrue(prompt.contains("Quality Requirements"))
        XCTAssertTrue(prompt.contains("<ridler-complete/>"))
    }

    func testBuildPromptIncludesProgressWhenPresent() {
        let story = makeStory(id: "US-001")
        let prd = PRDProject(project: "TestProject", description: "Test", userStories: [story])
        let prdPath = createPRD(stories: [story])

        // Write a progress.md file
        let progressPath = (tempDir as NSString).appendingPathComponent("progress.md")
        try! "## Previous work done here\n- Fixed bug X".write(toFile: progressPath, atomically: true, encoding: .utf8)

        let engine = RalphLoopEngine(
            prdFilePath: prdPath,
            workingDirectory: tempDir,
            maxIterations: 10
        )

        let prompt = engine.buildPrompt(for: story, prd: prd)

        XCTAssertTrue(prompt.contains("Previous Progress"))
        XCTAssertTrue(prompt.contains("Previous work done here"))
    }

    func testBuildPromptOmitsProgressWhenNotPresent() {
        let story = makeStory(id: "US-001")
        let prd = PRDProject(project: "TestProject", description: "Test", userStories: [story])
        let prdPath = createPRD(stories: [story])
        let engine = RalphLoopEngine(
            prdFilePath: prdPath,
            workingDirectory: tempDir,
            maxIterations: 10
        )

        let prompt = engine.buildPrompt(for: story, prd: prd)

        XCTAssertFalse(prompt.contains("Previous Progress"))
    }

    // MARK: - State Machine Integration Tests

    func testEngineStartsInReadyState() {
        let prdPath = createPRD(stories: [makeStory(id: "US-001")])
        let engine = RalphLoopEngine(
            prdFilePath: prdPath,
            workingDirectory: tempDir,
            maxIterations: 10
        )

        XCTAssertEqual(engine.stateMachine.state, .ready)
    }

    func testEngineTransitionsToRunningOnStart() async {
        let mock = MockProcessSpawner()
        mock.exitCode = 0
        mock.outputLines = ["{\"type\":\"system\",\"message\":\"init\"}"]

        let stories = [makeStory(id: "US-001", priority: 1, passes: false)]
        let prdPath = createPRD(stories: stories)
        let processManager = ClaudeProcessManager(spawner: mock)
        let engine = RalphLoopEngine(
            prdFilePath: prdPath,
            workingDirectory: tempDir,
            maxIterations: 1,
            processManager: processManager
        )

        await engine.start()

        // After start completes with max iterations = 1, should be stopped (max iterations reached)
        // or complete if the single story was marked as passed
        let state = engine.stateMachine.state
        XCTAssertTrue(state == .stopped || state == .complete || state == .error,
                      "Expected stopped, complete, or error but got \(state)")
    }

    func testEngineCompletesWhenAllStoriesPass() async {
        let mock = MockProcessSpawner()
        mock.exitCode = 0
        mock.outputLines = ["{\"type\":\"system\",\"message\":\"done\"}"]

        let stories = [makeStory(id: "US-001", priority: 1, passes: false)]
        let prdPath = createPRD(stories: stories)
        let processManager = ClaudeProcessManager(spawner: mock)
        let engine = RalphLoopEngine(
            prdFilePath: prdPath,
            workingDirectory: tempDir,
            maxIterations: 10,
            processManager: processManager
        )

        await engine.start()

        // Story should be marked as passed
        let updatedPrd = try! PRDFileManager.load(from: prdPath)
        XCTAssertTrue(updatedPrd.userStories[0].passes)
        XCTAssertFalse(updatedPrd.userStories[0].inProgress)
        XCTAssertEqual(engine.stateMachine.state, .complete)
    }

    func testEngineStopsAtMaxIterations() async {
        let mock = MockProcessSpawner()
        mock.exitCode = 0
        mock.outputLines = ["{\"type\":\"system\",\"message\":\"done\"}"]

        // Two stories but only 1 iteration allowed
        let stories = [
            makeStory(id: "US-001", priority: 1, passes: false),
            makeStory(id: "US-002", priority: 2, passes: false),
        ]
        let prdPath = createPRD(stories: stories)
        let processManager = ClaudeProcessManager(spawner: mock)
        let engine = RalphLoopEngine(
            prdFilePath: prdPath,
            workingDirectory: tempDir,
            maxIterations: 1,
            processManager: processManager
        )

        await engine.start()

        // Should have completed one story, then stopped at max
        XCTAssertEqual(engine.currentIteration, 1)
        XCTAssertEqual(engine.stateMachine.state, .stopped)
    }

    func testEngineTransitionsToErrorOnClaudeFailure() async {
        let mock = MockProcessSpawner()
        mock.exitCode = 1
        mock.outputLines = []

        let stories = [makeStory(id: "US-001", priority: 1, passes: false)]
        let prdPath = createPRD(stories: stories)
        let processManager = ClaudeProcessManager(spawner: mock)
        let engine = RalphLoopEngine(
            prdFilePath: prdPath,
            workingDirectory: tempDir,
            maxIterations: 10,
            processManager: processManager
        )

        await engine.start()

        XCTAssertEqual(engine.stateMachine.state, .error)
    }

    func testEnginePausesAfterCurrentIteration() async {
        let mock = MockProcessSpawner()
        mock.exitCode = 0
        mock.outputLines = ["{\"type\":\"system\",\"message\":\"done\"}"]
        mock.lineDelay = 0.05

        let stories = [
            makeStory(id: "US-001", priority: 1, passes: false),
            makeStory(id: "US-002", priority: 2, passes: false),
        ]
        let prdPath = createPRD(stories: stories)
        let processManager = ClaudeProcessManager(spawner: mock)
        let engine = RalphLoopEngine(
            prdFilePath: prdPath,
            workingDirectory: tempDir,
            maxIterations: 10,
            processManager: processManager
        )

        let task = Task {
            await engine.start()
        }

        // Give it time to start the first iteration
        try? await Task.sleep(nanoseconds: 100_000_000)
        engine.pause()

        await task.value

        // Should have completed at least one iteration and then paused
        XCTAssertTrue(engine.currentIteration >= 1)
        let state = engine.stateMachine.state
        // May be paused or complete (if it finished the only incomplete story before pause took effect)
        XCTAssertTrue(state == .paused || state == .complete,
                      "Expected paused or complete but got \(state)")
    }

    func testEngineStopsImmediately() async {
        let mock = MockProcessSpawner()
        mock.exitCode = 0
        mock.outputLines = ["{\"type\":\"system\",\"message\":\"line1\"}", "{\"type\":\"system\",\"message\":\"line2\"}"]
        mock.lineDelay = 0.5

        let stories = [makeStory(id: "US-001", priority: 1, passes: false)]
        let prdPath = createPRD(stories: stories)
        let processManager = ClaudeProcessManager(spawner: mock)
        let engine = RalphLoopEngine(
            prdFilePath: prdPath,
            workingDirectory: tempDir,
            maxIterations: 10,
            processManager: processManager
        )

        let task = Task {
            await engine.start()
        }

        // Give it time to start
        try? await Task.sleep(nanoseconds: 100_000_000)
        engine.stop()

        await task.value

        XCTAssertEqual(engine.stateMachine.state, .stopped)
        XCTAssertTrue(mock.terminated)
    }

    // MARK: - PRD File Updates

    func testEngineStoresLastPrompt() async {
        let mock = MockProcessSpawner()
        mock.exitCode = 0
        mock.outputLines = ["{\"type\":\"system\",\"message\":\"done\"}"]

        let stories = [makeStory(id: "US-001", priority: 1, passes: false)]
        let prdPath = createPRD(stories: stories)
        let processManager = ClaudeProcessManager(spawner: mock)
        let engine = RalphLoopEngine(
            prdFilePath: prdPath,
            workingDirectory: tempDir,
            maxIterations: 10,
            processManager: processManager
        )

        await engine.start()

        let updatedPrd = try! PRDFileManager.load(from: prdPath)
        XCTAssertNotNil(updatedPrd.userStories[0].lastPrompt)
        XCTAssertTrue(updatedPrd.userStories[0].lastPrompt!.contains("US-001"))
    }

    func testEngineMarksStoryInProgressDuringExecution() async {
        // Use a spawner with delay so we can check mid-execution
        let mock = MockProcessSpawner()
        mock.exitCode = 0
        mock.outputLines = ["{\"type\":\"system\",\"message\":\"working\"}"]
        mock.lineDelay = 0.2

        let stories = [makeStory(id: "US-001", priority: 1, passes: false)]
        let prdPath = createPRD(stories: stories)
        let processManager = ClaudeProcessManager(spawner: mock)
        let engine = RalphLoopEngine(
            prdFilePath: prdPath,
            workingDirectory: tempDir,
            maxIterations: 10,
            processManager: processManager
        )

        let task = Task {
            await engine.start()
        }

        // Give time for inProgress to be set
        try? await Task.sleep(nanoseconds: 100_000_000)

        let midPrd = try! PRDFileManager.load(from: prdPath)
        XCTAssertTrue(midPrd.userStories[0].inProgress)

        await task.value
    }

    // MARK: - Progress File Tests

    func testEngineAppendsToProgressFile() async {
        let mock = MockProcessSpawner()
        mock.exitCode = 0
        mock.outputLines = ["{\"type\":\"system\",\"message\":\"done\"}"]

        let stories = [makeStory(id: "US-001", title: "Add Feature X", priority: 1, passes: false)]
        let prdPath = createPRD(stories: stories)
        let processManager = ClaudeProcessManager(spawner: mock)
        let engine = RalphLoopEngine(
            prdFilePath: prdPath,
            workingDirectory: tempDir,
            maxIterations: 10,
            processManager: processManager
        )

        await engine.start()

        let progressPath = (tempDir as NSString).appendingPathComponent("progress.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: progressPath))

        let content = try! String(contentsOfFile: progressPath, encoding: .utf8)
        XCTAssertTrue(content.contains("US-001"))
        XCTAssertTrue(content.contains("Add Feature X"))
    }

    // MARK: - Log Entry Tests

    func testEngineProducesSystemLogEntries() async {
        let mock = MockProcessSpawner()
        mock.exitCode = 0
        mock.outputLines = ["{\"type\":\"system\",\"message\":\"init\"}"]

        let stories = [makeStory(id: "US-001", priority: 1, passes: false)]
        let prdPath = createPRD(stories: stories)
        let processManager = ClaudeProcessManager(spawner: mock)
        let engine = RalphLoopEngine(
            prdFilePath: prdPath,
            workingDirectory: tempDir,
            maxIterations: 10,
            processManager: processManager
        )

        await engine.start()

        // Should have system log entries for iteration start and completion
        let systemEntries = engine.logEntries.filter {
            if case .system = $0.type { return true }
            return false
        }
        XCTAssertTrue(systemEntries.count >= 2, "Expected at least 2 system log entries, got \(systemEntries.count)")
    }

    func testEngineTracksCurrentIteration() async {
        let mock = MockProcessSpawner()
        mock.exitCode = 0
        mock.outputLines = ["{\"type\":\"system\",\"message\":\"done\"}"]

        let stories = [makeStory(id: "US-001", priority: 1, passes: false)]
        let prdPath = createPRD(stories: stories)
        let processManager = ClaudeProcessManager(spawner: mock)
        let engine = RalphLoopEngine(
            prdFilePath: prdPath,
            workingDirectory: tempDir,
            maxIterations: 10,
            processManager: processManager
        )

        XCTAssertEqual(engine.currentIteration, 0)

        await engine.start()

        XCTAssertEqual(engine.currentIteration, 1)
    }

    func testEngineTracksCurrentStoryId() async {
        let mock = MockProcessSpawner()
        mock.exitCode = 0
        mock.outputLines = ["{\"type\":\"system\",\"message\":\"done\"}"]

        let stories = [makeStory(id: "US-042", priority: 1, passes: false)]
        let prdPath = createPRD(stories: stories)
        let processManager = ClaudeProcessManager(spawner: mock)
        let engine = RalphLoopEngine(
            prdFilePath: prdPath,
            workingDirectory: tempDir,
            maxIterations: 10,
            processManager: processManager
        )

        XCTAssertNil(engine.currentStoryId)

        await engine.start()

        XCTAssertEqual(engine.currentStoryId, "US-042")
    }

    // MARK: - Ridler Complete Detection

    func testEngineDetectsRidlerComplete() async {
        let mock = MockProcessSpawner()
        mock.exitCode = 0
        mock.outputLines = [
            "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Done! <ridler-complete/>\"}]}}"
        ]

        let stories = [makeStory(id: "US-001", priority: 1, passes: false)]
        let prdPath = createPRD(stories: stories)
        let processManager = ClaudeProcessManager(spawner: mock)
        let engine = RalphLoopEngine(
            prdFilePath: prdPath,
            workingDirectory: tempDir,
            maxIterations: 10,
            processManager: processManager
        )

        await engine.start()

        XCTAssertEqual(engine.stateMachine.state, .complete)
    }

    // MARK: - Resume Tests

    func testEngineCanResumeAfterPause() async {
        let mock = MockProcessSpawner()
        mock.exitCode = 0
        mock.outputLines = ["{\"type\":\"system\",\"message\":\"done\"}"]

        let stories = [
            makeStory(id: "US-001", priority: 1, passes: true),
            makeStory(id: "US-002", priority: 2, passes: false),
        ]
        let prdPath = createPRD(stories: stories)
        let stateMachine = LoopStateMachine()
        let processManager = ClaudeProcessManager(spawner: mock)
        let engine = RalphLoopEngine(
            prdFilePath: prdPath,
            workingDirectory: tempDir,
            maxIterations: 10,
            stateMachine: stateMachine,
            processManager: processManager
        )

        // Simulate paused state
        stateMachine.transition(to: .running)
        stateMachine.transition(to: .paused)

        await engine.resume()

        XCTAssertEqual(engine.stateMachine.state, .complete)
    }

    // MARK: - Error Description Tests

    func testRalphLoopErrorDescriptions() {
        XCTAssertEqual(
            RalphLoopError.noStoriesRemaining.errorDescription,
            "No remaining stories with passes == false"
        )
        XCTAssertEqual(
            RalphLoopError.prdLoadFailed("bad file").errorDescription,
            "Failed to load PRD: bad file"
        )
        XCTAssertEqual(
            RalphLoopError.prdSaveFailed("disk full").errorDescription,
            "Failed to save PRD: disk full"
        )
        XCTAssertEqual(
            RalphLoopError.claudeProcessFailed("crash").errorDescription,
            "Claude process failed: crash"
        )
        XCTAssertEqual(
            RalphLoopError.maxIterationsReached.errorDescription,
            "Maximum iterations reached"
        )
    }

    // MARK: - Invalid PRD Path

    func testEngineTransitionsToErrorOnInvalidPRDPath() async {
        let engine = RalphLoopEngine(
            prdFilePath: "/nonexistent/path/prd.json",
            workingDirectory: tempDir,
            maxIterations: 10
        )

        await engine.start()

        XCTAssertEqual(engine.stateMachine.state, .error)
    }

    // MARK: - Multiple Iterations

    func testEngineRunsMultipleIterations() async {
        let mock = MockProcessSpawner()
        mock.exitCode = 0
        mock.outputLines = ["{\"type\":\"system\",\"message\":\"done\"}"]

        let stories = [
            makeStory(id: "US-001", priority: 1, passes: false),
            makeStory(id: "US-002", priority: 2, passes: false),
        ]
        let prdPath = createPRD(stories: stories)
        let processManager = ClaudeProcessManager(spawner: mock)
        let engine = RalphLoopEngine(
            prdFilePath: prdPath,
            workingDirectory: tempDir,
            maxIterations: 10,
            processManager: processManager
        )

        await engine.start()

        XCTAssertEqual(engine.currentIteration, 2)
        XCTAssertEqual(engine.stateMachine.state, .complete)

        let finalPrd = try! PRDFileManager.load(from: prdPath)
        XCTAssertTrue(finalPrd.userStories[0].passes)
        XCTAssertTrue(finalPrd.userStories[1].passes)
    }
}
