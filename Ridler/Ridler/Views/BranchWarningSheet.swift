import SwiftUI

struct BranchWarningSheet: View {
    let currentBranch: String
    let prdName: String
    let onCreateBranch: (String) -> Void
    let onContinue: () -> Void
    let onCancel: () -> Void

    @State private var branchName: String

    init(
        currentBranch: String,
        prdName: String,
        onCreateBranch: @escaping (String) -> Void,
        onContinue: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.currentBranch = currentBranch
        self.prdName = prdName
        self.onCreateBranch = onCreateBranch
        self.onContinue = onContinue
        self.onCancel = onCancel
        self._branchName = State(initialValue: "ridler/\(prdName)")
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.yellow)

            Text("Protected Branch Warning")
                .font(.headline)

            Text("You are currently on the **\(currentBranch)** branch. Running the loop may commit changes directly to this protected branch.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Create a new branch:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Branch name", text: $branchName)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Continue on \(currentBranch)") {
                    onContinue()
                }

                Button("Create Branch") {
                    onCreateBranch(branchName)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(branchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
