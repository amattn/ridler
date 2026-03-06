import Foundation
import Combine
import os
import SwiftTerm
import AppKit

/// Manages an interactive Claude Code session for PRD editing.
/// Coordinates session configuration and holds the persistent terminal view.
final class ClaudeTerminalManager: ObservableObject {
    private static let logger = Logger(subsystem: "com.amattn.Ridler", category: "ClaudeTerminal")

    struct SessionConfig: Identifiable {
        let id = UUID()
        let executable: String
        let arguments: [String]
        let environment: [String: String]
        let workingDirectory: String
        let initialInput: String?
    }

    @Published var isRunning: Bool = false
    @Published var hasSessionHistory: Bool = false
    @Published var configError: String?
    @Published var activeSession: SessionConfig?

    /// Persistent terminal view — survives SwiftUI lifecycle.
    /// Set and managed by SwiftTerminalView.
    var terminalView: LocalProcessTerminalView?

    /// Starts an interactive Claude Code session.
    /// - Parameters:
    ///   - filePath: The PRD file path to edit (used as context)
    ///   - workingDirectory: The project root directory
    ///   - fileExists: Whether the file exists on disk (affects the prompt)
    ///   - fileName: The name of the file being edited
    func start(filePath: String, workingDirectory: URL, fileExists: Bool, fileName: String) {
        guard !isRunning else {
            Self.logger.warning("Claude terminal session already running")
            return
        }

        Self.logger.info("Starting Claude terminal for \(fileName) at \(workingDirectory.path)")

        let settings = SettingsManager.shared
        guard settings.isClaudeConfigDirValid else {
            Self.logger.error("Claude config directory not found: \(settings.resolvedClaudeConfigPath)")
            configError = "Claude config directory not found at \(settings.resolvedClaudeConfigPath)\n\nPlease set CLAUDE_CONFIG_DIR in Settings (\u{2318},) under \"Claude Code\"."
            return
        }

        configError = nil

        // Build arguments and determine initial prompt for interactive sessions
        var arguments = ["claude"]
        var initialInput: String? = nil

        guard let projectDir = Self.projectDirectory(from: workingDirectory) else {
            Self.logger.error("Could not find project directory from \(workingDirectory.path)")
            configError = "Could not find project directory containing prd.md"
            return
        }

        do {
            if fileExists {
                // Interactive mode: launch bare claude, send context as first user message
                let editPrompt = try TemplateManager.buildEditPrompt(
                    filePath: filePath, fileName: fileName, projectDirectoryURL: projectDir
                )
                initialInput = editPrompt + "\n"
            } else {
                // Generation mode: use -p for one-shot execution
                let prompt = try TemplateManager.buildCreatePrompt(
                    filePath: filePath, fileName: fileName, projectDirectoryURL: projectDir
                )
                arguments += ["-p", prompt]
            }
        } catch {
            Self.logger.error("Template rendering failed: \(error.localizedDescription)")
            configError = "Template error: \(error.localizedDescription)"
            return
        }

        let session = SessionConfig(
            executable: "/usr/bin/env",
            arguments: arguments,
            environment: Self.processEnvironment(),
            workingDirectory: workingDirectory.path,
            initialInput: initialInput
        )

        isRunning = true
        hasSessionHistory = true
        activeSession = session
    }

    /// Called by the SwiftTerminalView coordinator when the process terminates.
    func processDidTerminate(exitCode: Int32?) {
        Self.logger.info("Claude terminal session ended (exit code: \(exitCode.map { String($0) } ?? "nil"))")
        DispatchQueue.main.async { [weak self] in
            self?.isRunning = false
        }
    }

    /// Terminates the current Claude session.
    func terminate() {
        guard isRunning else {
            activeSession = nil
            return
        }
        Self.logger.info("Terminating Claude terminal session")

        if let tv = terminalView {
            // Send Ctrl+C to interrupt the running process
            tv.send([0x03])
        }

        // Force mark as stopped after timeout if process hasn't exited
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self, self.isRunning else { return }
            Self.logger.warning("Force-stopping Claude terminal session after timeout")
            self.isRunning = false
        }

        activeSession = nil
    }

    /// Derives the project's ridl directory from the working directory.
    private static func projectDirectory(from workingDirectory: URL) -> URL? {
        let ridlDir = workingDirectory.appendingPathComponent("ridl")
        if FileManager.default.fileExists(atPath: ridlDir.appendingPathComponent("prd.md").path) {
            return ridlDir
        }
        if FileManager.default.fileExists(atPath: workingDirectory.appendingPathComponent("prd.md").path) {
            return workingDirectory
        }
        return nil
    }

    /// Returns a process environment with an expanded PATH that includes
    /// common user binary directories where `claude` may be installed.
    static func processEnvironment() -> [String: String] {
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

        // Tell the child process it's running in a color-capable terminal
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"

        return env
    }

    deinit {
        terminate()
    }
}
