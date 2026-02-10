import SwiftUI

struct NewPRDSheet: View {
    @Binding var isPresented: Bool
    var onCreate: (PRDProject) -> Void

    @State private var prdName: String = ""
    @State private var selectedDirectory: URL?
    @State private var isDirectoryPickerPresented = false
    @State private var errorMessage: String?

    private var isNameValid: Bool {
        let pattern = /^[a-zA-Z0-9\-_]+$/
        return !prdName.isEmpty && prdName.wholeMatch(of: pattern) != nil
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("New PRD")
                .font(.headline)

            Form {
                TextField("PRD Name:", text: $prdName)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Text("Location:")
                    Text(selectedDirectory?.path ?? "No directory selected")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer()
                    Button("Choose...") {
                        isDirectoryPickerPresented = true
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .padding(.horizontal)

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
                .disabled(!isNameValid || selectedDirectory == nil)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 450, height: 220)
        .fileImporter(
            isPresented: $isDirectoryPickerPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result {
                selectedDirectory = urls.first
            }
        }
    }

    private func createPRD() {
        guard let parentDir = selectedDirectory else { return }

        let ridlDir = parentDir.appendingPathComponent(prdName)
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: ridlDir, withIntermediateDirectories: true)
            let prdFileURL = ridlDir.appendingPathComponent("prd.md")
            try "".write(to: prdFileURL, atomically: true, encoding: .utf8)

            let project = PRDProject(
                name: prdName,
                userStories: [],
                directoryURL: ridlDir
            )
            onCreate(project)
            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NewPRDSheet(isPresented: .constant(true), onCreate: { _ in })
}
