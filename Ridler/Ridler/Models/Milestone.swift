import Foundation

struct Milestone: Codable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    let definitionIds: [String]
    var version: String? = nil
    var theme: String? = nil
}
