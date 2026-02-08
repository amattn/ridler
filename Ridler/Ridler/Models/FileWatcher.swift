import Foundation

// MARK: - FileChangeEvent

struct FileChangeEvent: Equatable, Sendable {
    let path: String
    let directory: String
    let timestamp: Date

    init(path: String, directory: String, timestamp: Date = Date()) {
        self.path = path
        self.directory = directory
        self.timestamp = timestamp
    }
}

// MARK: - FileWatcherDelegate

protocol FileWatcherDelegate: AnyObject {
    func fileWatcher(_ watcher: FileWatcher, didDetectChangesIn event: FileChangeEvent)
}

// MARK: - Path Resolution

private func resolvedPath(_ path: String) -> String {
    var resolved = [CChar](repeating: 0, count: Int(PATH_MAX))
    guard realpath(path, &resolved) != nil else {
        return (path as NSString).standardizingPath
    }
    return String(cString: resolved)
}

// MARK: - FileWatcher

@Observable
final class FileWatcher {
    fileprivate var streams: [String: FSEventStreamRef] = [:]
    fileprivate let lock = NSLock()
    private let debounceInterval: TimeInterval
    private var pendingEvents: [String: DispatchWorkItem] = [:]
    fileprivate let callbackQueue = DispatchQueue(label: "com.amattn.ridler.filewatcher", qos: .utility)

    weak var delegate: FileWatcherDelegate?

    private(set) var watchedDirectories: [String] = []

    init(debounceInterval: TimeInterval = 0.5) {
        self.debounceInterval = debounceInterval
    }

    deinit {
        stopAll()
    }

    // MARK: - Public API

    func watch(directory: String) {
        // Resolve symlinks so FSEvents paths match our stored directory keys
        let resolvedDir = resolvedPath(directory)

        lock.lock()
        defer { lock.unlock() }

        guard streams[resolvedDir] == nil else { return }

        let context = Unmanaged.passUnretained(self)
        var fsContext = FSEventStreamContext(
            version: 0,
            info: context.toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let paths = [resolvedDir] as CFArray
        guard let stream = FSEventStreamCreate(
            nil,
            fsEventCallback,
            &fsContext,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            debounceInterval / 2,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(stream, callbackQueue)
        FSEventStreamStart(stream)

        streams[resolvedDir] = stream
        watchedDirectories = Array(streams.keys).sorted()
    }

    func stopWatching(directory: String) {
        let resolvedDir = resolvedPath(directory)

        lock.lock()
        defer { lock.unlock() }

        guard let stream = streams.removeValue(forKey: resolvedDir) else { return }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)

        pendingEvents[resolvedDir]?.cancel()
        pendingEvents.removeValue(forKey: resolvedDir)

        watchedDirectories = Array(streams.keys).sorted()
    }

    func stopAll() {
        lock.lock()
        let allDirs = Array(streams.keys)
        lock.unlock()

        for dir in allDirs {
            stopWatching(directory: dir)
        }
    }

    var isWatching: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !streams.isEmpty
    }

    func isWatching(directory: String) -> Bool {
        let resolvedDir = resolvedPath(directory)
        lock.lock()
        defer { lock.unlock() }
        return streams[resolvedDir] != nil
    }

    // MARK: - Internal callback

    fileprivate func handleFSEvents(paths: [String]) {
        lock.lock()

        let watchedDirs = Array(streams.keys)

        // Group events by their watched directory
        var eventsByDir: [String: [String]] = [:]
        for path in paths {
            for dir in watchedDirs {
                if path.hasPrefix(dir) {
                    eventsByDir[dir, default: []].append(path)
                    break
                }
            }
        }

        for (dir, dirPaths) in eventsByDir {
            // Cancel any pending debounced event for this directory
            pendingEvents[dir]?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let eventPath = dirPaths.first ?? dir
                let event = FileChangeEvent(path: eventPath, directory: dir)
                self.delegate?.fileWatcher(self, didDetectChangesIn: event)
            }

            pendingEvents[dir] = workItem
            callbackQueue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
        }

        lock.unlock()
    }
}

// MARK: - FSEvents C Callback

private func fsEventCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientCallBackInfo else { return }

    let watcher = Unmanaged<FileWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()

    guard let cfPaths = unsafeBitCast(eventPaths, to: CFArray.self) as? [String] else {
        return
    }

    watcher.handleFSEvents(paths: cfPaths)
}
