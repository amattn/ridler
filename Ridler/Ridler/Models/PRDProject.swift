import Foundation

struct UserStory: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var description: String
    var acceptanceCriteria: [String]
    var priority: Int
    var passes: Bool
    var inProgress: Bool
    var lastPrompt: String?
    var notes: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        acceptanceCriteria = try container.decode([String].self, forKey: .acceptanceCriteria)
        priority = try container.decode(Int.self, forKey: .priority)
        passes = try container.decodeIfPresent(Bool.self, forKey: .passes) ?? false
        inProgress = try container.decodeIfPresent(Bool.self, forKey: .inProgress) ?? false
        lastPrompt = try container.decodeIfPresent(String.self, forKey: .lastPrompt)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }

    init(id: String, title: String, description: String, acceptanceCriteria: [String],
         priority: Int, passes: Bool = false, inProgress: Bool = false,
         lastPrompt: String? = nil, notes: String? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.acceptanceCriteria = acceptanceCriteria
        self.priority = priority
        self.passes = passes
        self.inProgress = inProgress
        self.lastPrompt = lastPrompt
        self.notes = notes
    }
}

struct PRDProject: Codable, Equatable {
    var project: String
    var branchName: String?
    var description: String
    var userStories: [UserStory]
}
