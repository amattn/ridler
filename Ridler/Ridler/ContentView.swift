import SwiftUI
import UniformTypeIdentifiers
import os

struct ContentView: View {
    private static let logger = Logger(subsystem: "com.amattn.Ridler", category: "ContentView")
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
    @ObservedObject private var settings = SettingsManager.shared
    @State private var loopEngines: [String: RalphLoopEngine] = [:]
    @State private var terminalManagers: [String: ClaudeTerminalManager] = [:]
    @State private var showBranchWarning = false
    @State private var branchWarningIndex: Int?
    @State private var branchWarningBranch: String = ""
    @State private var showDebugWindow = false
    @State private var showTerminateSessionAlert = false
    @State private var pendingLoopStartIndex: Int?
    private let gitManager: GitManaging = GitManager()

    private var selectedProject: PRDProject? {
        guard let id = selectedProjectID else { return nil }
        return openProjects.first { $0.id == id }
    }

    private var selectedProjectIndex: Int? {
        guard let id = selectedProjectID else { return nil }
        return openProjects.firstIndex { $0.id == id }
    }

    @ViewBuilder
    private var mainContent: some View {
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
                        },
                        onAutoRetryChanged: { enabled in
                            let project = openProjects[selectedIndex]
                            loopEngines[project.id]?.updateAutoRetry(enabled)
                        },
                        onAudioNotificationsChanged: { enabled in
                            let project = openProjects[selectedIndex]
                            loopEngines[project.id]?.updateAudioNotifications(enabled)
                        }
                    )
                }

                NavigationSplitView(columnVisibility: $columnVisibility) {
                    SidebarView(
                        project: selectedProject,
                        selection: $sidebarSelection,
                        onResume: selectedProjectIndex.map { idx in
                            { startLoop(for: idx) }
                        }
                    )
                        .id(fileWatcher.changeToken)
                } content: {
                    DetailView(project: selectedProject, selection: sidebarSelection)
                        .id(fileWatcher.changeToken)
                } detail: {
                    rightPaneView
                }

                StatusBarView(
                    activityMessage: statusBarMessage(for: selectedProject),
                    loopState: selectedProject?.loopState ?? .ready,
                    debugMode: settings.debugMode,
                    debugInfo: debugStatusInfo(for: selectedProject)
                )
            }
        }
    }

    var body: some View {
        mainContent
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
        .alert("Delete PRD", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let project = projectToDelete {
                    deleteProject(project)
                }
            }
            Button("Cancel", role: .cancel) {
                projectToDelete = nil
            }
        } message: {
            if let project = projectToDelete {
                Text("Are you sure you want to delete \"\(project.name ?? project.id)\"? This will permanently delete the PRD files from disk.")
            }
        }
        .alert("Active Claude Session", isPresented: $showTerminateSessionAlert) {
            Button("Terminate and Start") {
                if let idx = pendingLoopStartIndex {
                    let project = openProjects[idx]
                    terminalManagers[project.id]?.terminate()
                    // Switch sidebar selection to a story to show log view
                    if case .file = sidebarSelection {
                        sidebarSelection = nil
                    }
                    startLoop(for: idx)
                }
                pendingLoopStartIndex = nil
            }
            Button("Cancel", role: .cancel) {
                pendingLoopStartIndex = nil
            }
        } message: {
            Text("A Claude Code editing session is active. Starting the loop will terminate the current session.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPRD)) { _ in
            isFilePickerPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRecentPRD)) { notification in
            if let url = notification.object as? URL {
                let store = FileSystemPRDStore()
                do {
                    let project = try store.loadProject(from: url)
                    addProject(project)
                } catch {
                    errorAlertMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newPRD)) { _ in
            isNewPRDPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .startLoop)) { _ in
            if let idx = selectedProjectIndex {
                startLoop(for: idx)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pauseLoop)) { _ in
            if let idx = selectedProjectIndex {
                pauseLoop(for: idx)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .stopLoop)) { _ in
            if let idx = selectedProjectIndex {
                stopLoop(for: idx)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToTab)) { notification in
            if let tabNumber = notification.object as? Int,
               tabNumber >= 1, tabNumber <= openProjects.count {
                selectedProjectID = openProjects[tabNumber - 1].id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusLogPanel)) { _ in
            columnVisibility = .all
        }
        .onReceive(NotificationCenter.default.publisher(for: .editPRD)) { _ in
            if selectedProject != nil {
                // Select the prd.md file in sidebar to trigger the Claude terminal pane
                sidebarSelection = .file(.prdMd)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDebugWindow)) { _ in
            showDebugWindow = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .deletePRD)) { _ in
            if let project = selectedProject {
                projectToDelete = project
                showDeleteConfirmation = true
            }
        }
        .onReceive(fileWatcher.$changeToken.dropFirst()) { _ in
            reloadAllProjects()
        }
        .sheet(isPresented: $showDebugWindow) {
            DebugInfoView(
                projects: openProjects,
                loopEngines: loopEngines,
                fileWatcher: fileWatcher
            )
        }
        .focusedSceneValue(\.selectedProject, selectedProject)
        .focusedSceneValue(\.hasProject, !openProjects.isEmpty)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
            return true
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

    @ViewBuilder
    private var rightPaneView: some View {
        if let project = selectedProject, case .file(let fileName) = sidebarSelection {
            let manager = getOrCreateTerminalManager(for: project)
            ClaudeTerminalView(
                fileName: fileName,
                project: project,
                isLoopRunning: project.loopState == .running,
                terminalManager: manager,
                onStartSession: { file in
                    startTerminalSession(file: file, project: project)
                }
            )
        } else {
            LogPanelView(
                entries: logStore.entries(for: selectedProject?.id ?? ""),
                isRunning: selectedProject?.loopState == .running
            )
        }
    }

    private func getOrCreateTerminalManager(for project: PRDProject) -> ClaudeTerminalManager {
        if let existing = terminalManagers[project.id] {
            return existing
        }
        let manager = ClaudeTerminalManager()
        terminalManagers[project.id] = manager
        return manager
    }

    private func startTerminalSession(file: PRDFileName, project: PRDProject) {
        guard let dirURL = project.directoryURL else { return }
        let filePath = dirURL.appendingPathComponent(file.rawValue).path
        let fileExists = FileManager.default.fileExists(atPath: filePath)
        let workingDir = dirURL.deletingLastPathComponent()

        let manager = getOrCreateTerminalManager(for: project)
        manager.start(
            filePath: filePath,
            workingDirectory: workingDir,
            fileExists: fileExists,
            fileName: file.rawValue
        )
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

    @State private var showDeleteConfirmation = false
    @State private var projectToDelete: PRDProject?

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
        .contextMenu {
            Button {
                if let idx = openProjects.firstIndex(where: { $0.id == project.id }) {
                    startLoop(for: idx)
                }
            } label: {
                Label("Start", systemImage: "play.fill")
            }
            .disabled(!project.loopState.canTransition(to: .running))

            Button {
                if let idx = openProjects.firstIndex(where: { $0.id == project.id }) {
                    pauseLoop(for: idx)
                }
            } label: {
                Label("Pause", systemImage: "pause.fill")
            }
            .disabled(!project.loopState.canTransition(to: .paused))

            Button {
                if let idx = openProjects.firstIndex(where: { $0.id == project.id }) {
                    stopLoop(for: idx)
                }
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .disabled(!project.loopState.canTransition(to: .stopped))

            Divider()

            Button {
                selectedProjectID = project.id
                sidebarSelection = .file(.prdMd)
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Divider()

            Button {
                closeProject(project)
            } label: {
                Label("Close", systemImage: "xmark")
            }

            Button(role: .destructive) {
                projectToDelete = project
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(project.loopState == .running)
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
        var projectToAdd = project
        projectToAdd.audioNotificationsEnabled = settings.audioNotifications
        projectToAdd.autoRetryEnabled = settings.autoRetryOnCrash
        openProjects.append(projectToAdd)
        selectedProjectID = projectToAdd.id
        Self.logger.info("Opened project: \(projectToAdd.name ?? projectToAdd.id)")
        if let dirURL = project.directoryURL {
            fileWatcher.watch(directoryURL: dirURL)
            RecentProjectsManager.shared.addRecent(dirURL)
        }
    }

    private func closeProject(_ project: PRDProject) {
        Self.logger.info("Closing project: \(project.name ?? project.id)")
        // Stop the engine if it's running
        if let engine = loopEngines[project.id] {
            engine.stop()
            loopEngines.removeValue(forKey: project.id)
        }
        // Terminate any active terminal session
        if let manager = terminalManagers[project.id] {
            manager.terminate()
            terminalManagers.removeValue(forKey: project.id)
        }
        if let dirURL = project.directoryURL {
            fileWatcher.unwatch(directoryURL: dirURL)
        }
        openProjects.removeAll { $0.id == project.id }
        if selectedProjectID == project.id {
            selectedProjectID = openProjects.first?.id
        }
    }

    private func deleteProject(_ project: PRDProject) {
        Self.logger.info("Deleting project: \(project.name ?? project.id)")
        closeProject(project)
        if let dirURL = project.directoryURL {
            try? FileManager.default.removeItem(at: dirURL)
        }
        projectToDelete = nil
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
                updated.autoRetryEnabled = openProjects[index].autoRetryEnabled
                updated.audioNotificationsEnabled = openProjects[index].audioNotificationsEnabled
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
            Self.logger.info("State transition for \(project.name ?? project.id): \(String(describing: newState))")
            if let idx = openProjects.firstIndex(where: { $0.id == project.id }) {
                openProjects[idx].loopState = newState
            }
        }
        engine.onIterationChange = { [self] count in
            Self.logger.info("Iteration \(count) for \(project.name ?? project.id)")
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
                let currentAutoRetry = openProjects[idx].autoRetryEnabled
                let currentAudio = openProjects[idx].audioNotificationsEnabled
                let currentMax = openProjects[idx].maxIterations
                let currentStart = openProjects[idx].loopStartDate
                openProjects[idx] = updatedProject
                openProjects[idx].loopState = currentState
                openProjects[idx].iterationCount = currentIteration
                openProjects[idx].pauseAfterStory = currentPause
                openProjects[idx].autoRetryEnabled = currentAutoRetry
                openProjects[idx].audioNotificationsEnabled = currentAudio
                openProjects[idx].maxIterations = currentMax
                openProjects[idx].loopStartDate = currentStart
            }
        }
        loopEngines[project.id] = engine
        return engine
    }

    private func startLoop(for index: Int) {
        let project = openProjects[index]
        Self.logger.info("Start loop requested for: \(project.name ?? project.id), state: \(String(describing: project.loopState))")

        // Check for active Claude terminal session
        if let manager = terminalManagers[project.id], manager.isRunning {
            pendingLoopStartIndex = index
            showTerminateSessionAlert = true
            return
        }

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
            Self.logger.error("Failed to create branch \(branchName): \(error.localizedDescription)")
            errorAlertMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    private func pauseLoop(for index: Int) {
        let project = openProjects[index]
        Self.logger.info("Pause loop requested for: \(project.name ?? project.id)")
        if let engine = loopEngines[project.id] {
            engine.pause()
        }
    }

    private func stopLoop(for index: Int) {
        let project = openProjects[index]
        Self.logger.info("Stop loop requested for: \(project.name ?? project.id)")
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

    private func debugStatusInfo(for project: PRDProject?) -> DebugStatusInfo? {
        guard settings.debugMode, let project else { return nil }
        let engine = loopEngines[project.id]
        let currentStory = project.userStories.first(where: { $0.inProgress })

        var elapsedStr: String?
        if let startDate = project.loopStartDate, project.loopState == .running {
            let elapsed = Date().timeIntervalSince(startDate)
            let iterCount = max(project.iterationCount, 1)
            let perIter = elapsed / Double(iterCount)
            let minutes = Int(perIter) / 60
            let seconds = Int(perIter) % 60
            elapsedStr = "\(minutes)m \(seconds)s"
        }

        return DebugStatusInfo(
            loopStateRawValue: "\(project.loopState)",
            currentStoryID: currentStory?.id,
            retryCount: engine?.currentRetryCount ?? 0,
            elapsedPerIteration: elapsedStr
        )
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, error in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    if let error {
                        DispatchQueue.main.async {
                            errorAlertMessage = error.localizedDescription
                            showErrorAlert = true
                        }
                    }
                    return
                }
                DispatchQueue.main.async {
                    let store = FileSystemPRDStore()
                    do {
                        let project = try store.loadProject(from: url)
                        addProject(project)
                    } catch {
                        errorAlertMessage = error.localizedDescription
                        showErrorAlert = true
                    }
                }
            }
            break // Only handle the first dropped item
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
