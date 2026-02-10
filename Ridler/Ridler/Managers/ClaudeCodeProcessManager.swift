import Foundation
import Combine
import os

final class ClaudeCodeProcessManager: ProcessManaging {
    private static let logger = Logger(subsystem: "com.amattn.Ridler", category: "ProcessManager")
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stderrData = Data()
    private var currentCommand = ""

    private let lineSubject = PassthroughSubject<String, Never>()
    private let exitSubject = PassthroughSubject<ProcessExitResult, Never>()

    private let queue = DispatchQueue(label: "com.amattn.Ridler.ClaudeCodeProcessManager", qos: .userInitiated)

    var isRunning: Bool {
        process?.isRunning ?? false
    }

    var processIdentifier: Int32? {
        guard let process, process.isRunning else { return nil }
        return process.processIdentifier
    }

    var exitPublisher: AnyPublisher<ProcessExitResult, Never> {
        exitSubject.eraseToAnyPublisher()
    }

    func spawn(prompt: String, workingDirectory: URL, logFileURL: URL) throws -> AnyPublisher<String, Never> {
        guard !isRunning else {
            Self.logger.error("Spawn failed: a process is already running")
            throw RidlerError.processError(
                command: "claude",
                exitCode: -1,
                stderr: "A process is already running"
            )
        }

        let settings = SettingsManager.shared
        guard settings.isClaudeConfigDirValid else {
            Self.logger.error("Claude config directory not found: \(settings.resolvedClaudeConfigPath)")
            throw RidlerError.claudeConfigNotFound(path: settings.resolvedClaudeConfigPath)
        }

        Self.logger.info("Spawning Claude Code in \(workingDirectory.path)")

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "claude",
            "--dangerously-skip-permissions",
            "--output-format", "stream-json",
            "-p", prompt
        ]
        process.currentDirectoryURL = workingDirectory
        process.environment = Self.processEnvironment()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        self.stderrData = Data()
        self.currentCommand = "claude --dangerously-skip-permissions --output-format stream-json -p <prompt>"

        // Set up log file handle for raw output capture
        let logFileHandle = createLogFileHandle(at: logFileURL)

        // Stream stdout line-by-line
        var stdoutBuffer = Data()
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            // Write raw data to log file
            logFileHandle?.write(data)

            stdoutBuffer.append(data)

            // Process complete lines
            while let newlineRange = stdoutBuffer.range(of: Data([0x0A])) {
                let lineData = stdoutBuffer.subdata(in: stdoutBuffer.startIndex..<newlineRange.lowerBound)
                stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...newlineRange.lowerBound)

                if let line = String(data: lineData, encoding: .utf8) {
                    self?.lineSubject.send(line)
                }
            }
        }

        // Capture stderr
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            // Write raw stderr to log file
            if let stderrPrefix = "[stderr] ".data(using: .utf8) {
                logFileHandle?.write(stderrPrefix)
            }
            logFileHandle?.write(data)

            self?.queue.async {
                self?.stderrData.append(data)
            }
        }

        // Set up termination handler
        process.terminationHandler = { [weak self] proc in
            guard let self else { return }

            // Close pipe handlers
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil

            // Close log file
            logFileHandle?.closeFile()

            var capturedData = Data()
            self.queue.sync {
                capturedData = self.stderrData
            }
            let stderrString = String(data: capturedData, encoding: .utf8) ?? ""

            let result = ProcessExitResult(
                exitCode: proc.terminationStatus,
                stderr: stderrString,
                command: self.currentCommand
            )

            if proc.terminationStatus != 0 {
                Self.logger.error("Claude Code exited with code \(proc.terminationStatus): \(stderrString.prefix(500))")
            } else {
                Self.logger.info("Claude Code exited successfully (code 0)")
            }

            DispatchQueue.main.async {
                self.exitSubject.send(result)
                self.process = nil
                self.stdoutPipe = nil
                self.stderrPipe = nil
            }
        }

        try process.run()
        Self.logger.info("Claude Code process started (PID: \(process.processIdentifier))")
        return lineSubject.eraseToAnyPublisher()
    }

    func kill() {
        guard let process, process.isRunning else { return }
        Self.logger.info("Killing Claude Code process (PID: \(process.processIdentifier))")
        process.terminate()
        // Give the process a moment to terminate gracefully, then force kill
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if self?.process?.isRunning == true {
                self?.process?.interrupt()
            }
        }
    }

    /// Returns a process environment with an expanded PATH that includes
    /// common user binary directories where `claude` may be installed.
    private static func processEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let additionalPaths = [
            "\(home)/.local/bin",
            "/usr/local/bin",
            "/opt/homebrew/bin",
        ]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (additionalPaths + [currentPath]).joined(separator: ":")

        let configDir = SettingsManager.shared.resolvedClaudeConfigPath
        env["CLAUDE_CONFIG_DIR"] = configDir

        return env
    }

    private func createLogFileHandle(at url: URL) -> FileHandle? {
        let fileManager = FileManager.default
        let dirURL = url.deletingLastPathComponent()

        // Ensure directory exists
        try? fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)

        // Create or append to log file
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }

        guard let handle = try? FileHandle(forWritingTo: url) else { return nil }
        handle.seekToEndOfFile()

        // Write session separator
        if let separator = "\n\n=== Claude Code Session: \(ISO8601DateFormatter().string(from: Date())) ===\n\n".data(using: .utf8) {
            handle.write(separator)
        }

        return handle
    }
}
