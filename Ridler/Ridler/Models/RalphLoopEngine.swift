import Foundation

enum RalphLoopError: Error, LocalizedError {
    case noStoriesRemaining
    case prdLoadFailed(String)
    case prdSaveFailed(String)
    case claudeProcessFailed(String)
    case maxIterationsReached

    var errorDescription: String? {
        switch self {
        case .noStoriesRemaining:
            return "No remaining stories with passes == false"
        case .prdLoadFailed(let detail):
            return "Failed to load PRD: \(detail)"
        case .prdSaveFailed(let detail):
            return "Failed to save PRD: \(detail)"
        case .claudeProcessFailed(let detail):
            return "Claude process failed: \(detail)"
        case .maxIterationsReached:
            return "Maximum iterations reached"
        }
    }
}

protocol RalphLoopEngineDelegate: AnyObject {
    func engine(_ engine: RalphLoopEngine, didProduceLogEntry entry: LogEntry)
    func engine(_ engine: RalphLoopEngine, didUpdateIteration current: Int, max: Int)
    func engine(_ engine: RalphLoopEngine, didUpdateStory story: UserStory)
}

@Observable
final class RalphLoopEngine {
    private(set) var currentIteration: Int = 0
    private(set) var currentStoryId: String?
    private(set) var logEntries: [LogEntry] = []

    let prdFilePath: String
    let workingDirectory: String
    let maxIterations: Int

    let stateMachine: LoopStateMachine
    private let processManager: ClaudeProcessManager
    private let parser: StreamingJSONLogParser

    weak var delegate: RalphLoopEngineDelegate?

    private var pauseRequested = false
    private var stopRequested = false

    init(
        prdFilePath: String,
        workingDirectory: String,
        maxIterations: Int,
        stateMachine: LoopStateMachine = LoopStateMachine(),
        processManager: ClaudeProcessManager = ClaudeProcessManager(),
        parser: StreamingJSONLogParser = StreamingJSONLogParser()
    ) {
        self.prdFilePath = prdFilePath
        self.workingDirectory = workingDirectory
        self.maxIterations = maxIterations
        self.stateMachine = stateMachine
        self.processManager = processManager
        self.parser = parser
    }

    // MARK: - Public Control

    func start() async {
        guard stateMachine.transition(to: .running) else { return }

        pauseRequested = false
        stopRequested = false
        currentIteration = 0

        await runLoop()
    }

    func resume() async {
        guard stateMachine.transition(to: .running) else { return }

        pauseRequested = false
        stopRequested = false

        await runLoop()
    }

    func pause() {
        guard stateMachine.state == .running else { return }
        pauseRequested = true
    }

    func stop() {
        guard stateMachine.state == .running || stateMachine.state == .paused else { return }
        stopRequested = true
        processManager.cancel()
    }

    // MARK: - Core Loop

    private func runLoop() async {
        while !stopRequested && !pauseRequested {
            // Check max iterations
            if currentIteration >= maxIterations {
                addLogEntry(.system("Maximum iterations reached (\(maxIterations))"))
                stateMachine.transition(to: .stopped)
                return
            }

            // Load current PRD state
            let prd: PRDProject
            do {
                prd = try PRDFileManager.load(from: prdFilePath)
            } catch {
                addLogEntry(.error("Failed to load PRD: \(error.localizedDescription)"))
                stateMachine.transition(to: .error)
                return
            }

            // Select next story
            guard let story = selectNextStory(from: prd) else {
                // All stories pass
                addLogEntry(.system("All stories complete!"))
                stateMachine.transition(to: .complete)
                return
            }

            currentIteration += 1
            currentStoryId = story.id
            delegate?.engine(self, didUpdateIteration: currentIteration, max: maxIterations)

            addLogEntry(.system("Starting iteration \(currentIteration)/\(maxIterations): \(story.id) - \(story.title)"))

            // Mark story as in progress
            do {
                var updatedPrd = prd
                if let idx = updatedPrd.userStories.firstIndex(where: { $0.id == story.id }) {
                    updatedPrd.userStories[idx].inProgress = true
                }
                try PRDFileManager.save(updatedPrd, to: prdFilePath)
            } catch {
                addLogEntry(.error("Failed to update PRD: \(error.localizedDescription)"))
                stateMachine.transition(to: .error)
                return
            }

            delegate?.engine(self, didUpdateStory: story)

            // Build prompt
            let prompt = buildPrompt(for: story, prd: prd)

            // Store lastPrompt
            do {
                var updatedPrd = try PRDFileManager.load(from: prdFilePath)
                if let idx = updatedPrd.userStories.firstIndex(where: { $0.id == story.id }) {
                    updatedPrd.userStories[idx].lastPrompt = prompt
                }
                try PRDFileManager.save(updatedPrd, to: prdFilePath)
            } catch {
                addLogEntry(.error("Failed to store lastPrompt: \(error.localizedDescription)"))
                // Non-fatal, continue
            }

            // Run Claude
            let success = await runClaude(prompt: prompt)

            // Check if stopped during execution
            if stopRequested {
                // Revert inProgress on stop
                do {
                    var updatedPrd = try PRDFileManager.load(from: prdFilePath)
                    if let idx = updatedPrd.userStories.firstIndex(where: { $0.id == story.id }) {
                        updatedPrd.userStories[idx].inProgress = false
                    }
                    try PRDFileManager.save(updatedPrd, to: prdFilePath)
                } catch {
                    // Best effort
                }
                stateMachine.transition(to: .stopped)
                return
            }

            if success {
                // Mark story as complete
                do {
                    var updatedPrd = try PRDFileManager.load(from: prdFilePath)
                    if let idx = updatedPrd.userStories.firstIndex(where: { $0.id == story.id }) {
                        updatedPrd.userStories[idx].passes = true
                        updatedPrd.userStories[idx].inProgress = false
                    }
                    try PRDFileManager.save(updatedPrd, to: prdFilePath)
                    addLogEntry(.system("Story \(story.id) completed successfully"))
                } catch {
                    addLogEntry(.error("Failed to update PRD after completion: \(error.localizedDescription)"))
                    stateMachine.transition(to: .error)
                    return
                }

                // Append to progress.md
                appendProgress(for: story)

                // Check if ridler-complete was detected
                if parser.ridlerCompleteDetected {
                    addLogEntry(.system("Ridler complete signal detected"))
                    stateMachine.transition(to: .complete)
                    return
                }

                // Check if all stories now pass
                do {
                    let finalPrd = try PRDFileManager.load(from: prdFilePath)
                    if finalPrd.userStories.allSatisfy({ $0.passes }) {
                        addLogEntry(.system("All stories complete!"))
                        stateMachine.transition(to: .complete)
                        return
                    }
                } catch {
                    // Continue to next iteration
                }
            } else {
                // Claude failed — mark story not in progress, transition to error
                do {
                    var updatedPrd = try PRDFileManager.load(from: prdFilePath)
                    if let idx = updatedPrd.userStories.firstIndex(where: { $0.id == story.id }) {
                        updatedPrd.userStories[idx].inProgress = false
                    }
                    try PRDFileManager.save(updatedPrd, to: prdFilePath)
                } catch {
                    // Best effort
                }
                addLogEntry(.error("Story \(story.id) iteration failed"))
                stateMachine.transition(to: .error)
                return
            }

            // Check pause after iteration completes
            if pauseRequested {
                addLogEntry(.system("Loop paused after iteration \(currentIteration)"))
                stateMachine.transition(to: .paused)
                return
            }
        }

        // Handle remaining state transitions
        if stopRequested {
            stateMachine.transition(to: .stopped)
        } else if pauseRequested {
            stateMachine.transition(to: .paused)
        }
    }

