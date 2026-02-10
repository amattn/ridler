import SwiftUI

struct DebugInfoView: View {
    let projects: [PRDProject]
    let loopEngines: [String: RalphLoopEngine]
    let fileWatcher: ProjectFileWatcher

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Debug Info")
                    .font(.title2.bold())

                memorySection

                ForEach(projects) { project in
                    projectSection(project)
                }

                fileWatcherSection
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    // MARK: - Memory Section

    private var memorySection: some View {
        GroupBox("Memory") {
            HStack {
                Text("App Memory Usage:")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formattedMemoryUsage)
                    .monospacedDigit()
            }
            .padding(.vertical, 2)
        }
    }

    private var formattedMemoryUsage: String {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let mb = Double(info.resident_size) / (1024 * 1024)
            return String(format: "%.1f MB", mb)
        }
        return "N/A"
    }

    // MARK: - Project Section

    private func projectSection(_ project: PRDProject) -> some View {
        GroupBox(project.name ?? project.id) {
            VStack(alignment: .leading, spacing: 6) {
                debugRow("Loop State", value: "\(project.loopState)")
                debugRow("Iteration Count", value: "\(project.iterationCount)")
                debugRow("Max Iterations", value: "\(project.maxIterations > 0 ? "\(project.maxIterations)" : "\(project.defaultMaxIterations) (default)")")

                if let engine = loopEngines[project.id] {
                    debugRow("Engine Retry Count", value: "\(engine.currentRetryCount)")
                    debugRow("Active Process PID", value: engine.activeProcessPID.map { "\($0)" } ?? "None")
                    debugRow("Last Error", value: engine.lastErrorMessage ?? "None")
                } else {
                    debugRow("Engine", value: "Not created")
                    debugRow("Active Process PID", value: "None")
                    debugRow("Last Error", value: "None")
                }

                if let startDate = project.loopStartDate {
                    debugRow("Loop Start", value: startDate.formatted(.dateTime))
                }

                let passCount = project.userStories.filter { $0.passes }.count
                debugRow("Stories", value: "\(passCount)/\(project.userStories.count) passed")

                if let currentStory = project.userStories.first(where: { $0.inProgress }) {
                    debugRow("Current Story", value: "\(currentStory.id) — \(currentStory.title)")
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - File Watcher Section

    private var fileWatcherSection: some View {
        GroupBox("File Watcher") {
            VStack(alignment: .leading, spacing: 6) {
                debugRow("Watched Directories", value: "\(fileWatcher.watchedCount)")
                debugRow("Change Token", value: fileWatcher.changeToken.uuidString.prefix(8).description)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Helpers

    private func debugRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .trailing)
            Text(value)
                .monospacedDigit()
                .textSelection(.enabled)
            Spacer()
        }
    }
}
