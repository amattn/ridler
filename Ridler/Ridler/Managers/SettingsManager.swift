import Foundation
import Combine

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private enum Keys {
        static let audioNotifications = "settings.audioNotifications"
        static let autoRetryOnCrash = "settings.autoRetryOnCrash"
        static let verboseLog = "settings.verboseLog"
        static let debugMode = "settings.debugMode"
    }

    @Published var audioNotifications: Bool {
        didSet { UserDefaults.standard.set(audioNotifications, forKey: Keys.audioNotifications) }
    }

    @Published var autoRetryOnCrash: Bool {
        didSet { UserDefaults.standard.set(autoRetryOnCrash, forKey: Keys.autoRetryOnCrash) }
    }

    @Published var verboseLog: Bool {
        didSet { UserDefaults.standard.set(verboseLog, forKey: Keys.verboseLog) }
    }

    @Published var debugMode: Bool {
        didSet { UserDefaults.standard.set(debugMode, forKey: Keys.debugMode) }
    }

    private init() {
        let defaults = UserDefaults.standard

        // Register defaults: audio on, auto-retry off, verbose off, debug off
        defaults.register(defaults: [
            Keys.audioNotifications: true,
            Keys.autoRetryOnCrash: false,
            Keys.verboseLog: false,
            Keys.debugMode: false,
        ])

        self.audioNotifications = defaults.bool(forKey: Keys.audioNotifications)
        self.autoRetryOnCrash = defaults.bool(forKey: Keys.autoRetryOnCrash)
        self.verboseLog = defaults.bool(forKey: Keys.verboseLog)
        self.debugMode = defaults.bool(forKey: Keys.debugMode)
    }
}
