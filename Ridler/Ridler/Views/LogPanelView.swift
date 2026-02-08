import SwiftUI

struct LogPanelView: View {
    let logEntries: [LogEntry]

    var body: some View {
        if logEntries.isEmpty {
            ContentUnavailableView("No Log Output",
                                   systemImage: "text.alignleft",
                                   description: Text("Log output will appear here when the loop is running."))
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(logEntries) { entry in
                        LogEntryRowView(entry: entry)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
    }
}

struct LogEntryRowView: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 14)
                .font(.caption)

            Text(displayText)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
    }

    private var iconName: String {
        switch entry.type {
        case .assistantText:
            return "text.bubble"
        case .toolUse:
            return "wrench"
        case .toolResult:
            return "arrow.turn.down.right"
        case .error:
            return "exclamationmark.triangle.fill"
        case .system:
            return "info.circle"
        }
    }

    private var iconColor: Color {
        switch entry.type {
        case .assistantText:
            return .primary
        case .toolUse:
            return .blue
        case .toolResult:
            return .secondary
        case .error:
            return .red
        case .system:
            return .yellow
        }
    }

    private var displayText: String {
        switch entry.type {
        case .assistantText(let text):
            return text
        case .toolUse(let toolName, let input):
            return "[\(toolName)] \(input)"
        case .toolResult(let output):
            return output
        case .error(let message):
            return "Error: \(message)"
        case .system(let message):
            return message
        }
    }
}
