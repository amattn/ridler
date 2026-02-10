import Foundation
import Combine

final class ProjectFileWatcher: ObservableObject {
    @Published private(set) var changeToken = UUID()

    private var monitors: [URL: DirectoryMonitor] = [:]
    private var cancellables: [URL: AnyCancellable] = [:]

    deinit {
        stopAll()
    }

    func watch(directoryURL: URL) {
        let standardized = directoryURL.standardizedFileURL
        guard monitors[standardized] == nil else { return }

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
        monitors[standardized]?.stop()
        monitors.removeValue(forKey: standardized)
        cancellables.removeValue(forKey: standardized)
    }

    func stopAll() {
        for monitor in monitors.values {
            monitor.stop()
        }
        monitors.removeAll()
        cancellables.removeAll()
    }
}
