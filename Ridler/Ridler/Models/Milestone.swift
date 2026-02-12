import Foundation

struct Milestone: Codable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    let storyIDs: [String]
    let version: String?
    let theme: String?

    enum CodingKeys: String, CodingKey {
        case name = "id"
        case storyIDs = "definitionIds"
        case version
        case theme
    }

    init(
        name: String,
        storyIDs: [String],
        version: String? = nil,
        theme: String? = nil
    ) {
        self.name = name
        self.storyIDs = storyIDs
        self.version = version
        self.theme = theme
    }
}
