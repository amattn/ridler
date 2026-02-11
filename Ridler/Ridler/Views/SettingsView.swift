import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("Audio notifications on completion", isOn: $settings.audioNotifications)
                    .help("Play a sound when a PRD reaches Complete state")
            }

            Section("Logging") {
                Toggle("Verbose log (show raw Claude JSON)", isOn: $settings.verboseLog)
                    .help("Display raw JSON output from Claude Code in the log view")
            }

            Section("Claude Code") {
                HStack {
                    Text("Config directory")
                    TextField("~/.claude/", text: $settings.claudeConfigDir)
                        .textFieldStyle(.roundedBorder)
                }
                .help("Path to the Claude Code config directory (CLAUDE_CONFIG_DIR). Restart sessions after changing.")
                if !settings.isClaudeConfigDirValid {
                    Label("Directory not found: \(settings.resolvedClaudeConfigPath)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            Section("Developer") {
                Toggle("Debug mode", isOn: $settings.debugMode)
                    .help("Enable debug features including the Debug Info window")
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 300)
    }
}
