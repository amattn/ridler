import SwiftUI
import AppKit

struct NewPRDSheet: View {
    @Binding var isPresented: Bool
    var prdManager: PRDManager

    @State private var prdName = ""
    @State private var saveDirectory = ""
    @State private var errorMessage: String?

    private var isNameValid: Bool {
        PRDManager.isValidPRDName(prdName)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("New PRD")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("PRD Name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("my-project", text: $prdName)
                    .textFieldStyle(.roundedBorder)

                if !prdName.isEmpty && !isNameValid {
                    Text("Name may only contain letters, numbers, dashes, and underscores.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Save Location")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(saveDirectory.isEmpty ? "No location selected" : saveDirectory)
                        .font(.caption)
                        .foregroundStyle(saveDirectory.isEmpty ? .tertiary : .primary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Choose...") {
                        chooseDirectory()
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    createPRD()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isNameValid || saveDirectory.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Save Location"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        saveDirectory = url.path
    }

    private func createPRD() {
        guard isNameValid, !saveDirectory.isEmpty else { return }

        let dirURL = URL(fileURLWithPath: saveDirectory).appendingPathComponent(prdName)

        do {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
            try prdManager.createPRD(name: prdName, directoryPath: dirURL.path)
            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
