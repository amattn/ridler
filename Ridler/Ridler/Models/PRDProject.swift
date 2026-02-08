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
}

struct PRDProject: Codable, Equatable {
    var project: String
    var branchName: String?
    var description: String
    var userStories: [UserStory]
}
