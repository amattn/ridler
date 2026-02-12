import Foundation
import Combine
import AVFoundation
import UserNotifications
import AppKit
import os

/// The Ralph loop engine orchestrates the autonomous execution loop:
/// read state → select next story → build prompt → invoke Claude Code → stream output → check completion → repeat.
final class RalphLoopEngine: ObservableObject {
    private static let logger = Logger(subsystem: "com.amattn.Ridler", category: "RalphLoopEngine")

    private let prdStore: PRDStore
    private let processManagerFactory: () -> ProcessManaging
    private let gitManager: GitManaging

    private var cancellables = Set<AnyCancellable>()
    private var currentProcessManager: ProcessManaging?
    private var currentParser: StreamingJSONParser?

    // Callbacks
    var onStateChange: ((LoopState) -> Void)?
    var onIterationChange: ((Int) -> Void)?
    var onLogEntry: ((LogEntry, String) -> Void)?
    var onProjectUpdated: ((PRDProject) -> Void)?

    private var projectID: String = ""
    private var projectName: String = ""
    private var directoryURL: URL?
    private var pauseAfterStory = false
    private var audioNotificationsEnabled = true
    private var maxIterations = 0
    private var iterationCount = 0
    private var loopState: LoopState = .ready
    private var completionDetected = false
    private var currentStoryID: String?
    private var audioPlayer: AVAudioPlayer?

    init(
        prdStore: PRDStore = FileSystemPRDStore(),
        processManagerFactory: @escaping () -> ProcessManaging = { ClaudeCodeProcessManager() },
        gitManager: GitManaging = GitManager()
    ) {
        self.prdStore = prdStore
        self.processManagerFactory = processManagerFactory
        self.gitManager = gitManager
    }

    // MARK: - Debug Properties

    /// Exposes the PID of the active Claude Code subprocess, or nil if none is running.
    var activeProcessPID: Int32? { currentProcessManager?.processIdentifier }

    /// Exposes the last error message, or nil if no error has occurred.
    private(set) var lastErrorMessage: String?

    // MARK: - Public API

    /// Starts the loop for the given project.
    func start(project: PRDProject) {
        guard loopState != .running else { return }

        self.projectID = project.id
        self.projectName = project.name ?? project.id
        self.directoryURL = project.directoryURL
        self.pauseAfterStory = project.pauseAfterStory
        self.audioNotificationsEnabled = project.audioNotificationsEnabled
        self.maxIterations = project.maxIterations > 0 ? project.maxIterations : project.defaultMaxIterations
        self.iterationCount = project.iterationCount
        self.loopState = .running
        self.completionDetected = false
        self.currentStoryID = nil

        onStateChange?(.running)
        logSystem("Loop started")

        runNextIteration()
    }

