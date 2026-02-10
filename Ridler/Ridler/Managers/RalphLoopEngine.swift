import Foundation
import Combine
import AppKit
import os

/// The Ralph loop engine orchestrates the autonomous execution loop:
/// read state → select next story → build prompt → invoke Claude Code → stream output → check completion → repeat.
final class RalphLoopEngine: ObservableObject {
    private static let logger = Logger(subsystem: "com.amattn.Ridler", category: "RalphLoopEngine")

    private let prdStore: PRDStore
    private let processManagerFactory: () -> ProcessManaging

    private var cancellables = Set<AnyCancellable>()
    private var currentProcessManager: ProcessManaging?
    private var currentParser: StreamingJSONParser?

    // Callbacks
    var onStateChange: ((LoopState) -> Void)?
    var onIterationChange: ((Int) -> Void)?
    var onLogEntry: ((LogEntry, String) -> Void)?
    var onProjectUpdated: ((PRDProject) -> Void)?

    private var projectID: String = ""
    private var directoryURL: URL?
    private var pauseAfterStory = false
    private var maxIterations = 0
    private var iterationCount = 0
    private var loopState: LoopState = .ready
    private var completionDetected = false

    init(
        prdStore: PRDStore = FileSystemPRDStore(),
        processManagerFactory: @escaping () -> ProcessManaging = { ClaudeCodeProcessManager() }
    ) {
        self.prdStore = prdStore
        self.processManagerFactory = processManagerFactory
    }

    // MARK: - Public API

    /// Starts the loop for the given project.
    func start(project: PRDProject) {
        guard loopState != .running else { return }

        self.projectID = project.id
        self.directoryURL = project.directoryURL
        self.pauseAfterStory = project.pauseAfterStory
        self.maxIterations = project.maxIterations > 0 ? project.maxIterations : project.defaultMaxIterations
        self.iterationCount = project.iterationCount
        self.loopState = .running
        self.completionDetected = false

        onStateChange?(.running)
        logSystem("Loop started")

        runNextIteration()
    }

    /// Resumes the loop after a pause.
    func resume(project: PRDProject) {
        guard loopState == .paused || loopState == .stopped || loopState == .error else { return }

        self.projectID = project.id
        self.directoryURL = project.directoryURL
        self.pauseAfterStory = project.pauseAfterStory
        self.maxIterations = project.maxIterations > 0 ? project.maxIterations : project.defaultMaxIterations
        self.iterationCount = project.iterationCount
        self.loopState = .running
        self.completionDetected = false

        onStateChange?(.running)
        logSystem("Loop resumed")

        runNextIteration()
    }

    /// Requests a pause after the current iteration completes.
    func pause() {
        guard loopState == .running else { return }
        loopState = .paused
        onStateChange?(.paused)
        logSystem("Pause requested — will pause after current story completes")
    }

    /// Stops the loop immediately, killing any running subprocess.
    func stop() {
        guard loopState == .running || loopState == .paused else { return }
        loopState = .stopped
        currentProcessManager?.kill()
        cancellables.removeAll()
        onStateChange?(.stopped)
        logSystem("Loop stopped")
    }

    /// Updates the pause-after-story setting.
    func updatePauseAfterStory(_ value: Bool) {
        self.pauseAfterStory = value
    }

    /// Updates the max iterations setting.
    func updateMaxIterations(_ value: Int) {
        self.maxIterations = value
    }

    // MARK: - Private

    private func runNextIteration() {
        guard loopState == .running else { return }
        guard let directoryURL else {
            transitionToError("No directory URL set for project")
            return
        }

        // Check iteration limit
        if iterationCount >= maxIterations {
            logSystem("Max iterations reached (\(maxIterations))")
            loopState = .stopped
            onStateChange?(.stopped)
            return
        }

        // Reload project state from disk
        let project: PRDProject
        do {
            project = try prdStore.loadProject(from: directoryURL)
        } catch {
            transitionToError("Failed to load project: \(error.localizedDescription)")
            return
        }

        // Select next story: filter passes: false, sort by priority, pick first
        guard let nextStory = selectNextStory(from: project) else {
            // All stories pass — complete
            logSystem("All stories pass — loop complete!")
            loopState = .complete
            onStateChange?(.complete)
            playCompletionSound()
            return
        }

        // Mark story as inProgress
        markStoryInProgress(nextStory.id, in: project)

        iterationCount += 1
        onIterationChange?(iterationCount)

        logSystem("Iteration \(iterationCount): Starting \(nextStory.id) — \(nextStory.title)")

        // Build prompt
        let prompt = buildPrompt(for: nextStory, project: project)

        // Spawn Claude Code process
        let processManager = processManagerFactory()
        self.currentProcessManager = processManager

        let parser = StreamingJSONParser()
        self.currentParser = parser

        let logFileURL = directoryURL.appendingPathComponent("claude.log")

        do {
            let linePublisher = try processManager.spawn(
                prompt: prompt,
                workingDirectory: directoryURL.deletingLastPathComponent(),
                logFileURL: logFileURL
            )

            // Subscribe parser to stdout lines
            let parseSub = parser.subscribe(to: linePublisher)
            cancellables.insert(parseSub)

            // Forward log entries
            let entrySub = parser.entryPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] entry in
                    guard let self else { return }
                    self.onLogEntry?(entry, self.projectID)
                }
            cancellables.insert(entrySub)

