import Foundation

enum SidebarSelection: Hashable {
    case file(PRDFileName)
    case promptTemplate(String) // template filename, e.g. "agent_instructions.liquid"
    case story(String) // story ID

    /// Whether this selection represents a file that should show the Claude terminal in the right pane.
    var isFileSelection: Bool {
        switch self {
        case .file, .promptTemplate: return true
        case .story: return false
        }
    }

    /// Display name for the selected file, if applicable.
    var fileDisplayName: String? {
        switch self {
        case .file(let f): return f.rawValue
        case .promptTemplate(let name): return name
        case .story: return nil
        }
    }
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
