import SwiftUI

struct SidebarView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Section {
                Text("PRD Files")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                Text("No PRD loaded")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            Divider()
                .padding(.vertical, 8)

            Section {
                Text("Stories")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                Text("No stories")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .frame(minWidth: 200)
    }
}

#Preview {
    SidebarView()
}
