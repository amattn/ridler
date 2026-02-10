import Foundation

enum SidebarSelection: Hashable {
    case file(PRDFileName)
    case story(String) // story ID
}

enum PRDFileName: String, CaseIterable, Hashable {
    case prdMd = "prd.md"
    case ridlMd = "ridl.md"
    case ridlJson = "ridl.json"

    var icon: String {
        switch self {
        case .prdMd: return "doc.text"
        case .ridlMd: return "doc.plaintext"
        case .ridlJson: return "doc.badge.gearshape"
        }
    }
}
