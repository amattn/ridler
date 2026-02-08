import XCTest
@testable import Ridler

final class StreamingJSONLogParserTests: XCTestCase {

    var parser: StreamingJSONLogParser!

    override func setUp() {
        super.setUp()
        parser = StreamingJSONLogParser()
    }

    // MARK: - Assistant Text Parsing

    func testParseAssistantTextWithMessageContent() {
        let json = """
        {"type":"assistant","message":{"content":[{"type":"text","text":"Hello, world!"}]}}
        """
        let entry = parser.parse(line: json)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .assistantText("Hello, world!"))
    }

    func testParseAssistantTextWithMultipleContentBlocks() {
        let json = """
        {"type":"assistant","message":{"content":[{"type":"text","text":"First"},{"type":"text","text":"Second"}]}}
        """
        let entry = parser.parse(line: json)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .assistantText("First\nSecond"))
    }

    func testParseContentBlockDelta() {
        let json = """
        {"type":"assistant","delta":{"text":"streaming text"}}
        """
        let entry = parser.parse(line: json)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .assistantText("streaming text"))
    }

    func testParseContentBlock() {
        let json = """
        {"type":"assistant","content_block":{"type":"text","text":"block text"}}
        """
        let entry = parser.parse(line: json)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .assistantText("block text"))
    }

    // MARK: - Tool Use Parsing

    func testParseToolUse() {
        let json = """
        {"type":"tool_use","name":"Read","input":{"file_path":"/tmp/test.swift"}}
        """
        let entry = parser.parse(line: json)
        XCTAssertNotNil(entry)
        if case .toolUse(let name, let input) = entry?.type {
            XCTAssertEqual(name, "Read")
            XCTAssertTrue(input.contains("test.swift"))
        } else {
            XCTFail("Expected toolUse entry")
        }
    }

    func testParseToolUseWithoutInput() {
        let json = """
        {"type":"tool_use","name":"Bash"}
        """
        let entry = parser.parse(line: json)
        XCTAssertNotNil(entry)
        if case .toolUse(let name, let input) = entry?.type {
            XCTAssertEqual(name, "Bash")
            XCTAssertEqual(input, "")
        } else {
            XCTFail("Expected toolUse entry")
        }
    }

    func testParseToolUseWithoutName() {
        let json = """
        {"type":"tool_use","input":{"command":"ls"}}
        """
        let entry = parser.parse(line: json)
        XCTAssertNotNil(entry)
        if case .toolUse(let name, _) = entry?.type {
            XCTAssertEqual(name, "unknown")
        } else {
            XCTFail("Expected toolUse entry")
        }
    }

    // MARK: - Tool Result Parsing

    func testParseToolResultWithContent() {
        let json = """
        {"type":"tool_result","content":"file contents here"}
        """
        let entry = parser.parse(line: json)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .toolResult(output: "file contents here"))
    }

    func testParseToolResultWithOutput() {
        let json = """
        {"type":"tool_result","output":"command output"}
        """
        let entry = parser.parse(line: json)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .toolResult(output: "command output"))
    }

    func testParseToolResultWithContentArray() {
        let json = """
        {"type":"tool_result","content":[{"type":"text","text":"result line 1"},{"type":"text","text":"result line 2"}]}
        """
        let entry = parser.parse(line: json)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .toolResult(output: "result line 1\nresult line 2"))
    }

    func testParseToolResultEmpty() {
        let json = """
        {"type":"tool_result"}
        """
        let entry = parser.parse(line: json)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .toolResult(output: ""))
    }

    // MARK: - Error Parsing

    func testParseErrorWithNestedError() {
        let json = """
        {"type":"error","error":{"message":"Rate limit exceeded"}}
        """
        let entry = parser.parse(line: json)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .error("Rate limit exceeded"))
    }

    func testParseErrorWithMessage() {
        let json = """
        {"type":"error","message":"Something went wrong"}
        """
        let entry = parser.parse(line: json)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .error("Something went wrong"))
    }

    func testParseErrorWithNoMessage() {
        let json = """
        {"type":"error"}
        """
        let entry = parser.parse(line: json)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .error("Unknown error"))
    }

    // MARK: - System Parsing

    func testParseSystemWithMessage() {
        let json = """
        {"type":"system","message":"Initializing session"}
        """
        let entry = parser.parse(line: json)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .system("Initializing session"))
    }

    func testParseSystemWithSubtype() {
        let json = """
        {"type":"system","subtype":"init"}
        """
        let entry = parser.parse(line: json)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .system("init"))
    }

    // MARK: - Result Parsing

    func testParseResultWithString() {
        let json = """
        {"type":"result","result":"Task completed successfully"}
        """
        let entry = parser.parse(line: json)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .assistantText("Task completed successfully"))
    }

    func testParseResultWithMessage() {
        let json = """
        {"type":"result","message":{"content":[{"type":"text","text":"Final output"}]}}
        """
        let entry = parser.parse(line: json)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .assistantText("Final output"))
    }

    // MARK: - Malformed Input

    func testEmptyLineReturnsNil() {
        let entry = parser.parse(line: "")
        XCTAssertNil(entry)
    }

    func testWhitespaceOnlyReturnsNil() {
        let entry = parser.parse(line: "   \n  ")
        XCTAssertNil(entry)
    }

    func testMalformedJsonReturnsError() {
        let entry = parser.parse(line: "{not valid json")
        XCTAssertNotNil(entry)
        if case .error(let msg) = entry?.type {
            XCTAssertTrue(msg.contains("Malformed JSON"))
        } else {
            XCTFail("Expected error entry for malformed JSON")
        }
    }

    func testPartialJsonReturnsError() {
        let entry = parser.parse(line: "{\"type\":")
        XCTAssertNotNil(entry)
        if case .error(let msg) = entry?.type {
            XCTAssertTrue(msg.contains("Malformed JSON"))
        } else {
            XCTFail("Expected error entry for partial JSON")
        }
    }

    func testGarbageDataReturnsError() {
        let entry = parser.parse(line: "this is not json at all")
        XCTAssertNotNil(entry)
        if case .error(let msg) = entry?.type {
            XCTAssertTrue(msg.contains("Malformed JSON"))
        } else {
            XCTFail("Expected error entry for garbage data")
        }
    }

    func testJsonArrayReturnsError() {
        let entry = parser.parse(line: "[1,2,3]")
        XCTAssertNotNil(entry)
        if case .error(let msg) = entry?.type {
            XCTAssertTrue(msg.contains("not a dictionary"))
        } else {
            XCTFail("Expected error entry for non-dictionary JSON")
        }
    }

    func testMissingTypeFieldReturnsError() {
        let entry = parser.parse(line: "{\"data\":\"hello\"}")
        XCTAssertNotNil(entry)
        if case .error(let msg) = entry?.type {
            XCTAssertTrue(msg.contains("Missing 'type'"))
        } else {
            XCTFail("Expected error entry for missing type field")
        }
    }

    // MARK: - Ridler Complete Detection

    func testRidlerCompleteDetectedInAssistantText() {
        XCTAssertFalse(parser.ridlerCompleteDetected)

        let json = """
        {"type":"assistant","message":{"content":[{"type":"text","text":"All done! <ridler-complete/>"}]}}
        """
        _ = parser.parse(line: json)

        XCTAssertTrue(parser.ridlerCompleteDetected)
    }

    func testRidlerCompleteDetectedInResult() {
        XCTAssertFalse(parser.ridlerCompleteDetected)

        let json = """
        {"type":"result","result":"Finished <ridler-complete/>"}
        """
        _ = parser.parse(line: json)

        XCTAssertTrue(parser.ridlerCompleteDetected)
    }

    func testRidlerCompleteNotDetectedWithoutSignal() {
        let json = """
        {"type":"assistant","message":{"content":[{"type":"text","text":"Just normal text"}]}}
        """
        _ = parser.parse(line: json)

        XCTAssertFalse(parser.ridlerCompleteDetected)
    }

    func testRidlerCompleteDetectedInDelta() {
        XCTAssertFalse(parser.ridlerCompleteDetected)

        let json = """
        {"type":"assistant","delta":{"text":"<ridler-complete/>"}}
        """
        _ = parser.parse(line: json)

        XCTAssertTrue(parser.ridlerCompleteDetected)
    }

    func testRidlerCompleteStaysDetectedAfterMoreParsing() {
        let json1 = """
        {"type":"assistant","message":{"content":[{"type":"text","text":"<ridler-complete/>"}]}}
        """
        _ = parser.parse(line: json1)
        XCTAssertTrue(parser.ridlerCompleteDetected)

        let json2 = """
        {"type":"assistant","message":{"content":[{"type":"text","text":"more text"}]}}
        """
        _ = parser.parse(line: json2)
        XCTAssertTrue(parser.ridlerCompleteDetected)
    }

    // MARK: - Unknown Type

    func testUnknownTypeReturnsSystem() {
        let json = """
        {"type":"ping","data":"keep-alive"}
        """
        let entry = parser.parse(line: json)
        XCTAssertNotNil(entry)
        if case .system(let msg) = entry?.type {
            XCTAssertTrue(msg.contains("Unknown event type: ping"))
        } else {
            XCTFail("Expected system entry for unknown type")
        }
    }

    // MARK: - LogEntry Properties

    func testLogEntryHasUniqueId() {
        let entry1 = LogEntry(type: .system("test1"))
        let entry2 = LogEntry(type: .system("test2"))
        XCTAssertNotEqual(entry1.id, entry2.id)
    }

    func testLogEntryHasTimestamp() {
        let before = Date()
        let entry = LogEntry(type: .system("test"))
        let after = Date()
        XCTAssertGreaterThanOrEqual(entry.timestamp, before)
        XCTAssertLessThanOrEqual(entry.timestamp, after)
    }

    // MARK: - Real Claude Stream-JSON Samples

    func testRealClaudeAssistantMessage() {
        let json = """
        {"type":"assistant","message":{"id":"msg_123","type":"message","role":"assistant","content":[{"type":"text","text":"I'll help you implement that feature."}],"model":"claude-sonnet-4-5-20250929","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":100,"output_tokens":10}}}
        """
        let entry = parser.parse(line: json)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .assistantText("I'll help you implement that feature."))
    }

    func testRealClaudeToolUseMessage() {
        let json = """
        {"type":"tool_use","name":"Read","input":{"file_path":"/Users/test/project/src/main.swift","limit":100}}
        """
        let entry = parser.parse(line: json)
        XCTAssertNotNil(entry)
        if case .toolUse(let name, let input) = entry?.type {
            XCTAssertEqual(name, "Read")
            XCTAssertTrue(input.contains("main.swift"))
        } else {
            XCTFail("Expected toolUse entry")
        }
    }

    func testRealClaudeErrorMessage() {
        let json = """
        {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}
        """
        let entry = parser.parse(line: json)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.type, .error("Overloaded"))
    }
}
