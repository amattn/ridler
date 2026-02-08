import SwiftUI
import UniformTypeIdentifiers

@main
struct RidlerApp: App {
    @State private var prdManager = PRDManager()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView(prdManager: prdManager)
        }
        .defaultSize(width: 1200, height: 700)
        .commands {
            // MARK: - File Menu
            CommandGroup(replacing: .newItem) {
                Button("New PRD...") {
                    prdManager.showNewPRDSheet = true
                }
                .keyboardShortcut("n")

                Button("Open PRD...") {
                    prdManager.openFilePanel()
                }
                .keyboardShortcut("o")

                Divider()

                Button("Edit PRD") {
                    guard let tabId = prdManager.selectedTabId else { return }
                    prdManager.editPRD(tabId: tabId)
                }
                .keyboardShortcut("e")
                .disabled(prdManager.selectedTab == nil)

                Divider()

                Button("Close Tab") {
                    guard let tabId = prdManager.selectedTabId else { return }
                    prdManager.requestCloseTab(id: tabId)
                }
                .keyboardShortcut("w")
                .disabled(prdManager.selectedTab == nil)
            }

            CommandGroup(after: .newItem) {
                if !prdManager.recentFiles.isEmpty {
                    Menu("Open Recent") {
                        ForEach(prdManager.recentFiles, id: \.self) { path in
                            Button(recentFileLabel(for: path)) {
                                do {
                                    try prdManager.openPRD(filePath: path)
                                } catch {
                                    prdManager.openErrorMessage = error.localizedDescription
                                    prdManager.showOpenError = true
                                }
                            }
                        }
                        Divider()
                        Button("Clear Menu") {
                            prdManager.clearRecentFiles()
                        }
                    }
                }
            }

            // MARK: - View Menu
            CommandGroup(after: .toolbar) {
                Button("Focus Log Panel") {
                    prdManager.focusLogPanelRequested = true
                }
                .keyboardShortcut("l")
                .disabled(prdManager.selectedTab == nil)
            }

            // MARK: - Window Menu
            CommandGroup(before: .windowList) {
                Button("Debug Info") {
                    openWindow(id: "debug-info")
                }
                .disabled(!SettingsManager.shared.debugMode)
            }

            // MARK: - PRD Menu
            CommandMenu("PRD") {
                Button("Start / Resume") {
                    guard let tabId = prdManager.selectedTabId else { return }
                    Task {
                        await prdManager.checkBranchAndStart(tabId: tabId)
                    }
                }
                .keyboardShortcut("r")
                .disabled(!canStartSelectedPRD)

                Button("Start / Resume") {
                    guard let tabId = prdManager.selectedTabId else { return }
                    Task {
                        await prdManager.checkBranchAndStart(tabId: tabId)
                    }
                }
                .keyboardShortcut(.return)
                .disabled(!canStartSelectedPRD)

                Button("Pause") {
                    guard let tabId = prdManager.selectedTabId else { return }
                    prdManager.pause(tabId: tabId)
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(selectedLoopState != .running)

                Button("Stop") {
                    guard let tabId = prdManager.selectedTabId else { return }
                    prdManager.stop(tabId: tabId)
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])
                .disabled(selectedLoopState != .running && selectedLoopState != .paused)

                Divider()

                // Tab switching: Cmd+1 through Cmd+9
                ForEach(0..<min(prdManager.tabs.count, 9), id: \.self) { index in
                    Button(prdManager.tabs[index].name) {
                        prdManager.selectedTabId = prdManager.tabs[index].id
                        prdManager.selectedStoryId = nil
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }
        }

        Window("Debug Info", id: "debug-info") {
            DebugWindowView(prdManager: prdManager)
        }
        .defaultSize(width: 500, height: 400)

        Settings {
            SettingsView()
        }
    }

    // MARK: - Helpers

    private var selectedLoopState: LoopState {
        guard let tabId = prdManager.selectedTabId else { return .ready }
        return prdManager.loopState(for: tabId)
    }

    private var canStartSelectedPRD: Bool {
        guard prdManager.selectedTab != nil else { return false }
        let state = selectedLoopState
        return state == .ready || state == .paused || state == .stopped || state == .error
    }

    private func recentFileLabel(for path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent().lastPathComponent
        return "\(dir)/\(url.lastPathComponent)"
    }
}
