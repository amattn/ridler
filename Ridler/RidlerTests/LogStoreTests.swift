import XCTest
@testable import Ridler

final class LogStoreTests: XCTestCase {

    func testEmptyStoreReturnsEmptyArray() {
        let store = LogStore()
        XCTAssertTrue(store.entries(for: "project1").isEmpty)
    }

    func testAppendEntry() {
        let store = LogStore()
        let entry = LogEntry(type: .assistantText, content: "Hello")
        store.append(entry, for: "project1")

        XCTAssertEqual(store.entries(for: "project1").count, 1)
        XCTAssertEqual(store.entries(for: "project1").first?.content, "Hello")
        XCTAssertEqual(store.entries(for: "project1").first?.type, .assistantText)
    }

    func testAppendMultipleEntries() {
        let store = LogStore()
        store.append(LogEntry(type: .assistantText, content: "First"), for: "p1")
        store.append(LogEntry(type: .toolUse, content: "Tool: Bash\n$ echo hi"), for: "p1")
        store.append(LogEntry(type: .toolResult, content: "hi"), for: "p1")

        let entries = store.entries(for: "p1")
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].type, .assistantText)
        XCTAssertEqual(entries[1].type, .toolUse)
        XCTAssertEqual(entries[2].type, .toolResult)
    }

    func testAppendSystemMessage() {
        let store = LogStore()
        store.appendSystem("Starting iteration 1", for: "project1")

        let entries = store.entries(for: "project1")
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.type, .system)
        XCTAssertEqual(entries.first?.content, "Starting iteration 1")
    }

    func testEntriesIsolatedByProjectID() {
        let store = LogStore()
        store.append(LogEntry(type: .assistantText, content: "Project A"), for: "projA")
        store.append(LogEntry(type: .error, content: "Project B error"), for: "projB")

        XCTAssertEqual(store.entries(for: "projA").count, 1)
        XCTAssertEqual(store.entries(for: "projB").count, 1)
        XCTAssertEqual(store.entries(for: "projA").first?.content, "Project A")
        XCTAssertEqual(store.entries(for: "projB").first?.content, "Project B error")
    }

    func testClearEntries() {
        let store = LogStore()
        store.append(LogEntry(type: .assistantText, content: "Hello"), for: "p1")
        store.append(LogEntry(type: .toolUse, content: "Tool: Read"), for: "p1")
        XCTAssertEqual(store.entries(for: "p1").count, 2)

        store.clear(for: "p1")
        XCTAssertTrue(store.entries(for: "p1").isEmpty)
    }

    func testClearDoesNotAffectOtherProjects() {
        let store = LogStore()
        store.append(LogEntry(type: .assistantText, content: "A"), for: "projA")
        store.append(LogEntry(type: .assistantText, content: "B"), for: "projB")

        store.clear(for: "projA")
        XCTAssertTrue(store.entries(for: "projA").isEmpty)
        XCTAssertEqual(store.entries(for: "projB").count, 1)
    }

    func testSystemMessageTypes() {
        let store = LogStore()
        store.appendSystem("Working on: US-001 - Create project", for: "p1")
        store.appendSystem("Story US-001 completed", for: "p1")
        store.appendSystem("Starting iteration 2", for: "p1")

        let entries = store.entries(for: "p1")
        XCTAssertEqual(entries.count, 3)
        for entry in entries {
            XCTAssertEqual(entry.type, .system)
        }
        XCTAssertTrue(entries[0].content.contains("US-001"))
        XCTAssertTrue(entries[1].content.contains("completed"))
        XCTAssertTrue(entries[2].content.contains("iteration 2"))
    }

    func testEntriesPreserveOrder() {
        let store = LogStore()
        for i in 0..<10 {
            store.append(LogEntry(type: .assistantText, content: "Entry \(i)"), for: "p1")
        }

        let entries = store.entries(for: "p1")
        XCTAssertEqual(entries.count, 10)
        for i in 0..<10 {
            XCTAssertEqual(entries[i].content, "Entry \(i)")
        }
    }

    func testNonexistentProjectReturnsEmpty() {
        let store = LogStore()
        store.append(LogEntry(type: .assistantText, content: "Hello"), for: "p1")
        XCTAssertTrue(store.entries(for: "nonexistent").isEmpty)
    }
}