            // Listen for ridler-complete signal
            let completionSub = parser.completionPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in
                    self?.completionDetected = true
                }
            cancellables.insert(completionSub)

            // Handle process exit
            let exitSub = processManager.exitPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] result in
                    self?.handleProcessExit(result, storyID: nextStory.id)
                }
            cancellables.insert(exitSub)

        } catch {
            transitionToError("Failed to spawn Claude Code: \(error.localizedDescription)")
        }
    }

    private func handleProcessExit(_ result: ProcessExitResult, storyID: String) {
        // Clean up
        currentProcessManager = nil
        currentParser = nil
        cancellables.removeAll()

        guard loopState == .running || loopState == .paused else {
            // Loop was stopped externally
            return
        }

        if result.exitCode != 0 && !completionDetected {
            logSystem("Claude Code exited with code \(result.exitCode): \(result.stderr)")
            transitionToError("Claude Code failed (exit \(result.exitCode)): \(result.stderr)")
            return
        }

        logSystem("Iteration \(iterationCount) completed for \(storyID)")

        // Reload project to check updated state
        guard let directoryURL else { return }
        do {
            let updatedProject = try prdStore.loadProject(from: directoryURL)
            onProjectUpdated?(updatedProject)

            // Check if all stories pass
            let allPass = updatedProject.userStories.allSatisfy { $0.passes }
            if allPass || completionDetected {
                logSystem("All stories pass — loop complete!")
                loopState = .complete
                onStateChange?(.complete)
                playCompletionSound()
                return
            }
        } catch {
            // Non-fatal — we continue the loop
            Self.logger.warning("Failed to reload project after iteration: \(error.localizedDescription)")
        }

        // Check if we should pause
        if loopState == .paused || pauseAfterStory {
            loopState = .paused
            onStateChange?(.paused)
            logSystem("Paused after story \(storyID)")
            return
        }

        // Continue to next iteration
        runNextIteration()
    }

    private func selectNextStory(from project: PRDProject) -> UserStory? {
        project.userStories
            .filter { !$0.passes }
            .sorted { $0.priority < $1.priority }
            .first
    }

    private func markStoryInProgress(_ storyID: String, in project: PRDProject) {
        guard let directoryURL else { return }
        var updated = project
        if let index = updated.userStories.firstIndex(where: { $0.id == storyID }) {
            updated.userStories[index].inProgress = true
        }
        do {
            try prdStore.writeProject(updated, to: directoryURL)
        } catch {
            Self.logger.warning("Failed to mark story \(storyID) as inProgress: \(error.localizedDescription)")
        }
    }

    private func buildPrompt(for story: UserStory, project: PRDProject) -> String {
        var prompt = """
        # Chief Agent Instructions

        You are an autonomous coding agent working on a software project.

        ## Your Task

        1. Read the PRD at `.chief/prds/ridler/prd.json`
        2. Read `progress.md` if it exists (check Codebase Patterns section first)
        3. Pick the **highest priority** user story where `passes: false` -- After determining which story to work on, output exact story id, e.g.: <ralph-status>\(story.id)</ralph-status>
        4. Mark the story as `inProgress: true` in the PRD
        5. Implement that single user story
        6. Run quality checks (e.g., typecheck, lint, test - use whatever your project requires)
        7. If checks pass, commit ALL changes with message: `feat: [\(story.id)] - \(story.title)`
        8. Update the PRD to set `passes: true` and `inProgress: false` for the completed story
        9. Append your progress to `progress.md`

        ## Target Story

        - **ID:** \(story.id)
        - **Title:** \(story.title)
        - **Priority:** \(story.priority)
        - **Description:** \(story.description)

        ### Acceptance Criteria
        """

        for criterion in story.acceptanceCriteria {
            prompt += "\n- \(criterion)"
        }

        prompt += """


        ## Progress Report Format

        APPEND to progress.md (never replace, always append):
        ```
        ## [Date/Time] - [\(story.id)]
        - What was implemented
        - Files changed
        - **Learnings for future iterations:**
          - Patterns discovered
          - Gotchas encountered
          - Useful context
        ---
        ```

        ## Quality Requirements

        - ALL commits must pass your project's quality checks (typecheck, lint, test)
        - Do NOT commit broken code
        - Keep changes focused and minimal
        - Follow existing code patterns

        ## Stop Condition

        After completing the user story, reply with:
        <ridler-complete/>
        """

        // Include progress.md context if it exists
        if let directoryURL {
            let progressURL = directoryURL.appendingPathComponent("progress.md")
            if let progressContent = try? String(contentsOf: progressURL, encoding: .utf8) {
                prompt += "\n\n## Previous Progress\n\n\(progressContent)"
            }
        }

        return prompt
    }

    private func transitionToError(_ message: String) {
        Self.logger.error("Loop error: \(message)")
        logSystem("Error: \(message)")
        loopState = .error
        onStateChange?(.error)
    }

    private func logSystem(_ message: String) {
        Self.logger.info("\(message)")
        let entry = LogEntry(type: .system, content: message)
        onLogEntry?(entry, projectID)
    }

    private func playCompletionSound() {
        // Use NSSound for simple audio notification
        NSSound.beep()
    }
}
