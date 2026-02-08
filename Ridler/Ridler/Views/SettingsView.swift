import SwiftUI

struct SettingsView: View {
    @State private var audioEnabled: Bool = NotificationManager.shared.audioEnabled
    @State private var autoRetryEnabled: Bool = SettingsManager.shared.autoRetryEnabled
    @State private var verboseLogEnabled: Bool = SettingsManager.shared.verboseLogEnabled
    @State private var debugMode: Bool = SettingsManager.shared.debugMode

    var body: some View {
        Form {
            Toggle("Audio notifications", isOn: $audioEnabled)
                .onChange(of: audioEnabled) { _, newValue in
                    NotificationManager.shared.audioEnabled = newValue
                }

            Toggle("Auto-retry on crash", isOn: $autoRetryEnabled)
                .onChange(of: autoRetryEnabled) { _, newValue in
                    SettingsManager.shared.autoRetryEnabled = newValue
                }

            Toggle("Verbose log", isOn: $verboseLogEnabled)
                .onChange(of: verboseLogEnabled) { _, newValue in
                    SettingsManager.shared.verboseLogEnabled = newValue
                }

            Section("Developer") {
                Toggle("Debug mode", isOn: $debugMode)
                    .onChange(of: debugMode) { _, newValue in
                        SettingsManager.shared.debugMode = newValue
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 350)
        .fixedSize()
    }
}
