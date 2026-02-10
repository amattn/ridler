import SwiftUI

@main
struct RidlerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open PRD...") {
                    NotificationCenter.default.post(name: .openPRD, object: nil)
                }
                .keyboardShortcut("o")

                Button("New PRD...") {
                    NotificationCenter.default.post(name: .newPRD, object: nil)
                }
                .keyboardShortcut("n")
            }
        }
    }
}

extension Notification.Name {
    static let openPRD = Notification.Name("openPRD")
    static let newPRD = Notification.Name("newPRD")
}
