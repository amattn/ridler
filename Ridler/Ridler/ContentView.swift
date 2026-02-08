import SwiftUI

struct ContentView: View {
    @State private var prdManager = PRDManager()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        if prdManager.selectedTab != nil {
            threeColumnLayout
                .navigationTitle(prdManager.selectedTab?.name ?? "Ridler")
        } else {
            emptyState
                .navigationTitle("Ridler")
        }
    }

    // MARK: - Three-Pane Layout

    private var threeColumnLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Left pane: Stories list
            if let stories = prdManager.selectedPRD?.userStories {
                StoriesListView(
                    stories: stories,
                    selectedStoryId: $prdManager.selectedStoryId
                )
            } else {
                ContentUnavailableView("No Stories",
                                       systemImage: "list.bullet",
                                       description: Text("This PRD has no user stories."))
            }
        } content: {
            // Middle pane: Story detail
            StoryDetailView(story: selectedStory)
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
}

#Preview {
    ContentView()
}
