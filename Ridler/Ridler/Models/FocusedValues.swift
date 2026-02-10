import SwiftUI

struct FocusedProjectKey: FocusedValueKey {
    typealias Value = PRDProject
}

struct FocusedHasProjectKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var selectedProject: PRDProject? {
        get { self[FocusedProjectKey.self] }
        set { self[FocusedProjectKey.self] = newValue }
    }

    var hasProject: Bool? {
        get { self[FocusedHasProjectKey.self] }
        set { self[FocusedHasProjectKey.self] = newValue }
    }
}
