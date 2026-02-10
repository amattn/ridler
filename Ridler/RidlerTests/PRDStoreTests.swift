import XCTest
@testable import Ridler

final class FileSystemPRDStoreTests: XCTestCase {
    var store: FileSystemPRDStore!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        store = FileSystemPRDStore()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RidlerTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - loadProject

    func testLoadProjectValidJSON() throws {
        let json = """
        {
            "project": "Test",
            "description": "A test project",
            "userStories": [
                {
                    "id": "US-001",
                    "title": "Story 1",
                    "description": "Description 1",
                    "priority": 1,
                    "acceptanceCriteria": ["AC1", "AC2"],
                    "passes": true,
                    "inProgress": false
                },
                {
                    "id": "US-002",
                    "title": "Story 2",
                    "description": "Description 2",
                    "priority": 2,
                    "acceptanceCriteria": ["AC3"]
                }
            ]
        }
        """
        try json.write(to: tempDir.appendingPathComponent("ridl.json"), atomically: true, encoding: .utf8)

        let project = try store.loadProject(from: tempDir)

        XCTAssertEqual(project.project, "Test")
        XCTAssertEqual(project.description, "A test project")
        XCTAssertEqual(project.userStories.count, 2)
        XCTAssertEqual(project.userStories[0].id, "US-001")
        XCTAssertTrue(project.userStories[0].passes)
        XCTAssertFalse(project.userStories[0].inProgress)
        XCTAssertEqual(project.userStories[1].id, "US-002")
        XCTAssertFalse(project.userStories[1].passes)
        XCTAssertFalse(project.userStories[1].inProgress)
        XCTAssertEqual(project.directoryURL, tempDir)
    }

    func testLoadProjectMissingOptionalFields() throws {
        let json = """
        {
            "userStories": [
                {
                    "id": "US-001",
                    "title": "Minimal",
                    "description": "Minimal story",
                    "priority": 1,
                    "acceptanceCriteria": []
                }
            ]
        }
        """
        try json.write(to: tempDir.appendingPathComponent("ridl.json"), atomically: true, encoding: .utf8)

        let project = try store.loadProject(from: tempDir)

        XCTAssertNil(project.name)
        XCTAssertNil(project.project)
        XCTAssertNil(project.description)
        XCTAssertNil(project.milestones)
        XCTAssertEqual(project.userStories.count, 1)
        XCTAssertFalse(project.userStories[0].passes)
        XCTAssertFalse(project.userStories[0].inProgress)
    }

