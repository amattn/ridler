import SwiftUI

struct LoopToolbar: CustomizableToolbarContent {
    let prdManager: PRDManager
    let loopStartDate: Date?

    var body: some CustomizableToolbarContent {
        let tabId = prdManager.selectedTabId ?? ""
        let state = prdManager.loopState(for: tabId)
        let iteration = prdManager.iterationCount(for: tabId)
        let maxIter = prdManager.defaultMaxIterations(for: tabId)

        ToolbarItem(id: "loopControls", placement: .primaryAction) {
            HStack(spacing: 12) {
                // State badge
                Text(state.label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(state.color.opacity(0.2))
                    .foregroundStyle(state.color)
                    .clipShape(Capsule())

                Divider()
                    .frame(height: 18)

                // Iteration counter
                Text("\(iteration) / \(maxIter)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                // Elapsed time
                if let startDate = loopStartDate, state == .running {
                    ElapsedTimeView(startDate: startDate)
                }

                Divider()
                    .frame(height: 18)

                // Start button
                Button {
                    guard let tabId = prdManager.selectedTabId else { return }
                    Task {
                        await prdManager.checkBranchAndStart(tabId: tabId)
                    }
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .disabled(!canStart(state: state))
                .help("Start or resume the loop")

                // Pause button
                Button {
                    guard let tabId = prdManager.selectedTabId else { return }
                    prdManager.pause(tabId: tabId)
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .disabled(state != .running)
                .help("Pause the loop after current iteration")

                // Stop button
                Button {
                    guard let tabId = prdManager.selectedTabId else { return }
                    prdManager.stop(tabId: tabId)
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(state != .running && state != .paused)
                .help("Stop the loop immediately")
            }
        }
    }

    private func canStart(state: LoopState) -> Bool {
        state == .ready || state == .paused || state == .stopped || state == .error
    }
}

struct ElapsedTimeView: View {
    let startDate: Date
    @State private var elapsed: TimeInterval = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(formattedElapsed)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .onReceive(timer) { _ in
                elapsed = Date().timeIntervalSince(startDate)
            }
            .onAppear {
                elapsed = Date().timeIntervalSince(startDate)
            }
    }

    private var formattedElapsed: String {
        let totalSeconds = Int(elapsed)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}
