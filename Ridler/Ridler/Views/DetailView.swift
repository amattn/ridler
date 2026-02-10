import SwiftUI

struct DetailView: View {
    var body: some View {
        VStack {
            Text("Select a story or file to view details")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 300)
    }
}

#Preview {
    DetailView()
}
