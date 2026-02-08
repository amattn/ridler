import AppKit
import UniformTypeIdentifiers

struct PRDTab: Identifiable, Equatable {
    let id: String
    let filePath: String
    var prdProject: PRDProject?
    var jsonPath: String?

    var name: String {
        prdProject?.project ?? URL(fileURLWithPath: filePath).deletingLastPathComponent().lastPathComponent
    }

    var directory: String {
        PRDFileManager.companionDirectory(for: filePath)
    }

    init(filePath: String, prdProject: PRDProject? = nil, jsonPath: String? = nil) {
        self.id = filePath
        self.filePath = filePath
        self.prdProject = prdProject
        self.jsonPath = jsonPath
    }
}

@Observable
final class PRDManager {
    private(set) var tabs: [PRDTab] = []
    var selectedTabId: String?
    var selectedStoryId: String?

    var showNewPRDSheet = false

    private(set) var engines: [String: RalphLoopEngine] = [:]
    private let fileWatcher: FileWatcher
    private let persistenceKey = "com.amattn.ridler.openedPRDs"
    private let recentFilesKey = "com.amattn.ridler.recentPRDs"
    private let maxRecentFiles = 10

    var recentFiles: [String] {
        UserDefaults.standard.stringArray(forKey: recentFilesKey) ?? []
    }

    var selectedTab: PRDTab? {
        guard let id = selectedTabId else { return nil }
        return tabs.first { $0.id == id }
    }

    var selectedPRD: PRDProject? {
        selectedTab?.prdProject
    }

    init(fileWatcher: FileWatcher = FileWatcher()) {
        self.fileWatcher = fileWatcher
        self.fileWatcher.delegate = self
        restoreOpenedPRDs()
    }

    // MARK: - Validation

    static func isValidPRDName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    // MARK: - Tab Management

    func openPRD(filePath: String) throws {
        let normalizedPath = (filePath as NSString).standardizingPath

        // Already open — switch to it
        if let existing = tabs.first(where: { $0.filePath == normalizedPath }) {
            selectedTabId = existing.id
            return
        }

        let (project, jsonPath) = try PRDFileManager.loadFromCompanion(filePath: normalizedPath)
        let tab = PRDTab(filePath: normalizedPath, prdProject: project, jsonPath: jsonPath)
        tabs.append(tab)
        selectedTabId = tab.id

        fileWatcher.watch(directory: tab.directory)
        addToRecentFiles(normalizedPath)
        persistOpenedPRDs()
    }

    func createPRD(name: String, directoryPath: String) throws {
        let dirURL = URL(fileURLWithPath: directoryPath)
        let prdPath = dirURL.appendingPathComponent("prd.md").path

        let content = "# \(name)\n\nNew PRD project.\n"
        try content.write(toFile: prdPath, atomically: true, encoding: .utf8)

        let tab = PRDTab(filePath: prdPath)
        tabs.append(tab)
        selectedTabId = tab.id

        fileWatcher.watch(directory: PRDFileManager.companionDirectory(for: prdPath))
        persistOpenedPRDs()
    }

    func closeTab(id: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[index]

        // Stop engine if running
        if let engine = engines[id] {
            engine.stop()
            engines.removeValue(forKey: id)
        }

        fileWatcher.stopWatching(directory: tab.directory)
        tabs.remove(at: index)

        // Select another tab or clear
        if selectedTabId == id {
            selectedTabId = tabs.last?.id
            selectedStoryId = nil
        }

        persistOpenedPRDs()
    }

    // MARK: - File Open

    func openFilePanel() {
        let panel = NSOpenPanel()
        panel.title = "Open PRD"
        var types: [UTType] = []
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        if let json = UTType(filenameExtension: "json") { types.append(json) }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? openPRD(filePath: url.path)
    }

    func clearRecentFiles() {
        UserDefaults.standard.removeObject(forKey: recentFilesKey)
    }

    private func addToRecentFiles(_ path: String) {
        var recents = UserDefaults.standard.stringArray(forKey: recentFilesKey) ?? []
        recents.removeAll { $0 == path }
        recents.insert(path, at: 0)
        if recents.count > maxRecentFiles {
            recents = Array(recents.prefix(maxRecentFiles))
        }
        UserDefaults.standard.set(recents, forKey: recentFilesKey)
    }

    // MARK: - Loop State

    func loopState(for tabId: String) -> LoopState {
        engines[tabId]?.stateMachine.state ?? .ready
    }

    func storyProgress(for tabId: String) -> (passed: Int, total: Int) {
        guard let tab = tabs.first(where: { $0.id == tabId }),
              let prd = tab.prdProject else { return (0, 0) }
        let passed = prd.userStories.filter { $0.passes }.count
        return (passed, prd.userStories.count)
    }

    func iterationCount(for tabId: String) -> Int {
        engines[tabId]?.currentIteration ?? 0
    }

    // MARK: - Loop Controls

    func start(tabId: String) async {
        guard let tab = tabs.first(where: { $0.id == tabId }),
              let jsonPath = tab.jsonPath else { return }

        let maxIter = defaultMaxIterations(for: tabId)

        let engine: RalphLoopEngine
        if let existing = engines[tabId], existing.stateMachine.state == .paused || existing.stateMachine.state == .stopped || existing.stateMachine.state == .error {
            engine = existing
            await engine.resume()
            return
        }

        engine = RalphLoopEngine(
            prdFilePath: jsonPath,
            workingDirectory: tab.directory,
            maxIterations: maxIter
        )
        engines[tabId] = engine
        await engine.start()
    }

    func pause(tabId: String) {
        engines[tabId]?.pause()
    }

    func stop(tabId: String) {
        engines[tabId]?.stop()
    }

    func defaultMaxIterations(for tabId: String) -> Int {
        guard let tab = tabs.first(where: { $0.id == tabId }),
              let prd = tab.prdProject else { return 5 }
        let remaining = prd.userStories.filter { !$0.passes }.count
        return max(remaining + 5, 5)
    }

    // MARK: - Reload

    func reloadPRD(tabId: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        let tab = tabs[index]

        guard let (project, jsonPath) = try? PRDFileManager.loadFromCompanion(filePath: tab.filePath) else { return }
        tabs[index] = PRDTab(filePath: tab.filePath, prdProject: project, jsonPath: jsonPath)
    }

    // MARK: - Persistence

    private func persistOpenedPRDs() {
        let paths = tabs.map { $0.filePath }
        UserDefaults.standard.set(paths, forKey: persistenceKey)
    }

    private func restoreOpenedPRDs() {
        guard let paths = UserDefaults.standard.stringArray(forKey: persistenceKey) else { return }
        for path in paths {
            try? openPRD(filePath: path)
        }
    }
}

// MARK: - FileWatcherDelegate

extension PRDManager: FileWatcherDelegate {
    func fileWatcher(_ watcher: FileWatcher, didDetectChangesIn event: FileChangeEvent) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for tab in self.tabs where tab.directory == event.directory || event.path.hasPrefix(tab.directory) {
                self.reloadPRD(tabId: tab.id)
            }
        }
    }
}
