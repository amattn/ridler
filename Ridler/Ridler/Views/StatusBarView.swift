import SwiftUI

struct StatusBarView: View {
    let activityMessage: String
    let loopState: LoopState
    var debugMode: Bool = false
    var debugInfo: DebugStatusInfo?

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack {
                Text(activityMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(messageColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                if debugMode, let info = debugInfo {
                    debugDetails(info)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(minHeight: 24)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    @ViewBuilder
    private func debugDetails(_ info: DebugStatusInfo) -> some View {
        HStack(spacing: 12) {
            Text("State: \(info.loopStateRawValue)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)

            if let storyID = info.currentStoryID {
                Text("Story: \(storyID)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if let elapsed = info.elapsedPerIteration {
                Text("Iter: \(elapsed)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
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

struct DebugStatusInfo {
    let loopStateRawValue: String
    let currentStoryID: String?
    let elapsedPerIteration: String?
}
