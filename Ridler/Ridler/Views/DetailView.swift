import SwiftUI

struct DetailView: View {
    let project: PRDProject?
    let selection: SidebarSelection?

    var body: some View {
        Group {
            if let selection, let project {
                switch selection {
                case .story(let storyID):
                    if let story = project.userStories.first(where: { $0.id == storyID }) {
                        storyDetailView(story: story, project: project)
                    } else {
                        placeholderView
                    }
                case .file:
                    placeholderView
                }
            } else {
                placeholderView
            }
        }
        .frame(minWidth: 300)
    }

    private var placeholderView: some View {
        Text("Select a story or file to view details")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func storyDetailView(story: UserStory, project: PRDProject) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                Text(story.title)
                    .font(.title2)
                    .fontWeight(.bold)

                // Status badge and priority
                HStack(spacing: 12) {
                    statusBadge(for: story)
                    priorityBadge(priority: story.priority)
                }

                Divider()

                // Description
                Text(story.description)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                // Acceptance Criteria
                if !story.acceptanceCriteria.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Acceptance Criteria")
                            .font(.headline)

                        ForEach(story.acceptanceCriteria, id: \.self) { criterion in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\u{2022}")
                                    .foregroundStyle(.secondary)
                                Text(criterion)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                // Error details (when project is in error state)
                if project.loopState == .error {
                    errorSection
                }

                Spacer()
            }
            .padding()
        }
    }

    private func statusBadge(for story: UserStory) -> some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon(for: story))
                .foregroundStyle(statusColor(for: story))
            Text(statusText(for: story))
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor(for: story).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func priorityBadge(priority: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.up.arrow.down")
                .foregroundStyle(.secondary)
            Text("Priority \(priority)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var errorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Label("Error", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text("An error occurred during execution. Check the log panel for details, or review claude.log in the PRD directory for the full output.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statusIcon(for story: UserStory) -> String {
        if story.passes {
            return "checkmark.circle.fill"
        } else if story.inProgress {
            return "circle.inset.filled"
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
            return .secondary
        }
    }

    private func statusText(for story: UserStory) -> String {
        if story.passes {
            return "Passed"
        } else if story.inProgress {
            return "In Progress"
        } else {
            return "Pending"
        }
    }
}

#Preview {
    DetailView(project: nil, selection: nil)
}
