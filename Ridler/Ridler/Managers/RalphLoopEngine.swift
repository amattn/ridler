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
    private var pauseAfterMilestone = false
    private var milestones: [Milestone]?
    private var audioNotificationsEnabled = true
    private var maxIterations = 0
    private var iterationCount = 0
    private var loopState: LoopState = .ready
    private var lastSignal: HarnessSignal?
    private var currentStoryID: String?
    private var currentPhase: IterationPhase = .implementation
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
        self.pauseAfterMilestone = project.pauseAfterMilestone
        self.milestones = project.milestones
        self.audioNotificationsEnabled = project.audioNotificationsEnabled
        self.maxIterations = project.maxIterations > 0 ? project.maxIterations : project.defaultMaxIterations
        self.iterationCount = project.iterationCount
        self.loopState = .running
        self.lastSignal = nil
        self.currentStoryID = nil
        self.currentPhase = .implementation

        // Ensure default prompt templates exist in the project's prompts directory
        if let directoryURL = project.directoryURL {
            do {
                try TemplateManager.ensureTemplatesExist(in: directoryURL)
            } catch {
                transitionToError("Failed to initialize prompt templates: \(error.localizedDescription)")
                return
            }

            // Validate all templates before starting
            let templateErrors = TemplateManager.validateAllTemplates(in: directoryURL)
            if let firstError = templateErrors.values.first {
                transitionToError("Template syntax error: \(firstError.errorDescription ?? firstError.message)")
                return
            }
        }

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
        self.pauseAfterMilestone = project.pauseAfterMilestone
        self.milestones = project.milestones
        self.audioNotificationsEnabled = project.audioNotificationsEnabled
        self.maxIterations = project.maxIterations > 0 ? project.maxIterations : project.defaultMaxIterations
        self.iterationCount = project.iterationCount
        self.loopState = .running
        self.lastSignal = nil
        self.currentStoryID = nil
        self.currentPhase = .implementation

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

    /// Updates the pause-after-milestone setting.
    func updatePauseAfterMilestone(_ value: Bool) {
        self.pauseAfterMilestone = value
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

        let nextStory: IterationDefinition

        if currentPhase == .verification, let storyID = currentStoryID,
           let story = project.iterationDefinitions.first(where: { $0.id == storyID }) {
            // Verification phase: reuse the same story
            nextStory = story
        } else {
            // Implementation phase: select next non-frozen story
            guard let selected = selectNextStory(from: project) else {
                logSystem("All stories pass — loop complete!")
                loopState = .complete
                onStateChange?(.complete)
                playCompletionSound()
                postCompletionNotification()
                return
            }
            nextStory = selected
            currentPhase = .implementation
        }

        currentStoryID = nextStory.id
        lastSignal = nil

        // Notify UI of the current story
        onProjectUpdated?(project)

        iterationCount += 1
        onIterationChange?(iterationCount)

        let phaseLabel = currentPhase == .implementation ? "Implementation" : "Verification"
        logSystem("Iteration \(iterationCount): \(phaseLabel) — \(nextStory.id) — \(nextStory.title)")

        // Build prompt from templates
        let templateNames: [String]
        switch currentPhase {
        case .implementation:
            templateNames = TemplateManager.implementationTemplateNames
        case .verification:
            templateNames = TemplateManager.verificationTemplateNames
        }
        let templateNamesStr = templateNames.map { "\($0).liquid" }.joined(separator: ", ")
        let promptsPath = directoryURL.appendingPathComponent("prompts").path
        logSystem("Rendering templates: \(templateNamesStr) from \(promptsPath)")
        logSystem("Template context: iteration.id=\(nextStory.id), iteration.priority=\(nextStory.priority), iteration.acceptance_criteria=[\(nextStory.acceptanceCriteria.count) items], project.universalContext=\(project.universalContext != nil ? "present" : "nil"), progress_content=\(runtimeFileExists("progress.md", in: directoryURL) ? "present" : "nil")")

        let prompt: String
        do {
            prompt = try buildPrompt(for: nextStory, project: project, phase: currentPhase)
        } catch {
            transitionToError("Template rendering failed: \(error.localizedDescription)")
            return
        }
        logSystem("Prompt rendered (\(prompt.count) chars) from \(templateNames.count) templates")
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

            // Listen for harness signals
            let signalSub = parser.signalPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] signal in
                    self?.lastSignal = signal
                }
            cancellables.insert(signalSub)

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

        let phaseLabel = currentPhase == .implementation ? "implementation" : "verification"

        // Handle blocked signal from either phase
        if lastSignal == .blocked {
            logSystem("Agent signaled blocked during \(phaseLabel) for \(storyID)")
            loopState = .paused
            onStateChange?(.paused)
            return
        }

        // Handle non-zero exit with no signal
        if result.exitCode != 0 && lastSignal == nil {
            logSystem("Claude Code exited with code \(result.exitCode): \(result.stderr)")
            transitionToError("Claude Code failed (exit \(result.exitCode)): \(result.stderr)")
            return
        }

        logSystem("Iteration \(iterationCount) \(phaseLabel) completed for \(storyID)")

        // Phase-specific handling
        switch currentPhase {
        case .implementation:
            // Implementation done — commit and move to verification
            commitStoryChanges(storyID: storyID, phase: .implementation)
            currentPhase = .verification
            logSystem("Transitioning to verification phase for \(storyID)")
            runNextIteration()

        case .verification:
            if lastSignal == .verificationFailed {
                // Verification found issues — loop back to implementation
                commitStoryChanges(storyID: storyID, phase: .verification)
                logSystem("Verification failed for \(storyID) — looping back to implementation")
                currentPhase = .implementation
                runNextIteration()
                return
            }

            // Verification passed — commit, log, and advance
            commitStoryChanges(storyID: storyID, phase: .verification)
            appendProgressLog(storyID: storyID, exitCode: result.exitCode)

            // Reload project to check updated state
            guard let directoryURL else { return }
            do {
                let updatedProject = try prdStore.loadProject(from: directoryURL)
                onProjectUpdated?(updatedProject)

                let allPass = updatedProject.iterationDefinitions.allSatisfy { $0.isFrozen }
                if allPass {
                    logSystem("All stories pass — loop complete!")
                    loopState = .complete
                    onStateChange?(.complete)
                    playCompletionSound()
                    postCompletionNotification()
                    return
                }
            } catch {
                Self.logger.warning("Failed to reload project after iteration: \(error.localizedDescription)")
            }

            // Check if we should pause
            if loopState == .paused || pauseAfterStory {
                loopState = .paused
                onStateChange?(.paused)
                logSystem("Paused after story \(storyID)")
                return
            }

            // Check if we should pause after milestone
            if pauseAfterMilestone, let milestones, isLastStoryInMilestone(storyID, milestones: milestones) {
                loopState = .paused
                onStateChange?(.paused)
                logSystem("Paused after milestone containing \(storyID)")
                return
            }

            // Continue to next iteration definition
            currentPhase = .implementation
            runNextIteration()
        }
    }

    private func selectNextStory(from project: PRDProject) -> IterationDefinition? {
        project.iterationDefinitions
            .filter { !$0.isFrozen }
            .sorted { $0.priority < $1.priority }
            .first
    }

    /// Returns true if the story is the last one in its milestone (i.e. all other stories in that milestone now pass).
    private func isLastStoryInMilestone(_ storyID: String, milestones: [Milestone]) -> Bool {
        guard let directoryURL, let project = try? prdStore.loadProject(from: directoryURL) else { return false }
        for milestone in milestones {
            guard milestone.storyIDs.contains(storyID) else { continue }
            let allOthersPass = milestone.storyIDs.allSatisfy { id in
                id == storyID || (project.iterationDefinitions.first { $0.id == id }?.isFrozen ?? false)
            }
            if allOthersPass { return true }
        }
        return false
    }

    private func runtimeFileExists(_ filename: String, in directoryURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent(filename).path)
    }

    private func readRuntimeFile(_ filename: String) -> String? {
        guard let directoryURL else { return nil }
        let url = directoryURL.appendingPathComponent(filename)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func buildPrompt(for story: IterationDefinition, project: PRDProject, phase: IterationPhase) throws -> String {
        let progressContent = readRuntimeFile("progress.md")
        let learningsContent = readRuntimeFile("learnings.md")
        let emergentContent = readRuntimeFile("emergent.md")

        switch phase {
        case .implementation:
            return try TemplateManager.buildImplementationPrompt(
                for: story,
                project: project,
                progressContent: progressContent,
                learningsContent: learningsContent,
                emergentContent: emergentContent
            )
        case .verification:
            return try TemplateManager.buildVerificationPrompt(
                for: story,
                project: project,
                progressContent: progressContent,
                learningsContent: learningsContent,
                emergentContent: emergentContent
            )
        }
    }

    private func commitStoryChanges(storyID: String, phase: IterationPhase) {
        guard let directoryURL else { return }

        // Look up story title
        var storyTitle = storyID
        if let project = try? prdStore.loadProject(from: directoryURL),
           let story = project.iterationDefinitions.first(where: { $0.id == storyID }) {
            storyTitle = story.title
        }

        let commitMessage: String
        switch phase {
        case .implementation:
            commitMessage = "feature: [\(storyID)] implementation - \(storyTitle)"
        case .verification:
            commitMessage = "verify: [\(storyID)] verification - \(storyTitle)"
        }

        let workingDirectory = directoryURL.deletingLastPathComponent()

        do {
            try gitManager.commitAllChanges(message: commitMessage, at: workingDirectory)
            logSystem("Committed: \(commitMessage)")
        } catch {
            Self.logger.warning("Git commit failed for \(storyID): \(error.localizedDescription)")
            logSystem("Git commit failed: \(error.localizedDescription)")
        }
    }

    private func appendProgressLog(storyID: String, exitCode: Int32) {
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
            storyTitle = "\(storyID) — \(story.title)"
        }

        let entry = """

        ## \(timestamp) - \(storyTitle)
        - **Iteration:** \(iterationCount)
        - **Status:** \(status)
        - **Phase:** verification complete
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
            Self.logger.info("Appended progress log entry for \(storyID)")
        } catch {
            Self.logger.warning("Failed to append progress log for \(storyID): \(error.localizedDescription)")
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
