import Foundation
import SwiftUI

/// Tracks which phase the engine is currently executing for an iteration definition.
enum IterationPhase: String {
    case implementation
    case verification
}

/// Harness signals emitted by the agent to communicate completion state.
enum HarnessSignal: Equatable {
    case complete              // <ridler-complete/>
    case verificationFailed    // <ridler-verification-failed/>
    case blocked               // <ridler-blocked/>
}

enum LoopState: String, Codable, Equatable {
    case ready
    case running
    case paused
    case stopped
    case complete
    case error

    /// Returns the set of states this state can transition to.
    var validTransitions: Set<LoopState> {
        switch self {
        case .ready:
            return [.running]
        case .running:
            return [.paused, .stopped, .complete, .error]
        case .paused:
            return [.running]
        case .stopped:
            return [.running]
        case .complete:
            return [.ready]
        case .error:
            return [.running]
        }
    }

    /// Whether a transition to the given state is valid.
    func canTransition(to newState: LoopState) -> Bool {
        validTransitions.contains(newState)
    }

    /// Attempts a transition to the given state. Returns the new state on success, or nil if the transition is invalid.
    func transition(to newState: LoopState) -> LoopState? {
        guard canTransition(to: newState) else { return nil }
        return newState
    }

    /// Color used for the state badge in the UI.
    var badgeColor: Color {
        switch self {
        case .ready:
            return .gray
        case .running:
            return .cyan
        case .paused:
            return .yellow
        case .stopped:
            return .gray
        case .complete:
            return .green
        case .error:
            return .red
        }
    }

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .ready:
            return "Ready"
        case .running:
            return "Running"
        case .paused:
            return "Paused"
        case .stopped:
            return "Stopped"
        case .complete:
            return "Complete"
        case .error:
            return "Error"
        }
    }
}
