import Foundation
import SwiftUI

enum LoopState: String, CaseIterable {
    case ready
    case running
    case paused
    case stopped
    case complete
    case error

    var color: Color {
        switch self {
        case .ready: return .gray
        case .running: return .cyan
        case .paused: return .yellow
        case .stopped: return .gray
        case .complete: return .green
        case .error: return .red
        }
    }

    var label: String {
        switch self {
        case .ready: return "Ready"
        case .running: return "Running"
        case .paused: return "Paused"
        case .stopped: return "Stopped"
        case .complete: return "Complete"
        case .error: return "Error"
        }
    }

    var validTransitions: Set<LoopState> {
        switch self {
        case .ready: return [.running]
        case .running: return [.paused, .stopped, .complete, .error]
        case .paused: return [.running]
        case .stopped: return [.running]
        case .complete: return []
        case .error: return [.running]
        }
    }
}

@Observable
final class LoopStateMachine {
    private(set) var state: LoopState = .ready

    @discardableResult
    func transition(to newState: LoopState) -> Bool {
        guard state.validTransitions.contains(newState) else {
            return false
        }
        state = newState
        return true
    }

    func reset() {
        state = .ready
    }
}
