import SwiftUI

struct StoryDetailView: View {
    let story: UserStory?

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
}
