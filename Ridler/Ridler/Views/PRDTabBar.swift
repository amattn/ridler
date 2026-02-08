import SwiftUI

struct PRDTabBar: View {
    @Bindable var prdManager: PRDManager

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(prdManager.tabs) { tab in
                        tabItem(for: tab)
                    }
                }
                .padding(.leading, 4)
            }

            Spacer(minLength: 0)

            // + button with menu
            Menu {
                Button("Open PRD...") {
                    prdManager.openFilePanel()
                }
                Button("New PRD...") {
                    prdManager.showNewPRDSheet = true
                }
            } label: {
                Image(systemName: "plus")
                    .font(.caption)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .padding(.trailing, 8)
        }
        .frame(height: 30)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Tab Item

    private func tabItem(for tab: PRDTab) -> some View {
        let isSelected = prdManager.selectedTabId == tab.id
        let state = prdManager.loopState(for: tab.id)
        let iteration = prdManager.iterationCount(for: tab.id)

        return Button {
            prdManager.selectedTabId = tab.id
            prdManager.selectedStoryId = nil
        } label: {
            HStack(spacing: 5) {
                stateIcon(state: state, iteration: iteration)
                    .font(.system(size: 9))

                Text(tab.name)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .overlay(alignment: .bottom) {
                if isSelected {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            tabContextMenu(for: tab, state: state)
        }
    }

    // MARK: - State Icon

    @ViewBuilder
    private func stateIcon(state: LoopState, iteration: Int) -> some View {
        switch state {
        case .ready:
            Image(systemName: "circle")
                .foregroundStyle(.gray)
        case .running:
            HStack(spacing: 2) {
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(.cyan)
                Text("\(iteration)")
                    .font(.system(size: 8).monospacedDigit())
                    .foregroundStyle(.cyan)
            }
        case .paused:
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.yellow)
        case .stopped:
            Image(systemName: "stop.circle")
                .foregroundStyle(.gray)
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func tabContextMenu(for tab: PRDTab, state: LoopState) -> some View {
        let canStart = state == .ready || state == .paused || state == .stopped || state == .error

        Button("Start") {
            Task {
                await prdManager.start(tabId: tab.id)
            }
        }
        .disabled(!canStart)

        Button("Pause") {
            prdManager.pause(tabId: tab.id)
        }
        .disabled(state != .running)

        Button("Stop") {
            prdManager.stop(tabId: tab.id)
        }
        .disabled(state != .running && state != .paused)

        Divider()

        Button("Edit") {
            // Placeholder — will be implemented in US-020
        }

        Divider()

        Button("Close") {
            prdManager.closeTab(id: tab.id)
        }

        Button("Delete", role: .destructive) {
            // Placeholder — will be implemented in US-021
        }
    }
}
