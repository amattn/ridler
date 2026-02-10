import Foundation

struct UserStory: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let priority: Int
    let acceptanceCriteria: [String]
    var passes: Bool
    var inProgress: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, description, priority, acceptanceCriteria, passes, inProgress
    }

    init(
        id: String,
        title: String,
        description: String,
        priority: Int,
        acceptanceCriteria: [String],
        passes: Bool = false,
        inProgress: Bool = false
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.priority = priority
        self.acceptanceCriteria = acceptanceCriteria
        self.passes = passes
        self.inProgress = inProgress
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        priority = try container.decode(Int.self, forKey: .priority)
        acceptanceCriteria = try container.decode([String].self, forKey: .acceptanceCriteria)
        passes = try container.decodeIfPresent(Bool.self, forKey: .passes) ?? false
        inProgress = try container.decodeIfPresent(Bool.self, forKey: .inProgress) ?? false
    }
}
