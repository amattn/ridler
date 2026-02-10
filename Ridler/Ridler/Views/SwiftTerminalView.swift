import SwiftUI
import SwiftTerm
import AppKit

/// NSViewRepresentable wrapper around SwiftTerm's LocalProcessTerminalView.
/// Provides real VT100/xterm terminal emulation for embedded Claude Code sessions.
struct SwiftTerminalView: NSViewRepresentable {
    @ObservedObject var manager: ClaudeTerminalManager

    func makeCoordinator() -> Coordinator {
        Coordinator(manager: manager)
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()

        // Create or reuse the persistent terminal view
        if manager.terminalView == nil {
            let tv = LocalProcessTerminalView(frame: .zero)
            tv.processDelegate = context.coordinator
            tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            tv.configureNativeColors()
            manager.terminalView = tv
        }

        if let tv = manager.terminalView {
            tv.processDelegate = context.coordinator
            tv.removeFromSuperview()
            tv.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(tv)
            NSLayoutConstraint.activate([
                tv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                tv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                tv.topAnchor.constraint(equalTo: container.topAnchor),
                tv.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }

        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        // Ensure the terminal view is attached to this container (handles sidebar re-navigation)
        if let tv = manager.terminalView, tv.superview !== container {
            tv.processDelegate = context.coordinator
            tv.removeFromSuperview()
            tv.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(tv)
            NSLayoutConstraint.activate([
                tv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                tv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                tv.topAnchor.constraint(equalTo: container.topAnchor),
                tv.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }

        // Detect session changes and start new processes
        let newSessionID = manager.activeSession?.id
        if newSessionID != context.coordinator.currentSessionID {
            if let session = manager.activeSession {
                context.coordinator.startSession(session)
            } else {
                context.coordinator.currentSessionID = nil
            }
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        let manager: ClaudeTerminalManager
        var currentSessionID: UUID?

        init(manager: ClaudeTerminalManager) {
            self.manager = manager
            super.init()
        }

        func startSession(_ session: ClaudeTerminalManager.SessionConfig) {
            // Create a fresh terminal view for the new session
            let tv = LocalProcessTerminalView(frame: .zero)
            tv.processDelegate = self
            tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            tv.configureNativeColors()

            // Replace the old terminal view in the manager
            let oldTV = manager.terminalView
            manager.terminalView = tv

            // Swap in the container if the old view was attached
            if let parent = oldTV?.superview {
                oldTV?.removeFromSuperview()
                tv.translatesAutoresizingMaskIntoConstraints = false
                parent.addSubview(tv)
                NSLayoutConstraint.activate([
                    tv.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
                    tv.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
                    tv.topAnchor.constraint(equalTo: parent.topAnchor),
                    tv.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
                ])
            }

            // Convert environment dictionary to ["KEY=VALUE"] array format (SwiftTerm API)
            let envArray = session.environment.map { "\($0.key)=\($0.value)" }

            tv.startProcess(
                executable: session.executable,
                args: session.arguments,
                environment: envArray,
                execName: "claude",
                currentDirectory: session.workingDirectory
            )

            currentSessionID = session.id

            // For interactive sessions, send initial context after claude starts up
            if let initialInput = session.initialInput {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak tv] in
                    guard let tv else { return }
                    tv.send(txt: initialInput)
                }
            }
        }

        // MARK: - LocalProcessTerminalViewDelegate

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            DispatchQueue.main.async { [weak self] in
                self?.manager.processDidTerminate(exitCode: exitCode)
            }
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            // No-op: not needed for Claude Code sessions
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
            // No-op: terminal handles resizing internally
        }

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            // No-op: title is managed by the parent view
        }
    }
}
