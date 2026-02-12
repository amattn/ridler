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
            "iterationDefinitions": [
                {
                    "id": "US-001",
                    "userStoryTitle": "Story 1",
                    "userStoryDescription": "Description 1",
                    "priority": 1,
                    "acceptanceCriteria": ["AC1", "AC2"],
                    "passes": true
                },
                {
                    "id": "US-002",
                    "userStoryTitle": "Story 2",
                    "userStoryDescription": "Description 2",
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
        XCTAssertEqual(project.iterationDefinitions.count, 2)
        XCTAssertEqual(project.iterationDefinitions[0].id, "US-001")
        XCTAssertTrue(project.iterationDefinitions[0].passes)
        XCTAssertFalse(project.iterationDefinitions[0].inProgress)
        XCTAssertEqual(project.iterationDefinitions[1].id, "US-002")
        XCTAssertFalse(project.iterationDefinitions[1].passes)
        XCTAssertFalse(project.iterationDefinitions[1].inProgress)
        XCTAssertEqual(project.directoryURL, tempDir)
    }

    func testLoadProjectMissingOptionalFields() throws {
        let json = """
        {
            "iterationDefinitions": [
                {
                    "id": "US-001",
                    "userStoryTitle": "Minimal",
                    "userStoryDescription": "Minimal story",
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
        XCTAssertEqual(project.iterationDefinitions.count, 1)
        XCTAssertFalse(project.iterationDefinitions[0].passes)
        XCTAssertFalse(project.iterationDefinitions[0].inProgress)
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
                XCTAssertEqual(key, "iterationDefinitions")
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
            "iterationDefinitions": []
        }
        """
        try json.write(to: tempDir.appendingPathComponent("ridl.json"), atomically: true, encoding: .utf8)

        let project = try store.loadProject(from: tempDir)
        XCTAssertEqual(project.directoryURL, tempDir)
    }

    func testLoadProjectFromFileURL() throws {
        let json = """
        {
            "iterationDefinitions": []
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
            iterationDefinitions: [
                IterationDefinition(
                    id: "US-001",
                    userStoryTitle: "Story 1",
                    userStoryDescription: "Desc",
                    priority: 1,
                    acceptanceCriteria: ["AC1"],
                    passes: false
                )
            ]
        )

        try store.writeProject(project, to: tempDir)

        let loaded = try store.loadProject(from: tempDir)
        XCTAssertEqual(loaded.project, "Test")
        XCTAssertEqual(loaded.description, "Round trip test")
        XCTAssertEqual(loaded.iterationDefinitions.count, 1)
        XCTAssertFalse(loaded.iterationDefinitions[0].passes)
        XCTAssertFalse(loaded.iterationDefinitions[0].inProgress)
    }

    func testWriteProjectProducesPrettyPrintedJSON() throws {
        let project = PRDProject(
            project: "Pretty",
            iterationDefinitions: []
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
            "iterationDefinitions": [
                {
                    "id": "US-001",
                    "userStoryTitle": "Story",
                    "userStoryDescription": "Desc",
                    "priority": 1,
                    "acceptanceCriteria": ["AC1"]
                }
            ],
            "milestones": [
                {
                    "id": "M1",
                    "definitionIds": ["US-001"]
                }
            ]
        }
        """
        try json.write(to: tempDir.appendingPathComponent("ridl.json"), atomically: true, encoding: .utf8)

        var project = try store.loadProject(from: tempDir)
        project.iterationDefinitions[0].passes = true

        try store.writeProject(project, to: tempDir)
        let reloaded = try store.loadProject(from: tempDir)

        XCTAssertEqual(reloaded.project, "Test")
        XCTAssertEqual(reloaded.description, "Full project")
        XCTAssertTrue(reloaded.iterationDefinitions[0].passes)
        XCTAssertFalse(reloaded.iterationDefinitions[0].inProgress)
        XCTAssertEqual(reloaded.milestones?.count, 1)
        XCTAssertEqual(reloaded.milestones?[0].name, "M1")
    }

    // MARK: - US-004: Write PRD state updates

    func testWriteProjectModifyPasses() throws {
        let json = """
        {
            "project": "State Test",
            "iterationDefinitions": [
                {
                    "id": "US-001",
                    "userStoryTitle": "Story 1",
                    "userStoryDescription": "Desc 1",
                    "priority": 1,
                    "acceptanceCriteria": ["AC1"]
                },
                {
                    "id": "US-002",
                    "userStoryTitle": "Story 2",
                    "userStoryDescription": "Desc 2",
                    "priority": 2,
                    "acceptanceCriteria": ["AC2"]
                }
            ]
        }
        """
        try json.write(to: tempDir.appendingPathComponent("ridl.json"), atomically: true, encoding: .utf8)

        // Read
        var project = try store.loadProject(from: tempDir)
        XCTAssertFalse(project.iterationDefinitions[0].passes)

        // Modify: mark story 1 as passed
        project.iterationDefinitions[0].passes = true

        // Write
        try store.writeProject(project, to: tempDir)

        // Read again
        var reloaded = try store.loadProject(from: tempDir)
        XCTAssertTrue(reloaded.iterationDefinitions[0].passes)
        XCTAssertFalse(reloaded.iterationDefinitions[0].inProgress)
        XCTAssertFalse(reloaded.iterationDefinitions[1].passes)

        // Modify: mark story 1 as passed (already), verify stability
        reloaded.iterationDefinitions[0].passes = true

        // Write again
        try store.writeProject(reloaded, to: tempDir)

        // Read final state
        let final = try store.loadProject(from: tempDir)
        XCTAssertTrue(final.iterationDefinitions[0].passes)
        XCTAssertFalse(final.iterationDefinitions[1].passes)
    }

    func testWriteProjectConcurrentSafety() throws {
        // Verify that concurrent writes using .atomic don't corrupt the file
        let project = PRDProject(
            project: "Concurrent",
            iterationDefinitions: [
                IterationDefinition(id: "US-001", userStoryTitle: "S1", userStoryDescription: "D1", priority: 1, acceptanceCriteria: ["AC1"]),
                IterationDefinition(id: "US-002", userStoryTitle: "S2", userStoryDescription: "D2", priority: 2, acceptanceCriteria: ["AC2"])
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
                    copy.iterationDefinitions[0].passes = (i % 2 == 0)
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
        XCTAssertEqual(final.iterationDefinitions.count, 2)
    }

    func testWriteProjectMultipleStoryStateUpdates() throws {
        let json = """
        {
            "project": "Multi",
            "description": "Multiple updates",
            "iterationDefinitions": [
                {
                    "id": "US-001",
                    "userStoryTitle": "Story 1",
                    "userStoryDescription": "Desc 1",
                    "priority": 1,
                    "acceptanceCriteria": ["AC1"]
                },
                {
                    "id": "US-002",
                    "userStoryTitle": "Story 2",
                    "userStoryDescription": "Desc 2",
                    "priority": 2,
                    "acceptanceCriteria": ["AC2"]
                },
                {
                    "id": "US-003",
                    "userStoryTitle": "Story 3",
                    "userStoryDescription": "Desc 3",
                    "priority": 3,
                    "acceptanceCriteria": ["AC3"]
                }
            ]
        }
        """
        try json.write(to: tempDir.appendingPathComponent("ridl.json"), atomically: true, encoding: .utf8)

        var project = try store.loadProject(from: tempDir)

        // Update multiple stories at once
        project.iterationDefinitions[0].passes = true
        project.iterationDefinitions[1].passes = true

        try store.writeProject(project, to: tempDir)
        let reloaded = try store.loadProject(from: tempDir)

        XCTAssertTrue(reloaded.iterationDefinitions[0].passes)
        XCTAssertFalse(reloaded.iterationDefinitions[0].inProgress)
        XCTAssertTrue(reloaded.iterationDefinitions[1].passes)
        XCTAssertFalse(reloaded.iterationDefinitions[1].inProgress)
        XCTAssertFalse(reloaded.iterationDefinitions[2].passes)
        XCTAssertFalse(reloaded.iterationDefinitions[2].inProgress)
        // All other fields preserved
        XCTAssertEqual(reloaded.project, "Multi")
        XCTAssertEqual(reloaded.description, "Multiple updates")
    }

    // MARK: - JSON error messages

    func testJSONErrorIncludesFileNameAndKey() throws {
        // Missing required "userStoryTitle" field in an iteration definition
        let json = """
        {
            "iterationDefinitions": [
                {
                    "id": "US-001",
                    "userStoryDescription": "No title",
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
            XCTAssertTrue(desc.contains("userStoryTitle"), "Error should include key: \(desc)")
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

    // MARK: - V2 fields round-trip through store

    func testV2FieldsPreservedThroughStore() throws {
        let json = """
        {
            "version": "2.0.0",
            "generatedBy": "ridl-cli",
            "branchName": "feature/test",
            "iterationDefinitions": [
                {
                    "id": "US-001",
                    "userStoryTitle": "Story",
                    "userStoryDescription": "Desc",
                    "priority": 1,
                    "acceptanceCriteria": ["AC1"],
                    "prdReferences": ["Section 2.1"],
                    "notes": "A note"
                }
            ],
            "universalContext": {
                "nonFunctionalRequirements": ["NFR1"],
                "technicalArchitecture": ["Arch1"]
            }
        }
        """
        try json.write(to: tempDir.appendingPathComponent("ridl.json"), atomically: true, encoding: .utf8)

        let project = try store.loadProject(from: tempDir)
        XCTAssertEqual(project.version, "2.0.0")
        XCTAssertEqual(project.branchName, "feature/test")
        XCTAssertEqual(project.iterationDefinitions[0].prdReferences, ["Section 2.1"])
        XCTAssertEqual(project.iterationDefinitions[0].notes, "A note")
        XCTAssertEqual(project.universalContext?.nonFunctionalRequirements, ["NFR1"])

        // Write back and verify preservation
        try store.writeProject(project, to: tempDir)
        let reloaded = try store.loadProject(from: tempDir)
        XCTAssertEqual(reloaded.version, "2.0.0")
        XCTAssertEqual(reloaded.generatedBy, "ridl-cli")
        XCTAssertEqual(reloaded.branchName, "feature/test")
        XCTAssertEqual(reloaded.iterationDefinitions[0].prdReferences, ["Section 2.1"])
        XCTAssertEqual(reloaded.universalContext?.technicalArchitecture, ["Arch1"])
    }
}
