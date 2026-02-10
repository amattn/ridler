## Codebase Patterns
- Xcode project is at `Ridler/Ridler.xcodeproj` with source files in `Ridler/Ridler/`
- Project uses SwiftUI lifecycle (`@main struct RidlerApp: App`)
- Bundle identifier: `com.amattn.Ridler`
- Deployment target: macOS 14.0, arm64 only
- Project groups: Models, Views, ViewModels, Managers, Protocols (all under `Ridler/Ridler/`)
- Build with: `cd Ridler && xcodebuild -project Ridler.xcodeproj -scheme Ridler -configuration Debug -arch arm64 build`
- Test with: `cd Ridler && xcodebuild -project Ridler.xcodeproj -scheme Ridler -configuration Debug -arch arm64 test`
- App sandbox is disabled (entitlements file sets `com.apple.security.app-sandbox` to false) — needed for subprocess spawning
- Test target: `RidlerTests` at `Ridler/RidlerTests/` — uses `@testable import Ridler`
- pbxproj ID conventions: A-prefix for app target, C-prefix for test target, D-prefix for test configs
- Models are in `Ridler/Ridler/Models/`: UserStory, LoopState, Milestone, PRDProject, RidlerError
- PRDProject runtime-only properties (loopState, iterationCount, directoryURL) are excluded from Codable
- UserStory.passes and .inProgress default to false when omitted from JSON

---

## 2026-02-09 - US-001
- **What was implemented:** Created Xcode project with SwiftUI app target for macOS
- **Files changed:**
  - `Ridler/Ridler.xcodeproj/project.pbxproj` — Xcode project configuration
  - `Ridler/Ridler.xcodeproj/xcshareddata/xcschemes/Ridler.xcscheme` — Build scheme
  - `Ridler/Ridler/RidlerApp.swift` — SwiftUI app entry point
  - `Ridler/Ridler/ContentView.swift` — Empty window content view
  - `Ridler/Ridler/Ridler.entitlements` — App entitlements (sandbox disabled)
  - `Ridler/Ridler/Assets.xcassets/` — Asset catalog with AppIcon placeholder
  - `Ridler/Ridler/Preview Content/` — Preview assets
  - `Ridler/Ridler/Models/`, `Views/`, `ViewModels/`, `Managers/`, `Protocols/` — Empty group directories
- **Learnings for future iterations:**
  - Hand-crafted `project.pbxproj` works well — use short hex-like IDs (e.g., A10001) for readability
  - The pbxproj uses objectVersion 56 (Xcode 14+ compatible)
  - Empty directories for groups are included in the pbxproj as PBXGroup entries with empty children arrays
  - Build verification command: `xcodebuild -project Ridler.xcodeproj -scheme Ridler -configuration Debug -arch arm64 build`
---

## 2026-02-09 - US-002
- **What was implemented:** Core data models for the Ridler app — UserStory, LoopState, Milestone, PRDProject, and RidlerError
- **Files changed:**
  - `Ridler/Ridler/Models/UserStory.swift` — UserStory model with Codable, Identifiable, Equatable; resilient decoding (passes/inProgress default to false)
  - `Ridler/Ridler/Models/LoopState.swift` — LoopState enum (ready, running, paused, stopped, complete, error)
  - `Ridler/Ridler/Models/Milestone.swift` — Milestone model with name and storyIDs
  - `Ridler/Ridler/Models/PRDProject.swift` — PRDProject model with JSON-serialized fields and runtime-only state (loopState, iterationCount, directoryURL)
  - `Ridler/Ridler/Models/RidlerError.swift` — Error types conforming to LocalizedError with descriptive messages
  - `Ridler/Ridler.xcodeproj/project.pbxproj` — Added 5 model files to app target, added RidlerTests unit test target
  - `Ridler/Ridler.xcodeproj/xcshareddata/xcschemes/Ridler.xcscheme` — Added test target reference
  - `Ridler/RidlerTests/ModelTests.swift` — 22 unit tests covering round-trip encoding, default values, error descriptions
- **Learnings for future iterations:**
  - Adding a test target requires: PBXContainerItemProxy, PBXTargetDependency, separate PBXSourcesBuildPhase, separate PBXFrameworksBuildPhase, separate build configs with BUNDLE_LOADER and TEST_HOST
  - Test target build settings need `TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Ridler.app/Contents/MacOS/Ridler"` and `BUNDLE_LOADER = "$(TEST_HOST)"`
  - Use `@testable import Ridler` in test files to access internal types
  - PRDProject's runtime properties (loopState, iterationCount, directoryURL) are excluded from CodingKeys and initialized to defaults in init(from:)
  - All 22 tests pass in ~0.02 seconds
---
