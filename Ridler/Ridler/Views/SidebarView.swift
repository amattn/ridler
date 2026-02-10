import SwiftUI

struct SidebarView: View {
    let project: PRDProject?
    @Binding var selection: SidebarSelection?

    @State private var isFileSectionExpanded = true
    @State private var collapsedMilestones: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let project {
                fileBrowserSection(project: project)

                Divider()
                    .padding(.vertical, 8)

                storiesSection(project: project)
            } else {
                Text("No PRD loaded")
                    .foregroundStyle(.secondary)
                    .padding()
            }

            Spacer()

            if let project, !project.userStories.isEmpty {
                progressBar(project: project)
            }
        }
        .frame(minWidth: 200)
    }

    @ViewBuilder
    private func fileBrowserSection(project: PRDProject) -> some View {
        Button {
            withAnimation {
                isFileSectionExpanded.toggle()
            }
        } label: {
            HStack {
                Image(systemName: isFileSectionExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                Text("PRD Files")
                    .font(.headline)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.vertical, 8)

        if isFileSectionExpanded {
            ForEach(PRDFileName.allCases, id: \.self) { file in
                fileRow(file: file, project: project)
            }
        }
    }

    @ViewBuilder
    private func fileRow(file: PRDFileName, project: PRDProject) -> some View {
        let exists = fileExists(file, in: project)
        let isSelected = selection == .file(file)

        Button {
            selection = .file(file)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: file.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(exists ? .primary : .tertiary)
                    .frame(width: 18)

                Text(file.rawValue)
                    .font(.system(size: 13))
                    .foregroundStyle(exists ? .primary : .secondary)

                if !exists {
                    Text("(not yet created)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            .background(isSelected ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.3) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stories Section

    @ViewBuilder
    private func storiesSection(project: PRDProject) -> some View {
        if project.userStories.isEmpty {
            Text("No stories")
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        } else if let milestones = project.milestones, !milestones.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(milestones) { milestone in
                        milestoneGroup(milestone: milestone, project: project)
                    }

                    // Show ungrouped stories (not in any milestone)
                    let groupedIDs = Set(milestones.flatMap { $0.storyIDs })
                    let ungrouped = project.userStories.filter { !groupedIDs.contains($0.id) }
                    if !ungrouped.isEmpty {
                        ForEach(ungrouped) { story in
                            storyRow(story: story)
                        }
                    }
                }
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(project.userStories) { story in
                        storyRow(story: story)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func milestoneGroup(milestone: Milestone, project: PRDProject) -> some View {
        let stories = milestone.storyIDs.compactMap { id in
            project.userStories.first { $0.id == id }
        }
        let passedCount = stories.filter(\.passes).count
        let isCollapsed = collapsedMilestones.contains(milestone.name)

        Button {
            withAnimation {
                if isCollapsed {
                    collapsedMilestones.remove(milestone.name)
                } else {
                    collapsedMilestones.insert(milestone.name)
                }
            }
        } label: {
            HStack {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                Text(milestone.name)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(passedCount)/\(stories.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.vertical, 6)

        if !isCollapsed {
            ForEach(stories) { story in
                storyRow(story: story)
            }
        }
    }

    @ViewBuilder
    private func storyRow(story: UserStory) -> some View {
        let isSelected = selection == .story(story.id)

        Button {
            selection = .story(story.id)
        } label: {
            HStack(spacing: 8) {
                storyStatusIcon(story: story)
                    .frame(width: 18)

                Text(story.id)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(story.title)
                    .font(.system(size: 13))
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            .background(isSelected ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.3) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func storyStatusIcon(story: UserStory) -> some View {
        Group {
            if story.passes {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if story.inProgress {
                Image(systemName: "circle.inset.filled")
                    .foregroundStyle(.cyan)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 13))
    }

    // MARK: - Progress Bar

    private func progressBar(project: PRDProject) -> some View {
        let total = project.userStories.count
        let passed = project.userStories.filter(\.passes).count
        let fraction = total > 0 ? Double(passed) / Double(total) : 0
        let percentage = Int(fraction * 100)

        return VStack(spacing: 4) {
            Divider()
            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(nsColor: .separatorColor))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.green)
                            .frame(width: geo.size.width * fraction, height: 6)
                    }
                }
                .frame(height: 6)

                Text("\(percentage)%  \(passed)/\(total)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    // MARK: - File Helpers

    private func fileExists(_ file: PRDFileName, in project: PRDProject) -> Bool {
        guard let dirURL = project.directoryURL else { return false }
        let fileURL = dirURL.appendingPathComponent(file.rawValue)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
}

#Preview {
    SidebarView(project: nil, selection: .constant(nil))
}