    // MARK: - Story Selection

    func selectNextStory(from prd: PRDProject) -> UserStory? {
        prd.userStories
            .filter { !$0.passes }
            .sorted { $0.priority < $1.priority }
            .first
    }

    // MARK: - Prompt Building

    func buildPrompt(for story: UserStory, prd: PRDProject) -> String {
        var parts: [String] = []

        // Agent instructions
        parts.append("# Chief Agent Instructions")
        parts.append("")
        parts.append("You are an autonomous coding agent working on a software project.")
        parts.append("")
        parts.append("## Your Task")
        parts.append("")
        parts.append("Implement the following user story:")
        parts.append("")

        // Story details
        parts.append("## Story: \(story.id) - \(story.title)")
        parts.append("")
        parts.append("**Description:** \(story.description)")
        parts.append("")
        parts.append("**Acceptance Criteria:**")
        for criterion in story.acceptanceCriteria {
            parts.append("- \(criterion)")
        }
        parts.append("")

        // Progress context
        let progressContent = readProgressFile()
        if let content = progressContent, !content.isEmpty {
            parts.append("## Previous Progress")
            parts.append("")
            parts.append(content)
            parts.append("")
        }

        // Quality requirements
        parts.append("## Quality Requirements")
        parts.append("")
        parts.append("- ALL commits must pass your project's quality checks (typecheck, lint, test)")
        parts.append("- Do NOT commit broken code")
        parts.append("- Keep changes focused and minimal")
        parts.append("- Follow existing code patterns")
        parts.append("")

        // Completion signal
        parts.append("## Completion")
        parts.append("")
        parts.append("When you have fully implemented this story and all acceptance criteria are met, end your response with:")
        parts.append("<ridler-complete/>")

        return parts.joined(separator: "\n")
    }

    // MARK: - Claude Execution

    private func runClaude(prompt: String) async -> Bool {
        do {
            let result = try await processManager.run(
                prompt: prompt,
                workingDirectory: workingDirectory
            ) { [weak self] line in
                guard let self else { return }
                if let entry = self.parser.parse(line: line) {
                    DispatchQueue.main.async {
                        self.logEntries.append(entry)
                        self.delegate?.engine(self, didProduceLogEntry: entry)
                    }
                }
            }
            return result.success
        } catch {
            addLogEntry(.error("Claude process error: \(error.localizedDescription)"))
            return false
        }
    }

    // MARK: - Progress File

    private func readProgressFile() -> String? {
        let dir = PRDFileManager.companionDirectory(for: prdFilePath)
        let progressPath = (dir as NSString).appendingPathComponent("progress.md")
        return try? String(contentsOfFile: progressPath, encoding: .utf8)
    }

    private func appendProgress(for story: UserStory) {
        let dir = PRDFileManager.companionDirectory(for: prdFilePath)
        let progressPath = (dir as NSString).appendingPathComponent("progress.md")

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let timestamp = dateFormatter.string(from: Date())

        let entry = """

        ## \(timestamp) - \(story.id)
        - Completed: \(story.title)
        - Implemented by Ralph Loop Engine iteration \(currentIteration)
        ---
        """

        if FileManager.default.fileExists(atPath: progressPath) {
            if let handle = FileHandle(forWritingAtPath: progressPath) {
                handle.seekToEndOfFile()
                if let data = entry.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            }
        } else {
            try? entry.write(toFile: progressPath, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Logging

    private func addLogEntry(_ type: LogEntryType) {
        let entry = LogEntry(type: type)
        logEntries.append(entry)
        delegate?.engine(self, didProduceLogEntry: entry)
    }
}
