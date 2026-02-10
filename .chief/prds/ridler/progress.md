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
- File watching: `DirectoryMonitor` uses `DispatchSource.makeFileSystemObjectSource` with `.write` event mask; `ProjectFileWatcher` aggregates monitors and debounces changes via Combine
- DispatchSource `.write` events can fire multiple times per file operation — always debounce or use `.prefix(1)` in tests
- Use `.id(changeToken)` on SwiftUI views to force re-creation when file content changes externally (ensures disk reads are refreshed)
- DecodingError mapping: use `mapDecodingError()` pattern to convert Swift DecodingError into RidlerError.jsonDecoding with file, key, jsonPath
- Views are in `Ridler/Ridler/Views/`: SidebarView, DetailView, LogPanelView, EmptyStateView, NewPRDSheet
- ContentView conditionally shows EmptyStateView (no PRDs open) or tab bar + NavigationSplitView (PRDs open)
- ContentView uses `openProjects: [PRDProject]` array + `selectedProjectID: String?` for multi-PRD tab support
- Menu commands (Cmd+O, Cmd+N) use NotificationCenter (.openPRD, .newPRD) to communicate from RidlerApp to ContentView
- Duplicate project detection uses `.standardizedFileURL` for reliable URL comparison
- pbxproj IDs for views: A10012-A10016 (build files), A20014-A20018 (file refs)
- Use `import UniformTypeIdentifiers` when using `.fileImporter` with `UTType` content types
- SidebarView accepts `project: PRDProject?` and `selection: Binding<SidebarSelection?>` for file/story selection
- SidebarSelection enum (in Models/SidebarSelection.swift): `.file(PRDFileName)` or `.story(String)` — mutual exclusion between file and story selections
- PRDFileName enum has `.allCases` for iterating prd.md, ridl.md, ridl.json with icons
- ContentView owns `@State sidebarSelection: SidebarSelection?` and passes binding to SidebarView

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

## 2026-02-09 - US-006
- **What was implemented:** Empty state view shown on first launch when no PRDs are loaded, with "Open PRD..." and "New PRD..." buttons that trigger File > Open and File > New flows
- **Files changed:**
  - `Ridler/Ridler/Views/EmptyStateView.swift` — New view with welcome message, icon, and two action buttons (Open PRD, New PRD)
  - `Ridler/Ridler/Views/NewPRDSheet.swift` — New sheet for creating a PRD: name input with validation, directory picker, creates ridl/ folder with empty prd.md
  - `Ridler/Ridler/ContentView.swift` — Conditionally shows EmptyStateView (when no PRD loaded) or NavigationSplitView (when PRD loaded); added fileImporter for Open flow and sheet for New flow; imports UniformTypeIdentifiers
  - `Ridler/Ridler.xcodeproj/project.pbxproj` — Added EmptyStateView.swift (A10015/A20017) and NewPRDSheet.swift (A10016/A20018) to app target
- **Learnings for future iterations:**
  - `fileImporter(allowedContentTypes:)` requires `import UniformTypeIdentifiers` for UTType references
  - PRD name validation uses Swift Regex: `/^[a-zA-Z0-9\-_]+$/`
  - NewPRDSheet creates the directory structure and empty prd.md, then returns a PRDProject to the caller
  - ContentView uses `@State private var currentProject: PRDProject?` to toggle between empty state and three-pane layout
  - All 43 tests still pass (pure UI story — no new tests needed)
---

## 2026-02-09 - US-007
- **What was implemented:** File > Open flow with multi-PRD tab support, error alerts for invalid files, and Cmd+O/Cmd+N keyboard shortcuts via menu bar
- **Files changed:**
  - `Ridler/Ridler/ContentView.swift` — Changed from single `currentProject` to `openProjects` array + `selectedProjectID` for multi-PRD support; added tab bar showing open PRDs with close buttons; added error alert for load failures; added `onReceive` for menu command notifications
  - `Ridler/Ridler/RidlerApp.swift` — Added `.commands()` modifier with File > Open PRD (Cmd+O) and New PRD (Cmd+N) menu items using NotificationCenter to trigger actions in ContentView
- **Learnings for future iterations:**
  - SwiftUI `.commands()` modifier on WindowGroup replaces default File menu items; use `CommandGroup(replacing: .newItem)` to customize
  - NotificationCenter is a clean pattern for App → View communication for menu commands: post from `.commands()`, receive with `.onReceive()` in ContentView
  - Duplicate project prevention: compare `directoryURL?.standardizedFileURL` to avoid opening the same PRD twice
  - `PRDProject.id` uses `name ?? directoryURL?.lastPathComponent ?? UUID().uuidString` — works well for tab identification
  - Tab close behavior: when closing the selected tab, auto-select the first remaining tab
  - All 43 tests still pass (pure UI story — no new tests needed)
---

