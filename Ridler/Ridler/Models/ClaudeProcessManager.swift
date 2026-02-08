import Foundation
import os

enum ClaudeProcessError: Error, LocalizedError {
    case processNotRunning
    case processAlreadyRunning
    case processFailedWithExitCode(Int32, stderr: String)
    case executableNotFound(String)

    var errorDescription: String? {
        switch self {
        case .processNotRunning:
            return "No Claude process is currently running"
        case .processAlreadyRunning:
            return "A Claude process is already running"
        case .processFailedWithExitCode(let code, let stderr):
            if stderr.isEmpty {
                return "Claude process exited with code \(code)"
            }
            return "Claude process exited with code \(code)\n\(stderr)"
        case .executableNotFound(let path):
            return "Claude executable not found at: \(path)"
        }
    }
}

struct ClaudeProcessResult {
    let exitCode: Int32
    let stderr: String
    var success: Bool { exitCode == 0 }
}

protocol ProcessSpawning: Sendable {
    func spawn(
        executablePath: String,
        arguments: [String],
        workingDirectory: String,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws -> ClaudeProcessResult
    func terminate()
    var processIdentifier: Int32? { get }
}

private final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""

    func append(_ text: String, emitLine: (String) -> Void) {
        lock.lock()
        buffer += text
        while let newlineIndex = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<newlineIndex])
            buffer = String(buffer[buffer.index(after: newlineIndex)...])
            lock.unlock()
            emitLine(line)
            lock.lock()
        }
        lock.unlock()
    }

    func flush(emitLine: (String) -> Void) {
        lock.lock()
        let remaining = buffer
        buffer = ""
        lock.unlock()
        if !remaining.isEmpty {
            emitLine(remaining)
        }
    }
}

private final class LockIsolatedValue<Value>: @unchecked Sendable {
    private var _value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        self._value = value
    }

    func withLock<T>(_ operation: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation(&_value)
    }
}

final class RealProcessSpawner: ProcessSpawning, @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func spawn(
        executablePath: String,
        arguments: [String],
        workingDirectory: String,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws -> ClaudeProcessResult {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executablePath)
        proc.arguments = arguments
        proc.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        lock.lock()
        self.process = proc
        lock.unlock()

        let fileHandle = stdoutPipe.fileHandleForReading
        let lineBuffer = LineBuffer()

        fileHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            guard let text = String(data: data, encoding: .utf8) else { return }
            lineBuffer.append(text, emitLine: onOutput)
        }

        let stderrCollector = LockIsolatedValue<String>("")
        let stderrHandle = stderrPipe.fileHandleForReading
        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            guard let text = String(data: data, encoding: .utf8) else { return }
            stderrCollector.withLock { $0 += text }
        }

        return try await withCheckedThrowingContinuation { continuation in
            proc.terminationHandler = { [weak self] process in
                fileHandle.readabilityHandler = nil
                stderrHandle.readabilityHandler = nil
                lineBuffer.flush(emitLine: onOutput)
                let stderrOutput = stderrCollector.withLock { $0 }.trimmingCharacters(in: .whitespacesAndNewlines)
                self?.lock.lock()
                self?.process = nil
                self?.lock.unlock()
                continuation.resume(returning: ClaudeProcessResult(exitCode: process.terminationStatus, stderr: stderrOutput))
            }

            do {
                try proc.run()
            } catch {
                self.lock.lock()
                self.process = nil
                self.lock.unlock()
                fileHandle.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    func terminate() {
        lock.lock()
        let proc = process
        lock.unlock()
        proc?.terminate()
    }

    var processIdentifier: Int32? {
        lock.lock()
        defer { lock.unlock() }
        return process?.processIdentifier
    }
}

@Observable
final class ClaudeProcessManager {
    private(set) var isRunning = false
    private(set) var outputLines: [String] = []

    private let spawner: ProcessSpawning
    private let claudePath: String

    init(spawner: ProcessSpawning = RealProcessSpawner(), claudePath: String = "/usr/local/bin/claude") {
        self.spawner = spawner
        self.claudePath = claudePath
    }

    func run(prompt: String, workingDirectory: String, onLine: (@Sendable (String) -> Void)? = nil) async throws -> ClaudeProcessResult {
        guard !isRunning else {
            RidlerLogger.process.error("Attempted to spawn Claude while already running")
            throw ClaudeProcessError.processAlreadyRunning
        }

        RidlerLogger.process.info("Spawning Claude process, workDir=\(workingDirectory, privacy: .public)")

        await MainActor.run {
            self.isRunning = true
            self.outputLines = []
        }

        do {
            let result = try await spawner.spawn(
                executablePath: claudePath,
                arguments: [
                    "--print",
                    "--dangerously-skip-permissions",
                    "--output-format", "stream-json",
                    prompt
                ],
                workingDirectory: workingDirectory,
                onOutput: { [weak self] line in
                    DispatchQueue.main.async {
                        self?.outputLines.append(line)
                    }
                    onLine?(line)
                }
            )

            await MainActor.run {
                self.isRunning = false
            }

            if !result.success {
                RidlerLogger.process.error("Claude process exited with code \(result.exitCode)")
                throw ClaudeProcessError.processFailedWithExitCode(result.exitCode, stderr: result.stderr)
            }

            RidlerLogger.process.info("Claude process completed successfully")
            return result
        } catch {
            await MainActor.run {
                self.isRunning = false
            }
            RidlerLogger.process.error("Claude process threw error: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func cancel() {
        RidlerLogger.process.info("Cancelling Claude process")
        spawner.terminate()
    }

    var processIdentifier: Int32? {
        spawner.processIdentifier
    }
}
