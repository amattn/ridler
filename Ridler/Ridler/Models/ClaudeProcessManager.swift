import Foundation

enum ClaudeProcessError: Error, LocalizedError {
    case processNotRunning
    case processAlreadyRunning
    case processFailedWithExitCode(Int32)
    case executableNotFound(String)

    var errorDescription: String? {
        switch self {
        case .processNotRunning:
            return "No Claude process is currently running"
        case .processAlreadyRunning:
            return "A Claude process is already running"
        case .processFailedWithExitCode(let code):
            return "Claude process exited with code \(code)"
        case .executableNotFound(let path):
            return "Claude executable not found at: \(path)"
        }
    }
}

struct ClaudeProcessResult {
    let exitCode: Int32
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

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        lock.lock()
        self.process = proc
        lock.unlock()

        let fileHandle = pipe.fileHandleForReading
        let lineBuffer = LineBuffer()

        fileHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            guard let text = String(data: data, encoding: .utf8) else { return }
            lineBuffer.append(text, emitLine: onOutput)
        }

        return try await withCheckedThrowingContinuation { continuation in
            proc.terminationHandler = { [weak self] process in
                fileHandle.readabilityHandler = nil
                lineBuffer.flush(emitLine: onOutput)
                self?.lock.lock()
                self?.process = nil
                self?.lock.unlock()
                continuation.resume(returning: ClaudeProcessResult(exitCode: process.terminationStatus))
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
            throw ClaudeProcessError.processAlreadyRunning
        }

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
                throw ClaudeProcessError.processFailedWithExitCode(result.exitCode)
            }

            return result
        } catch {
            await MainActor.run {
                self.isRunning = false
            }
            throw error
        }
    }

    func cancel() {
        spawner.terminate()
    }
}
