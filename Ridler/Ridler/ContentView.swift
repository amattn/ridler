import SwiftUI

struct ContentView: View {
    @State private var prdManager = PRDManager()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var loopStartDate: Date?

    var body: some View {
        VStack(spacing: 0) {
            if prdManager.tabs.count > 0 {
                PRDTabBar(prdManager: prdManager)
            }

            if prdManager.selectedTab != nil {
                threeColumnLayout
                    .navigationTitle(prdManager.selectedTab?.name ?? "Ridler")
                    .toolbar {
                        LoopToolbar(prdManager: prdManager, loopStartDate: loopStartDate)
                    }
                    .onChange(of: currentLoopState) { oldValue, newValue in
                        if newValue == .running && oldValue != .running {
                            loopStartDate = Date()
                        } else if newValue != .running {
                            loopStartDate = nil
                        }
                    }
            } else {
                emptyState
                    .navigationTitle("Ridler")
            }

            if prdManager.selectedTab != nil {
                StatusBarView(activityMessage: activityMessage,
                             loopState: currentLoopState)
            }
        }
    }

    // MARK: - Three-Pane Layout

    private var threeColumnLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Left pane: Stories list
            if let stories = prdManager.selectedPRD?.userStories {
                StoriesListView(
                    stories: stories,
                    selectedStoryId: $prdManager.selectedStoryId,
                    loopState: currentLoopState
                )
            } else {
                ContentUnavailableView("No Stories",
                                       systemImage: "list.bullet",
                                       description: Text("This PRD has no user stories."))
            }
        } content: {
            // Middle pane: Story detail
            StoryDetailView(story: selectedStory,
                           loopState: currentLoopState,
                           lastErrorMessage: lastErrorMessage)
        } detail: {
            // Right pane: Log panel
            let tabId = prdManager.selectedTabId ?? ""
            let entries = prdManager.engines[tabId]?.logEntries ?? []
            LogPanelView(logEntries: entries)
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No PRD Loaded")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("Open an existing PRD or create a new one to get started.")
                .font(.body)
                .foregroundStyle(.tertiary)

            HStack(spacing: 16) {
                Button("Open PRD") {
                    // Placeholder — will be implemented in US-017
                }
                .buttonStyle(.borderedProminent)

                Button("New PRD") {
                    // Placeholder — will be implemented in US-018
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var selectedStory: UserStory? {
        guard let storyId = prdManager.selectedStoryId,
              let stories = prdManager.selectedPRD?.userStories else { return nil }
        return stories.first { $0.id == storyId }
    }

    private var currentLoopState: LoopState {
        guard let tabId = prdManager.selectedTabId else { return .ready }
        return prdManager.loopState(for: tabId)
    }

    private var activityMessage: String {
        guard let tabId = prdManager.selectedTabId,
              let engine = prdManager.engines[tabId] else {
            return "Ready"
        }

        let state = prdManager.loopState(for: tabId)
        switch state {
        case .running:
            if let storyId = engine.currentStoryId,
               let story = prdManager.selectedPRD?.userStories.first(where: { $0.id == storyId }) {
                return "Working on: \(story.id) - \(story.title)"
            }
            return "Running..."
        case .paused:
            return "Paused"
        case .stopped:
            return "Stopped"
        case .complete:
            return "All stories complete"
        case .error:
            if let lastError = lastErrorMessage {
                return "Error: \(lastError)"
            }
            return "Error occurred"
        case .ready:
            return "Ready"
        }
    }

    private var lastErrorMessage: String? {
        guard let tabId = prdManager.selectedTabId,
              let engine = prdManager.engines[tabId],
              let entry = engine.logEntries.last(where: { if case .error = $0.type { return true } else { return false } })
        else { return nil }
        if case .error(let message) = entry.type {
            return message
        }
        return nil
    }
}

#Preview {
    ContentView()
}
