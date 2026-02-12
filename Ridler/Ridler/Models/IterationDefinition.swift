import Foundation

struct IterationDefinition: Codable, Identifiable, Equatable {
    let id: String
    let userStoryTitle: String
    let userStoryDescription: String
    let priority: Int
    let acceptanceCriteria: [String]
    var passes: Bool
    var inProgress: Bool
    let prdReferences: [String]?
    let milestone: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userStoryTitle
        case userStoryDescription
        case priority
        case acceptanceCriteria
        case passes
        case prdReferences
        case milestone
        case notes
    }

    init(
        id: String,
        userStoryTitle: String,
        userStoryDescription: String,
        priority: Int,
        acceptanceCriteria: [String],
        passes: Bool = false,
        inProgress: Bool = false,
        prdReferences: [String]? = nil,
        milestone: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.userStoryTitle = userStoryTitle
        self.userStoryDescription = userStoryDescription
        self.priority = priority
        self.acceptanceCriteria = acceptanceCriteria
        self.passes = passes
        self.inProgress = inProgress
        self.prdReferences = prdReferences
        self.milestone = milestone
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userStoryTitle = try container.decode(String.self, forKey: .userStoryTitle)
        userStoryDescription = try container.decode(String.self, forKey: .userStoryDescription)
        priority = try container.decode(Int.self, forKey: .priority)
        acceptanceCriteria = try container.decode([String].self, forKey: .acceptanceCriteria)
        passes = try container.decodeIfPresent(Bool.self, forKey: .passes) ?? false
        inProgress = false
        prdReferences = try container.decodeIfPresent([String].self, forKey: .prdReferences)
        milestone = try container.decodeIfPresent(String.self, forKey: .milestone)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
}