    /// Resumes the loop after a pause.
    func resume(project: PRDProject) {
        guard loopState == .paused || loopState == .stopped || loopState == .error else { return }

        self.projectID = project.id
        self.projectName = project.name ?? project.id
        self.directoryURL = project.directoryURL
        self.pauseAfterStory = project.pauseAfterStory
        self.audioNotificationsEnabled = project.audioNotificationsEnabled
        self.maxIterations = project.maxIterations > 0 ? project.maxIterations : project.defaultMaxIterations
        self.iterationCount = project.iterationCount
        self.loopState = .running
        self.completionDetected = false
        self.currentStoryID = nil

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

    /// Updates the audio notifications setting.
    func updateAudioNotifications(_ enabled: Bool) {
        self.audioNotificationsEnabled = enabled
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
            postCompletionNotification()
            return
        }

        currentStoryID = nextStory.id
        completionDetected = false

        // Mark story as inProgress
        markStoryInProgress(nextStory.id, in: project)

        iterationCount += 1
        onIterationChange?(iterationCount)

        logSystem("Iteration \(iterationCount): Starting \(nextStory.id) — \(nextStory.userStoryTitle)")

        // Build prompt
        let prompt = buildPrompt(for: nextStory, project: project)
        logSystem("Prompt:\n\(prompt)")

        // Spawn Claude Code process
        let processManager = processManagerFactory()
        self.currentProcessManager = processManager

        let parser = StreamingJSONParser()
        self.currentParser = parser

        let logFileURL = directoryURL.appendingPathComponent("ridler.log")

        do {
            let linePublisher = try processManager.spawn(
                prompt: prompt,
                workingDirectory: directoryURL.deletingLastPathComponent(),
                logFileURL: logFileURL
            )

            // Subscribe parser to stdout lines
            let parseSub = parser.subscribe(to: linePublisher)
            cancellables.insert(parseSub)

            // Forward log entries tagged with the current story
            let storyIDForIteration = self.currentStoryID
            let entrySub = parser.entryPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] entry in
                    guard let self else { return }
                    let taggedEntry = LogEntry(
                        id: entry.id,
                        timestamp: entry.timestamp,
                        type: entry.type,
                        content: entry.content,
                        storyID: storyIDForIteration,
                        rawJSON: entry.rawJSON
                    )
                    self.onLogEntry?(taggedEntry, self.projectID)
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

        // Append progress entry for this iteration
        appendProgress(storyID: storyID, exitCode: result.exitCode)

        // Create git commit for the completed story
        commitStoryChanges(storyID: storyID)

        // Reload project to check updated state
        guard let directoryURL else { return }
        do {
            let updatedProject = try prdStore.loadProject(from: directoryURL)
            onProjectUpdated?(updatedProject)

            // Check if all stories pass
            let allPass = updatedProject.iterationDefinitions.allSatisfy { $0.passes }
            if allPass {
                logSystem("All stories pass — loop complete!")
                loopState = .complete
                onStateChange?(.complete)
                playCompletionSound()
                postCompletionNotification()
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

    private func selectNextStory(from project: PRDProject) -> IterationDefinition? {
        project.iterationDefinitions
            .filter { !$0.passes }
            .sorted { $0.priority < $1.priority }
            .first
    }

    private func markStoryInProgress(_ storyID: String, in project: PRDProject) {
        // inProgress is runtime-only (not serialized in v2), so just notify via callback
        var updated = project
        if let index = updated.iterationDefinitions.firstIndex(where: { $0.id == storyID }) {
            updated.iterationDefinitions[index].inProgress = true
        }
        onProjectUpdated?(updated)
    }

    private func buildPrompt(for story: IterationDefinition, project: PRDProject) -> String {
        var prompt = """
        # Chief Agent Instructions

        You are an autonomous coding agent working on a software project.

        ## Your Task

        1. Read the PRD at `ridl/ridl.json`
        2. Read `progress.md` if it exists (check Codebase Patterns section first)
        3. Pick the **highest priority** iteration definition where `passes: false` -- After determining which story to work on, output exact story id, e.g.: <ralph-status>\(story.id)</ralph-status>
        4. Implement that single iteration definition
        5. Run quality checks (e.g., typecheck, lint, test - use whatever your project requires)
        6. If checks pass, commit ALL changes with message: `feature: [\(story.id)] - \(story.userStoryTitle)`
        7. Append your progress to `progress.md`
        8. **LAST STEP — do this after everything else is done:** Update `ridl/ridl.json` to set `"passes": true` for the completed iteration definition. This MUST be the final action you take, outside of any cleanup tasks or final logging for debug or non-user facing purposes.

        ## Target Story

        - **ID:** \(story.id)
        - **Title:** \(story.userStoryTitle)
        - **Priority:** \(story.priority)
        - **Description:** \(story.userStoryDescription)

        ### Acceptance Criteria
        """

        for criterion in story.acceptanceCriteria {
            prompt += "\n- \(criterion)"
        }

        // Add prdReferences if present
        if let refs = story.prdReferences, !refs.isEmpty {
            prompt += "\n\n### PRD References"
            for ref in refs {
                prompt += "\n- \(ref)"
            }
        }

        // Add universalContext if present
        if let ctx = project.universalContext {
            prompt += "\n\n## Universal Context"
            if let nfr = ctx.nonFunctionalRequirements, !nfr.isEmpty {
                prompt += "\n\n### Non-Functional Requirements"
                for item in nfr {
                    prompt += "\n- \(item)"
                }
            }
            if let devExp = ctx.developerExperience, !devExp.isEmpty {
                prompt += "\n\n### Developer Experience"
                for item in devExp {
                    prompt += "\n- \(item)"
                }
            }
            if let techArch = ctx.technicalArchitecture, !techArch.isEmpty {
                prompt += "\n\n### Technical Architecture"
                for item in techArch {
                    prompt += "\n- \(item)"
                }
            }
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

    private func commitStoryChanges(storyID: String) {
        guard let directoryURL else { return }

        // Look up story title
        var storyTitle = storyID
        if let project = try? prdStore.loadProject(from: directoryURL),
           let story = project.iterationDefinitions.first(where: { $0.id == storyID }) {
            storyTitle = story.userStoryTitle
        }

        let commitMessage = "feature: [\(storyID)] - \(storyTitle)"
        let workingDirectory = directoryURL.deletingLastPathComponent()

        do {
            try gitManager.commitAllChanges(message: commitMessage, at: workingDirectory)
            logSystem("Committed: \(commitMessage)")
        } catch {
            Self.logger.warning("Git commit failed for \(storyID): \(error.localizedDescription)")
            logSystem("Git commit failed: \(error.localizedDescription)")
        }
    }

    private func appendProgress(storyID: String, exitCode: Int32) {
        guard let directoryURL else { return }

        let progressURL = directoryURL.appendingPathComponent("progress.md")
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let timestamp = dateFormatter.string(from: Date())
        let status = exitCode == 0 ? "Completed successfully" : "Exited with code \(exitCode)"

        // Look up story title from disk
        var storyTitle = storyID
        if let project = try? prdStore.loadProject(from: directoryURL),
           let story = project.iterationDefinitions.first(where: { $0.id == storyID }) {
            storyTitle = "\(storyID) — \(story.userStoryTitle)"
        }

        let entry = """

        ## \(timestamp) - \(storyTitle)
        - **Iteration:** \(iterationCount)
        - **Status:** \(status)
        - Claude Code session completed for this story
        ---

        """

        do {
            if FileManager.default.fileExists(atPath: progressURL.path) {
                let handle = try FileHandle(forWritingTo: progressURL)
                handle.seekToEndOfFile()
                if let data = entry.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            } else {
                try entry.data(using: .utf8)?.write(to: progressURL, options: .atomic)
            }
            Self.logger.info("Appended progress entry for \(storyID)")
        } catch {
            Self.logger.warning("Failed to append progress for \(storyID): \(error.localizedDescription)")
        }
    }

    private func transitionToError(_ message: String) {
        Self.logger.error("[\(self.projectName)] iteration=\(self.iterationCount) story=\(self.currentStoryID ?? "none") Error: \(message)")
        logSystem("Error: \(message)")
        lastErrorMessage = message
        loopState = .error
        onStateChange?(.error)
    }

    private func logSystem(_ message: String) {
        Self.logger.info("[\(self.projectName)] iteration=\(self.iterationCount) \(message)")
        let entry = LogEntry(type: .system, content: message, storyID: currentStoryID)
        onLogEntry?(entry, projectID)
    }

    private func playCompletionSound() {
        guard audioNotificationsEnabled else { return }

        // Use a system sound via AVAudioPlayer
        let soundPath = "/System/Library/Sounds/Glass.aiff"
        let soundURL = URL(fileURLWithPath: soundPath)
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
            audioPlayer?.play()
        } catch {
            Self.logger.warning("Failed to play completion sound: \(error.localizedDescription)")
        }
    }

    private func postCompletionNotification() {
        // Only post notification when the app is not frontmost
        guard !NSApplication.shared.isActive else { return }

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            guard granted else {
                if let error {
                    Self.logger.warning("Notification authorization denied: \(error.localizedDescription)")
                }
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "PRD Complete"
            content.body = "\(self.projectName) has finished all stories."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "ridler-complete-\(self.projectID)",
                content: content,
                trigger: nil // Deliver immediately
            )

            center.add(request) { error in
                if let error {
                    Self.logger.warning("Failed to post notification: \(error.localizedDescription)")
                }
            }
        }
    }
}
