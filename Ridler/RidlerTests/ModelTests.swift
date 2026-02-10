import XCTest
@testable import Ridler

final class UserStoryTests: XCTestCase {

    func testRoundTripEncoding() throws {
        let story = UserStory(
            id: "US-001",
            title: "Test Story",
            description: "A test story",
            priority: 1,
            acceptanceCriteria: ["Criterion 1", "Criterion 2"],
            passes: true,
            inProgress: false
        )

        let data = try JSONEncoder().encode(story)
        let decoded = try JSONDecoder().decode(UserStory.self, from: data)

        XCTAssertEqual(story, decoded)
    }

    func testDefaultsWhenFieldsOmitted() throws {
        let json = """
        {
            "id": "US-002",
            "title": "Minimal Story",
            "description": "No passes or inProgress",
            "priority": 2,
            "acceptanceCriteria": ["AC1"]
        }
        """.data(using: .utf8)!

        let story = try JSONDecoder().decode(UserStory.self, from: json)

        XCTAssertEqual(story.id, "US-002")
        XCTAssertEqual(story.title, "Minimal Story")
        XCTAssertEqual(story.priority, 2)
        XCTAssertFalse(story.passes)
        XCTAssertFalse(story.inProgress)
    }

    func testPassesDefaultsToFalse() throws {
        let json = """
        {
            "id": "US-003",
            "title": "Story",
            "description": "Desc",
            "priority": 1,
            "acceptanceCriteria": [],
            "inProgress": true
        }
        """.data(using: .utf8)!

        let story = try JSONDecoder().decode(UserStory.self, from: json)

        XCTAssertFalse(story.passes)
        XCTAssertTrue(story.inProgress)
    }

    func testInProgressDefaultsToFalse() throws {
        let json = """
        {
            "id": "US-004",
            "title": "Story",
            "description": "Desc",
            "priority": 1,
            "acceptanceCriteria": [],
            "passes": true
        }
        """.data(using: .utf8)!

        let story = try JSONDecoder().decode(UserStory.self, from: json)

        XCTAssertTrue(story.passes)
        XCTAssertFalse(story.inProgress)
    }

    func testIdentifiable() {
        let story = UserStory(
            id: "US-005",
            title: "Test",
            description: "Test",
            priority: 1,
            acceptanceCriteria: []
        )
        XCTAssertEqual(story.id, "US-005")
    }
}

final class LoopStateTests: XCTestCase {

    func testAllCasesEncodeDecode() throws {
        let cases: [LoopState] = [.ready, .running, .paused, .stopped, .complete, .error]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for state in cases {
            let data = try encoder.encode(state)
            let decoded = try decoder.decode(LoopState.self, from: data)
            XCTAssertEqual(state, decoded)
        }
    }

    func testRawValues() {
        XCTAssertEqual(LoopState.ready.rawValue, "ready")
        XCTAssertEqual(LoopState.running.rawValue, "running")
        XCTAssertEqual(LoopState.paused.rawValue, "paused")
        XCTAssertEqual(LoopState.stopped.rawValue, "stopped")
        XCTAssertEqual(LoopState.complete.rawValue, "complete")
        XCTAssertEqual(LoopState.error.rawValue, "error")
    }
}

final class MilestoneTests: XCTestCase {

    func testRoundTripEncoding() throws {
        let milestone = Milestone(name: "M1", storyIDs: ["US-001", "US-002"])

        let data = try JSONEncoder().encode(milestone)
        let decoded = try JSONDecoder().decode(Milestone.self, from: data)

        XCTAssertEqual(milestone, decoded)
    }

    func testIdentifiable() {
        let milestone = Milestone(name: "M1", storyIDs: [])
        XCTAssertEqual(milestone.id, "M1")
    }
}

final class PRDProjectTests: XCTestCase {

