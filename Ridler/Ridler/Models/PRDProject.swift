import Foundation

struct PRDProject: Codable, Identifiable, Equatable {
    var id: String { name ?? directoryURL?.lastPathComponent ?? UUID().uuidString }

    let name: String?
    let project: String?
    let description: String?
    var iterationDefinitions: [IterationDefinition]
    var milestones: [Milestone]?
    var loopState: LoopState
    var iterationCount: Int

    var pauseAfterStory: Bool
    var pauseAfterMilestone: Bool
    var audioNotificationsEnabled: Bool
    var maxIterations: Int
    var loopStartDate: Date?

    var directoryURL: URL?

    // v2 fields
    let version: String?
    let generatedBy: String?
    let branchName: String?
    let universalContext: UniversalContext?

    enum CodingKeys: String, CodingKey {
        case name, project, description
        case iterationDefinitions
        case milestones
        case version, generatedBy, branchName, universalContext
    }

    /// Default max iterations: remaining stories + 5, minimum 5
    var defaultMaxIterations: Int {
        let remaining = iterationDefinitions.filter { !$0.isFrozen }.count
        return max(remaining + 5, 5)
    }

    init(
        name: String? = nil,
        project: String? = nil,
        description: String? = nil,
        iterationDefinitions: [IterationDefinition] = [],
        milestones: [Milestone]? = nil,
        loopState: LoopState = .ready,
        iterationCount: Int = 0,
        pauseAfterStory: Bool = false,
        pauseAfterMilestone: Bool = false,
        audioNotificationsEnabled: Bool = true,
        maxIterations: Int = 0,
        loopStartDate: Date? = nil,
        directoryURL: URL? = nil,
        version: String? = nil,
        generatedBy: String? = nil,
        branchName: String? = nil,
        universalContext: UniversalContext? = nil
    ) {
        self.name = name
        self.project = project
        self.description = description
        self.iterationDefinitions = iterationDefinitions
        self.milestones = milestones
        self.loopState = loopState
        self.iterationCount = iterationCount
        self.pauseAfterStory = pauseAfterStory
        self.pauseAfterMilestone = pauseAfterMilestone
        self.audioNotificationsEnabled = audioNotificationsEnabled
        self.maxIterations = maxIterations
        self.loopStartDate = loopStartDate
        self.directoryURL = directoryURL
        self.version = version
        self.generatedBy = generatedBy
        self.branchName = branchName
        self.universalContext = universalContext
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        project = try container.decodeIfPresent(String.self, forKey: .project)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        iterationDefinitions = try container.decode([IterationDefinition].self, forKey: .iterationDefinitions)
        milestones = try container.decodeIfPresent([Milestone].self, forKey: .milestones)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        generatedBy = try container.decodeIfPresent(String.self, forKey: .generatedBy)
        branchName = try container.decodeIfPresent(String.self, forKey: .branchName)
        universalContext = try container.decodeIfPresent(UniversalContext.self, forKey: .universalContext)
        loopState = .ready
        iterationCount = 0
        pauseAfterStory = false
        pauseAfterMilestone = false
        audioNotificationsEnabled = true
        maxIterations = 0
        loopStartDate = nil
        directoryURL = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(project, forKey: .project)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(iterationDefinitions, forKey: .iterationDefinitions)
        try container.encodeIfPresent(milestones, forKey: .milestones)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encodeIfPresent(generatedBy, forKey: .generatedBy)
        try container.encodeIfPresent(branchName, forKey: .branchName)
        try container.encodeIfPresent(universalContext, forKey: .universalContext)
    }
}
