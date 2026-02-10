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