## 2026-02-09 - US-008
- **What was implemented:** Verified that Create new PRD via File > New is fully implemented. All acceptance criteria were satisfied by prior work in US-006 (NewPRDSheet with name validation, directory picker, ridl/ folder creation with empty prd.md) and US-007 (Cmd+N keyboard shortcut, tab-based interface for opened PRDs).
- **Files changed:**
  - `.chief/prds/ridler/prd.json` — Marked US-008 as passes: true
- **Learnings for future iterations:**
  - Some user stories may already be fully implemented by earlier stories — always verify existing code before writing new code
  - The NewPRDSheet flow: Cmd+N → NotificationCenter → isNewPRDPresented → sheet → createPRD() → onCreate callback → addProject() → appears as tab
  - PRD name validation regex: `/^[a-zA-Z0-9\-_]+$/` in NewPRDSheet
  - All 43 tests still pass
---

## 2026-02-09 - US-009
- **What was implemented:** Enhanced PRD tab bar with state indicator icons and a [+] button with menu for Open/New PRD
- **Files changed:**
  - `Ridler/Ridler/ContentView.swift` — Added `stateIndicator(for:)` view builder that renders per-state icons (gray dot for ready, cyan play + iteration count for running, yellow pause for paused, gray stop for stopped, green checkmark for complete, red X for error); added Menu-based [+] button at end of tab bar with "Open PRD..." and "New PRD..." options
- **Learnings for future iterations:**
  - Tab bar state indicators use the project's `loopState` property — currently all projects start as `.ready` (gray dot)
  - Running state shows both a play icon and iteration count inline using HStack
  - SwiftUI `Menu` component works well for dropdown button — no popover/sheet needed
  - Close tab was already implemented in US-007; clicking a tab already switches view without affecting other loops
  - All 43 tests still pass (pure UI story — no new tests needed)
---

## 2026-02-09 - US-010
- **What was implemented:** PRD file browser in the left sidebar pane with collapsible "PRD Files" header, three file rows (prd.md, ridl.md, ridl.json), file-type icons, dimmed appearance for missing files, and mutual exclusion with story selection
- **Files changed:**
  - `Ridler/Ridler/Models/SidebarSelection.swift` — New enum for sidebar selection: `.file(PRDFileName)` or `.story(String)` with `PRDFileName` enum defining the three PRD files with icons
  - `Ridler/Ridler/Views/SidebarView.swift` — Replaced placeholder with full file browser: collapsible header, file rows with existence checks, selection highlighting, dimmed missing files with "(not yet created)" note
  - `Ridler/Ridler/ContentView.swift` — Added `sidebarSelection` state and passes project + selection binding to SidebarView
  - `Ridler/Ridler.xcodeproj/project.pbxproj` — Added SidebarSelection.swift (A10017/A20019) to app target and Models group
- **Learnings for future iterations:**
  - SidebarView now requires `project: PRDProject?` and `selection: Binding<SidebarSelection?>` — update callers when modifying
  - PRDFileName.allCases iterates in declaration order: prdMd, ridlMd, ridlJson
  - File existence checked via `FileManager.default.fileExists(atPath:)` using `project.directoryURL` + filename
  - pbxproj IDs: A10017 (build file), A20019 (file ref) for SidebarSelection.swift
  - All 43 tests still pass (pure UI story — no new tests needed)
---

## 2026-02-09 - US-011
- **What was implemented:** Stories list in left pane with scrollable story rows, status icons, selection highlighting, progress bar, and milestone grouping support
- **Files changed:**
  - `Ridler/Ridler/Views/SidebarView.swift` — Replaced placeholder "Stories" section with full implementation: `storiesSection()` renders either flat list or milestone-grouped list; `storyRow()` shows status icon + story ID + title with selection highlight; `milestoneGroup()` renders collapsible headers with pass count summary; `progressBar()` shows filled bar with percentage and count; `storyStatusIcon()` renders checkmark (passed), filled dot (in-progress), or circle (pending)
- **Learnings for future iterations:**
  - Story status icons: `checkmark.circle.fill` (green, passed), `circle.inset.filled` (cyan, in-progress), `circle` (secondary, pending)
  - Milestone grouping uses `@State collapsedMilestones: Set<String>` to track collapsed state
  - Ungrouped stories (not in any milestone) are shown after all milestone groups
  - Progress bar uses GeometryReader to calculate filled width as fraction of total width
  - Selection is mutual exclusion between file and story via shared `SidebarSelection?` binding
  - All 43 tests still pass (pure UI story — no new tests needed)
---

## 2026-02-09 - US-012
- **What was implemented:** Story detail panel in the middle pane showing full story details when a story is selected from the sidebar
- **Files changed:**
  - `Ridler/Ridler/Views/DetailView.swift` — Replaced placeholder with full story detail view: title in bold, status badge (Passed/In Progress/Pending with color-coded icons), priority badge, description with word wrapping, acceptance criteria as bulleted list, error section with claude.log tip when project is in error state
  - `Ridler/Ridler/ContentView.swift` — Updated to pass `project` and `sidebarSelection` to DetailView
  - `.chief/prds/ridler/prd.json` — Marked US-012 as passes: true
