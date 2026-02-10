import Foundation
import Combine

protocol ProcessManaging {
    /// Spawns a Claude Code subprocess with the given prompt, working in the specified directory.
    /// Returns a publisher that streams stdout lines in real-time.
    func spawn(prompt: String, workingDirectory: URL, logFileURL: URL) throws -> AnyPublisher<String, Never>

    /// Kills the currently running subprocess.
    func kill()

    /// Whether a subprocess is currently running.
    var isRunning: Bool { get }

    /// The PID of the current subprocess, or nil if none is running.
    var processIdentifier: Int32? { get }

    /// Publisher that emits the process exit result when the process terminates.
    var exitPublisher: AnyPublisher<ProcessExitResult, Never> { get }
}

struct ProcessExitResult: Equatable {
    let exitCode: Int32
    let stderr: String
    let command: String
}
