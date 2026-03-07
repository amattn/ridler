import XCTest
@testable import Ridler

final class IterationDefinitionTests: XCTestCase {

    func testRoundTripEncoding() throws {
        let story = IterationDefinition(
            id: "US-001",
            title: "Test Story",
            description: "A test story",
            priority: 1,
            acceptanceCriteria: [
                AcceptanceCriterion(criterion: "Criterion 1", status: .pass),
                AcceptanceCriterion(criterion: "Criterion 2", status: .pass),
            ]
        )

        let data = try JSONEncoder().encode(story)
        let decoded = try JSONDecoder().decode(IterationDefinition.self, from: data)

        XCTAssertEqual(decoded.id, story.id)
        XCTAssertEqual(decoded.title, story.title)
        XCTAssertEqual(decoded.description, story.description)
        XCTAssertEqual(decoded.priority, story.priority)
        XCTAssertEqual(decoded.acceptanceCriteria, story.acceptanceCriteria)
        XCTAssertTrue(decoded.isFrozen)
    }

    func testV3StructuredCriteriaDecoding() throws {
        let json = """
        {
            "id": "US-002",
            "title": "Structured Story",
            "description": "Has structured criteria",
            "priority": 2,
            "acceptanceCriteria": [
                {"criterion": "AC1", "status": "pass"},
                {"criterion": "AC2", "status": "fail"}
            ]
        }
        """.data(using: .utf8)!

        let story = try JSONDecoder().decode(IterationDefinition.self, from: json)

        XCTAssertEqual(story.id, "US-002")
        XCTAssertEqual(story.title, "Structured Story")
        XCTAssertEqual(story.priority, 2)
        XCTAssertFalse(story.isFrozen)
        XCTAssertTrue(story.hasFailingCriteria)
        XCTAssertEqual(story.acceptanceCriteria[0].status, .pass)
        XCTAssertEqual(story.acceptanceCriteria[1].status, .fail)
    }

    func testIdentifiable() {
        let story = IterationDefinition(
            id: "US-005",
            title: "Test",
            description: "Test",
            priority: 1,
            acceptanceCriteria: []
        )
        XCTAssertEqual(story.id, "US-005")
    }

    func testOptionalFields() throws {
        let json = """
        {
            "id": "US-006",
            "title": "Story with refs",
            "description": "Has PRD references and notes",
            "priority": 1,
            "acceptanceCriteria": [{"criterion": "AC1", "status": "not_started"}],
            "prdReferences": ["PRD Section 2.1", "PRD Section 3.4"],
            "milestone": "M1",
            "notes": "Important implementation note"
        }
        """.data(using: .utf8)!

        let story = try JSONDecoder().decode(IterationDefinition.self, from: json)

        XCTAssertEqual(story.prdReferences, ["PRD Section 2.1", "PRD Section 3.4"])
        XCTAssertEqual(story.milestone, "M1")
        XCTAssertEqual(story.notes, "Important implementation note")
    }

    func testOptionalFieldsNil() throws {
        let json = """
        {
            "id": "US-007",
            "title": "Minimal",
            "description": "No optional fields",
            "priority": 1,
            "acceptanceCriteria": []
        }
        """.data(using: .utf8)!

        let story = try JSONDecoder().decode(IterationDefinition.self, from: json)

        XCTAssertNil(story.prdReferences)
        XCTAssertNil(story.milestone)
        XCTAssertNil(story.notes)
    }

    func testEncodingKeys() throws {
        let story = IterationDefinition(
            id: "US-008",
            title: "Test",
            description: "Desc",
            priority: 1,
            acceptanceCriteria: [AcceptanceCriterion(criterion: "AC1", status: .pass)]
        )

        let data = try JSONEncoder().encode(story)
        let jsonString = String(data: data, encoding: .utf8)!

        XCTAssertTrue(jsonString.contains("\"title\""))
        XCTAssertTrue(jsonString.contains("\"description\""))
        XCTAssertTrue(jsonString.contains("\"acceptanceCriteria\""))
    }

    func testIsFrozenAllPass() {
        let story = IterationDefinition(
            id: "US-009",
            title: "All pass",
            description: "Desc",
            priority: 1,
            acceptanceCriteria: [
                AcceptanceCriterion(criterion: "AC1", status: .pass),
                AcceptanceCriterion(criterion: "AC2", status: .pass),
            ]
        )
        XCTAssertTrue(story.isFrozen)
    }

