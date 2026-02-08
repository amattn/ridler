import SwiftUI

struct StatusBarView: View {
    let activityMessage: String
    let loopState: LoopState
    var debugMode: Bool = false
    var currentStoryId: String?
    var retryCount: Int = 0
    var iterationStartDate: Date?

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

    private var iterationElapsed: String {
        guard let start = iterationStartDate else { return "0s" }
        let elapsed = Int(Date().timeIntervalSince(start))
        if elapsed >= 3600 {
            return "\(elapsed / 3600)h \((elapsed % 3600) / 60)m \(elapsed % 60)s"
        } else if elapsed >= 60 {
            return "\(elapsed / 60)m \(elapsed % 60)s"
        } else {
            return "\(elapsed)s"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
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

            if debugMode {
                HStack {
                    Text("state: \(loopState.rawValue) | story: \(currentStoryId ?? "none") | retries: \(retryCount) | iter elapsed: \(iterationElapsed)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
        }
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
