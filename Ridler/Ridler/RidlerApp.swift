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

            CommandGroup(after: .newItem) {
                Divider()

                Button("Start/Resume Loop") {
                    NotificationCenter.default.post(name: .startLoop, object: nil)
                }
                .keyboardShortcut("r")

                Button("Start/Resume Loop") {
                    NotificationCenter.default.post(name: .startLoop, object: nil)
                }
                .keyboardShortcut(.return)

                Button("Pause Loop") {
                    NotificationCenter.default.post(name: .pauseLoop, object: nil)
                }
                .keyboardShortcut(".")

                Button("Stop Loop") {
                    NotificationCenter.default.post(name: .stopLoop, object: nil)
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])

                Divider()

                Button("Focus Log Panel") {
                    NotificationCenter.default.post(name: .focusLogPanel, object: nil)
                }
                .keyboardShortcut("l")

                Button("Edit Current PRD") {
                    NotificationCenter.default.post(name: .editPRD, object: nil)
                }
                .keyboardShortcut("e")

                Divider()

                ForEach(1...9, id: \.self) { index in
                    Button("Switch to PRD \(index)") {
                        NotificationCenter.default.post(name: .switchToTab, object: index)
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(index))))
                }
            }
        }
    }
}

extension Notification.Name {
    static let openPRD = Notification.Name("openPRD")
    static let newPRD = Notification.Name("newPRD")
    static let startLoop = Notification.Name("startLoop")
    static let pauseLoop = Notification.Name("pauseLoop")
    static let stopLoop = Notification.Name("stopLoop")
    static let switchToTab = Notification.Name("switchToTab")
    static let focusLogPanel = Notification.Name("focusLogPanel")
    static let editPRD = Notification.Name("editPRD")
}
