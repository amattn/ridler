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
    let prdReferences: [String]?
    let milestone: String?
    let notes: String?

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

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case priority
        case acceptanceCriteria
        case prdReferences
        case milestone
        case notes
        // Legacy v2 keys (decode-only)
        case userStoryTitle
        case userStoryDescription
        case passes
    }

    init(
        id: String,
        title: String,
        description: String,
        priority: Int,
        acceptanceCriteria: [AcceptanceCriterion],
        prdReferences: [String]? = nil,
        milestone: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.priority = priority
        self.acceptanceCriteria = acceptanceCriteria
        self.prdReferences = prdReferences
        self.milestone = milestone
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)

        // v3 keys first, fall back to v2 legacy keys
        if let t = try container.decodeIfPresent(String.self, forKey: .title) {
            title = t
        } else {
            title = try container.decode(String.self, forKey: .userStoryTitle)
        }

        if let d = try container.decodeIfPresent(String.self, forKey: .description) {
            description = d
        } else {
            description = try container.decode(String.self, forKey: .userStoryDescription)
        }

        priority = try container.decode(Int.self, forKey: .priority)

        // Try v3 structured format first, fall back to v2 flat string array
        if let structured = try? container.decode([AcceptanceCriterion].self, forKey: .acceptanceCriteria) {
            acceptanceCriteria = structured
        } else {
            let flat = try container.decode([String].self, forKey: .acceptanceCriteria)
            let legacyPasses = try container.decodeIfPresent(Bool.self, forKey: .passes) ?? false
            let defaultStatus: AcceptanceCriterion.CriterionStatus = legacyPasses ? .pass : .notStarted
            acceptanceCriteria = flat.map { AcceptanceCriterion(criterion: $0, status: defaultStatus) }
        }

        prdReferences = try container.decodeIfPresent([String].self, forKey: .prdReferences)
        milestone = try container.decodeIfPresent(String.self, forKey: .milestone)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(priority, forKey: .priority)
        try container.encode(acceptanceCriteria, forKey: .acceptanceCriteria)
        try container.encodeIfPresent(prdReferences, forKey: .prdReferences)
        try container.encodeIfPresent(milestone, forKey: .milestone)
        try container.encodeIfPresent(notes, forKey: .notes)
        // Never encode legacy keys (passes, userStoryTitle, userStoryDescription)
    }
}
