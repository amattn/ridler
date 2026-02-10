import SwiftUI

struct EmptyStateView: View {
    var onOpenPRD: () -> Void
    var onNewPRD: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Welcome to Ridler")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text("Open an existing PRD or create a new one to get started.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            HStack(spacing: 16) {
                Button(action: onOpenPRD) {
                    Label("Open PRD...", systemImage: "folder")
                        .frame(minWidth: 140)
                }
                .controlSize(.large)

                Button(action: onNewPRD) {
                    Label("New PRD...", systemImage: "plus.square")
                        .frame(minWidth: 140)
                }
                .controlSize(.large)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    EmptyStateView(onOpenPRD: {}, onNewPRD: {})
        .frame(width: 600, height: 400)
}
