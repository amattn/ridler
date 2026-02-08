import AppKit
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()

    private let audioEnabledKey = "com.amattn.ridler.audioNotificationsEnabled"

    var audioEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: audioEnabledKey) == nil {
                return true // default on
            }
            return UserDefaults.standard.bool(forKey: audioEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: audioEnabledKey)
        }
    }

    private init() {
        requestNotificationPermission()
    }

    // MARK: - Permission

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Audio

    func playCompletionSound() {
        guard audioEnabled else { return }
        NSSound.beep()
    }

    // MARK: - macOS Notification

    func postCompletionNotification(prdName: String) {
        guard !NSApp.isActive else { return }

        let content = UNMutableNotificationContent()
        content.title = "PRD Complete"
        content.body = "\(prdName) — All stories complete"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "ridler.complete.\(prdName).\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Combined

    func notifyCompletion(prdName: String) {
        playCompletionSound()
        postCompletionNotification(prdName: prdName)
    }
}
