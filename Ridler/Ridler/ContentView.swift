import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var openProjects: [PRDProject] = []
    @State private var selectedProjectID: String?
    @State private var isFilePickerPresented = false
    @State private var isNewPRDPresented = false
    @State private var sidebarSelection: SidebarSelection?
    @State private var errorAlertMessage: String?
    @State private var showErrorAlert = false
    @StateObject private var fileWatcher = ProjectFileWatcher()
    @StateObject private var logStore = LogStore()
    @State private var loopEngines: [String: RalphLoopEngine] = [:]
    @State private var showBranchWarning = false
    @State private var branchWarningIndex: Int?
    @State private var branchWarningBranch: String = ""
    private let gitManager: GitManaging = GitManager()

    private var selectedProject: PRDProject? {
        guard let id = selectedProjectID else { return nil }
        return openProjects.first { $0.id == id }
    }

    private var selectedProjectIndex: Int? {
        guard let id = selectedProjectID else { return nil }
        return openProjects.firstIndex { $0.id == id }
    }

    var body: some View {
        Group {
            if openProjects.isEmpty {
                EmptyStateView(
                    onOpenPRD: { isFilePickerPresented = true },
                    onNewPRD: { isNewPRDPresented = true }
                )
            } else {
                VStack(spacing: 0) {
                    tabBar

                    if let selectedIndex = selectedProjectIndex {
                        LoopToolbarView(
                            project: $openProjects[selectedIndex],
                            onStart: { startLoop(for: selectedIndex) },
                            onPause: { pauseLoop(for: selectedIndex) },
                            onStop: { stopLoop(for: selectedIndex) },
                            onMaxIterationsChanged: { newValue in
                                let project = openProjects[selectedIndex]
                                loopEngines[project.id]?.updateMaxIterations(newValue)
                            }
                        )
                    }

                    NavigationSplitView(columnVisibility: $columnVisibility) {
                        SidebarView(project: selectedProject, selection: $sidebarSelection)
                            .id(fileWatcher.changeToken)
                    } content: {
                        DetailView(project: selectedProject, selection: sidebarSelection)
                            .id(fileWatcher.changeToken)
                    } detail: {
                        LogPanelView(
                            entries: logStore.entries(for: selectedProject?.id ?? ""),
                            isRunning: selectedProject?.loopState == .running
                        )
                    }

                    StatusBarView(
                        activityMessage: statusBarMessage(for: selectedProject),
                        loopState: selectedProject?.loopState ?? .ready
                    )
                }
            }
        }
        .frame(minWidth: 900, minHeight: 500)
        .fileImporter(
            isPresented: $isFilePickerPresented,
            allowedContentTypes: [.folder, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $isNewPRDPresented) {
            NewPRDSheet(isPresented: $isNewPRDPresented) { project in
                addProject(project)
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("Copy") {
                if let errorAlertMessage {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(errorAlertMessage, forType: .string)
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            if let errorAlertMessage {
                Text(errorAlertMessage)
            }
        }
        .sheet(isPresented: $showBranchWarning) {
            if let idx = branchWarningIndex {
                BranchWarningSheet(
                    currentBranch: branchWarningBranch,
                    prdName: openProjects[idx].name ?? openProjects[idx].id,
                    onCreateBranch: { newBranch in
                        showBranchWarning = false
                        handleCreateBranch(newBranch, for: idx)
                    },
                    onContinue: {
                        showBranchWarning = false
                        proceedWithStart(for: idx)
                    },
                    onCancel: {
                        showBranchWarning = false
                    }
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPRD)) { _ in
            isFilePickerPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .newPRD)) { _ in
            isNewPRDPresented = true
        }
        .onReceive(fileWatcher.$changeToken.dropFirst()) { _ in
            reloadAllProjects()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(openProjects) { project in
                tabItem(for: project)
            }

            Menu {
                Button("Open PRD...") {
                    isFilePickerPresented = true
                }
                Button("New PRD...") {
                    isNewPRDPresented = true
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)

            Spacer()
        }
        .frame(height: 32)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func stateIndicator(for project: PRDProject) -> some View {
        Group {
            switch project.loopState {
            case .ready:
                Image(systemName: "circle.fill")
                    .foregroundStyle(project.loopState.badgeColor)
            case .running:
                HStack(spacing: 2) {
                    Image(systemName: "play.fill")
                        .foregroundStyle(project.loopState.badgeColor)
                    Text("\(project.iterationCount)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(project.loopState.badgeColor)
                }
            case .paused:
                Image(systemName: "pause.fill")
                    .foregroundStyle(project.loopState.badgeColor)
            case .stopped:
                Image(systemName: "stop.fill")
                    .foregroundStyle(project.loopState.badgeColor)
            case .complete:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(project.loopState.badgeColor)
            case .error:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(project.loopState.badgeColor)
            }
        }
        .font(.system(size: 9))
    }

    private func tabItem(for project: PRDProject) -> some View {
        let isSelected = selectedProjectID == project.id
        return HStack(spacing: 6) {
            stateIndicator(for: project)

            Text(project.name ?? project.id)
                .font(.system(size: 12))
                .lineLimit(1)

            Button {
                closeProject(project)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.3) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedProjectID = project.id
        }
    }

    private func addProject(_ project: PRDProject) {
        // Don't add duplicate projects (same directory)
        if let dirURL = project.directoryURL,
           openProjects.contains(where: { $0.directoryURL?.standardizedFileURL == dirURL.standardizedFileURL }) {
            // Select the existing one instead
            if let existing = openProjects.first(where: { $0.directoryURL?.standardizedFileURL == dirURL.standardizedFileURL }) {
                selectedProjectID = existing.id
            }
            return
        }
        openProjects.append(project)
        selectedProjectID = project.id
        if let dirURL = project.directoryURL {
            fileWatcher.watch(directoryURL: dirURL)
        }
    }

    private func closeProject(_ project: PRDProject) {
        // Stop the engine if it's running
        if let engine = loopEngines[project.id] {
            engine.stop()
            loopEngines.removeValue(forKey: project.id)
        }
        if let dirURL = project.directoryURL {
            fileWatcher.unwatch(directoryURL: dirURL)
        }
        openProjects.removeAll { $0.id == project.id }
        if selectedProjectID == project.id {
            selectedProjectID = openProjects.first?.id
        }
    }

    private func reloadAllProjects() {
        let store = FileSystemPRDStore()
        for index in openProjects.indices {
            guard let dirURL = openProjects[index].directoryURL else { continue }
            do {
                let reloaded = try store.loadProject(from: dirURL)
                var updated = reloaded
                updated.loopState = openProjects[index].loopState
                updated.iterationCount = openProjects[index].iterationCount
                updated.pauseAfterStory = openProjects[index].pauseAfterStory
                updated.maxIterations = openProjects[index].maxIterations
                updated.loopStartDate = openProjects[index].loopStartDate
                openProjects[index] = updated
            } catch {
                // File may be mid-write; ignore transient errors
            }
        }
    }

    private func getOrCreateEngine(for project: PRDProject) -> RalphLoopEngine {
        if let existing = loopEngines[project.id] {
            return existing
        }
        let engine = RalphLoopEngine()
        engine.onStateChange = { [self] newState in
            if let idx = openProjects.firstIndex(where: { $0.id == project.id }) {
                openProjects[idx].loopState = newState
            }
        }
        engine.onIterationChange = { [self] count in
            if let idx = openProjects.firstIndex(where: { $0.id == project.id }) {
                openProjects[idx].iterationCount = count
            }
        }
        engine.onLogEntry = { [self] entry, projectID in
            logStore.append(entry, for: projectID)
        }
        engine.onProjectUpdated = { [self] updatedProject in
            if let idx = openProjects.firstIndex(where: { $0.id == updatedProject.id }) {
                let currentState = openProjects[idx].loopState
                let currentIteration = openProjects[idx].iterationCount
                let currentPause = openProjects[idx].pauseAfterStory
                let currentMax = openProjects[idx].maxIterations
                let currentStart = openProjects[idx].loopStartDate
                openProjects[idx] = updatedProject
                openProjects[idx].loopState = currentState
                openProjects[idx].iterationCount = currentIteration
                openProjects[idx].pauseAfterStory = currentPause
                openProjects[idx].maxIterations = currentMax
                openProjects[idx].loopStartDate = currentStart
            }
        }
        loopEngines[project.id] = engine
        return engine
    }

    private func startLoop(for index: Int) {
        let project = openProjects[index]

        // Skip branch check when resuming from paused/stopped/error
        if project.loopState == .paused || project.loopState == .stopped || project.loopState == .error {
            proceedWithStart(for: index)
            return
        }

        // Check for protected branch before first start
        guard let dirURL = project.directoryURL else {
            proceedWithStart(for: index)
            return
        }

        let workingDir = dirURL.deletingLastPathComponent()
        do {
            let branch = try gitManager.currentBranch(at: workingDir)
            if gitManager.isProtectedBranch(branch) {
                branchWarningBranch = branch
                branchWarningIndex = index
                showBranchWarning = true
                return
            }
        } catch {
            // Not a git repo or git not available — proceed without warning
        }

        proceedWithStart(for: index)
    }

    private func proceedWithStart(for index: Int) {
        let project = openProjects[index]
        let engine = getOrCreateEngine(for: project)

        if project.maxIterations == 0 {
            openProjects[index].maxIterations = project.defaultMaxIterations
        }
        if project.loopStartDate == nil {
            openProjects[index].loopStartDate = Date()
        }

        openProjects[index].loopState = .running

        let projectToStart = openProjects[index]
        if project.loopState == .paused || project.loopState == .stopped || project.loopState == .error {
            engine.resume(project: projectToStart)
        } else {
            engine.start(project: projectToStart)
        }
    }

    private func handleCreateBranch(_ branchName: String, for index: Int) {
        guard let dirURL = openProjects[index].directoryURL else { return }
        let workingDir = dirURL.deletingLastPathComponent()
        do {
            try gitManager.createAndCheckoutBranch(branchName, at: workingDir)
            proceedWithStart(for: index)
        } catch {
            errorAlertMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    private func pauseLoop(for index: Int) {
        let project = openProjects[index]
        if let engine = loopEngines[project.id] {
            engine.pause()
        }
    }

    private func stopLoop(for index: Int) {
        let project = openProjects[index]
        if let engine = loopEngines[project.id] {
            engine.stop()
        }
    }

    private func statusBarMessage(for project: PRDProject?) -> String {
        guard let project else { return "No PRD loaded" }
        switch project.loopState {
        case .ready:
            return "Ready"
        case .running:
            if let story = project.userStories.first(where: { $0.inProgress }) {
                return "Working on: \(story.id) — \(story.title)"
            }
            return "Running..."
        case .paused:
            if let story = project.userStories.first(where: { $0.inProgress }) {
                return "Paused on: \(story.id) — \(story.title)"
            }
            return "Paused"
        case .stopped:
            return "Stopped"
        case .complete:
            let passCount = project.userStories.filter { $0.passes }.count
            return "Complete — \(passCount)/\(project.userStories.count) stories passed"
        case .error:
            return "Error — check log for details"
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let store = FileSystemPRDStore()
            do {
                let project = try store.loadProject(from: url)
                addProject(project)
            } catch {
                errorAlertMessage = error.localizedDescription
                showErrorAlert = true
            }
        case .failure(let error):
            errorAlertMessage = error.localizedDescription
            showErrorAlert = true
        }
    }
}

#Preview {
    ContentView()
}
