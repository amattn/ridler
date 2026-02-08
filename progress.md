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
---
