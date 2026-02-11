import SwiftUI

struct LoopToolbarView: View {
    @Binding var project: PRDProject
    var onStart: () -> Void = {}
    var onPause: () -> Void = {}
    var onStop: () -> Void = {}
    var onMaxIterationsChanged: ((Int) -> Void)?
    var onAudioNotificationsChanged: ((Bool) -> Void)?
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 12) {
            // Loop control buttons
            controlButtons

            Divider()
                .frame(height: 20)

            // State badge
            stateBadge

            Divider()
                .frame(height: 20)

            // Iteration counter
            iterationCounter

            Divider()
                .frame(height: 20)

            // Elapsed time
            elapsedTimeView

            Spacer()

            // Audio notifications toggle
            Toggle("Audio", isOn: Binding(
                get: { project.audioNotificationsEnabled },
                set: { newValue in
                    project.audioNotificationsEnabled = newValue
                    onAudioNotificationsChanged?(newValue)
                }
            ))
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .help("Play sound on completion")

            // Pause after story toggle
            Toggle("Pause after story", isOn: $project.pauseAfterStory)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .onChange(of: project.loopState) { _, newState in
            handleStateChange(newState)
        }
    }

    private var controlButtons: some View {
        HStack(spacing: 4) {
            // Start/Resume button
            Button {
                onStart()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .disabled(!project.loopState.canTransition(to: .running))
            .help("Start / Resume")

            // Pause button
            Button {
                onPause()
            } label: {
                Image(systemName: "pause.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .disabled(!project.loopState.canTransition(to: .paused))
            .help("Pause after current story")

            // Stop button
            Button {
                onStop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .disabled(!project.loopState.canTransition(to: .stopped))
            .help("Stop immediately")
        }
    }

    private var stateBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(project.loopState.badgeColor)
                .frame(width: 8, height: 8)
            Text(project.loopState.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(project.loopState.badgeColor)
        }
    }

    private var iterationCounter: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("\(project.iterationCount) / \(effectiveMaxIterations)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            Button {
                adjustMaxIterations(by: -5)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.borderless)
            .disabled(effectiveMaxIterations <= 5)
            .help("-5 max iterations")

            Button {
                adjustMaxIterations(by: 5)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.borderless)
            .help("+5 max iterations")
        }
    }

    private var effectiveMaxIterations: Int {
        project.maxIterations > 0 ? project.maxIterations : project.defaultMaxIterations
    }

    private var elapsedTimeView: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(formattedElapsedTime)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var formattedElapsedTime: String {
        let totalSeconds = Int(elapsedTime)
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

    private func adjustMaxIterations(by delta: Int) {
        let current = effectiveMaxIterations
        let newValue = max(5, current + delta)
        project.maxIterations = newValue
        onMaxIterationsChanged?(newValue)
    }

    private func handleStateChange(_ newState: LoopState) {
        switch newState {
        case .running:
            startTimer()
        case .paused, .stopped, .complete, .error:
            stopTimer()
        case .ready:
            stopTimer()
            elapsedTime = 0
            project.loopStartDate = nil
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if let startDate = project.loopStartDate {
                elapsedTime = Date().timeIntervalSince(startDate)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
