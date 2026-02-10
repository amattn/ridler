import SwiftUI

struct StatusBarView: View {
    let activityMessage: String
    let loopState: LoopState

    var body: some View {
        HStack {
            Text(activityMessage)
                .font(.system(size: 11))
                .foregroundStyle(messageColor)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(height: 24)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var messageColor: Color {
        switch loopState {
        case .running:
            return .cyan
        case .paused:
            return .yellow
        case .error:
            return .red
        default:
            return .secondary
        }
    }
}
