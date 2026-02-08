import SwiftUI
import UniformTypeIdentifiers

@main
struct RidlerApp: App {
    @State private var prdManager = PRDManager()

    var body: some Scene {
        WindowGroup {
            ContentView(prdManager: prdManager)
        }
        .defaultSize(width: 1200, height: 700)
        .commands {
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
            }

            CommandGroup(after: .newItem) {
                if !prdManager.recentFiles.isEmpty {
                    Menu("Open Recent") {
                        ForEach(prdManager.recentFiles, id: \.self) { path in
                            Button(recentFileLabel(for: path)) {
                                try? prdManager.openPRD(filePath: path)
                            }
                        }
                        Divider()
                        Button("Clear Menu") {
                            prdManager.clearRecentFiles()
                        }
                    }
                }
            }
        }
    }

    private func recentFileLabel(for path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent().lastPathComponent
        return "\(dir)/\(url.lastPathComponent)"
    }
}
