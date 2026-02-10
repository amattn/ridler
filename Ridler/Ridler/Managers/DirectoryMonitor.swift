import Foundation
import Combine

final class DirectoryMonitor: ObservableObject {
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
        guard fileDescriptor >= 0 else { return }

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
        source?.cancel()
        source = nil
    }
}
