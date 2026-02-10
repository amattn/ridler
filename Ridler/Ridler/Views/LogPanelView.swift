import SwiftUI

struct LogPanelView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Log")
                .font(.headline)
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            ScrollView {
                Text("No log output yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .frame(minWidth: 250)
    }
}

#Preview {
    LogPanelView()
}
