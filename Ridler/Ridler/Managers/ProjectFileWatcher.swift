import Foundation
import Combine
import os

final class ProjectFileWatcher: ObservableObject {
    private static let logger = Logger(subsystem: "com.amattn.Ridler", category: "FileWatcher")
    @Published private(set) var changeToken = UUID()

    var watchedCount: Int { monitors.count }

    private var monitors: [URL: DirectoryMonitor] = [:]
    private var cancellables: [URL: AnyCancellable] = [:]

    deinit {
        stopAll()
    }

    func watch(directoryURL: URL) {
        let standardized = directoryURL.standardizedFileURL
        guard monitors[standardized] == nil else { return }

        Self.logger.info("Watching directory: \(standardized.path)")
        let monitor = DirectoryMonitor(directoryURL: standardized)
        monitors[standardized] = monitor

        let cancellable = monitor.$lastChangeDate
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.changeToken = UUID()
            }
        cancellables[standardized] = cancellable

        monitor.start()
    }

    func unwatch(directoryURL: URL) {
        let standardized = directoryURL.standardizedFileURL
        Self.logger.info("Unwatching directory: \(standardized.path)")
        monitors[standardized]?.stop()
        monitors.removeValue(forKey: standardized)
        cancellables.removeValue(forKey: standardized)
    }

    func stopAll() {
        Self.logger.info("Stopping all file watchers (\(self.monitors.count) active)")
        for monitor in monitors.values {
            monitor.stop()
        }
        monitors.removeAll()
        cancellables.removeAll()
    }
}
