import SwiftUI

/// View that displays an interactive Claude Code terminal session for editing PRD files.
/// Shows in the right pane when a PRD file row is selected in the sidebar.
struct ClaudeTerminalView: View {
    let fileDisplayName: String
    let project: PRDProject?
    let isLoopRunning: Bool
    @ObservedObject var terminalManager: ClaudeTerminalManager
    let onStartSession: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if isLoopRunning {
                disabledState
            } else if let error = terminalManager.configError {
                errorState(error)
            } else if terminalManager.activeSession != nil {
                terminalContent
            } else {
                idleState
            }
        }
        .frame(minWidth: 250)
    }

    private var header: some View {
        HStack {
            Image(systemName: "terminal")
                .foregroundStyle(.cyan)
            Text("Claude Code \u{2014} \(fileDisplayName)")
                .font(.headline)

            Spacer()

            if terminalManager.isRunning {
                Button {
                    terminalManager.terminate()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var disabledState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "pause.circle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Pause the loop to edit this file")
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var idleState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "terminal")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Edit \(fileDisplayName) with Claude Code")
                .font(.body)
                .foregroundStyle(.secondary)

            Button {
                onStartSession()
            } label: {
                Label("Start Editing Session", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var terminalContent: some View {
        VStack(spacing: 0) {
            SwiftTerminalView(manager: terminalManager)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !terminalManager.isRunning {
                Divider()
                HStack {
                    Spacer()
                    Button {
                        onStartSession()
                    } label: {
                        Label("Start New Session", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
    }
}
