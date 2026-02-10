import Foundation

struct PRDProject: Codable, Identifiable, Equatable {
    var id: String { name ?? directoryURL?.lastPathComponent ?? UUID().uuidString }

    let name: String?
    let project: String?
    let description: String?
    var userStories: [UserStory]
    var milestones: [Milestone]?
    var loopState: LoopState
    var iterationCount: Int

    var pauseAfterStory: Bool
    var autoRetryEnabled: Bool
    var maxIterations: Int
    var loopStartDate: Date?

    var directoryURL: URL?

    enum CodingKeys: String, CodingKey {
        case name, project, description, userStories, milestones
    }

    /// Default max iterations: remaining stories + 5, minimum 5
    var defaultMaxIterations: Int {
        let remaining = userStories.filter { !$0.passes }.count
        return max(remaining + 5, 5)
    }

    init(
        name: String? = nil,
        project: String? = nil,
        description: String? = nil,
        userStories: [UserStory] = [],
        milestones: [Milestone]? = nil,
        loopState: LoopState = .ready,
        iterationCount: Int = 0,
        pauseAfterStory: Bool = false,
        autoRetryEnabled: Bool = false,
        maxIterations: Int = 0,
        loopStartDate: Date? = nil,
        directoryURL: URL? = nil
    ) {
        self.name = name
        self.project = project
        self.description = description
        self.userStories = userStories
        self.milestones = milestones
        self.loopState = loopState
        self.iterationCount = iterationCount
        self.pauseAfterStory = pauseAfterStory
        self.autoRetryEnabled = autoRetryEnabled
        self.maxIterations = maxIterations
        self.loopStartDate = loopStartDate
        self.directoryURL = directoryURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        project = try container.decodeIfPresent(String.self, forKey: .project)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        userStories = try container.decode([UserStory].self, forKey: .userStories)
        milestones = try container.decodeIfPresent([Milestone].self, forKey: .milestones)
        loopState = .ready
        iterationCount = 0
        pauseAfterStory = false
        autoRetryEnabled = false
        maxIterations = 0
        loopStartDate = nil
        directoryURL = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(project, forKey: .project)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(userStories, forKey: .userStories)
        try container.encodeIfPresent(milestones, forKey: .milestones)
    }
}
