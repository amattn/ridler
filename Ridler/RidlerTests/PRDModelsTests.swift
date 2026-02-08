import XCTest
@testable import Ridler

final class PRDModelsTests: XCTestCase {

    // MARK: - Sample JSON

    let sampleJSON = """
    {
        "project": "TestProject",
        "branchName": "ridl/test-project",
        "description": "A test project for unit testing",
        "userStories": [
            {
                "id": "US-001",
                "title": "First Story",
                "description": "As a user, I want to test decoding.",
                "acceptanceCriteria": ["Criterion A", "Criterion B"],
                "priority": 1,
                "passes": true,
                "inProgress": false,
                "notes": "Some notes"
            },
            {
                "id": "US-002",
                "title": "Second Story",
                "description": "As a user, I want to test encoding.",
                "acceptanceCriteria": ["Criterion C"],
                "priority": 2,
                "passes": false,
                "inProgress": true,
                "lastPrompt": "Build this feature",
                "notes": ""
            }
        ]
    }
    """

    // MARK: - Decoding Tests

    func testDecodesPRDProject() throws {
        let data = Data(sampleJSON.utf8)
        let project = try JSONDecoder().decode(PRDProject.self, from: data)

        XCTAssertEqual(project.project, "TestProject")
        XCTAssertEqual(project.branchName, "ridl/test-project")
        XCTAssertEqual(project.description, "A test project for unit testing")
        XCTAssertEqual(project.userStories.count, 2)
    }

    func testDecodesUserStoryFields() throws {
        let data = Data(sampleJSON.utf8)
        let project = try JSONDecoder().decode(PRDProject.self, from: data)
        let story = project.userStories[0]

        XCTAssertEqual(story.id, "US-001")
        XCTAssertEqual(story.title, "First Story")
        XCTAssertEqual(story.description, "As a user, I want to test decoding.")
        XCTAssertEqual(story.acceptanceCriteria, ["Criterion A", "Criterion B"])
        XCTAssertEqual(story.priority, 1)
        XCTAssertTrue(story.passes)
        XCTAssertFalse(story.inProgress)
        XCTAssertNil(story.lastPrompt)
        XCTAssertEqual(story.notes, "Some notes")
    }

    func testDecodesOptionalLastPrompt() throws {
        let data = Data(sampleJSON.utf8)
        let project = try JSONDecoder().decode(PRDProject.self, from: data)
        let story = project.userStories[1]

        XCTAssertEqual(story.lastPrompt, "Build this feature")
        XCTAssertTrue(story.inProgress)
        XCTAssertFalse(story.passes)
    }

    func testDecodesOptionalBranchName() throws {
        let json = """
        {
            "project": "NoBranch",
            "description": "No branch name",
            "userStories": []
        }
        """
        let data = Data(json.utf8)
        let project = try JSONDecoder().decode(PRDProject.self, from: data)

        XCTAssertNil(project.branchName)
        XCTAssertEqual(project.project, "NoBranch")
    }

    // MARK: - Encoding Tests

    func testEncodesAndDecodesRoundTrip() throws {
        let data = Data(sampleJSON.utf8)
        let original = try JSONDecoder().decode(PRDProject.self, from: data)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(original)

        let decoded = try JSONDecoder().decode(PRDProject.self, from: encoded)

        XCTAssertEqual(original, decoded)
    }

    func testRoundTripPreservesAllFields() throws {
        let story = UserStory(
            id: "US-099",
            title: "Round Trip",
            description: "Testing round trip",
            acceptanceCriteria: ["A", "B", "C"],
            priority: 42,
            passes: true,
            inProgress: false,
            lastPrompt: "Do the thing",
            notes: "Important note"
        )
        let project = PRDProject(
            project: "RoundTrip",
            branchName: "ridl/round-trip",
            description: "Round trip test",
            userStories: [story]
        )

        let encoder = JSONEncoder()
        let encoded = try encoder.encode(project)
        let decoded = try JSONDecoder().decode(PRDProject.self, from: encoded)

        XCTAssertEqual(project, decoded)
        XCTAssertEqual(decoded.userStories[0].lastPrompt, "Do the thing")
        XCTAssertEqual(decoded.userStories[0].notes, "Important note")
        XCTAssertEqual(decoded.branchName, "ridl/round-trip")
    }