    func testRoundTripEncoding() throws {
        let project = PRDProject(
            name: "Test Project",
            project: "Test",
            description: "A test project",
            userStories: [
                UserStory(
                    id: "US-001",
                    title: "Story 1",
                    description: "Desc 1",
                    priority: 1,
                    acceptanceCriteria: ["AC1"]
                )
            ],
            milestones: [Milestone(name: "M1", storyIDs: ["US-001"])]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(project)
        let decoded = try JSONDecoder().decode(PRDProject.self, from: data)

        XCTAssertEqual(decoded.name, "Test Project")
        XCTAssertEqual(decoded.project, "Test")
        XCTAssertEqual(decoded.description, "A test project")
        XCTAssertEqual(decoded.userStories.count, 1)
        XCTAssertEqual(decoded.userStories[0].id, "US-001")
        XCTAssertEqual(decoded.milestones?.count, 1)
        XCTAssertEqual(decoded.loopState, .ready)
        XCTAssertEqual(decoded.iterationCount, 0)
    }

    func testDecodingFromRidlJSON() throws {
        let json = """
        {
            "project": "Ridler",
            "description": "A macOS app",
            "userStories": [
                {
                    "id": "US-001",
                    "title": "Create project",
                    "description": "Set up Xcode",
                    "priority": 1,
                    "acceptanceCriteria": ["AC1", "AC2"],
                    "passes": true,
                    "inProgress": false
                },
                {
                    "id": "US-002",
                    "title": "Add models",
                    "description": "Define data models",
                    "priority": 2,
                    "acceptanceCriteria": ["AC3"]
                }
            ]
        }
        """.data(using: .utf8)!

        let project = try JSONDecoder().decode(PRDProject.self, from: json)

        XCTAssertEqual(project.project, "Ridler")
        XCTAssertEqual(project.userStories.count, 2)
        XCTAssertTrue(project.userStories[0].passes)
        XCTAssertFalse(project.userStories[0].inProgress)
        XCTAssertFalse(project.userStories[1].passes)
        XCTAssertFalse(project.userStories[1].inProgress)
        XCTAssertEqual(project.loopState, .ready)
        XCTAssertEqual(project.iterationCount, 0)
        XCTAssertNil(project.directoryURL)
    }

    func testRuntimePropertiesNotSerialized() throws {
        var project = PRDProject(
            name: "Test",
            userStories: [],
            loopState: .running,
            iterationCount: 5,
            directoryURL: URL(fileURLWithPath: "/tmp/test")
        )
        project.loopState = .running
        project.iterationCount = 5

        let data = try JSONEncoder().encode(project)
        let jsonString = String(data: data, encoding: .utf8)!

        XCTAssertFalse(jsonString.contains("loopState"))
        XCTAssertFalse(jsonString.contains("iterationCount"))
        XCTAssertFalse(jsonString.contains("directoryURL"))

        let decoded = try JSONDecoder().decode(PRDProject.self, from: data)
        XCTAssertEqual(decoded.loopState, .ready)
        XCTAssertEqual(decoded.iterationCount, 0)
        XCTAssertNil(decoded.directoryURL)
    }

    func testIdentifiable() {
        let project = PRDProject(name: "MyProject", userStories: [])
        XCTAssertEqual(project.id, "MyProject")
    }

    func testMilestonesOptional() throws {
        let json = """
        {
            "userStories": []
        }
        """.data(using: .utf8)!

        let project = try JSONDecoder().decode(PRDProject.self, from: json)
        XCTAssertNil(project.milestones)
        XCTAssertNil(project.name)
        XCTAssertNil(project.project)
    }

    func testModifyStoryState() throws {
        let json = """
        {
            "project": "Test",
            "userStories": [
                {
                    "id": "US-001",
                    "title": "Story",
                    "description": "Desc",
                    "priority": 1,
                    "acceptanceCriteria": []
                }
            ]
        }
        """.data(using: .utf8)!

        var project = try JSONDecoder().decode(PRDProject.self, from: json)
        XCTAssertFalse(project.userStories[0].passes)

        project.userStories[0].passes = true
        project.userStories[0].inProgress = false

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let reEncoded = try encoder.encode(project)
        let reDecoded = try JSONDecoder().decode(PRDProject.self, from: reEncoded)

        XCTAssertTrue(reDecoded.userStories[0].passes)
        XCTAssertFalse(reDecoded.userStories[0].inProgress)
    }
}

final class RidlerErrorTests: XCTestCase {

    func testFileNotFoundDescription() {
        let error = RidlerError.fileNotFound(
            path: "/path/to/dir",
            filenames: ["prd.md", "ridl.json"]
        )
        let desc = error.errorDescription!
        XCTAssertTrue(desc.contains("/path/to/dir"))
        XCTAssertTrue(desc.contains("prd.md"))
        XCTAssertTrue(desc.contains("ridl.json"))
    }

    func testJSONDecodingDescription() {
        let error = RidlerError.jsonDecoding(
            file: "ridl.json",
            key: "title",
            jsonPath: "userStories.0",
            underlyingMessage: "Expected String"
        )
        let desc = error.errorDescription!
        XCTAssertTrue(desc.contains("ridl.json"))
        XCTAssertTrue(desc.contains("title"))
        XCTAssertTrue(desc.contains("userStories.0"))
    }

    func testProcessErrorDescription() {
        let error = RidlerError.processError(
            command: "claude --help",
            exitCode: 1,
            stderr: "not found"
        )
        let desc = error.errorDescription!
        XCTAssertTrue(desc.contains("claude --help"))
        XCTAssertTrue(desc.contains("1"))
        XCTAssertTrue(desc.contains("not found"))
    }

    func testGitErrorDescription() {
        let error = RidlerError.gitError(
            command: "git checkout -b feature",
            stderr: "already exists"
        )
        let desc = error.errorDescription!
        XCTAssertTrue(desc.contains("git checkout -b feature"))
        XCTAssertTrue(desc.contains("already exists"))
    }

    func testLoopErrorDescription() {
        let error = RidlerError.loopError(message: "Max iterations reached")
        let desc = error.errorDescription!
        XCTAssertTrue(desc.contains("Max iterations reached"))
    }

    func testConformsToLocalizedError() {
        let error: LocalizedError = RidlerError.loopError(message: "test")
        XCTAssertNotNil(error.errorDescription)
    }

    func testEquatable() {
        let a = RidlerError.fileNotFound(path: "/a", filenames: ["f1"])
        let b = RidlerError.fileNotFound(path: "/a", filenames: ["f1"])
        let c = RidlerError.fileNotFound(path: "/b", filenames: ["f1"])
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
