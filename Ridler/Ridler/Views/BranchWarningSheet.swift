import SwiftUI

struct BranchWarningSheet: View {
    @Binding var isPresented: Bool
    var prdManager: PRDManager
    var tabId: String
    var currentBranch: String
    var suggestedBranch: String

    @State private var branchName: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.yellow)

            Text("Protected Branch")
                .font(.headline)

            Text("You are on the **\(currentBranch)** branch. It is recommended to create a new branch before starting the loop.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Branch Name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("ridler/my-project", text: $branchName)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Continue on \(currentBranch)") {
                    isPresented = false
                    Task {
                        await prdManager.start(tabId: tabId)
                    }
                }

                Button("Create Branch") {
                    isPresented = false
                    Task {
                        await prdManager.createBranchAndStart(tabId: tabId, branchName: branchName)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(branchName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 450)
        .onAppear {
            branchName = suggestedBranch
        }
    }
}
