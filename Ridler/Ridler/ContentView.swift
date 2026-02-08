import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var prdManager: PRDManager
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var loopStartDate: Date?
    @State private var isDragOver = false

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
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
        }
        .overlay {
            if isDragOver {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.1))
                    .padding(4)
            }
        }
        .sheet(isPresented: $prdManager.showNewPRDSheet) {
            NewPRDSheet(isPresented: $prdManager.showNewPRDSheet,
                        prdManager: prdManager)
        }
        .sheet(isPresented: $prdManager.showBranchWarning) {
            BranchWarningSheet(
                isPresented: $prdManager.showBranchWarning,
                prdManager: prdManager,
                tabId: prdManager.branchWarningTabId ?? "",
                currentBranch: prdManager.branchWarningCurrentBranch,
                suggestedBranch: prdManager.branchWarningSuggestedBranch
            )
        }
        .alert("Close PRD?", isPresented: $prdManager.showCloseConfirmation) {
            Button("Close", role: .destructive) {
                if let tabId = prdManager.closeConfirmationTabId {
                    prdManager.closeTab(id: tabId)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A loop is currently running for this PRD. Closing will stop the loop.")
        }
        .alert("Delete PRD?", isPresented: $prdManager.showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let tabId = prdManager.deleteConfirmationTabId {
                    prdManager.deletePRD(tabId: tabId)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete PRD and all its files? This cannot be undone.")
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
                    prdManager.openFilePanel()
                }
                .buttonStyle(.borderedProminent)

                Button("New PRD") {
                    prdManager.showNewPRDSheet = true
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

    // MARK: - Drag and Drop

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                let ext = url.pathExtension.lowercased()
                guard ext == "md" || ext == "json" else { return }

                DispatchQueue.main.async {
                    try? prdManager.openPRD(filePath: url.path)
                }
            }
        }
        return true
    }
}

#Preview {
    ContentView(prdManager: PRDManager())
}
