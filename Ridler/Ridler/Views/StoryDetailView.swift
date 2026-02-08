import SwiftUI

struct StoryDetailView: View {
    let story: UserStory?
    var loopState: LoopState = .ready
    var lastErrorMessage: String?

    var body: some View {
        if let story {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Title
                    Text(story.title)
                        .font(.title2)
                        .fontWeight(.bold)

                    // Status and priority
                    HStack(spacing: 12) {
                        Label(story.passes ? "Passed" : (story.inProgress ? "In Progress" : "Pending"),
                              systemImage: story.passes ? "checkmark.circle.fill" : (story.inProgress ? "arrow.triangle.2.circlepath.circle.fill" : "circle"))
                            .foregroundStyle(story.passes ? .green : (story.inProgress ? .cyan : .gray))
                            .font(.subheadline)

                        Text("Priority: \(story.priority)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Error details
                    if loopState == .error {
                        errorSection
                    }

                    Divider()

                    // Description
                    Text("Description")
                        .font(.headline)
                    Text(story.description)
                        .font(.body)

                    Divider()

                    // Acceptance Criteria
                    Text("Acceptance Criteria")
                        .font(.headline)
                    ForEach(story.acceptanceCriteria, id: \.self) { criterion in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\u{2022}")
                            Text(criterion)
                                .font(.body)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView("No Story Selected",
                                   systemImage: "doc.text",
                                   description: Text("Select a story from the list to view its details."))
        }
    }

    // MARK: - Error Section

    private var errorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Error", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)

            if let errorMessage = lastErrorMessage {
                Text(errorMessage)
                    .font(.body)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            Label("Check claude.log in the PRD directory for more details.",
                  systemImage: "doc.text.magnifyingglass")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
