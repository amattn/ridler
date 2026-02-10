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
- PRDStore protocol in `Protocols/PRDStore.swift` defines read/write interface for PRD files
- FileSystemPRDStore in `Managers/FileSystemPRDStore.swift` implements disk I/O with ridl/ folder convention
- When resolving URLs: directories are used as-is, files resolve to their parent directory
- URL comparison gotcha: `deletingLastPathComponent()` adds trailing slash — use `.standardizedFileURL` for comparisons
- DecodingError mapping: use `mapDecodingError()` pattern to convert Swift DecodingError into RidlerError.jsonDecoding with file, key, jsonPath
- Views are in `Ridler/Ridler/Views/`: SidebarView, DetailView, LogPanelView
- ContentView uses `NavigationSplitView` with three columns (sidebar, content, detail) and `columnVisibility` state
- pbxproj IDs for views: A10012-A10014 (build files), A20014-A20016 (file refs)

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

## 2026-02-09 - US-003
- **What was implemented:** PRDStore protocol and FileSystemPRDStore for reading/writing PRD files from disk
- **Files changed:**
  - `Ridler/Ridler/Protocols/PRDStore.swift` — Protocol defining read/write interface: loadProject, loadMarkdown, loadMarkdownIfExists, writeProject
  - `Ridler/Ridler/Managers/FileSystemPRDStore.swift` — File-system implementation with ridl/ folder convention, directory resolution (file or folder URL), DecodingError → RidlerError mapping
  - `Ridler/RidlerTests/PRDStoreTests.swift` — 18 unit tests: valid JSON loading, missing optional fields, malformed JSON, missing required fields, missing files, nonexistent directories, file URL resolution, markdown loading/missing, optional markdown, round-trip write, pretty-printed output, field preservation, error message content
  - `Ridler/Ridler.xcodeproj/project.pbxproj` — Added PRDStore.swift, FileSystemPRDStore.swift to app target, PRDStoreTests.swift to test target
- **Learnings for future iterations:**
  - `URL.deletingLastPathComponent()` adds a trailing slash, causing `XCTAssertEqual` to fail — use `.standardizedFileURL` for URL comparisons in tests
  - pbxproj IDs continue pattern: A10010-A10011 for app build files, A20012-A20013 for file refs, C10002/C20003 for test files
  - FileSystemPRDStore uses `.atomic` writing for safety and `[.prettyPrinted, .sortedKeys]` for human-readable JSON
  - resolveDirectory() allows passing either a folder URL or a file URL (resolves to parent directory)
  - All 40 tests pass (22 existing + 18 new)
---

## 2026-02-09 - US-004
- **What was implemented:** Verified and tested PRD state update writing to ridl.json, including round-trip state modification and concurrent write safety
- **Files changed:**
  - `Ridler/RidlerTests/PRDStoreTests.swift` — Added 3 new tests: `testWriteProjectModifyPassesAndInProgress` (multi-step read→modify→write→read cycle), `testWriteProjectConcurrentSafety` (10 concurrent writes don't corrupt), `testWriteProjectMultipleStoryStateUpdates` (batch update multiple stories)
- **Learnings for future iterations:**
  - The writeProject implementation from US-003 already satisfied US-004's requirements — `.atomic` writing prevents file corruption during concurrent access
  - For concurrent tests, use `DispatchQueue` with `.concurrent` attribute and `XCTestExpectation` with `expectedFulfillmentCount`
  - After concurrent writes, always verify the file remains valid JSON by loading it back
  - All 43 tests pass (22 model + 21 PRDStore)
---

## 2026-02-09 - US-005
- **What was implemented:** Three-pane window layout using NavigationSplitView
- **Files changed:**
  - `Ridler/Ridler/ContentView.swift` — Replaced single Text view with NavigationSplitView using three columns (sidebar, content, detail) with columnVisibility state binding
  - `Ridler/Ridler/Views/SidebarView.swift` — Left pane placeholder with "PRD Files" and "Stories" sections, min width 200
  - `Ridler/Ridler/Views/DetailView.swift` — Middle pane placeholder for story detail / file content, min width 300
  - `Ridler/Ridler/Views/LogPanelView.swift` — Right pane placeholder for log view / Claude terminal, min width 250
  - `Ridler/Ridler.xcodeproj/project.pbxproj` — Added 3 view files to app target (A10012-A10014, A20014-A20016)
- **Learnings for future iterations:**
  - NavigationSplitView with three columns uses sidebar/content/detail pattern — sidebar auto-collapses on narrow windows
  - `NavigationSplitViewVisibility.all` as default ensures all three panes are visible on launch
  - `.frame(minWidth: 900, minHeight: 500)` on ContentView ensures reasonable minimum window size
  - All 43 tests still pass (no new tests needed — this is pure UI)
---
