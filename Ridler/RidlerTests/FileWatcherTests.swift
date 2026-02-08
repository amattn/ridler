import XCTest
@testable import Ridler

// MARK: - MockFileWatcherDelegate

final class MockFileWatcherDelegate: FileWatcherDelegate {
    var receivedEvents: [FileChangeEvent] = []
    var expectation: XCTestExpectation?

    func fileWatcher(_ watcher: FileWatcher, didDetectChangesIn event: FileChangeEvent) {
        receivedEvents.append(event)
        expectation?.fulfill()
    }
}

// MARK: - FileChangeEvent Tests

final class FileChangeEventTests: XCTestCase {

    func testFileChangeEventProperties() {
        let date = Date()
        let event = FileChangeEvent(path: "/tmp/test/file.json", directory: "/tmp/test", timestamp: date)
        XCTAssertEqual(event.path, "/tmp/test/file.json")
        XCTAssertEqual(event.directory, "/tmp/test")
        XCTAssertEqual(event.timestamp, date)
    }

    func testFileChangeEventEquality() {
        let date = Date()
        let event1 = FileChangeEvent(path: "/tmp/file.json", directory: "/tmp", timestamp: date)
        let event2 = FileChangeEvent(path: "/tmp/file.json", directory: "/tmp", timestamp: date)
        XCTAssertEqual(event1, event2)
    }

    func testFileChangeEventInequality() {
        let date = Date()
        let event1 = FileChangeEvent(path: "/tmp/file1.json", directory: "/tmp", timestamp: date)
        let event2 = FileChangeEvent(path: "/tmp/file2.json", directory: "/tmp", timestamp: date)
        XCTAssertNotEqual(event1, event2)
    }

    func testFileChangeEventDefaultTimestamp() {
        let before = Date()
        let event = FileChangeEvent(path: "/tmp/file.json", directory: "/tmp")
        let after = Date()
        XCTAssertGreaterThanOrEqual(event.timestamp, before)
        XCTAssertLessThanOrEqual(event.timestamp, after)
    }
}

// MARK: - FileWatcher Tests

final class FileWatcherTests: XCTestCase {

    private var tempDir1: String!
    private var tempDir2: String!
    // Resolved paths (FSEvents reports real paths, resolving symlinks like /var -> /private/var)
    private var resolvedDir1: String!
    private var resolvedDir2: String!

    private func realResolvedPath(_ path: String) -> String {
        var resolved = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(path, &resolved) != nil else { return path }
        return String(cString: resolved)
    }

