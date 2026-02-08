import SwiftUI

struct LogPanelView: View {
    let logEntries: [LogEntry]

    @State private var autoScrollEnabled = true
    @State private var scrollViewHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            if logEntries.isEmpty {
                ContentUnavailableView("No Log Output",
                                       systemImage: "text.alignleft",
                                       description: Text("Log output will appear here when the loop is running."))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(logEntries) { entry in
                                LogEntryRowView(entry: entry)
                            }
                            // Invisible anchor at bottom for scroll-to
                            Color.clear
                                .frame(height: 1)
                                .id("log-bottom-anchor")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            GeometryReader { contentGeo in
                                Color.clear
                                    .onAppear {
                                        contentHeight = contentGeo.size.height
                                    }
                                    .onChange(of: contentGeo.size.height) { _, newHeight in
                                        contentHeight = newHeight
                                    }
                                    .onChange(of: contentGeo.frame(in: .named("logScroll")).minY) { _, newMinY in
                                        // minY is 0 when at top, negative when scrolled down
                                        scrollOffset = -newMinY
                                        let distanceFromBottom = contentHeight - scrollOffset - scrollViewHeight
                                        if distanceFromBottom > 40 {
                                            autoScrollEnabled = false
                                        } else if distanceFromBottom <= 20 {
                                            autoScrollEnabled = true
                                        }
                                    }
                            }
                        )
                    }
                    .coordinateSpace(name: "logScroll")
                    .background(
                        GeometryReader { scrollGeo in
                            Color.clear
                                .onAppear {
                                    scrollViewHeight = scrollGeo.size.height
                                }
                                .onChange(of: scrollGeo.size.height) { _, newHeight in
                                    scrollViewHeight = newHeight
                                }
                        }
                    )
                    .onChange(of: logEntries.count) { oldCount, newCount in
                        if autoScrollEnabled && newCount > oldCount {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo("log-bottom-anchor", anchor: .bottom)
                            }
                        }
                    }
                }

                // Auto-scroll indicator bar
                autoScrollIndicator
            }
        }
    }

    // MARK: - Auto-Scroll Indicator

    private var autoScrollIndicator: some View {
        HStack(spacing: 4) {
            Spacer()
            Image(systemName: autoScrollEnabled ? "arrow.down.to.line" : "hand.raised")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(autoScrollEnabled ? "Auto-scroll" : "Manual scroll")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 3)
        .background(.bar)
        .contentShape(Rectangle())
        .onTapGesture {
            autoScrollEnabled.toggle()
        }
    }
}

// MARK: - Log Entry Row

struct LogEntryRowView: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 14)
                .font(.caption)

            displayContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private var displayContent: some View {
        switch entry.type {
        case .assistantText(let text):
            if CodeHighlighter.containsCodeBlock(text) {
                highlightedTextView(text)
            } else {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        default:
            Text(displayText)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func highlightedTextView(_ text: String) -> some View {
        let segments = CodeHighlighter.parseSegments(text)
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(segments.enumerated()), id: \.offset) { item in
                segmentView(item.element)
            }
        }
    }

    @ViewBuilder
    private func segmentView(_ segment: TextSegment) -> some View {
        switch segment {
        case .plain(let plainText):
            Text(plainText)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: 2) {
                if !language.isEmpty {
                    Text(language)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.top, 4)
                }
                Text(CodeHighlighter.highlight(code: code, language: language))
                    .textSelection(.enabled)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.2))
            .cornerRadius(4)
        }
    }

    private var iconName: String {
        switch entry.type {
        case .assistantText:
            return "text.bubble"
        case .toolUse(let toolName, _):
            return toolIconName(for: toolName)
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

    /// Returns a tool-specific SF Symbol name based on the Claude Code tool name.
    private func toolIconName(for toolName: String) -> String {
        switch toolName.lowercased() {
        case "read":
            return "doc.text"
        case "edit":
            return "pencil"
        case "write":
            return "square.and.pencil"
        case "bash":
            return "terminal"
        case "glob":
            return "doc.text.magnifyingglass"
        case "grep":
            return "magnifyingglass"
        case "todowrite":
            return "checklist"
        case "task":
            return "arrow.triangle.branch"
        case "webfetch":
            return "globe"
        case "websearch":
            return "magnifyingglass.circle"
        case "notebookedit":
            return "book"
        default:
            return "wrench"
        }
    }
}
