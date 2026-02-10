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

            contentView
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
    }

    @ViewBuilder
    private var contentView: some View {
        let segments = SyntaxHighlighter.parseSegments(entry.content)
        let hasCodeBlocks = segments.contains { if case .codeBlock = $0 { return true } else { return false } }

        if hasCodeBlocks {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .text(let text):
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(textColor)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    case .codeBlock(let language, let code):
                        HighlightedCodeView(code: code, language: language)
                    }
                }
            }
        } else {
            Text(entry.content)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
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

// MARK: - Highlighted Code View

private struct HighlightedCodeView: NSViewRepresentable {
    let code: String
    let language: String?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.black.withAlphaComponent(0.06)
        textView.textContainerInset = NSSize(width: 8, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0

        scrollView.documentView = textView

        let highlighted = SyntaxHighlighter.highlight(code: code, language: language)
        textView.textStorage?.setAttributedString(highlighted)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let highlighted = SyntaxHighlighter.highlight(code: code, language: language)
        textView.textStorage?.setAttributedString(highlighted)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let textView = nsView.documentView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return nil }

        let width = proposal.width ?? 300
        textContainer.containerSize = NSSize(width: max(width - 16, 50), height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)

        return CGSize(width: width, height: usedRect.height + 12) // 6pt top + 6pt bottom inset
    }
}

#Preview {
    LogPanelView(
        entries: [
            LogEntry(type: .system, content: "Starting iteration 1"),
            LogEntry(type: .system, content: "Working on: US-020 - Log view with streaming output"),
            LogEntry(type: .assistantText, content: "I'll implement the log view with streaming output.\n\n```swift\nfunc highlight(code: String) -> NSAttributedString {\n    let result = NSMutableAttributedString(string: code)\n    return result\n}\n```\n\nThat should work."),
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