    func testIsFrozenEmptyCriteria() {
        let story = IterationDefinition(
            id: "US-010",
            title: "Empty",
            description: "Desc",
            priority: 1,
            acceptanceCriteria: []
        )
        XCTAssertFalse(story.isFrozen)
    }

    func testHasErrors() {
        let story = IterationDefinition(
            id: "US-011",
            title: "Has error",
            description: "Desc",
            priority: 1,
            acceptanceCriteria: [
                AcceptanceCriterion(criterion: "AC1", status: .pass),
                AcceptanceCriterion(criterion: "AC2", status: .error),
            ]
        )
        XCTAssertTrue(story.hasErrors)
        XCTAssertFalse(story.isFrozen)
    }

    func testHasFailingCriteria() {
        let story = IterationDefinition(
            id: "US-012",
            title: "Has fail",
            description: "Desc",
            priority: 1,
            acceptanceCriteria: [
                AcceptanceCriterion(criterion: "AC1", status: .pass),
                AcceptanceCriterion(criterion: "AC2", status: .fail),
            ]
        )
        XCTAssertTrue(story.hasFailingCriteria)
        XCTAssertFalse(story.isFrozen)
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

    // MARK: - Valid Transitions

    func testReadyToRunning() {
        XCTAssertTrue(LoopState.ready.canTransition(to: .running))
        XCTAssertEqual(LoopState.ready.transition(to: .running), .running)
    }

    func testRunningToPaused() {
        XCTAssertTrue(LoopState.running.canTransition(to: .paused))
        XCTAssertEqual(LoopState.running.transition(to: .paused), .paused)
    }

    func testRunningToStopped() {
        XCTAssertTrue(LoopState.running.canTransition(to: .stopped))
        XCTAssertEqual(LoopState.running.transition(to: .stopped), .stopped)
    }

    func testRunningToComplete() {
        XCTAssertTrue(LoopState.running.canTransition(to: .complete))
        XCTAssertEqual(LoopState.running.transition(to: .complete), .complete)
    }

    func testRunningToError() {
        XCTAssertTrue(LoopState.running.canTransition(to: .error))
        XCTAssertEqual(LoopState.running.transition(to: .error), .error)
    }

    func testPausedToRunning() {
        XCTAssertTrue(LoopState.paused.canTransition(to: .running))
        XCTAssertEqual(LoopState.paused.transition(to: .running), .running)
    }

    func testStoppedToRunning() {
        XCTAssertTrue(LoopState.stopped.canTransition(to: .running))
        XCTAssertEqual(LoopState.stopped.transition(to: .running), .running)
    }

    func testErrorToRunning() {
        XCTAssertTrue(LoopState.error.canTransition(to: .running))
        XCTAssertEqual(LoopState.error.transition(to: .running), .running)
    }

    // MARK: - Invalid Transitions

    func testReadyCannotTransitionToNonRunning() {
        let invalidTargets: [LoopState] = [.paused, .stopped, .complete, .error, .ready]
        for target in invalidTargets {
            XCTAssertFalse(LoopState.ready.canTransition(to: target), "Ready should not transition to \(target)")
            XCTAssertNil(LoopState.ready.transition(to: target), "Ready.transition(to: \(target)) should return nil")
        }
    }

    func testRunningCannotTransitionToReadyOrSelf() {
        XCTAssertFalse(LoopState.running.canTransition(to: .ready))
        XCTAssertNil(LoopState.running.transition(to: .ready))
        XCTAssertFalse(LoopState.running.canTransition(to: .running))
        XCTAssertNil(LoopState.running.transition(to: .running))
    }

    func testPausedCannotTransitionToNonRunning() {
        let invalidTargets: [LoopState] = [.paused, .stopped, .complete, .error, .ready]
        for target in invalidTargets {
            XCTAssertFalse(LoopState.paused.canTransition(to: target), "Paused should not transition to \(target)")
            XCTAssertNil(LoopState.paused.transition(to: target))
        }
    }

    func testStoppedCannotTransitionToNonRunning() {
        let invalidTargets: [LoopState] = [.paused, .stopped, .complete, .error, .ready]
        for target in invalidTargets {
            XCTAssertFalse(LoopState.stopped.canTransition(to: target), "Stopped should not transition to \(target)")
            XCTAssertNil(LoopState.stopped.transition(to: target))
        }
    }

    func testCompleteCanTransitionToReady() {
        XCTAssertTrue(LoopState.complete.canTransition(to: .ready), "Complete should transition to ready")
        XCTAssertEqual(LoopState.complete.transition(to: .ready), .ready)

        let invalidTargets: [LoopState] = [.running, .paused, .stopped, .complete, .error]
        for target in invalidTargets {
            XCTAssertFalse(LoopState.complete.canTransition(to: target), "Complete should not transition to \(target)")
            XCTAssertNil(LoopState.complete.transition(to: target))
        }
    }

    func testErrorCannotTransitionToNonRunning() {
        let invalidTargets: [LoopState] = [.paused, .stopped, .complete, .error, .ready]
        for target in invalidTargets {
            XCTAssertFalse(LoopState.error.canTransition(to: target), "Error should not transition to \(target)")
            XCTAssertNil(LoopState.error.transition(to: target))
        }
    }

    // MARK: - Badge Color and Display Name

    func testBadgeColorAssignment() {
        XCTAssertNotNil(LoopState.ready.badgeColor)
        XCTAssertNotNil(LoopState.running.badgeColor)
        XCTAssertNotNil(LoopState.paused.badgeColor)
        XCTAssertNotNil(LoopState.stopped.badgeColor)
        XCTAssertNotNil(LoopState.complete.badgeColor)
        XCTAssertNotNil(LoopState.error.badgeColor)
    }

    func testDisplayNames() {
        XCTAssertEqual(LoopState.ready.displayName, "Ready")
        XCTAssertEqual(LoopState.running.displayName, "Running")
        XCTAssertEqual(LoopState.paused.displayName, "Paused")
        XCTAssertEqual(LoopState.stopped.displayName, "Stopped")
        XCTAssertEqual(LoopState.complete.displayName, "Complete")
        XCTAssertEqual(LoopState.error.displayName, "Error")
    }

    // MARK: - Valid Transitions Set

    func testValidTransitionsSets() {
        XCTAssertEqual(LoopState.ready.validTransitions, [.running])
        XCTAssertEqual(LoopState.running.validTransitions, [.paused, .stopped, .complete, .error])
        XCTAssertEqual(LoopState.paused.validTransitions, [.running])
        XCTAssertEqual(LoopState.stopped.validTransitions, [.running])
        XCTAssertEqual(LoopState.complete.validTransitions, [.ready])
        XCTAssertEqual(LoopState.error.validTransitions, [.running])
    }
}

final class MilestoneTests: XCTestCase {

