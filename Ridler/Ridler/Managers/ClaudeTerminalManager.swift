import Foundation
import Combine
import os

/// Manages an interactive Claude Code session for PRD editing.
/// Uses a pseudo-terminal (PTY) to provide proper terminal I/O.
final class ClaudeTerminalManager: ObservableObject {
    private static let logger = Logger(subsystem: "com.amattn.Ridler", category: "ClaudeTerminal")

    @Published var outputText: String = ""
    @Published var isRunning: Bool = false

    private var process: Process?
    private var primaryFD: Int32 = -1
    private var replicaFD: Int32 = -1
    private var readSource: DispatchSourceRead?

    private let outputQueue = DispatchQueue(label: "com.amattn.Ridler.ClaudeTerminal.output", qos: .userInitiated)

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

        outputText = ""

        // Create pseudo-terminal pair
        var primary: Int32 = 0
        var replica: Int32 = 0
        guard openpty(&primary, &replica, nil, nil, nil) == 0 else {
            Self.logger.error("Failed to create pseudo-terminal")
            outputText = "Error: Failed to create pseudo-terminal\n"
            return
        }
        self.primaryFD = primary
        self.replicaFD = replica

        // Build arguments
        var arguments = ["claude"]
        if fileExists {
            arguments += ["-p", "I want to edit the PRD file at: \(filePath)\n\nPlease read the file and help me modify it. Show me the current contents first."]
        } else {
            let prompt: String
            switch fileName {
            case "ridl.md":
                prompt = "The file \(filePath) does not exist yet. Please create ridl.md from the existing prd.md in the same directory. Read prd.md first, then create ridl.md with user stories and acceptance criteria."
            case "ridl.json":
                prompt = "The file \(filePath) does not exist yet. Please create ridl.json from the existing ridl.md or prd.md in the same directory. Read the existing files first, then create ridl.json in the proper format."
            default:
                prompt = "The file \(filePath) does not exist yet. Please create it with appropriate initial content."
            }
            arguments += ["-p", prompt]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.standardInput = FileHandle(fileDescriptor: replica, closeOnDealloc: false)
        process.standardOutput = FileHandle(fileDescriptor: replica, closeOnDealloc: false)
        process.standardError = FileHandle(fileDescriptor: replica, closeOnDealloc: false)

        // Set up reading from the primary side of the PTY
        let source = DispatchSource.makeReadSource(fileDescriptor: primary, queue: outputQueue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(primary, &buffer, buffer.count)
            if bytesRead > 0 {
                if let text = String(bytes: buffer[0..<bytesRead], encoding: .utf8) {
                    DispatchQueue.main.async {
                        self.outputText += text
                        // Cap output at 500KB to prevent memory issues
                        if self.outputText.count > 500_000 {
                            let startIndex = self.outputText.index(self.outputText.endIndex, offsetBy: -400_000)
                            self.outputText = String(self.outputText[startIndex...])
                        }
                    }
                }
            }
        }
        source.setCancelHandler {
            close(primary)
        }
        source.resume()
        self.readSource = source

        // Handle termination
        process.terminationHandler = { [weak self] proc in
            Self.logger.info("Claude terminal session ended (exit code: \(proc.terminationStatus))")
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.cleanup()
            }
        }

        do {
            try process.run()
            self.process = process
            self.isRunning = true
            Self.logger.info("Claude terminal session started (PID: \(process.processIdentifier))")
        } catch {
            Self.logger.error("Failed to start Claude terminal: \(error.localizedDescription)")
            outputText = "Error: Failed to start Claude Code: \(error.localizedDescription)\n"
            cleanup()
        }
    }

    /// Sends input text to the running Claude session.
    func sendInput(_ text: String) {
        guard isRunning, primaryFD >= 0 else { return }
        if let data = text.data(using: .utf8) {
            data.withUnsafeBytes { buffer in
                if let baseAddress = buffer.baseAddress {
                    _ = write(primaryFD, baseAddress, buffer.count)
                }
            }
        }
    }

    /// Terminates the current Claude session.
    func terminate() {
        guard let process, process.isRunning else {
            isRunning = false
            cleanup()
            return
        }
        Self.logger.info("Terminating Claude terminal session (PID: \(process.processIdentifier))")
        process.terminate()
        // Force kill after 2 seconds if needed
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if self?.process?.isRunning == true {
                self?.process?.interrupt()
            }
        }
    }

    private func cleanup() {
        readSource?.cancel()
        readSource = nil

        if replicaFD >= 0 {
            close(replicaFD)
            replicaFD = -1
        }
        // primaryFD is closed by the dispatch source cancel handler
        primaryFD = -1
        process = nil
    }

    deinit {
        terminate()
    }
}