- **Learnings for future iterations:**
  - DetailView now accepts `project: PRDProject?` and `selection: SidebarSelection?` — must update callers when changing signature
  - Status badge pattern: icon + text in an HStack with colored background using `statusColor.opacity(0.1)` for subtle badge effect
  - `.fixedSize(horizontal: false, vertical: true)` ensures text wraps properly in VStack layouts within ScrollView
  - The `.file` case in SidebarSelection falls through to placeholder — US-013 will handle file content display
  - All 43 tests still pass (pure UI story — no new tests needed)
---

## 2026-02-09 - US-013
- **What was implemented:** File content view in the middle pane that displays PRD file contents when a file row is selected in the sidebar
- **Files changed:**
  - `Ridler/Ridler/Views/DetailView.swift` — Replaced `.file` placeholder with full file content view: header with icon and filename, markdown rendering for .md files using `AttributedString(markdown:)`, pretty-printed JSON for .json files using `JSONSerialization`, empty state for non-existent files, read-only text selection enabled
  - `.chief/prds/ridler/prd.json` — Marked US-013 as passes: true
- **Learnings for future iterations:**
  - `AttributedString(markdown:, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))` renders inline markdown (bold, italic, code, links) while preserving whitespace — good for basic markdown rendering in SwiftUI Text
  - For JSON pretty-printing, use `JSONSerialization.jsonObject` → `JSONSerialization.data(withJSONObject:options:.prettyPrinted)` round-trip — this handles any valid JSON and reformats it cleanly
  - Fallback pattern: try AttributedString markdown → fall back to plain monospaced text → fall back to "File is empty" — ensures no crash on any content
  - `.textSelection(.enabled)` makes read-only text copyable by the user
  - All 43 tests still pass (pure UI story — no new tests needed)
---

## 2026-02-09 - US-014
- **What was implemented:** File watcher for external PRD changes using DispatchSource, with auto-reload of project data and UI refresh
- **Files changed:**
  - `Ridler/Ridler/Managers/DirectoryMonitor.swift` — New class that watches a single directory using `DispatchSource.makeFileSystemObjectSource` with `.write` event mask; publishes `lastChangeDate` via `@Published` on main thread
  - `Ridler/Ridler/Managers/ProjectFileWatcher.swift` — New `ObservableObject` that manages multiple `DirectoryMonitor` instances; debounces changes with 300ms delay; publishes `changeToken` (UUID) for view identity invalidation
  - `Ridler/Ridler/ContentView.swift` — Added `@StateObject fileWatcher`; starts/stops watching in `addProject`/`closeProject`; `reloadAllProjects()` reloads PRD data from disk on change; `.id(fileWatcher.changeToken)` on SidebarView and DetailView forces re-render
  - `Ridler/RidlerTests/FileWatcherTests.swift` — 7 unit tests: file creation detection, file modification detection, stop prevents notifications, main thread delivery, change token updates, unwatch stops monitoring, duplicate watch ignored
  - `Ridler/Ridler.xcodeproj/project.pbxproj` — Added DirectoryMonitor.swift (A10018/A20020), ProjectFileWatcher.swift (A10019/A20021), FileWatcherTests.swift (C10003/C20004)
- **Learnings for future iterations:**
  - `DispatchSource.makeFileSystemObjectSource` with `.write` event mask detects file changes within a directory — works well for monitoring PRD directories
  - DispatchSource `.write` events can fire multiple times for a single file operation (e.g., atomic writes create temp file then rename) — use `.debounce()` for production code and `.prefix(1)` for tests
  - Dictionary literal `[:]` not `[]` for empty dictionaries in Swift — compiler error otherwise
  - Using `.id(changeToken)` on SwiftUI views forces complete view re-creation when files change — ensures disk reads are refreshed for file content display
  - `reloadAllProjects()` preserves runtime state (loopState, iterationCount) while refreshing disk-based state (user stories, milestones) — important for not disrupting running loops
  - All 50 tests pass (43 existing + 7 new)
---

## 2026-02-09 - US-015
- **What was implemented:** Error alerts with descriptive messages and a Copy button to copy error text to clipboard
- **Files changed:**
  - `Ridler/Ridler/ContentView.swift` — Changed error alert title from "Error Opening PRD" to generic "Error"; added "Copy" button that copies the full error message to `NSPasteboard.general` (clipboard)
  - `.chief/prds/ridler/prd.json` — Marked US-015 as passes: true
- **Learnings for future iterations:**
  - Most of US-015's acceptance criteria were already satisfied by prior stories (US-002 for LocalizedError conformance, US-003 for JSON/file error details)
  - `NSPasteboard.general` is available in macOS SwiftUI without additional imports — `clearContents()` then `setString(_:forType: .string)` to copy text
  - SwiftUI `.alert` supports multiple buttons — non-cancel buttons appear before the cancel button
  - The `reloadAllProjects()` method intentionally silences transient errors during file watching — this is correct behavior for mid-write filesystem events
  - All 50 tests pass (no new tests needed — the error infrastructure was already well-tested)
---
