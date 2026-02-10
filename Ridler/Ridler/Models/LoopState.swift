import Foundation

enum LoopState: String, Codable, Equatable {
    case ready
    case running
    case paused
    case stopped
    case complete
    case error
}
