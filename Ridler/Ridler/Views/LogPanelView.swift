import SwiftUI

struct LogPanelView: View {
    let entries: [LogEntry]
    let isRunning: Bool

    @State private var autoScroll = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if entries.isEmpty {
                emptyState
            } else {
                logScrollView
            }
        }
        .frame(minWidth: 250)
    }

    private var header: some View {
        HStack {
            Text("Log")
                .font(.headline)

            Spacer()

            if !entries.isEmpty {
                autoScrollIndicator
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var autoScrollIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: autoScroll ? "arrow.down.to.line" : "hand.raised")
                .font(.system(size: 10))
            Text(autoScroll ? "Auto" : "Manual")
                .font(.system(size: 10))
        }
        .foregroundStyle(autoScroll ? .cyan : .secondary)
    }

    private var emptyState: some View {
        ScrollView {
            Text("No log output yet")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }

    private var logScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(entries) { entry in
                        LogEntryRow(entry: entry)
                            .id(entry.id)
                    }

                    // Bottom sentinel for scroll detection
                    Color.clear
                        .frame(height: 1)
                        .id("log-bottom")
                        .onAppear {
                            autoScroll = true
                        }
                        .onDisappear {
                            if isRunning {
                                autoScroll = false
                            }
                        }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: entries.count) { _, _ in
                if autoScroll {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("log-bottom", anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Log Entry Row

private struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            entryIcon
                .frame(width: 16, alignment: .center)

            Text(entry.content)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
    }

    private var entryIcon: some View {
        Image(systemName: iconName)
            .font(.system(size: 10))
            .foregroundStyle(iconColor)
    }

    private var iconName: String {
        switch entry.type {
        case .assistantText:
            return "bubble.left.fill"
        case .toolUse:
            return toolIcon
        case .toolResult:
            return "arrow.turn.down.left"
        case .error:
            return "exclamationmark.triangle.fill"
        case .system:
            return "info.circle.fill"
        }
    }

    private var toolIcon: String {
        let content = entry.content.lowercased()
        if content.hasPrefix("tool: bash") {
            return "terminal.fill"
        } else if content.hasPrefix("tool: read") {
            return "doc.text.fill"
        } else if content.hasPrefix("tool: edit") {
            return "pencil"
        } else if content.hasPrefix("tool: write") {
            return "square.and.pencil"
        } else if content.hasPrefix("tool: glob") {
            return "magnifyingglass"
        } else if content.hasPrefix("tool: grep") {
            return "text.magnifyingglass"
        } else if content.hasPrefix("tool: task") {
            return "list.bullet"
        } else if content.hasPrefix("tool: todowrite") {
            return "checklist"
        } else if content.hasPrefix("tool: webfetch") || content.hasPrefix("tool: websearch") {
            return "globe"
        } else {
            return "wrench.fill"
        }
    }

    private var iconColor: Color {
        switch entry.type {
        case .assistantText:
            return .cyan
        case .toolUse:
            return .purple
        case .toolResult:
            return .secondary
        case .error:
            return .red
        case .system:
            return .blue
        }
    }

    private var textColor: Color {
        switch entry.type {
        case .error:
            return .red
        case .system:
            return .blue
        default:
            return .primary
        }
    }

    private var backgroundColor: Color {
        switch entry.type {
        case .error:
            return .red.opacity(0.05)
        case .system:
            return .blue.opacity(0.05)
        default:
            return .clear
        }
    }
}

#Preview {
    LogPanelView(
        entries: [
            LogEntry(type: .system, content: "Starting iteration 1"),
            LogEntry(type: .system, content: "Working on: US-020 - Log view with streaming output"),
            LogEntry(type: .assistantText, content: "I'll implement the log view with streaming output."),
            LogEntry(type: .toolUse, content: "Tool: Read\nRidler/Ridler/Views/LogPanelView.swift"),
            LogEntry(type: .toolResult, content: "File contents..."),
            LogEntry(type: .toolUse, content: "Tool: Bash\n$ xcodebuild build"),
            LogEntry(type: .toolResult, content: "Build succeeded"),
            LogEntry(type: .error, content: "Test failed: testExample"),
            LogEntry(type: .system, content: "Story US-020 completed"),
        ],
        isRunning: true
    )
    .frame(width: 400, height: 500)
}
