import XCTest
@testable import Ridler

final class PRDTabTests: XCTestCase {

    func testTabIdIsFilePath() {
        let tab = PRDTab(filePath: "/tmp/test/prd.md")
        XCTAssertEqual(tab.id, "/tmp/test/prd.md")
    }

    func testTabNameFromProject() {
        let project = PRDProject(project: "MyProject", description: "desc", userStories: [])
        let tab = PRDTab(filePath: "/tmp/test/prd.md", prdProject: project)
        XCTAssertEqual(tab.name, "MyProject")
    }

    func testTabNameFallsBackToDirectoryName() {
        let tab = PRDTab(filePath: "/tmp/test-dir/prd.md")
        XCTAssertEqual(tab.name, "test-dir")
    }

    func testTabDirectory() {
        let tab = PRDTab(filePath: "/tmp/projects/myapp/prd.md")
        XCTAssertEqual(tab.directory, "/tmp/projects/myapp")
    }

    func testTabEquality() {
        let proj = PRDProject(project: "P", description: "d", userStories: [])
        let tab1 = PRDTab(filePath: "/tmp/a/prd.md", prdProject: proj, jsonPath: "/tmp/a/ridl.json")
        let tab2 = PRDTab(filePath: "/tmp/a/prd.md", prdProject: proj, jsonPath: "/tmp/a/ridl.json")
        XCTAssertEqual(tab1, tab2)
    }
}

final class PRDManagerTests: XCTestCase {