    func testRoundTripEncoding() throws {
        let milestone = Milestone(name: "M1", definitionIds: ["US-001", "US-002"])

        let data = try JSONEncoder().encode(milestone)
        let decoded = try JSONDecoder().decode(Milestone.self, from: data)

        XCTAssertEqual(milestone, decoded)
    }

    func testIdentifiable() {
        let milestone = Milestone(name: "M1", definitionIds: [])
        XCTAssertEqual(milestone.id, "M1")
    }

    func testCodingKeys() throws {
        let milestone = Milestone(name: "M1", definitionIds: ["US-001"], version: "1.0", theme: "Core Setup")

        let data = try JSONEncoder().encode(milestone)
        let jsonString = String(data: data, encoding: .utf8)!

        XCTAssertTrue(jsonString.contains("\"name\""))
        XCTAssertTrue(jsonString.contains("\"definitionIds\""))
    }

    func testDecoding() throws {
        let json = """
        {
            "name": "M2",
            "definitionIds": ["US-003", "US-004"],
            "version": "2.0",
            "theme": "UI Layer"
        }
        """.data(using: .utf8)!

        let milestone = try JSONDecoder().decode(Milestone.self, from: json)

        XCTAssertEqual(milestone.name, "M2")
        XCTAssertEqual(milestone.definitionIds, ["US-003", "US-004"])
        XCTAssertEqual(milestone.version, "2.0")
        XCTAssertEqual(milestone.theme, "UI Layer")
    }

    func testOptionalFields() throws {
        let json = """
        {
            "name": "M3",
            "definitionIds": ["US-005"]
        }
        """.data(using: .utf8)!

        let milestone = try JSONDecoder().decode(Milestone.self, from: json)

        XCTAssertEqual(milestone.name, "M3")
        XCTAssertNil(milestone.version)
        XCTAssertNil(milestone.theme)
    }
}

final class PRDProjectTests: XCTestCase {

