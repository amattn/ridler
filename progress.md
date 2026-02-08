## Codebase Patterns
- Xcode project lives at `Ridler/Ridler.xcodeproj`, Swift sources at `Ridler/Ridler/`
- Build command: `cd Ridler && xcodebuild -project Ridler.xcodeproj -scheme Ridler -configuration Debug -arch arm64 build`
- Bundle identifier: `com.amattn.ridler`
- Target: macOS 14.0+, Apple Silicon (arm64) only
- SwiftUI App lifecycle with `@main` entry point in `RidlerApp.swift`

---

## 2026-02-08 - US-001
- What was implemented: Created Xcode project with SwiftUI App lifecycle, empty window displaying "Ridler" title
- Files changed:
  - `Ridler/Ridler.xcodeproj/project.pbxproj` (new - Xcode project file)
  - `Ridler/Ridler/RidlerApp.swift` (new - app entry point with WindowGroup)
  - `Ridler/Ridler/ContentView.swift` (new - empty window with NavigationStack and title)
  - `.gitignore` (updated - added Xcode/macOS ignores)
- **Learnings for future iterations:**
  - Hand-crafted `project.pbxproj` works fine for simple projects - use unique hex IDs for all objects
  - `.navigationTitle()` requires `NavigationStack` wrapper on macOS to display in the title bar
  - The `ARCHS = arm64` build setting restricts to Apple Silicon only
  - `MACOSX_DEPLOYMENT_TARGET = 14.0` sets the minimum macOS version
  - Build with `xcodebuild` and check for warnings/errors using grep on output
  - Test target `RidlerTests` is set up as a hosted unit test (`BUNDLE_LOADER`/`TEST_HOST` pointing to Ridler.app)
  - Run tests with: `cd Ridler && xcodebuild -project Ridler.xcodeproj -scheme Ridler -destination 'platform=macOS,arch=arm64' test`
  - New source files need: PBXFileReference, PBXBuildFile, added to PBXSourcesBuildPhase and PBXGroup in project.pbxproj
  - Models directory is at `Ridler/Ridler/Models/`
---

## 2026-02-08 - US-002
- What was implemented: PRDProject and UserStory Codable data models, PRDFileManager for JSON load/save and companion file resolution, RidlerTests unit test target with 14 tests
- Files changed:
  - `Ridler/Ridler/Models/PRDProject.swift` (new - UserStory and PRDProject Codable structs)
  - `Ridler/Ridler/Models/PRDFileManager.swift` (new - load/save/companion file logic)
  - `Ridler/RidlerTests/PRDModelsTests.swift` (new - 14 unit tests for decoding, encoding, round-trip, file operations)
  - `Ridler/Ridler.xcodeproj/project.pbxproj` (updated - added new source files, Models group, RidlerTests target)
- **Learnings for future iterations:**
  - Test target uses `BUNDLE_LOADER` and `TEST_HOST` to run as hosted tests inside Ridler.app
  - Use `@testable import Ridler` to access internal types from tests
  - PBXContainerItemProxy + PBXTargetDependency are needed to link test target to app target
  - The `-scheme RidlerTests` doesn't work directly — use `-scheme Ridler` with `test` action instead
  - Optional Codable fields (like `lastPrompt`, `notes`, `branchName`) decode as nil when absent from JSON
  - PRDFileManager.loadFromCompanion tries ridl.json first, then prd.json when given a non-JSON file path
---
