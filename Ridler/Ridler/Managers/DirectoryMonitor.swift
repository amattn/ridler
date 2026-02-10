import Foundation
import Combine
import os

final class DirectoryMonitor: ObservableObject {
    private static let logger = Logger(subsystem: "com.amattn.Ridler", category: "DirectoryMonitor")
    @Published private(set) var lastChangeDate: Date?

    private let directoryURL: URL
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "com.amattn.Ridler.DirectoryMonitor", qos: .utility)

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    deinit {
        stop()
    }

    func start() {
        guard source == nil else { return }

        fileDescriptor = open(directoryURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            Self.logger.error("Failed to open directory for monitoring: \(self.directoryURL.path)")
            return
        }
        Self.logger.debug("Started monitoring: \(self.directoryURL.path)")

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: queue
        )

        source.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.lastChangeDate = Date()
            }
        }

        source.setCancelHandler { [weak self] in
            guard let self, self.fileDescriptor >= 0 else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        }

        source.resume()
        self.source = source
    }

    func stop() {
        Self.logger.debug("Stopped monitoring: \(self.directoryURL.path)")
        source?.cancel()
        source = nil
    }
}