    func testRoundTripEncoding() throws {
        let project = PRDProject(
            name: "Test Project",
            project: "Test",
            description: "A test project",
            iterationDefinitions: [
                IterationDefinition(
                    id: "US-001",
                    title: "Story 1",
                    description: "Desc 1",
                    priority: 1,
                    acceptanceCriteria: [AcceptanceCriterion(criterion: "AC1", status: .notStarted)]
                )
            ],
            milestones: [Milestone(name: "M1", definitionIds: ["US-001"])]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(project)
        let decoded = try JSONDecoder().decode(PRDProject.self, from: data)

        XCTAssertEqual(decoded.name, "Test Project")
        XCTAssertEqual(decoded.project, "Test")
        XCTAssertEqual(decoded.description, "A test project")
        XCTAssertEqual(decoded.iterationDefinitions.count, 1)
        XCTAssertEqual(decoded.iterationDefinitions[0].id, "US-001")
        XCTAssertEqual(decoded.milestones?.count, 1)
        XCTAssertEqual(decoded.loopState, .ready)
        XCTAssertEqual(decoded.iterationCount, 0)
    }

    func testDecodingFromRidlJSON() throws {
        let json = """
        {
            "project": "Ridler",
            "description": "A macOS app",
            "iterationDefinitions": [
                {
                    "id": "US-001",
                    "title": "Create project",
                    "description": "Set up Xcode",
                    "priority": 1,
                    "acceptanceCriteria": [
                        {"criterion": "AC1", "status": "pass"},
                        {"criterion": "AC2", "status": "pass"}
                    ]
                },
                {
                    "id": "US-002",
                    "title": "Add models",
                    "description": "Define data models",
                    "priority": 2,
                    "acceptanceCriteria": [{"criterion": "AC3", "status": "not_started"}]
                }
            ]
        }
        """.data(using: .utf8)!

        let project = try JSONDecoder().decode(PRDProject.self, from: json)

        XCTAssertEqual(project.project, "Ridler")
        XCTAssertEqual(project.iterationDefinitions.count, 2)
        XCTAssertTrue(project.iterationDefinitions[0].isFrozen)
        XCTAssertEqual(project.iterationDefinitions[0].title, "Create project")
        XCTAssertFalse(project.iterationDefinitions[1].isFrozen)
        XCTAssertEqual(project.loopState, .ready)
        XCTAssertEqual(project.iterationCount, 0)
        XCTAssertNil(project.directoryURL)
    }

    func testRuntimePropertiesNotSerialized() throws {
        var project = PRDProject(
            name: "Test",
            iterationDefinitions: [],
            loopState: .running,
            iterationCount: 5,
            pauseAfterStory: true,
            directoryURL: URL(fileURLWithPath: "/tmp/test")
        )
        project.loopState = .running
        project.iterationCount = 5

        let data = try JSONEncoder().encode(project)
        let jsonString = String(data: data, encoding: .utf8)!

        XCTAssertFalse(jsonString.contains("loopState"))
        XCTAssertFalse(jsonString.contains("iterationCount"))
        XCTAssertFalse(jsonString.contains("directoryURL"))
        XCTAssertFalse(jsonString.contains("pauseAfterStory"))

        let decoded = try JSONDecoder().decode(PRDProject.self, from: data)
        XCTAssertEqual(decoded.loopState, .ready)
        XCTAssertEqual(decoded.iterationCount, 0)
        XCTAssertFalse(decoded.pauseAfterStory)
        XCTAssertNil(decoded.directoryURL)
    }

    func testIdentifiable() {
        let project = PRDProject(name: "MyProject", iterationDefinitions: [])
        XCTAssertEqual(project.id, "MyProject")
    }

    func testMilestonesOptional() throws {
        let json = """
        {
            "iterationDefinitions": []
        }
        """.data(using: .utf8)!

        let project = try JSONDecoder().decode(PRDProject.self, from: json)
        XCTAssertNil(project.milestones)
        XCTAssertNil(project.name)
        XCTAssertNil(project.project)
    }

    func testModifyCriterionStatus() throws {
        let json = """
        {
            "project": "Test",
            "iterationDefinitions": [
                {
                    "id": "US-001",
                    "title": "Story",
                    "description": "Desc",
                    "priority": 1,
                    "acceptanceCriteria": [{"criterion": "AC1", "status": "not_started"}]
                }
            ]
        }
        """.data(using: .utf8)!

        var project = try JSONDecoder().decode(PRDProject.self, from: json)
        XCTAssertFalse(project.iterationDefinitions[0].isFrozen)

        project.iterationDefinitions[0].acceptanceCriteria[0].status = .pass

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let reEncoded = try encoder.encode(project)
        let reDecoded = try JSONDecoder().decode(PRDProject.self, from: reEncoded)

        XCTAssertTrue(reDecoded.iterationDefinitions[0].isFrozen)
    }

    func testMetadataFields() throws {
        let json = """
        {
            "version": "3.0.0",
            "generatedBy": "ridl-cli",
            "branchName": "feature/my-feature",
            "iterationDefinitions": [],
            "universalContext": {
                "nonFunctionalRequirements": ["Performance must be <100ms"],
                "developerExperience": ["Use SwiftUI patterns"],
                "technicalArchitecture": ["MVVM architecture"]
            }
        }
        """.data(using: .utf8)!

        let project = try JSONDecoder().decode(PRDProject.self, from: json)

        XCTAssertEqual(project.version, "3.0.0")
        XCTAssertEqual(project.generatedBy, "ridl-cli")
        XCTAssertEqual(project.branchName, "feature/my-feature")
        XCTAssertNotNil(project.universalContext)
        XCTAssertEqual(project.universalContext?.nonFunctionalRequirements, ["Performance must be <100ms"])
        XCTAssertEqual(project.universalContext?.developerExperience, ["Use SwiftUI patterns"])
        XCTAssertEqual(project.universalContext?.technicalArchitecture, ["MVVM architecture"])
    }

    func testV3UniversalContextWithTestingAndVerification() throws {
        let json = """
        {
            "version": "3.0.0",
            "iterationDefinitions": [],
            "universalContext": {
                "nonFunctionalRequirements": ["NFR1"],
                "testingAndVerification": ["Run swift test", "Verify no regressions"]
            }
        }
        """.data(using: .utf8)!

        let project = try JSONDecoder().decode(PRDProject.self, from: json)

        XCTAssertEqual(project.universalContext?.testingAndVerification, ["Run swift test", "Verify no regressions"])
        XCTAssertEqual(project.universalContext?.nonFunctionalRequirements, ["NFR1"])
    }

    func testMetadataFieldsRoundTrip() throws {
        let project = PRDProject(
            name: "Test Project",
            iterationDefinitions: [],
            version: "3.0.0",
            generatedBy: "ridl-cli",
            branchName: "dev/test",
            universalContext: UniversalContext(
                nonFunctionalRequirements: ["NFR1"],
                developerExperience: nil,
                technicalArchitecture: ["Arch1"],
                testingAndVerification: nil
            )
        )

        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(PRDProject.self, from: data)

        XCTAssertEqual(decoded.version, "3.0.0")
        XCTAssertEqual(decoded.generatedBy, "ridl-cli")
        XCTAssertEqual(decoded.branchName, "dev/test")
        XCTAssertEqual(decoded.universalContext?.nonFunctionalRequirements, ["NFR1"])
        XCTAssertNil(decoded.universalContext?.developerExperience)
        XCTAssertEqual(decoded.universalContext?.technicalArchitecture, ["Arch1"])
    }

    func testEncodingUsesIterationDefinitionsKey() throws {
        let project = PRDProject(
            name: "Test",
            iterationDefinitions: [
                IterationDefinition(id: "US-001", title: "S1", description: "D1", priority: 1, acceptanceCriteria: [])
            ]
        )

        let data = try JSONEncoder().encode(project)
        let jsonString = String(data: data, encoding: .utf8)!

        XCTAssertTrue(jsonString.contains("iterationDefinitions"))
        XCTAssertFalse(jsonString.contains("\"userStories\""))
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
            jsonPath: "iterationDefinitions.0",
            underlyingMessage: "Expected String"
        )
        let desc = error.errorDescription!
        XCTAssertTrue(desc.contains("ridl.json"))
        XCTAssertTrue(desc.contains("title"))
        XCTAssertTrue(desc.contains("iterationDefinitions.0"))
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
