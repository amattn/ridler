import SwiftUI

@main
struct RidlerApp: App {
    @FocusedValue(\.selectedProject) private var selectedProject: PRDProject?
    @FocusedValue(\.hasProject) private var hasProject: Bool?
    @StateObject private var recentProjects = RecentProjectsManager.shared
    @ObservedObject private var settings = SettingsManager.shared

    private var projectLoopState: LoopState {
        selectedProject?.loopState ?? .ready
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            // Settings (Cmd+,) is automatically provided by the Settings scene below

            // MARK: - File Menu
            CommandGroup(replacing: .newItem) {
                Button("New PRD...") {
                    NotificationCenter.default.post(name: .newPRD, object: nil)
                }
                .keyboardShortcut("n")

                Button("Open PRD...") {
                    NotificationCenter.default.post(name: .openPRD, object: nil)
                }
                .keyboardShortcut("o")

                Menu("Open Recent") {
                    ForEach(recentProjects.recentURLs, id: \.absoluteString) { url in
                        Button(url.lastPathComponent) {
                            NotificationCenter.default.post(name: .openRecentPRD, object: url)
                        }
                    }

                    if !recentProjects.recentURLs.isEmpty {
                        Divider()
                        Button("Clear Menu") {
                            recentProjects.clearRecents()
                        }
                    }
                }
                .disabled(recentProjects.recentURLs.isEmpty)
            }

            // MARK: - View Menu
            CommandGroup(after: .toolbar) {
                Button("Focus Log Panel") {
                    NotificationCenter.default.post(name: .focusLogPanel, object: nil)
                }
                .keyboardShortcut("l")
                .disabled(hasProject != true)
            }

            // MARK: - PRD Menu
            CommandMenu("PRD") {
                Button("Start/Resume Loop") {
                    NotificationCenter.default.post(name: .startLoop, object: nil)
                }
                .keyboardShortcut("r")
                .disabled(hasProject != true || !projectLoopState.canTransition(to: .running))

                Button("Start/Resume Loop") {
                    NotificationCenter.default.post(name: .startLoop, object: nil)
                }
                .keyboardShortcut(.return)
                .disabled(hasProject != true || !projectLoopState.canTransition(to: .running))

                Button("Pause Loop") {
                    NotificationCenter.default.post(name: .pauseLoop, object: nil)
                }
                .keyboardShortcut(".")
                .disabled(hasProject != true || !projectLoopState.canTransition(to: .paused))

                Button("Stop Loop") {
                    NotificationCenter.default.post(name: .stopLoop, object: nil)
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])
                .disabled(hasProject != true || !projectLoopState.canTransition(to: .stopped))

                Divider()

                Button("Edit Current PRD") {
                    NotificationCenter.default.post(name: .editPRD, object: nil)
                }
                .keyboardShortcut("e")
                .disabled(hasProject != true)

                Divider()

                Button("Delete PRD...") {
                    NotificationCenter.default.post(name: .deletePRD, object: nil)
                }
                .disabled(hasProject != true || projectLoopState == .running)
            }

            // MARK: - Window Menu
            CommandGroup(before: .windowList) {
                Button("Debug Info") {
                    NotificationCenter.default.post(name: .openDebugWindow, object: nil)
                }
                .disabled(!settings.debugMode)

                Divider()

                ForEach(1...9, id: \.self) { index in
                    Button("Switch to PRD \(index)") {
                        NotificationCenter.default.post(name: .switchToTab, object: index)
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(index))))
                }

                Divider()
            }
        }

        Settings {
            SettingsView()
        }
    }
}

extension Notification.Name {
    static let openPRD = Notification.Name("openPRD")
    static let openRecentPRD = Notification.Name("openRecentPRD")
    static let newPRD = Notification.Name("newPRD")
    static let startLoop = Notification.Name("startLoop")
    static let pauseLoop = Notification.Name("pauseLoop")
    static let stopLoop = Notification.Name("stopLoop")
    static let switchToTab = Notification.Name("switchToTab")
    static let focusLogPanel = Notification.Name("focusLogPanel")
    static let editPRD = Notification.Name("editPRD")
    static let openDebugWindow = Notification.Name("openDebugWindow")
    static let deletePRD = Notification.Name("deletePRD")
}
