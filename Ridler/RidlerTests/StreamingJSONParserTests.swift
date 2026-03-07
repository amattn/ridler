import XCTest
import Combine
@testable import Ridler

final class StreamingJSONParserTests: XCTestCase {
    var parser: StreamingJSONParser!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        parser = StreamingJSONParser()
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        parser = nil
        super.tearDown()
    }

    // MARK: - Assistant Text Parsing

    func testParseAssistantTextWithContentString() {
        let json = #"{"type": "assistant", "content": "Hello, I will help you implement this feature."}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .assistantText)
        XCTAssertEqual(entry?.content, "Hello, I will help you implement this feature.")
    }

    func testParseAssistantTextWithContentArray() {
        let json = #"{"type": "assistant", "content": [{"type": "text", "text": "Let me read the file first."}]}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .assistantText)
        XCTAssertEqual(entry?.content, "Let me read the file first.")
    }

    func testParseAssistantTextWithMessageField() {
        let json = #"{"type": "assistant", "message": "Working on it..."}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .assistantText)
        XCTAssertEqual(entry?.content, "Working on it...")
    }

    func testParseAssistantTextMultipleContentBlocks() {
        let json = #"{"type": "assistant", "content": [{"type": "text", "text": "First part."}, {"type": "text", "text": "Second part."}]}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .assistantText)
        XCTAssertEqual(entry?.content, "First part.\nSecond part.")
    }

    // MARK: - Tool Use Parsing

    func testParseToolUseWithBashCommand() {
        let json = #"{"type": "tool_use", "tool": "Bash", "input": {"command": "npm test"}}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .toolUse)
        XCTAssertTrue(entry!.content.contains("Bash"))
        XCTAssertTrue(entry!.content.contains("$ npm test"))
    }

    func testParseToolUseWithReadFile() {
        let json = #"{"type": "tool_use", "tool": "Read", "input": {"file_path": "/src/main.swift"}}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .toolUse)
        XCTAssertTrue(entry!.content.contains("Read"))
        XCTAssertTrue(entry!.content.contains("/src/main.swift"))
    }

    func testParseToolUseWithGlobPattern() {
        let json = #"{"type": "tool_use", "tool": "Glob", "input": {"pattern": "**/*.swift"}}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .toolUse)
        XCTAssertTrue(entry!.content.contains("Glob"))
        XCTAssertTrue(entry!.content.contains("**/*.swift"))
    }

    func testParseToolUseWithNameField() {
        let json = #"{"type": "tool_use", "name": "Edit", "input": {"file_path": "/src/app.swift"}}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .toolUse)
        XCTAssertTrue(entry!.content.contains("Edit"))
    }

    func testParseToolUseWithoutToolName() {
        let json = #"{"type": "tool_use", "input": {"command": "ls"}}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .toolUse)
        XCTAssertTrue(entry!.content.contains("unknown"))
    }

    // MARK: - Tool Result Parsing

    func testParseToolResultWithOutput() {
        let json = #"{"type": "tool_result", "output": "File content here..."}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .toolResult)
        XCTAssertEqual(entry?.content, "File content here...")
    }

    func testParseToolResultWithContentArray() {
        let json = #"{"type": "tool_result", "content": [{"type": "text", "text": "Test passed!"}]}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .toolResult)
        XCTAssertEqual(entry?.content, "Test passed!")
    }

    // MARK: - Error Parsing

    func testParseErrorWithMessageString() {
        let json = #"{"type": "error", "message": "Rate limit exceeded"}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .error)
        XCTAssertEqual(entry?.content, "Rate limit exceeded")
    }

    func testParseErrorWithErrorObject() {
        let json = #"{"type": "error", "error": {"type": "overloaded_error", "message": "Server is overloaded"}}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .error)
        XCTAssertTrue(entry!.content.contains("overloaded_error"))
        XCTAssertTrue(entry!.content.contains("Server is overloaded"))
    }

    func testParseErrorWithErrorString() {
        let json = #"{"type": "error", "error": "Something went wrong"}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .error)
        XCTAssertEqual(entry?.content, "Something went wrong")
    }

    // MARK: - Result Parsing

    func testParseResultMessage() {
        let json = #"{"type": "result", "result": "Task completed successfully."}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .assistantText)
        XCTAssertEqual(entry?.content, "Task completed successfully.")
    }

    // MARK: - System / Unknown Type Parsing

    func testParseUnknownTypeAsSystem() {
        let json = #"{"type": "system", "message": "Session started"}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .system)
        XCTAssertTrue(entry!.content.contains("Session started"))
    }

    func testParseCustomTypeAsSystem() {
        let json = #"{"type": "init", "message": "Initializing..."}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .system)
        XCTAssertTrue(entry!.content.contains("init"))
        XCTAssertTrue(entry!.content.contains("Initializing..."))
    }

    // MARK: - Malformed JSON Handling

    func testMalformedJSONReturnsNil() {
        let entry = parser.parseLine("this is not json")
        XCTAssertNil(entry)
    }

    func testPartialJSONReturnsNil() {
        let entry = parser.parseLine(#"{"type": "assistant", "content":"#)
        XCTAssertNil(entry)
    }

    func testEmptyLineReturnsNil() {
        let entry = parser.parseLine("")
        XCTAssertNil(entry)
    }

    func testWhitespaceOnlyLineReturnsNil() {
        let entry = parser.parseLine("   \t  \n  ")
        XCTAssertNil(entry)
    }

    func testJSONArrayReturnsNil() {
        let entry = parser.parseLine(#"[1, 2, 3]"#)
        XCTAssertNil(entry)
    }

    func testJSONWithoutTypeFieldParsesAsSystem() {
        let json = #"{"message": "no type field"}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .system)
    }

    // MARK: - Ridler Complete Signal Detection

    func testDetectRidlerCompleteInAssistantContent() {
        let expectation = XCTestExpectation(description: "Completion detected")

        parser.signalPublisher
            .prefix(1)
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        let json = #"{"type": "assistant", "content": "All stories complete. <ridler-complete/>"}"#
        parser.parseLine(json)

        wait(for: [expectation], timeout: 1.0)
    }

    func testDetectRidlerCompleteInRawText() {
        let expectation = XCTestExpectation(description: "Completion detected")

        parser.signalPublisher
            .prefix(1)
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        // Non-JSON line containing the signal
        let _ = parser.parseLine("<ridler-complete/>")

        wait(for: [expectation], timeout: 1.0)
    }

    func testDetectRidlerCompleteInResult() {
        let expectation = XCTestExpectation(description: "Completion detected")

        parser.signalPublisher
            .prefix(1)
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        let json = #"{"type": "result", "result": "Done! <ridler-complete/>"}"#
        parser.parseLine(json)

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Entry Publisher

    func testEntryPublisherEmitsForValidJSON() {
        let expectation = XCTestExpectation(description: "Entry emitted")
        var receivedEntry: LogEntry?

        parser.entryPublisher
            .prefix(1)
            .sink { entry in
                receivedEntry = entry
                expectation.fulfill()
            }
            .store(in: &cancellables)

        let json = #"{"type": "assistant", "content": "Hello"}"#
        parser.parseLine(json)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedEntry?.type, .assistantText)
        XCTAssertEqual(receivedEntry?.content, "Hello")
    }

    func testEntryPublisherDoesNotEmitForMalformedJSON() {
        let expectation = XCTestExpectation(description: "No entry emitted")
        expectation.isInverted = true

        parser.entryPublisher
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        parser.parseLine("not json")

        wait(for: [expectation], timeout: 0.5)
    }

    // MARK: - Subscribe to Line Publisher

    func testSubscribeToLinePublisher() {
        let lineSubject = PassthroughSubject<String, Never>()
        let expectation = XCTestExpectation(description: "Entries received")
        expectation.expectedFulfillmentCount = 3
        var entries: [LogEntry] = []

        parser.entryPublisher
            .sink { entry in
                entries.append(entry)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        let subscription = parser.subscribe(to: lineSubject.eraseToAnyPublisher())
        cancellables.insert(subscription)

        lineSubject.send(#"{"type": "assistant", "content": "Step 1"}"#)
        lineSubject.send(#"{"type": "tool_use", "tool": "Read", "input": {"file_path": "/test.swift"}}"#)
        lineSubject.send(#"{"type": "tool_result", "output": "file contents"}"#)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].type, .assistantText)
        XCTAssertEqual(entries[1].type, .toolUse)
        XCTAssertEqual(entries[2].type, .toolResult)
    }

    func testSubscribeSkipsMalformedLines() {
        let lineSubject = PassthroughSubject<String, Never>()
        let expectation = XCTestExpectation(description: "Valid entries received")
        expectation.expectedFulfillmentCount = 2
        var entries: [LogEntry] = []

        parser.entryPublisher
            .sink { entry in
                entries.append(entry)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        let subscription = parser.subscribe(to: lineSubject.eraseToAnyPublisher())
        cancellables.insert(subscription)

        lineSubject.send(#"{"type": "assistant", "content": "Before"}"#)
        lineSubject.send("malformed line")
        lineSubject.send("")
        lineSubject.send(#"{"type": "assistant", "content": "After"}"#)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].content, "Before")
        XCTAssertEqual(entries[1].content, "After")
    }

    // MARK: - Realistic Claude Output Sequences

    func testRealisticClaudeOutputSequence() {
        let lines = [
            #"{"type": "system", "message": "Claude Code session started"}"#,
            #"{"type": "assistant", "content": "I'll implement the streaming JSON parser for you."}"#,
            #"{"type": "tool_use", "tool": "Read", "input": {"file_path": "/src/parser.swift"}}"#,
            #"{"type": "tool_result", "output": "import Foundation\nclass Parser { }"}"#,
            #"{"type": "tool_use", "tool": "Edit", "input": {"file_path": "/src/parser.swift"}}"#,
            #"{"type": "tool_result", "output": "File edited successfully"}"#,
            #"{"type": "tool_use", "tool": "Bash", "input": {"command": "swift test"}}"#,
            #"{"type": "tool_result", "output": "All tests passed"}"#,
            #"{"type": "assistant", "content": "Implementation complete. <ridler-complete/>"}"#
        ]

        var entries: [LogEntry] = []
        var completionDetected = false

        let completionExpectation = XCTestExpectation(description: "Completion detected")

        parser.signalPublisher
            .prefix(1)
            .sink { signal in
                if signal == .complete { completionDetected = true }
                completionExpectation.fulfill()
            }
            .store(in: &cancellables)

        for line in lines {
            if let entry = parser.parseLine(line) {
                entries.append(entry)
            }
        }

        wait(for: [completionExpectation], timeout: 1.0)

        XCTAssertEqual(entries.count, 9)
        XCTAssertEqual(entries[0].type, .system)
        XCTAssertEqual(entries[1].type, .assistantText)
        XCTAssertEqual(entries[2].type, .toolUse)
        XCTAssertEqual(entries[3].type, .toolResult)
        XCTAssertEqual(entries[4].type, .toolUse)
        XCTAssertEqual(entries[5].type, .toolResult)
        XCTAssertEqual(entries[6].type, .toolUse)
        XCTAssertEqual(entries[7].type, .toolResult)
        XCTAssertEqual(entries[8].type, .assistantText)
        XCTAssertTrue(completionDetected)
    }

    // MARK: - LogEntry Properties

    func testLogEntryHasUniqueIDs() {
        let entry1 = parser.parseLine(#"{"type": "assistant", "content": "A"}"#)
        let entry2 = parser.parseLine(#"{"type": "assistant", "content": "B"}"#)

        XCTAssertNotNil(entry1)
        XCTAssertNotNil(entry2)
        XCTAssertNotEqual(entry1?.id, entry2?.id)
    }

    func testLogEntryHasTimestamp() {
        let before = Date()
        let entry = parser.parseLine(#"{"type": "assistant", "content": "Test"}"#)
        let after = Date()

        XCTAssertNotNil(entry)
        XCTAssertGreaterThanOrEqual(entry!.timestamp, before)
        XCTAssertLessThanOrEqual(entry!.timestamp, after)
    }

    // MARK: - Nested Assistant Text (Real Claude Code Output)

    func testParseNestedAssistantMessage() {
        let json = #"{"session_id":"abc","type":"assistant","message":{"content":[{"type":"text","text":"I will help you."}],"id":"msg_1","role":"assistant","model":"claude-opus-4-6"}}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .assistantText)
        XCTAssertEqual(entry?.content, "I will help you.")
    }

    func testParseNestedAssistantMessageMultipleBlocks() {
        let json = #"{"type":"assistant","message":{"content":[{"type":"text","text":"First."},{"type":"text","text":"Second."}],"role":"assistant"}}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .assistantText)
        XCTAssertEqual(entry?.content, "First.\nSecond.")
    }

    // MARK: - Nested Assistant with Tool Use Blocks

    func testParseAssistantWithToolUseBlock() {
        let json = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_01","name":"Read","input":{"file_path":"/src/main.swift"}}],"role":"assistant"}}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .toolUse)
        XCTAssertTrue(entry!.content.contains("Read"))
        XCTAssertTrue(entry!.content.contains("/src/main.swift"))
    }

    func testParseAssistantWithBashToolUseBlock() {
        let json = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_02","name":"Bash","input":{"command":"xcodebuild build"}}],"role":"assistant"}}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .toolUse)
        XCTAssertTrue(entry!.content.contains("Bash"))
        XCTAssertTrue(entry!.content.contains("$ xcodebuild build"))
    }

    func testParseAssistantWithGlobToolUseBlock() {
        let json = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_03","name":"Glob","input":{"pattern":"**/*.swift"}}],"role":"assistant"}}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .toolUse)
        XCTAssertTrue(entry!.content.contains("Glob"))
        XCTAssertTrue(entry!.content.contains("**/*.swift"))
    }

    func testParseAssistantWithTaskToolUseBlock() {
        let json = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_04","name":"Task","input":{"description":"Explore project","subagent_type":"Explore","prompt":"Explore the Xcode project..."}}],"role":"assistant"}}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .toolUse)
        XCTAssertTrue(entry!.content.contains("Task"))
        XCTAssertTrue(entry!.content.contains("Explore the Xcode project"))
    }

    func testParseAssistantWithTodoWriteToolUseBlock() {
        let json = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_05","name":"TodoWrite","input":{"todos":[{"content":"Fix build","status":"pending"}]}}],"role":"assistant"}}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .toolUse)
        XCTAssertTrue(entry!.content.contains("TodoWrite"))
    }

    // MARK: - Nested Tool Use / Tool Result (flat type)

    func testParseNestedToolUse() {
        let json = #"{"type":"tool_use","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/src/main.swift"}}]}}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .toolUse)
        XCTAssertTrue(entry!.content.contains("Read"))
        XCTAssertTrue(entry!.content.contains("/src/main.swift"))
    }

    func testParseNestedToolResult() {
        let json = #"{"type":"tool_result","message":{"content":[{"type":"text","text":"file contents here"}]}}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .toolResult)
        XCTAssertEqual(entry?.content, "file contents here")
    }

    func testParseNestedResult() {
        let json = #"{"type":"result","message":{"content":[{"type":"text","text":"Task completed. <ridler-complete/>"}]}}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .assistantText)
        XCTAssertTrue(entry!.content.contains("Task completed."))
    }

    // MARK: - User Messages (tool results returned to Claude)

    func testParseUserToolResultWithStringContent() {
        let json = #"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_01","type":"tool_result","content":"     1→import Foundation\n     2→class Parser { }"}]}}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .toolResult)
        XCTAssertTrue(entry!.content.contains("import Foundation"))
    }

    func testParseUserToolResultWithError() {
        let json = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"<tool_use_error>File does not exist.</tool_use_error>","is_error":true,"tool_use_id":"toolu_01"}]},"tool_use_result":"Error: File does not exist."}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .error)
        XCTAssertTrue(entry!.content.contains("File does not exist"))
        // XML tags should be stripped
        XCTAssertFalse(entry!.content.contains("<tool_use_error>"))
    }

    func testParseUserToolResultWithSiblingError() {
        let json = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"<tool_use_error>Sibling tool call errored</tool_use_error>","is_error":true,"tool_use_id":"toolu_01"}]}}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .error)
        XCTAssertTrue(entry!.content.contains("Sibling tool call errored"))
    }

    func testParseUserToolResultWithContentArray() {
        let json = #"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_01","type":"tool_result","content":[{"type":"text","text":"Agent summary here."},{"type":"text","text":"agentId: abc123"}]}]}}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .toolResult)
        XCTAssertTrue(entry!.content.contains("Agent summary here."))
        XCTAssertTrue(entry!.content.contains("agentId: abc123"))
    }

    func testParseUserToolResultTodoWriteResponse() {
        let json = #"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_01","type":"tool_result","content":"Todos have been modified successfully."}]}}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .toolResult)
        XCTAssertTrue(entry!.content.contains("Todos have been modified"))
    }

    func testParseUserTextBlockAsAgentPrompt() {
        let json = #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Explore the Xcode project at /path/to/project"}]},"parent_tool_use_id":"toolu_01"}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .system)
        XCTAssertTrue(entry!.content.contains("[agent prompt]"))
        XCTAssertTrue(entry!.content.contains("Explore the Xcode project"))
    }

    // MARK: - System Init Messages

    func testParseSystemInitMessage() {
        let json = #"{"type":"system","subtype":"init","cwd":"/Users/kai/project","model":"claude-opus-4-6","claude_code_version":"2.1.39","session_id":"abc"}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .system)
        XCTAssertTrue(entry!.content.contains("[system:init]"))
        XCTAssertTrue(entry!.content.contains("claude-opus-4-6"))
        XCTAssertTrue(entry!.content.contains("/Users/kai/project"))
        XCTAssertTrue(entry!.content.contains("v2.1.39"))
    }

    func testParseSystemInitDoesNotDumpFullJSON() {
        let json = #"{"type":"system","subtype":"init","cwd":"/proj","model":"claude-opus-4-6","tools":["Bash","Read","Edit"],"session_id":"abc","claude_code_version":"2.1.39"}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        // Should NOT contain the tools array dump
        XCTAssertFalse(entry!.content.contains("[\"Bash\""))
    }

    // MARK: - rawJSON Population

    func testRawJSONIsPopulated() {
        let json = #"{"type": "assistant", "content": "Hello"}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertNotNil(entry?.rawJSON)
        XCTAssertTrue(entry!.rawJSON!.contains("assistant"))
    }

    func testRawJSONIsPopulatedForNestedFormat() {
        let json = #"{"type":"assistant","message":{"content":[{"type":"text","text":"nested"}]}}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertNotNil(entry?.rawJSON)
        XCTAssertTrue(entry!.rawJSON!.contains("message"))
    }

    func testRawJSONNilForManualLogEntry() {
        let entry = LogEntry(type: .system, content: "manual entry")
        XCTAssertNil(entry.rawJSON)
    }

    func testRawJSONPopulatedForUserMessage() {
        let json = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"ok","tool_use_id":"toolu_01"}]}}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry?.rawJSON)
    }

    // MARK: - Edge Cases

    func testLineWithLeadingTrailingWhitespace() {
        let json = #"  {"type": "assistant", "content": "Hello"}  "#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .assistantText)
        XCTAssertEqual(entry?.content, "Hello")
    }

    func testFallbackContentForUnknownFields() {
        let json = #"{"type": "assistant", "unknown_field": "some value"}"#
        let entry = parser.parseLine(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .assistantText)
        // Should have fallback JSON content since no recognized content fields exist
        XCTAssertFalse(entry!.content.isEmpty)
    }
}