    override func setUp() {
        super.setUp()
        tempDir1 = NSTemporaryDirectory() + "FileWatcherTests1_\(UUID().uuidString)"
        tempDir2 = NSTemporaryDirectory() + "FileWatcherTests2_\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: tempDir1, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(atPath: tempDir2, withIntermediateDirectories: true)
        resolvedDir1 = realResolvedPath(tempDir1)
        resolvedDir2 = realResolvedPath(tempDir2)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tempDir1)
        try? FileManager.default.removeItem(atPath: tempDir2)
        super.tearDown()
    }

    // MARK: - Watch/Stop Tests

    func testInitialStateNotWatching() {
        let watcher = FileWatcher()
        XCTAssertFalse(watcher.isWatching)
        XCTAssertTrue(watcher.watchedDirectories.isEmpty)
    }

    func testWatchDirectoryStartsWatching() {
        let watcher = FileWatcher()
        watcher.watch(directory: tempDir1)
        XCTAssertTrue(watcher.isWatching)
        XCTAssertTrue(watcher.isWatching(directory: tempDir1))
        XCTAssertEqual(watcher.watchedDirectories, [resolvedDir1])
        watcher.stopAll()
    }

    func testWatchMultipleDirectories() {
        let watcher = FileWatcher()
        watcher.watch(directory: tempDir1)
        watcher.watch(directory: tempDir2)
        XCTAssertTrue(watcher.isWatching(directory: tempDir1))
        XCTAssertTrue(watcher.isWatching(directory: tempDir2))
        XCTAssertEqual(watcher.watchedDirectories.count, 2)
        watcher.stopAll()
    }

    func testWatchSameDirectoryTwiceIsNoop() {
        let watcher = FileWatcher()
        watcher.watch(directory: tempDir1)
        watcher.watch(directory: tempDir1)
        XCTAssertEqual(watcher.watchedDirectories.count, 1)
        watcher.stopAll()
    }

    func testStopWatchingDirectory() {
        let watcher = FileWatcher()
        watcher.watch(directory: tempDir1)
        watcher.watch(directory: tempDir2)
        watcher.stopWatching(directory: tempDir1)
        XCTAssertFalse(watcher.isWatching(directory: tempDir1))
        XCTAssertTrue(watcher.isWatching(directory: tempDir2))
        XCTAssertEqual(watcher.watchedDirectories, [resolvedDir2])
        watcher.stopAll()
    }

    func testStopWatchingUnwatchedDirectoryIsNoop() {
        let watcher = FileWatcher()
        watcher.stopWatching(directory: "/nonexistent")
        XCTAssertFalse(watcher.isWatching)
    }

    func testStopAllClearsAllWatchers() {
        let watcher = FileWatcher()
        watcher.watch(directory: tempDir1)
        watcher.watch(directory: tempDir2)
        watcher.stopAll()
        XCTAssertFalse(watcher.isWatching)
        XCTAssertTrue(watcher.watchedDirectories.isEmpty)
    }

    func testWatchedDirectoriesAreSorted() {
        let watcher = FileWatcher()
        let dirs = [resolvedDir1!, resolvedDir2!].sorted()
        // Watch in reverse order to confirm sorting
        if resolvedDir1 < resolvedDir2 {
            watcher.watch(directory: tempDir2)
            watcher.watch(directory: tempDir1)
        } else {
            watcher.watch(directory: tempDir1)
            watcher.watch(directory: tempDir2)
        }
        XCTAssertEqual(watcher.watchedDirectories, dirs)
        watcher.stopAll()
    }

    // MARK: - File Change Detection Tests

    func testDetectsFileCreation() {
        let watcher = FileWatcher(debounceInterval: 0.1)
        let delegate = MockFileWatcherDelegate()
        delegate.expectation = expectation(description: "File creation detected")
        watcher.delegate = delegate
        watcher.watch(directory: tempDir1)

        let filePath = (tempDir1 as NSString).appendingPathComponent("test.json")
        try! "{}".write(toFile: filePath, atomically: true, encoding: .utf8)

        waitForExpectations(timeout: 5.0)
        XCTAssertFalse(delegate.receivedEvents.isEmpty)
        XCTAssertEqual(delegate.receivedEvents.first?.directory, resolvedDir1)
        watcher.stopAll()
    }

    func testDetectsFileModification() {
        let watcher = FileWatcher(debounceInterval: 0.1)
        let delegate = MockFileWatcherDelegate()
        watcher.delegate = delegate
        watcher.watch(directory: tempDir1)

        // Create file first
        let filePath = (tempDir1 as NSString).appendingPathComponent("existing.json")
        try! "{}".write(toFile: filePath, atomically: true, encoding: .utf8)

        // Wait for creation event, then modify
        let modifyExpectation = expectation(description: "File modification detected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            delegate.receivedEvents.removeAll()
            delegate.expectation = modifyExpectation
            try! "{\"updated\": true}".write(toFile: filePath, atomically: true, encoding: .utf8)
        }

        waitForExpectations(timeout: 5.0)
        XCTAssertFalse(delegate.receivedEvents.isEmpty)
        XCTAssertEqual(delegate.receivedEvents.first?.directory, self.resolvedDir1)
        watcher.stopAll()
    }

    func testDetectsFileDeletion() {
        let watcher = FileWatcher(debounceInterval: 0.1)
        let delegate = MockFileWatcherDelegate()
        watcher.delegate = delegate
        watcher.watch(directory: tempDir1)

        // Create file first
        let filePath = (tempDir1 as NSString).appendingPathComponent("todelete.json")
        try! "{}".write(toFile: filePath, atomically: true, encoding: .utf8)

        // Wait for creation event, then delete
        let deleteExpectation = expectation(description: "File deletion detected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            delegate.receivedEvents.removeAll()
            delegate.expectation = deleteExpectation
            try! FileManager.default.removeItem(atPath: filePath)
        }

        waitForExpectations(timeout: 5.0)
        XCTAssertFalse(delegate.receivedEvents.isEmpty)
        XCTAssertEqual(delegate.receivedEvents.first?.directory, self.resolvedDir1)
        watcher.stopAll()
    }

    // MARK: - Debounce Tests

    func testDebounceCoalescesRapidChanges() {
        let watcher = FileWatcher(debounceInterval: 0.3)
        let delegate = MockFileWatcherDelegate()
        delegate.expectation = expectation(description: "Debounced event received")
        watcher.delegate = delegate
        watcher.watch(directory: tempDir1)

        // Write multiple files rapidly
        for i in 0..<5 {
            let filePath = (tempDir1 as NSString).appendingPathComponent("rapid\(i).json")
            try! "{}".write(toFile: filePath, atomically: true, encoding: .utf8)
        }

        waitForExpectations(timeout: 5.0)

        // Allow a bit more time for any extra events
        let noMoreExpectation = expectation(description: "Wait for extra events")
        noMoreExpectation.isInverted = true
        delegate.expectation = noMoreExpectation
        waitForExpectations(timeout: 1.0)

        // Debounce should have coalesced the rapid writes
        XCTAssertLessThanOrEqual(delegate.receivedEvents.count, 3)
        watcher.stopAll()
    }

    // MARK: - Multiple Directory Tests

    func testEventsFromMultipleDirectories() {
        let watcher = FileWatcher(debounceInterval: 0.1)
        let delegate = MockFileWatcherDelegate()
        delegate.expectation = expectation(description: "Events from both dirs")
        delegate.expectation?.expectedFulfillmentCount = 2
        watcher.delegate = delegate
        watcher.watch(directory: tempDir1)
        watcher.watch(directory: tempDir2)

        // Write to both directories
        let file1 = (tempDir1 as NSString).appendingPathComponent("file1.json")
        let file2 = (tempDir2 as NSString).appendingPathComponent("file2.json")
        try! "{}".write(toFile: file1, atomically: true, encoding: .utf8)
        try! "{}".write(toFile: file2, atomically: true, encoding: .utf8)

        waitForExpectations(timeout: 5.0)

        let dirs = Set(delegate.receivedEvents.map { $0.directory })
        XCTAssertTrue(dirs.contains(resolvedDir1))
        XCTAssertTrue(dirs.contains(resolvedDir2))
        watcher.stopAll()
    }

    // MARK: - Event Path Tests

    func testEventIncludesAffectedFilePath() {
        let watcher = FileWatcher(debounceInterval: 0.1)
        let delegate = MockFileWatcherDelegate()
        delegate.expectation = expectation(description: "Event with file path")
        watcher.delegate = delegate
        watcher.watch(directory: tempDir1)

        let filePath = (tempDir1 as NSString).appendingPathComponent("specific.json")
        try! "{}".write(toFile: filePath, atomically: true, encoding: .utf8)

        waitForExpectations(timeout: 5.0)
        XCTAssertFalse(delegate.receivedEvents.isEmpty)
        let event = delegate.receivedEvents.first!
        // The event path should be within the watched directory (resolved)
        XCTAssertTrue(event.path.hasPrefix(resolvedDir1))
        XCTAssertEqual(event.directory, resolvedDir1)
        watcher.stopAll()
    }

    // MARK: - Stopped Watcher Tests

    func testStoppedWatcherDoesNotReceiveEvents() {
        let watcher = FileWatcher(debounceInterval: 0.1)
        let delegate = MockFileWatcherDelegate()
        watcher.delegate = delegate
        watcher.watch(directory: tempDir1)
        watcher.stopWatching(directory: tempDir1)

        // Write after stopping
        let filePath = (tempDir1 as NSString).appendingPathComponent("afterstop.json")
        try! "{}".write(toFile: filePath, atomically: true, encoding: .utf8)

        let noEventExpectation = expectation(description: "No events after stop")
        noEventExpectation.isInverted = true
        delegate.expectation = noEventExpectation
        waitForExpectations(timeout: 1.0)

        XCTAssertTrue(delegate.receivedEvents.isEmpty)
    }

    // MARK: - Cleanup Tests

    func testDeinitStopsAllWatchers() {
        var watcher: FileWatcher? = FileWatcher()
        watcher!.watch(directory: tempDir1)
        watcher!.watch(directory: tempDir2)
        XCTAssertTrue(watcher!.isWatching)
        watcher = nil
        // No assertion needed — we verify no crash on dealloc
    }

    // MARK: - Custom Debounce Interval

    func testCustomDebounceInterval() {
        let watcher = FileWatcher(debounceInterval: 1.0)
        let delegate = MockFileWatcherDelegate()
        watcher.delegate = delegate
        watcher.watch(directory: tempDir1)

        let filePath = (tempDir1 as NSString).appendingPathComponent("debounce.json")
        try! "{}".write(toFile: filePath, atomically: true, encoding: .utf8)

        // With 1s debounce, should not get event within 0.5s
        let tooSoon = expectation(description: "Too soon")
        tooSoon.isInverted = true
        delegate.expectation = tooSoon
        waitForExpectations(timeout: 0.5)
        XCTAssertTrue(delegate.receivedEvents.isEmpty)

        // But should get it within 2s total
        let gotIt = expectation(description: "Got event")
        delegate.expectation = gotIt
        waitForExpectations(timeout: 3.0)
        XCTAssertFalse(delegate.receivedEvents.isEmpty)
        watcher.stopAll()
    }
}
