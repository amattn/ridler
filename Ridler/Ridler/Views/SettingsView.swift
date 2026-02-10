import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("Audio notifications on completion", isOn: $settings.audioNotifications)
                    .help("Play a sound when a PRD reaches Complete state")
            }

            Section("Execution") {
                Toggle("Auto-retry on Claude Code crash", isOn: $settings.autoRetryOnCrash)
                    .help("Automatically retry when Claude Code exits with an error (up to 3 retries with exponential backoff)")
            }

            Section("Logging") {
                Toggle("Verbose log (show raw Claude JSON)", isOn: $settings.verboseLog)
                    .help("Display raw JSON output from Claude Code in the log view")
            }

            Section("Developer") {
                Toggle("Debug mode", isOn: $settings.debugMode)
                    .help("Enable debug features including the Debug Info window")
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 280)
    }
}
