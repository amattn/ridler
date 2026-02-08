import SwiftUI

struct StoriesListView: View {
    let stories: [UserStory]
    @Binding var selectedStoryId: String?
    var loopState: LoopState = .ready

    var body: some View {
        VStack(spacing: 0) {
            // Warning banner for interrupted stories
            if let interruptedStory = interruptedStory {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("\(interruptedStory.id) was interrupted")
                        .font(.caption)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.yellow.opacity(0.15))
            }

            List(stories, selection: $selectedStoryId) { story in
                HStack(spacing: 8) {
                    Image(systemName: statusIcon(for: story))
                        .foregroundStyle(statusColor(for: story))
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(story.id)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(story.title)
                            .font(.body)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 2)
            }
            .listStyle(.sidebar)

            // Progress bar
            progressBar
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        let passed = stories.filter { $0.passes }.count
        let total = stories.count
        let fraction = total > 0 ? Double(passed) / Double(total) : 0
        let percentage = Int(fraction * 100)

        return VStack(spacing: 4) {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)

            Text("\(percentage)% — \(passed)/\(total) stories")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Interrupted Story Detection

    /// Detects a story marked inProgress that isn't currently being worked on by a running loop.
    private var interruptedStory: UserStory? {
        guard loopState != .running else { return nil }
        return stories.first { $0.inProgress && !$0.passes }
    }

    // MARK: - Status Helpers

    private func statusIcon(for story: UserStory) -> String {
        if story.passes {
            return "checkmark.circle.fill"
        } else if story.inProgress {
            return "arrow.triangle.2.circlepath.circle.fill"
        } else {
            return "circle"
        }
    }

    private func statusColor(for story: UserStory) -> Color {
        if story.passes {
            return .green
        } else if story.inProgress {
            return .cyan
        } else {
            return .gray
        }
    }
}
