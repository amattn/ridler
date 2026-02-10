import XCTest
import Combine
@testable import Ridler

final class DirectoryMonitorTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RidlerTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testDetectsFileCreation() {
        let monitor = DirectoryMonitor(directoryURL: tempDir)
        let expectation = expectation(description: "File change detected")

        var cancellable: AnyCancellable?
        cancellable = monitor.$lastChangeDate
            .dropFirst()
            .prefix(1)
            .sink { _ in
                expectation.fulfill()
                _ = cancellable
            }

        monitor.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let fileURL = self.tempDir.appendingPathComponent("test.txt")
            try? "hello".write(to: fileURL, atomically: true, encoding: .utf8)
        }

        waitForExpectations(timeout: 2)
        monitor.stop()
    }

    func testDetectsFileModification() {
        let fileURL = tempDir.appendingPathComponent("existing.txt")
        try? "initial".write(to: fileURL, atomically: true, encoding: .utf8)

        let monitor = DirectoryMonitor(directoryURL: tempDir)
        let expectation = expectation(description: "File modification detected")

        var cancellable: AnyCancellable?
        cancellable = monitor.$lastChangeDate
            .dropFirst()
            .prefix(1)
            .sink { _ in
                expectation.fulfill()
                _ = cancellable
            }

        monitor.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            try? "modified".write(to: fileURL, atomically: true, encoding: .utf8)
        }

        waitForExpectations(timeout: 2)
        monitor.stop()
    }

    func testStopPreventsNotifications() {
        let monitor = DirectoryMonitor(directoryURL: tempDir)
        monitor.start()
        monitor.stop()

        let expectation = expectation(description: "Should not be fulfilled")
        expectation.isInverted = true

        var cancellable: AnyCancellable?
        cancellable = monitor.$lastChangeDate
            .dropFirst()
            .prefix(1)
            .sink { _ in
                expectation.fulfill()
                _ = cancellable
            }

        let fileURL = tempDir.appendingPathComponent("test.txt")
        try? "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        waitForExpectations(timeout: 0.5)
    }

    func testLastChangeDateUpdatedOnMainThread() {
        let monitor = DirectoryMonitor(directoryURL: tempDir)
        let expectation = expectation(description: "Change on main thread")

        var cancellable: AnyCancellable?
        cancellable = monitor.$lastChangeDate
            .dropFirst()
            .prefix(1)
            .sink { _ in
                XCTAssertTrue(Thread.isMainThread)
                expectation.fulfill()
                _ = cancellable
            }

        monitor.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let fileURL = self.tempDir.appendingPathComponent("test.txt")
            try? "hello".write(to: fileURL, atomically: true, encoding: .utf8)
        }

        waitForExpectations(timeout: 2)
        monitor.stop()
    }
}

final class ProjectFileWatcherTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RidlerTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testChangeTokenUpdatesOnFileChange() {
        let watcher = ProjectFileWatcher()
        watcher.watch(directoryURL: tempDir)

        let expectation = expectation(description: "Change token updated")

        var cancellable: AnyCancellable?
        cancellable = watcher.$changeToken
            .dropFirst()
            .prefix(1)
            .sink { _ in
                expectation.fulfill()
                _ = cancellable
            }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let fileURL = self.tempDir.appendingPathComponent("ridl.json")
            try? "{}".write(to: fileURL, atomically: true, encoding: .utf8)
        }

        waitForExpectations(timeout: 3)
        watcher.stopAll()
    }

    func testUnwatchStopsMonitoring() {
        let watcher = ProjectFileWatcher()
        watcher.watch(directoryURL: tempDir)
        watcher.unwatch(directoryURL: tempDir)

        let expectation = expectation(description: "Should not fire")
        expectation.isInverted = true

        var cancellable: AnyCancellable?
        cancellable = watcher.$changeToken
            .dropFirst()
            .prefix(1)
            .sink { _ in
                expectation.fulfill()
                _ = cancellable
            }

        let fileURL = tempDir.appendingPathComponent("test.txt")
        try? "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        waitForExpectations(timeout: 1)
    }

    func testDuplicateWatchIsIgnored() {
        let watcher = ProjectFileWatcher()
        watcher.watch(directoryURL: tempDir)
        watcher.watch(directoryURL: tempDir)

        let expectation = expectation(description: "Single change token update")

        var cancellable: AnyCancellable?
        cancellable = watcher.$changeToken
            .dropFirst()
            .prefix(1)
            .sink { _ in
                expectation.fulfill()
                _ = cancellable
            }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let fileURL = self.tempDir.appendingPathComponent("test.txt")
            try? "hello".write(to: fileURL, atomically: true, encoding: .utf8)
        }

        waitForExpectations(timeout: 3)
        watcher.stopAll()
    }
}
