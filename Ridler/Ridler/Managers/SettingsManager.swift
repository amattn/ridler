import Foundation
import Combine
import os

final class SettingsManager: ObservableObject {
    private static let logger = Logger(subsystem: "com.amattn.Ridler", category: "Settings")
    static let shared = SettingsManager()

    private enum Keys {
        static let audioNotifications = "settings.audioNotifications"
        static let autoRetryOnCrash = "settings.autoRetryOnCrash"
        static let verboseLog = "settings.verboseLog"
        static let debugMode = "settings.debugMode"
        static let claudeConfigDir = "settings.claudeConfigDir"
    }

    static let defaultClaudeConfigDir = "~/.claude/"

    @Published var audioNotifications: Bool {
        didSet {
            UserDefaults.standard.set(audioNotifications, forKey: Keys.audioNotifications)
            Self.logger.info("Audio notifications: \(self.audioNotifications)")
        }
    }

    @Published var autoRetryOnCrash: Bool {
        didSet {
            UserDefaults.standard.set(autoRetryOnCrash, forKey: Keys.autoRetryOnCrash)
            Self.logger.info("Auto-retry on crash: \(self.autoRetryOnCrash)")
        }
    }

    @Published var verboseLog: Bool {
        didSet {
            UserDefaults.standard.set(verboseLog, forKey: Keys.verboseLog)
            Self.logger.info("Verbose log: \(self.verboseLog)")
        }
    }

    @Published var debugMode: Bool {
        didSet {
            UserDefaults.standard.set(debugMode, forKey: Keys.debugMode)
            Self.logger.info("Debug mode: \(self.debugMode)")
        }
    }

    @Published var claudeConfigDir: String {
        didSet {
            UserDefaults.standard.set(claudeConfigDir, forKey: Keys.claudeConfigDir)
            Self.logger.info("Claude config dir: \(self.claudeConfigDir)")
        }
    }

    /// The resolved absolute path for the Claude config directory.
    var resolvedClaudeConfigPath: String {
        NSString(string: claudeConfigDir).expandingTildeInPath
    }

    /// Whether the configured Claude config directory exists on disk.
    var isClaudeConfigDirValid: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: resolvedClaudeConfigPath, isDirectory: &isDir) && isDir.boolValue
    }

    private init() {
        let defaults = UserDefaults.standard

        // Register defaults: audio on, auto-retry off, verbose off, debug off
        defaults.register(defaults: [
            Keys.audioNotifications: true,
            Keys.autoRetryOnCrash: false,
            Keys.verboseLog: false,
            Keys.debugMode: false,
            Keys.claudeConfigDir: Self.defaultClaudeConfigDir,
        ])

        self.audioNotifications = defaults.bool(forKey: Keys.audioNotifications)
        self.autoRetryOnCrash = defaults.bool(forKey: Keys.autoRetryOnCrash)
        self.verboseLog = defaults.bool(forKey: Keys.verboseLog)
        self.debugMode = defaults.bool(forKey: Keys.debugMode)
        self.claudeConfigDir = defaults.string(forKey: Keys.claudeConfigDir) ?? Self.defaultClaudeConfigDir
    }
}
