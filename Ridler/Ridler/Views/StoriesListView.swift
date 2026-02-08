import SwiftUI

struct StoriesListView: View {
    let stories: [UserStory]
    @Binding var selectedStoryId: String?

    var body: some View {
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
    }

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
