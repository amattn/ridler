import Foundation

/// Per-criterion status tracking for the red/green testing workflow.
struct AcceptanceCriterion: Codable, Identifiable, Equatable {
    var id: String { criterion }
    let criterion: String
    var status: CriterionStatus

    enum CriterionStatus: String, Codable {
        case notStarted = "not_started"
        case fail
        case pass
        case error
    }
}

struct IterationDefinition: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let priority: Int
    var acceptanceCriteria: [AcceptanceCriterion]
    var prdReferences: [String]? = nil
    var milestone: String? = nil
    var notes: String? = nil

    /// True when all acceptance criteria have status `.pass`.
    var isFrozen: Bool {
        !acceptanceCriteria.isEmpty && acceptanceCriteria.allSatisfy { $0.status == .pass }
    }

    /// True when any criterion has status `.fail`.
    var hasFailingCriteria: Bool {
        acceptanceCriteria.contains { $0.status == .fail }
    }

    /// True when any criterion has status `.error`.
    var hasErrors: Bool {
        acceptanceCriteria.contains { $0.status == .error }
    }
}
