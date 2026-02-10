import Foundation

struct Milestone: Codable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    let storyIDs: [String]

    enum CodingKeys: String, CodingKey {
        case name, storyIDs
    }
}
