import SwiftUI

/// View that displays an interactive Claude Code terminal session for editing PRD files.
/// Shows in the right pane when a PRD file row is selected in the sidebar.
struct ClaudeTerminalView: View {
    let fileName: PRDFileName
    let project: PRDProject?
    let isLoopRunning: Bool
    @ObservedObject var terminalManager: ClaudeTerminalManager
    let onStartSession: (PRDFileName) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if isLoopRunning {
                disabledState
            } else if terminalManager.isRunning {
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
            Text("Claude Code — \(fileName.rawValue)")
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

    private var idleState: some View {
        VStack(spacing: 12) {
            Spacer()

            if !terminalManager.outputText.isEmpty {
                // Show previous session output
                TerminalOutputView(text: terminalManager.outputText)
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Edit \(fileName.rawValue) with Claude Code")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Button {
                onStartSession(fileName)
            } label: {
                Label(
                    terminalManager.outputText.isEmpty ? "Start Editing Session" : "Start New Session",
                    systemImage: "play.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var terminalContent: some View {
        VStack(spacing: 0) {
            TerminalOutputView(text: terminalManager.outputText)

            Divider()

            TerminalInputView { input in
                terminalManager.sendInput(input + "\n")
            }
        }
    }
}

// MARK: - Terminal Output View

/// Displays terminal output text with auto-scrolling.
private struct TerminalOutputView: View {
    let text: String
    @State private var autoScroll = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Strip ANSI escape codes for cleaner display
                Text(stripAnsiCodes(text))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)

                Color.clear
                    .frame(height: 1)
                    .id("terminal-bottom")
                    .onAppear { autoScroll = true }
                    .onDisappear { autoScroll = false }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: text) { _, _ in
                if autoScroll {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("terminal-bottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    private func stripAnsiCodes(_ text: String) -> String {
        // Remove ANSI escape sequences for terminal colors/formatting
        let pattern = "\u{1B}\\[[0-9;]*[a-zA-Z]"
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }
}

// MARK: - Terminal Input View

/// A text field for sending input to the terminal session.
private struct TerminalInputView: View {
    let onSubmit: (String) -> Void
    @State private var inputText = ""

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.cyan)

            TextField("Type a message...", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .onSubmit {
                    guard !inputText.isEmpty else { return }
                    onSubmit(inputText)
                    inputText = ""
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
