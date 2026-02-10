## Codebase Patterns
- Xcode project is at `Ridler/Ridler.xcodeproj` with source files in `Ridler/Ridler/`
- Project uses SwiftUI lifecycle (`@main struct RidlerApp: App`)
- Bundle identifier: `com.amattn.Ridler`
- Deployment target: macOS 14.0, arm64 only
- Project groups: Models, Views, ViewModels, Managers, Protocols (all under `Ridler/Ridler/`)
- Build with: `cd Ridler && xcodebuild -project Ridler.xcodeproj -scheme Ridler -configuration Debug -arch arm64 build`
- App sandbox is disabled (entitlements file sets `com.apple.security.app-sandbox` to false) — needed for subprocess spawning

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