    func testRoundTripWithNilOptionals() throws {
        let story = UserStory(
            id: "US-100",
            title: "Nil Optionals",
            description: "No optional fields set",
            acceptanceCriteria: [],
            priority: 1,
            passes: false,
            inProgress: false,
            lastPrompt: nil,
            notes: nil
        )
        let project = PRDProject(
            project: "NilTest",
            branchName: nil,
            description: "Nil optionals test",
            userStories: [story]
        )

        let encoder = JSONEncoder()
        let encoded = try encoder.encode(project)
        let decoded = try JSONDecoder().decode(PRDProject.self, from: encoded)

        XCTAssertEqual(project, decoded)
        XCTAssertNil(decoded.userStories[0].lastPrompt)
        XCTAssertNil(decoded.userStories[0].notes)
        XCTAssertNil(decoded.branchName)
    }

    // MARK: - File Manager Tests

    func testLoadAndSaveRoundTrip() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let jsonPath = tmpDir.appendingPathComponent("ridl.json").path

        // Write sample JSON
        try Data(sampleJSON.utf8).write(to: URL(fileURLWithPath: jsonPath))

        // Load
        let loaded = try PRDFileManager.load(from: jsonPath)
        XCTAssertEqual(loaded.project, "TestProject")
        XCTAssertEqual(loaded.userStories.count, 2)

        // Save
        try PRDFileManager.save(loaded, to: jsonPath)

        // Reload and verify round-trip
        let reloaded = try PRDFileManager.load(from: jsonPath)
        XCTAssertEqual(loaded, reloaded)
    }

    func testLoadFileNotFound() {
        XCTAssertThrowsError(try PRDFileManager.load(from: "/nonexistent/path/ridl.json")) { error in
            XCTAssertTrue(error is PRDFileError)
        }
    }

    func testCompanionDirectory() {
        let dir = PRDFileManager.companionDirectory(for: "/Users/test/projects/myapp/ridl.json")
        XCTAssertEqual(dir, "/Users/test/projects/myapp")
    }

    func testCompanionFilePath() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let prdPath = tmpDir.appendingPathComponent("prd.md").path
        let jsonPath = tmpDir.appendingPathComponent("ridl.json").path

        // Create both files
        try Data("# PRD".utf8).write(to: URL(fileURLWithPath: prdPath))
        try Data(sampleJSON.utf8).write(to: URL(fileURLWithPath: jsonPath))

        // Find companion
        let found = PRDFileManager.companionFilePath(for: prdPath, named: "ridl.json")
        XCTAssertEqual(found, jsonPath)

        // Non-existent companion
        let notFound = PRDFileManager.companionFilePath(for: prdPath, named: "nonexistent.txt")
        XCTAssertNil(notFound)
    }

    func testLoadFromCompanionWithJsonFile() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let jsonPath = tmpDir.appendingPathComponent("ridl.json").path
        try Data(sampleJSON.utf8).write(to: URL(fileURLWithPath: jsonPath))

        let (project, path) = try PRDFileManager.loadFromCompanion(filePath: jsonPath)
        XCTAssertEqual(project.project, "TestProject")
        XCTAssertEqual(path, jsonPath)
    }

    func testLoadFromCompanionWithPrdMd() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let prdPath = tmpDir.appendingPathComponent("prd.md").path
        let jsonPath = tmpDir.appendingPathComponent("ridl.json").path

        try Data("# PRD".utf8).write(to: URL(fileURLWithPath: prdPath))
        try Data(sampleJSON.utf8).write(to: URL(fileURLWithPath: jsonPath))

        let (project, path) = try PRDFileManager.loadFromCompanion(filePath: prdPath)
        XCTAssertEqual(project.project, "TestProject")
        XCTAssertEqual(path, jsonPath)
    }

    func testLoadFromCompanionWithPrdJson() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let prdPath = tmpDir.appendingPathComponent("prd.md").path
        let prdJsonPath = tmpDir.appendingPathComponent("prd.json").path

        try Data("# PRD".utf8).write(to: URL(fileURLWithPath: prdPath))
        try Data(sampleJSON.utf8).write(to: URL(fileURLWithPath: prdJsonPath))

        let (project, path) = try PRDFileManager.loadFromCompanion(filePath: prdPath)
        XCTAssertEqual(project.project, "TestProject")
        XCTAssertEqual(path, prdJsonPath)
    }
}