    func testLoadProjectMalformedJSON() throws {
        let badJSON = "{ this is not valid json }"
        try badJSON.write(to: tempDir.appendingPathComponent("ridl.json"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try store.loadProject(from: tempDir)) { error in
            guard let ridlerError = error as? RidlerError else {
                XCTFail("Expected RidlerError, got \(error)")
                return
            }
            if case .jsonDecoding(let file, _, _, _) = ridlerError {
                XCTAssertEqual(file, "ridl.json")
            } else {
                XCTFail("Expected jsonDecoding error, got \(ridlerError)")
            }
        }
    }

    func testLoadProjectMissingRequiredField() throws {
        let json = """
        {
            "project": "Test"
        }
        """
        try json.write(to: tempDir.appendingPathComponent("ridl.json"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try store.loadProject(from: tempDir)) { error in
            guard let ridlerError = error as? RidlerError else {
                XCTFail("Expected RidlerError, got \(error)")
                return
            }
            if case .jsonDecoding(let file, let key, _, _) = ridlerError {
                XCTAssertEqual(file, "ridl.json")
                XCTAssertEqual(key, "userStories")
            } else {
                XCTFail("Expected jsonDecoding error, got \(ridlerError)")
            }
        }
    }

    func testLoadProjectMissingFile() {
        XCTAssertThrowsError(try store.loadProject(from: tempDir)) { error in
            guard let ridlerError = error as? RidlerError else {
                XCTFail("Expected RidlerError, got \(error)")
                return
            }
            if case .fileNotFound(let path, let filenames) = ridlerError {
                XCTAssertEqual(path, tempDir.path)
                XCTAssertTrue(filenames.contains("ridl.json"))
            } else {
                XCTFail("Expected fileNotFound error, got \(ridlerError)")
            }
        }
    }

    func testLoadProjectNonexistentDirectory() {
        let bogusDir = tempDir.appendingPathComponent("nonexistent")

        XCTAssertThrowsError(try store.loadProject(from: bogusDir)) { error in
            guard let ridlerError = error as? RidlerError else {
                XCTFail("Expected RidlerError, got \(error)")
                return
            }
            if case .fileNotFound(let path, _) = ridlerError {
                XCTAssertTrue(path.contains("nonexistent"))
            } else {
                XCTFail("Expected fileNotFound error, got \(ridlerError)")
            }
        }
    }

    func testLoadProjectSetsDirectoryURL() throws {
        let json = """
        {
            "userStories": []
        }
        """
        try json.write(to: tempDir.appendingPathComponent("ridl.json"), atomically: true, encoding: .utf8)

        let project = try store.loadProject(from: tempDir)
        XCTAssertEqual(project.directoryURL, tempDir)
    }

    func testLoadProjectFromFileURL() throws {
        let json = """
        {
            "userStories": []
        }
        """
        try json.write(to: tempDir.appendingPathComponent("ridl.json"), atomically: true, encoding: .utf8)
        let prdMd = "# PRD\nSome content"
        try prdMd.write(to: tempDir.appendingPathComponent("prd.md"), atomically: true, encoding: .utf8)

        // Pass a file URL instead of a directory URL
        let fileURL = tempDir.appendingPathComponent("prd.md")
        let project = try store.loadProject(from: fileURL)
        XCTAssertEqual(project.directoryURL?.standardizedFileURL, tempDir.standardizedFileURL)
    }

    // MARK: - loadMarkdown

    func testLoadMarkdownSuccess() throws {
        let content = "# My PRD\n\nThis is a test PRD."
        try content.write(to: tempDir.appendingPathComponent("prd.md"), atomically: true, encoding: .utf8)

        let loaded = try store.loadMarkdown(filename: "prd.md", from: tempDir)
        XCTAssertEqual(loaded, content)
    }

    func testLoadMarkdownMissingFile() {
        XCTAssertThrowsError(try store.loadMarkdown(filename: "prd.md", from: tempDir)) { error in
            guard let ridlerError = error as? RidlerError else {
                XCTFail("Expected RidlerError, got \(error)")
                return
            }
            if case .fileNotFound(_, let filenames) = ridlerError {
                XCTAssertTrue(filenames.contains("prd.md"))
            } else {
                XCTFail("Expected fileNotFound error, got \(ridlerError)")
            }
        }
    }

    func testLoadRidlMdSuccess() throws {
        let content = "# RIDL\n\n## US-001\nCreate project"
        try content.write(to: tempDir.appendingPathComponent("ridl.md"), atomically: true, encoding: .utf8)

        let loaded = try store.loadMarkdown(filename: "ridl.md", from: tempDir)
        XCTAssertEqual(loaded, content)
    }

    // MARK: - loadMarkdownIfExists

    func testLoadMarkdownIfExistsReturnsContent() throws {
        let content = "# Optional file"
        try content.write(to: tempDir.appendingPathComponent("ridl.md"), atomically: true, encoding: .utf8)

        let loaded = store.loadMarkdownIfExists(filename: "ridl.md", from: tempDir)
        XCTAssertEqual(loaded, content)
    }

    func testLoadMarkdownIfExistsReturnsNilWhenMissing() {
        let loaded = store.loadMarkdownIfExists(filename: "ridl.md", from: tempDir)
        XCTAssertNil(loaded)
    }

    // MARK: - writeProject

    func testWriteProjectRoundTrip() throws {
        let project = PRDProject(
            project: "Test",
            description: "Round trip test",
            userStories: [
                UserStory(
                    id: "US-001",
                    title: "Story 1",
                    description: "Desc",
                    priority: 1,
                    acceptanceCriteria: ["AC1"],
                    passes: false,
                    inProgress: true
                )
            ]
        )

        try store.writeProject(project, to: tempDir)

        let loaded = try store.loadProject(from: tempDir)
        XCTAssertEqual(loaded.project, "Test")
        XCTAssertEqual(loaded.description, "Round trip test")
        XCTAssertEqual(loaded.userStories.count, 1)
        XCTAssertFalse(loaded.userStories[0].passes)
        XCTAssertTrue(loaded.userStories[0].inProgress)
    }

    func testWriteProjectProducesPrettyPrintedJSON() throws {
        let project = PRDProject(
            project: "Pretty",
            userStories: []
        )

        try store.writeProject(project, to: tempDir)

        let data = try Data(contentsOf: tempDir.appendingPathComponent("ridl.json"))
        let jsonString = String(data: data, encoding: .utf8)!

        // Pretty-printed JSON contains newlines and indentation
        XCTAssertTrue(jsonString.contains("\n"))
        XCTAssertTrue(jsonString.contains("  "))
    }

    func testWriteProjectPreservesAllFields() throws {
        let json = """
        {
            "project": "Test",
            "description": "Full project",
            "userStories": [
                {
                    "id": "US-001",
                    "title": "Story",
                    "description": "Desc",
                    "priority": 1,
                    "acceptanceCriteria": ["AC1"]
                }
            ],
            "milestones": [
                {
                    "name": "M1",
                    "storyIDs": ["US-001"]
                }
            ]
        }
        """
        try json.write(to: tempDir.appendingPathComponent("ridl.json"), atomically: true, encoding: .utf8)

        var project = try store.loadProject(from: tempDir)
        project.userStories[0].passes = true
        project.userStories[0].inProgress = false

        try store.writeProject(project, to: tempDir)
        let reloaded = try store.loadProject(from: tempDir)

        XCTAssertEqual(reloaded.project, "Test")
        XCTAssertEqual(reloaded.description, "Full project")
        XCTAssertTrue(reloaded.userStories[0].passes)
        XCTAssertFalse(reloaded.userStories[0].inProgress)
        XCTAssertEqual(reloaded.milestones?.count, 1)
        XCTAssertEqual(reloaded.milestones?[0].name, "M1")
    }

    // MARK: - US-004: Write PRD state updates

    func testWriteProjectModifyPassesAndInProgress() throws {
        // Read → modify passes/inProgress → write → read
        let json = """
        {
            "project": "State Test",
            "userStories": [
                {
                    "id": "US-001",
                    "title": "Story 1",
                    "description": "Desc 1",
                    "priority": 1,
                    "acceptanceCriteria": ["AC1"],
                    "passes": false,
                    "inProgress": false
                },
                {
                    "id": "US-002",
                    "title": "Story 2",
                    "description": "Desc 2",
                    "priority": 2,
                    "acceptanceCriteria": ["AC2"],
                    "passes": false,
                    "inProgress": false
                }
            ]
        }
        """
        try json.write(to: tempDir.appendingPathComponent("ridl.json"), atomically: true, encoding: .utf8)

        // Read
        var project = try store.loadProject(from: tempDir)
        XCTAssertFalse(project.userStories[0].passes)
        XCTAssertFalse(project.userStories[0].inProgress)

        // Modify: mark story 1 as in progress
        project.userStories[0].inProgress = true

        // Write
        try store.writeProject(project, to: tempDir)

        // Read again
        var reloaded = try store.loadProject(from: tempDir)
        XCTAssertFalse(reloaded.userStories[0].passes)
        XCTAssertTrue(reloaded.userStories[0].inProgress)
        XCTAssertFalse(reloaded.userStories[1].passes)
        XCTAssertFalse(reloaded.userStories[1].inProgress)

        // Modify: mark story 1 as passed, no longer in progress
        reloaded.userStories[0].passes = true
        reloaded.userStories[0].inProgress = false

        // Write again
        try store.writeProject(reloaded, to: tempDir)

        // Read final state
        let final = try store.loadProject(from: tempDir)
        XCTAssertTrue(final.userStories[0].passes)
        XCTAssertFalse(final.userStories[0].inProgress)
        XCTAssertFalse(final.userStories[1].passes)
        XCTAssertFalse(final.userStories[1].inProgress)
    }

    func testWriteProjectConcurrentSafety() throws {
        // Verify that concurrent writes using .atomic don't corrupt the file
        let project = PRDProject(
            project: "Concurrent",
            userStories: [
                UserStory(id: "US-001", title: "S1", description: "D1", priority: 1, acceptanceCriteria: ["AC1"]),
                UserStory(id: "US-002", title: "S2", description: "D2", priority: 2, acceptanceCriteria: ["AC2"])
            ]
        )
        try store.writeProject(project, to: tempDir)

        let expectation = XCTestExpectation(description: "Concurrent writes complete")
        expectation.expectedFulfillmentCount = 10
        let queue = DispatchQueue(label: "concurrent-test", attributes: .concurrent)

        for i in 0..<10 {
            queue.async {
                do {
                    var copy = project
                    copy.userStories[0].passes = (i % 2 == 0)
                    copy.userStories[1].inProgress = (i % 2 != 0)
                    try self.store.writeProject(copy, to: self.tempDir)
                    expectation.fulfill()
                } catch {
                    XCTFail("Concurrent write failed: \(error)")
                }
            }
        }

        wait(for: [expectation], timeout: 5.0)

        // File should be valid JSON after all concurrent writes
        let final = try store.loadProject(from: tempDir)
        XCTAssertEqual(final.project, "Concurrent")
        XCTAssertEqual(final.userStories.count, 2)
    }

    func testWriteProjectMultipleStoryStateUpdates() throws {
        let json = """
        {
            "project": "Multi",
            "description": "Multiple updates",
            "userStories": [
                {
                    "id": "US-001",
                    "title": "Story 1",
                    "description": "Desc 1",
                    "priority": 1,
                    "acceptanceCriteria": ["AC1"]
                },
                {
                    "id": "US-002",
                    "title": "Story 2",
                    "description": "Desc 2",
                    "priority": 2,
                    "acceptanceCriteria": ["AC2"]
                },
                {
                    "id": "US-003",
                    "title": "Story 3",
                    "description": "Desc 3",
                    "priority": 3,
                    "acceptanceCriteria": ["AC3"]
                }
            ]
        }
        """
        try json.write(to: tempDir.appendingPathComponent("ridl.json"), atomically: true, encoding: .utf8)

        var project = try store.loadProject(from: tempDir)

        // Update multiple stories at once
        project.userStories[0].passes = true
        project.userStories[1].passes = true
        project.userStories[1].inProgress = false
        project.userStories[2].inProgress = true

        try store.writeProject(project, to: tempDir)
        let reloaded = try store.loadProject(from: tempDir)

        XCTAssertTrue(reloaded.userStories[0].passes)
        XCTAssertFalse(reloaded.userStories[0].inProgress)
        XCTAssertTrue(reloaded.userStories[1].passes)
        XCTAssertFalse(reloaded.userStories[1].inProgress)
        XCTAssertFalse(reloaded.userStories[2].passes)
        XCTAssertTrue(reloaded.userStories[2].inProgress)
        // All other fields preserved
        XCTAssertEqual(reloaded.project, "Multi")
        XCTAssertEqual(reloaded.description, "Multiple updates")
    }

    // MARK: - JSON error messages

    func testJSONErrorIncludesFileNameAndKey() throws {
        // Missing required "title" field in a user story
        let json = """
        {
            "userStories": [
                {
                    "id": "US-001",
                    "description": "No title",
                    "priority": 1,
                    "acceptanceCriteria": []
                }
            ]
        }
        """
        try json.write(to: tempDir.appendingPathComponent("ridl.json"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try store.loadProject(from: tempDir)) { error in
            guard let ridlerError = error as? RidlerError else {
                XCTFail("Expected RidlerError")
                return
            }
            let desc = ridlerError.errorDescription ?? ""
            XCTAssertTrue(desc.contains("ridl.json"), "Error should include filename: \(desc)")
            XCTAssertTrue(desc.contains("title"), "Error should include key: \(desc)")
        }
    }

    func testFileNotFoundErrorIncludesPath() {
        let bogusDir = tempDir.appendingPathComponent("does-not-exist")

        do {
            _ = try store.loadProject(from: bogusDir)
            XCTFail("Should have thrown")
        } catch {
            guard let ridlerError = error as? RidlerError else {
                XCTFail("Expected RidlerError")
                return
            }
            let desc = ridlerError.errorDescription ?? ""
            XCTAssertTrue(desc.contains("does-not-exist"), "Error should include path: \(desc)")
        }
    }
}
