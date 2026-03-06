import MarkdownUI
import SwiftUI

struct DetailView: View {
    let project: PRDProject?
    let selection: SidebarSelection?

    var body: some View {
        Group {
            if let selection, let project {
                switch selection {
                case .story(let storyID):
                    if let story = project.iterationDefinitions.first(where: { $0.id == storyID }) {
                        storyDetailView(story: story, project: project)
                    } else {
                        placeholderView
                    }
                case .file(let fileName):
                    fileContentView(fileName: fileName, project: project)
                case .promptTemplate(let name):
                    templateContentView(name: name, project: project)
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

    private func storyDetailView(story: IterationDefinition, project: PRDProject) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                Text(story.userStoryTitle)
                    .font(.title2)
                    .fontWeight(.bold)

                // Status badge and priority
                HStack(spacing: 12) {
                    statusBadge(for: story)
                    priorityBadge(priority: story.priority)
                }

                Divider()

                // Description
                Text(story.userStoryDescription)
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

                // PRD References
                if let refs = story.prdReferences, !refs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PRD References")
                            .font(.headline)

                        ForEach(refs, id: \.self) { ref in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\u{2022}")
                                    .foregroundStyle(.secondary)
                                Text(ref)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                // Notes
                if let notes = story.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.headline)

                        Text(notes)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
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

    private func fileContentView(fileName: PRDFileName, project: PRDProject) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: fileName.icon)
                    .foregroundStyle(.secondary)
                Text(fileName.rawValue)
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Content
            if let directoryURL = project.directoryURL {
                let fileURL = directoryURL.appendingPathComponent(fileName.rawValue)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    fileContentBody(fileName: fileName, fileURL: fileURL)
                } else {
                    emptyFileView(fileName: fileName)
                }
            } else {
                emptyFileView(fileName: fileName)
            }
        }
    }

    private func templateContentView(name: String, project: PRDProject) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "doc.text.below.ecg")
                    .foregroundStyle(.orange)
                Text(name)
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if let dirURL = project.directoryURL {
                let templateURL = dirURL.appendingPathComponent("prompts").appendingPathComponent(name)
                if let content = try? String(contentsOf: templateURL, encoding: .utf8), !content.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        templateErrorBanner(content: content, fileName: name)

                        ScrollView {
                            Text(content)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "doc")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("Template file not found")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func templateErrorBanner(content: String, fileName: String) -> some View {
        if let error = TemplateManager.validateTemplate(content: content, fileName: fileName) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Template Error")
                        .font(.system(size: 12, weight: .semibold))
                    Text(error.message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(10)
            .background(Color.red.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
            )
            .cornerRadius(6)
            .padding()
        }
    }

    private func fileContentBody(fileName: PRDFileName, fileURL: URL) -> some View {
        ScrollView {
            Group {
                switch fileName {
                case .prdMd, .ridlMd:
                    markdownView(fileURL: fileURL)
                case .ridlJson:
                    jsonView(fileURL: fileURL)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func markdownView(fileURL: URL) -> some View {
        Group {
            if let content = try? String(contentsOf: fileURL, encoding: .utf8), !content.isEmpty {
                Markdown(content)
                    .textSelection(.enabled)
            } else {
                Text("File is empty")
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
    }

    private func jsonView(fileURL: URL) -> some View {
        Group {
            if let data = try? Data(contentsOf: fileURL),
               let jsonObject = try? JSONSerialization.jsonObject(with: data),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                Text(prettyString)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let content = try? String(contentsOf: fileURL, encoding: .utf8), !content.isEmpty {
                Text(content)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("File is empty")
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
    }

    private func emptyFileView(fileName: PRDFileName) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "doc")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("\(fileName.rawValue) does not exist yet")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statusBadge(for story: IterationDefinition) -> some View {
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
            Text("An error occurred during execution. Check the log panel for details, or review ridler.log in the PRD directory for the full output.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statusIcon(for story: IterationDefinition) -> String {
        if story.passes {
            return "checkmark.circle.fill"
        } else if story.inProgress {
            return "circle.inset.filled"
        } else {
            return "circle"
        }
    }

    private func statusColor(for story: IterationDefinition) -> Color {
        if story.passes {
            return .green
        } else if story.inProgress {
            return .cyan
        } else {
            return .secondary
        }
    }

    private func statusText(for story: IterationDefinition) -> String {
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
