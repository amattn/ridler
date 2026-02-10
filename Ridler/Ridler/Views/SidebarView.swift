import SwiftUI

struct SidebarView: View {
    let project: PRDProject?
    @Binding var selection: SidebarSelection?

    @State private var isFileSectionExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let project {
                fileBrowserSection(project: project)

                Divider()
                    .padding(.vertical, 8)

                Section {
                    Text("Stories")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.vertical, 8)

                    Text("No stories")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
            } else {
                Text("No PRD loaded")
                    .foregroundStyle(.secondary)
                    .padding()
            }

            Spacer()
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

    private func fileExists(_ file: PRDFileName, in project: PRDProject) -> Bool {
        guard let dirURL = project.directoryURL else { return false }
        let fileURL = dirURL.appendingPathComponent(file.rawValue)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
}

#Preview {
    SidebarView(project: nil, selection: .constant(nil))
}