    private var tempDir: String!
    private var manager: PRDManager!

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory() + "PRDManagerTests-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        // Use a unique persistence key to avoid polluting UserDefaults
        manager = PRDManager(fileWatcher: FileWatcher(debounceInterval: 10.0))
        // Clear any persisted state
        UserDefaults.standard.removeObject(forKey: "com.amattn.ridler.openedPRDs")
    }

    override func tearDown() {
        manager = nil
        try? FileManager.default.removeItem(atPath: tempDir)
        UserDefaults.standard.removeObject(forKey: "com.amattn.ridler.openedPRDs")
        super.tearDown()
    }

    // MARK: - Helpers

    private func createSamplePRD(name: String = "TestProject", dir: String? = nil) -> (jsonPath: String, prdDir: String) {
        let prdDir = dir ?? tempDir + "/\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: prdDir, withIntermediateDirectories: true)

        let project = PRDProject(
            project: name,
            description: "Test project",
            userStories: [
                UserStory(id: "US-001", title: "First Story", description: "Desc A",
                          acceptanceCriteria: ["AC1"], priority: 1, passes: true, inProgress: false),
                UserStory(id: "US-002", title: "Second Story", description: "Desc B",
                          acceptanceCriteria: ["AC2"], priority: 2, passes: false, inProgress: false)
            ]
        )

        let jsonPath = prdDir + "/prd.json"
        try! PRDFileManager.save(project, to: jsonPath)
        return (jsonPath, prdDir)
    }

    // MARK: - Open PRD Tests

    func testOpenPRDAddsTab() throws {
        let (jsonPath, _) = createSamplePRD()
        try manager.openPRD(filePath: jsonPath)

        XCTAssertEqual(manager.tabs.count, 1)
        XCTAssertEqual(manager.tabs[0].prdProject?.project, "TestProject")
        XCTAssertEqual(manager.tabs[0].jsonPath, jsonPath)
    }

    func testOpenPRDSelectsNewTab() throws {
        let (jsonPath, _) = createSamplePRD()
        try manager.openPRD(filePath: jsonPath)

        XCTAssertNotNil(manager.selectedTabId)
        XCTAssertEqual(manager.selectedTab?.prdProject?.project, "TestProject")
    }

    func testOpenSamePRDTwiceSwitchesToExisting() throws {
        let (jsonPath, _) = createSamplePRD()
        try manager.openPRD(filePath: jsonPath)
        try manager.openPRD(filePath: jsonPath)

        XCTAssertEqual(manager.tabs.count, 1)
    }

    func testOpenMultiplePRDs() throws {
        let (json1, _) = createSamplePRD(name: "Project1")
        let (json2, _) = createSamplePRD(name: "Project2")

        try manager.openPRD(filePath: json1)
        try manager.openPRD(filePath: json2)

        XCTAssertEqual(manager.tabs.count, 2)
        // Selected tab should be the last opened
        XCTAssertEqual(manager.selectedTab?.prdProject?.project, "Project2")
    }

    func testOpenInvalidPathThrows() {
        XCTAssertThrowsError(try manager.openPRD(filePath: "/nonexistent/prd.json"))
    }

    // MARK: - Create PRD Tests

    func testCreatePRDCreatesFileAndOpens() throws {
        let dir = tempDir + "/newproject"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        try manager.createPRD(name: "NewApp", directoryPath: dir)

        XCTAssertEqual(manager.tabs.count, 1)
        let prdPath = dir + "/prd.md"
        XCTAssertTrue(FileManager.default.fileExists(atPath: prdPath))

        let content = try String(contentsOfFile: prdPath, encoding: .utf8)
        XCTAssertTrue(content.contains("# NewApp"))
    }

    // MARK: - Close Tab Tests

    func testCloseTabRemovesIt() throws {
        let (jsonPath, _) = createSamplePRD()
        try manager.openPRD(filePath: jsonPath)
        let tabId = manager.tabs[0].id

        manager.closeTab(id: tabId)

        XCTAssertEqual(manager.tabs.count, 0)
        XCTAssertNil(manager.selectedTabId)
    }

    func testCloseTabSelectsAnother() throws {
        let (json1, _) = createSamplePRD(name: "Project1")
        let (json2, _) = createSamplePRD(name: "Project2")

        try manager.openPRD(filePath: json1)
        try manager.openPRD(filePath: json2)

        let tab2Id = manager.tabs[1].id
        manager.closeTab(id: tab2Id)

        XCTAssertEqual(manager.tabs.count, 1)
        XCTAssertEqual(manager.selectedTab?.prdProject?.project, "Project1")
    }

    func testCloseNonSelectedTabKeepsSelection() throws {
        let (json1, _) = createSamplePRD(name: "Project1")
        let (json2, _) = createSamplePRD(name: "Project2")

        try manager.openPRD(filePath: json1)
        try manager.openPRD(filePath: json2)

        let tab1Id = manager.tabs[0].id
        manager.closeTab(id: tab1Id)

        XCTAssertEqual(manager.tabs.count, 1)
        XCTAssertEqual(manager.selectedTab?.prdProject?.project, "Project2")
    }

    // MARK: - Story Progress Tests

    func testStoryProgress() throws {
        let (jsonPath, _) = createSamplePRD()
        try manager.openPRD(filePath: jsonPath)
        let tabId = manager.tabs[0].id

        let progress = manager.storyProgress(for: tabId)
        XCTAssertEqual(progress.passed, 1)
        XCTAssertEqual(progress.total, 2)
    }

    func testStoryProgressForUnknownTab() {
        let progress = manager.storyProgress(for: "nonexistent")
        XCTAssertEqual(progress.passed, 0)
        XCTAssertEqual(progress.total, 0)
    }

    // MARK: - Loop State Tests

    func testDefaultLoopState() throws {
        let (jsonPath, _) = createSamplePRD()
        try manager.openPRD(filePath: jsonPath)
        let tabId = manager.tabs[0].id

        XCTAssertEqual(manager.loopState(for: tabId), .ready)
    }

    func testLoopStateForUnknownTab() {
        XCTAssertEqual(manager.loopState(for: "nonexistent"), .ready)
    }

    // MARK: - Iteration Count Tests

    func testDefaultIterationCount() throws {
        let (jsonPath, _) = createSamplePRD()
        try manager.openPRD(filePath: jsonPath)
        let tabId = manager.tabs[0].id

        XCTAssertEqual(manager.iterationCount(for: tabId), 0)
    }

    // MARK: - Max Iterations Tests

    func testDefaultMaxIterations() throws {
        let (jsonPath, _) = createSamplePRD()
        try manager.openPRD(filePath: jsonPath)
        let tabId = manager.tabs[0].id

        // 1 remaining + 5 = 6, max(6, 5) = 6
        let maxIter = manager.defaultMaxIterations(for: tabId)
        XCTAssertEqual(maxIter, 6)
    }

    func testMaxIterationsMinimumFive() throws {
        let prdDir = tempDir + "/\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: prdDir, withIntermediateDirectories: true)

        let project = PRDProject(
            project: "AllDone",
            description: "Everything passes",
            userStories: [
                UserStory(id: "US-001", title: "Done", description: "Done",
                          acceptanceCriteria: [], priority: 1, passes: true, inProgress: false)
            ]
        )
        let jsonPath = prdDir + "/prd.json"
        try PRDFileManager.save(project, to: jsonPath)

        try manager.openPRD(filePath: jsonPath)
        let tabId = manager.tabs[0].id

        // 0 remaining + 5 = 5, max(5, 5) = 5
        XCTAssertEqual(manager.defaultMaxIterations(for: tabId), 5)
    }

    func testMaxIterationsUnknownTab() {
        XCTAssertEqual(manager.defaultMaxIterations(for: "nonexistent"), 5)
    }

    // MARK: - Reload Tests

    func testReloadPRDUpdatesData() throws {
        let (jsonPath, _) = createSamplePRD(name: "OriginalName")
        try manager.openPRD(filePath: jsonPath)
        let tabId = manager.tabs[0].id

        XCTAssertEqual(manager.tabs[0].prdProject?.project, "OriginalName")

        // Modify the file on disk
        var project = try PRDFileManager.load(from: jsonPath)
        project.project = "UpdatedName"
        try PRDFileManager.save(project, to: jsonPath)

        manager.reloadPRD(tabId: tabId)

        XCTAssertEqual(manager.tabs[0].prdProject?.project, "UpdatedName")
    }

    func testReloadNonexistentTabIsNoOp() {
        // Should not crash
        manager.reloadPRD(tabId: "nonexistent")
    }

    // MARK: - Selected PRD Tests

    func testSelectedPRDReturnsCorrectProject() throws {
        let (jsonPath, _) = createSamplePRD(name: "SelectedProject")
        try manager.openPRD(filePath: jsonPath)

        XCTAssertEqual(manager.selectedPRD?.project, "SelectedProject")
    }

    func testSelectedPRDIsNilWhenNoTabSelected() {
        XCTAssertNil(manager.selectedPRD)
    }

    // MARK: - Selected Story Tests

    func testSelectedStoryIdDefaultsToNil() {
        XCTAssertNil(manager.selectedStoryId)
    }

    func testSelectedStoryIdCanBeSet() throws {
        let (jsonPath, _) = createSamplePRD()
        try manager.openPRD(filePath: jsonPath)

        manager.selectedStoryId = "US-001"
        XCTAssertEqual(manager.selectedStoryId, "US-001")
    }

    // MARK: - Persistence Tests

    func testPersistenceStoresOpenedPaths() throws {
        let (jsonPath, _) = createSamplePRD()
        try manager.openPRD(filePath: jsonPath)

        let paths = UserDefaults.standard.stringArray(forKey: "com.amattn.ridler.openedPRDs")
        XCTAssertNotNil(paths)
        XCTAssertEqual(paths?.count, 1)
    }

    func testCloseTabUpdatesPersistence() throws {
        let (jsonPath, _) = createSamplePRD()
        try manager.openPRD(filePath: jsonPath)
        let tabId = manager.tabs[0].id

        manager.closeTab(id: tabId)

        let paths = UserDefaults.standard.stringArray(forKey: "com.amattn.ridler.openedPRDs")
        XCTAssertNotNil(paths)
        XCTAssertEqual(paths?.count, 0)
    }

    // MARK: - Pause/Stop without Engine

    func testPauseWithoutEngineIsNoOp() throws {
        let (jsonPath, _) = createSamplePRD()
        try manager.openPRD(filePath: jsonPath)
        let tabId = manager.tabs[0].id

        // Should not crash
        manager.pause(tabId: tabId)
    }

    func testStopWithoutEngineIsNoOp() throws {
        let (jsonPath, _) = createSamplePRD()
        try manager.openPRD(filePath: jsonPath)
        let tabId = manager.tabs[0].id

        // Should not crash
        manager.stop(tabId: tabId)
    }
}
