import SwiftUI
import Darwin

struct DebugWindowView: View {
    @Bindable var prdManager: PRDManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: - App Memory Usage
                Section {
                    LabeledContent("Resident Size") {
                        Text(formattedMemoryUsage)
                            .monospacedDigit()
                    }
                } header: {
                    Text("Memory")
                        .font(.headline)
                }

                Divider()

                // MARK: - File Watcher
                Section {
                    if prdManager.fileWatcherDirectories.isEmpty {
                        Text("None")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(prdManager.fileWatcherDirectories, id: \.self) { dir in
                            Text(dir)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                } header: {
                    Text("File Watcher — Watched Directories")
                        .font(.headline)
                }

                Divider()

                // MARK: - PRD Tabs
                Section {
                    if prdManager.tabs.isEmpty {
                        Text("No PRDs open")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(prdManager.tabs) { tab in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tab.name)
                                    .font(.headline)

                                let state = prdManager.loopState(for: tab.id)
                                let iteration = prdManager.iterationCount(for: tab.id)
                                let engine = prdManager.engines[tab.id]
                                let pid = engine?.processManager.processIdentifier
                                let lastError = lastErrorMessage(for: tab.id)

                                LabeledContent("Loop State") {
                                    Text(state.label)
                                        .foregroundStyle(state.color)
                                }

                                LabeledContent("Iteration") {
                                    Text("\(iteration)")
                                        .monospacedDigit()
                                }

                                LabeledContent("Process PID") {
                                    if let pid {
                                        Text("\(pid)")
                                            .monospacedDigit()
                                    } else {
                                        Text("—")
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                LabeledContent("Last Error") {
                                    if let lastError {
                                        Text(lastError)
                                            .foregroundStyle(.red)
                                            .textSelection(.enabled)
                                    } else {
                                        Text("None")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)

                            if tab.id != prdManager.tabs.last?.id {
                                Divider()
                            }
                        }
                    }
                } header: {
                    Text("PRD Tabs")
                        .font(.headline)
                }
            }
            .padding()
        }
        .frame(minWidth: 450, minHeight: 350)
        .navigationTitle("Debug Info")
    }

    // MARK: - Helpers

    private var formattedMemoryUsage: String {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return "Unavailable" }
        let bytes = info.resident_size
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    private func lastErrorMessage(for tabId: String) -> String? {
        guard let engine = prdManager.engines[tabId] else { return nil }
        for entry in engine.logEntries.reversed() {
            if case .error(let msg) = entry.type {
                return msg
            }
        }
        return nil
    }
}
