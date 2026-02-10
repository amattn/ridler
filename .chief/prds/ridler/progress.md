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
- LoopState has `validTransitions`, `canTransition(to:)`, `transition(to:)`, `badgeColor`, `displayName` — use these instead of hardcoding colors or transitions
- PRDProject runtime-only properties now include: loopState, iterationCount, pauseAfterStory, maxIterations, loopStartDate, directoryURL — all must be preserved in `reloadAllProjects()`
- ProcessManaging protocol in `Protocols/ProcessManaging.swift` defines interface for spawning, streaming, and killing subprocesses
- ClaudeCodeProcessManager in `Managers/ClaudeCodeProcessManager.swift` spawns Claude Code with `--dangerously-skip-permissions --output-format stream-json` flags via `/usr/bin/env claude`
- Process stdout streamed line-by-line via Combine PassthroughSubject; stderr captured via Data buffer synchronized with DispatchQueue
- ProcessExitResult struct carries exitCode, stderr, and command for error reporting
- Log file created per-PRD at specified URL; raw stdout/stderr appended with session separator
- Process kill: `terminate()` first, then `interrupt()` after 2-second timeout for force kill
- pbxproj IDs: A10021/A20023 (ProcessManaging), A10022/A20024 (ClaudeCodeProcessManager), C10004/C20005 (ProcessManagerTests)
- StreamingJSONParser in `Managers/StreamingJSONParser.swift` parses Claude Code stream-json output line-by-line into LogEntry values; use `subscribe(to:)` to connect to ClaudeCodeProcessManager's stdout publisher
- LogEntry model in `Models/LogEntry.swift` with LogEntryType enum: .assistantText, .toolUse, .toolResult, .error, .system
- pbxproj IDs: A10023/A20025 (LogEntry), A10024/A20026 (StreamingJSONParser), C10005/C20006 (StreamingJSONParserTests)
- pbxproj IDs: A10025/A20027 (LogStore), C10006/C20007 (LogStoreTests)
- LogStore (ObservableObject) in `Managers/LogStore.swift` — stores `[LogEntry]` per project ID; used by ContentView as `@StateObject` and passed to LogPanelView
- LogPanelView accepts `entries: [LogEntry]` and `isRunning: Bool` — renders typed log entries with icons, auto-scroll via ScrollViewReader
- macOS 14.0 deployment target means `onScrollGeometryChange` is NOT available — use `onAppear`/`onDisappear` on a bottom sentinel view for scroll detection instead
- RalphLoopEngine in `Managers/RalphLoopEngine.swift` — use callbacks (onStateChange, onIterationChange, onLogEntry, onProjectUpdated) to communicate back to ContentView; one engine per project stored in `loopEngines: [String: RalphLoopEngine]`
- LoopToolbarView accepts onStart/onPause/onStop closures — delegates control to ContentView which manages engine lifecycle
- pbxproj IDs: A10026/A20028 (RalphLoopEngine), C10007/C20008 (RalphLoopEngineTests)
- GitManaging protocol in `Protocols/GitManaging.swift` defines interface for git operations (currentBranch, isProtectedBranch, createAndCheckoutBranch, commitAllChanges) — enables test mocking
- RalphLoopEngine accepts `gitManager: GitManaging` parameter for dependency injection; commits after each successful iteration with message format `feat: [US-XXX] - Story Title`
- Git commit failures in the loop are non-fatal — logged as warnings but don't stop the loop
- PRDProject runtime-only properties now include: autoRetryEnabled, audioNotificationsEnabled — must be preserved in `reloadAllProjects()` and `onProjectUpdated`
- SyntaxHighlighter in `Managers/SyntaxHighlighter.swift` — use `parseSegments()` to split content into text/code blocks, `highlight()` to apply NSAttributedString coloring; HighlightedCodeView (NSViewRepresentable) in LogPanelView for rendering
- pbxproj IDs: A10031/A20033 (SyntaxHighlighter), C10009/C20010 (SyntaxHighlighterTests)
- FocusedValues for menu state: `FocusedValues.swift` defines `selectedProject` and `hasProject` keys; ContentView publishes via `.focusedSceneValue()`; RidlerApp reads via `@FocusedValue`
- RecentProjectsManager (`Managers/RecentProjectsManager.swift`) — singleton `ObservableObject` managing recent PRD URLs via UserDefaults with URL bookmarks; `addRecent()` called from ContentView's `addProject()`; accessed via `RecentProjectsManager.shared`
- pbxproj IDs: A10033/A20035 (RecentProjectsManager)
- RalphLoopEngine auto-retry: 3 max retries, exponential backoff (2s, 8s, 18s), per-story retry count tracking, `updateAutoRetry()` for runtime toggle
- GitManager in `Managers/GitManager.swift` shells out to `/usr/bin/git` for git operations
- Protected branch detection: ContentView.startLoop() checks branch before first start (skipped on resume); shows BranchWarningSheet with three options: create branch (recommended), continue, cancel
- Working directory for git operations: `directoryURL.deletingLastPathComponent()` (project root, not PRD dir)
- pbxproj IDs: A10027/A20029 (GitManaging), A10028/A20030 (GitManager), A10029/A20031 (BranchWarningSheet), C10008/C20009 (GitManagerTests)

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

## 2026-02-09 - US-016
- **What was implemented:** Loop state machine with valid transitions, color-coded badges, display names, and "pause after story" mode support
- **Files changed:**
  - `Ridler/Ridler/Models/LoopState.swift` — Added `validTransitions` computed property defining allowed state transitions, `canTransition(to:)` and `transition(to:)` methods, `badgeColor` (SwiftUI Color) for UI badges, and `displayName` for human-readable labels
  - `Ridler/Ridler/Models/PRDProject.swift` — Added `pauseAfterStory: Bool` runtime-only property (excluded from Codable, defaults to false)
  - `Ridler/Ridler/ContentView.swift` — Updated `stateIndicator(for:)` to use `loopState.badgeColor` instead of hardcoded colors; preserved `pauseAfterStory` in `reloadAllProjects()`
  - `Ridler/RidlerTests/ModelTests.swift` — Added 17 new tests: 8 valid transition tests (ready→running, running→paused/stopped/complete/error, paused→running, stopped→running, error→running), 6 invalid transition tests (ready→non-running, running→self/ready, paused/stopped/error→non-running, complete→any), badge color test, display name test, validTransitions set test, pauseAfterStory not serialized test
  - `.chief/prds/ridler/prd.json` — Marked US-016 as passes: true
- **Learnings for future iterations:**
  - LoopState is a Hashable enum so `Set<LoopState>` works for `validTransitions` — convenient for transition validation
  - `import SwiftUI` in LoopState.swift is needed for the `Color` type in `badgeColor`
  - Runtime-only properties on PRDProject (loopState, iterationCount, pauseAfterStory, directoryURL) must all be preserved in `reloadAllProjects()` — don't forget new runtime properties
  - The `transition(to:)` method returns `LoopState?` (nil for invalid) rather than throwing — this is simpler for callers who can use `if let`
  - All 67 tests pass (50 existing + 17 new)
---

## 2026-02-09 - US-017
- **What was implemented:** Toolbar with loop controls — Start/Pause/Stop buttons, iteration counter, elapsed time display, color-coded state badge, and "Pause after story" toggle
- **Files changed:**
  - `Ridler/Ridler/Views/LoopToolbarView.swift` — New view with: Start/Pause/Stop buttons (enabled/disabled based on `canTransition`), state badge (colored dot + display name), iteration counter (current / max with monospaced font), elapsed time display (Xh Ym Zs format with 1-second timer), "Pause after story" checkbox toggle
  - `Ridler/Ridler/Models/PRDProject.swift` — Added `maxIterations` (Int, runtime-only) and `loopStartDate` (Date?, runtime-only) properties; added `defaultMaxIterations` computed property (remaining stories + 5, minimum 5)
  - `Ridler/Ridler/ContentView.swift` — Added `selectedProjectIndex` computed property for binding; inserted `LoopToolbarView` between tab bar and NavigationSplitView; preserved `maxIterations` and `loopStartDate` in `reloadAllProjects()`
  - `Ridler/Ridler.xcodeproj/project.pbxproj` — Added LoopToolbarView.swift (A10020/A20022) to app target and Views group
- **Learnings for future iterations:**
  - `LoopToolbarView` uses `@Binding var project: PRDProject` — needs binding via `$openProjects[selectedIndex]` from ContentView
  - `selectedProjectIndex` is needed to get a binding to the selected project; `selectedProject` (read-only computed) is insufficient for bindings
  - Timer-based elapsed time: `Timer.scheduledTimer` updates `@State elapsedTime` every second; timer started/stopped based on state transitions
  - `onChange(of: project.loopState)` uses the new two-parameter closure syntax (`{ _, newState in }`)
  - pbxproj IDs: A10020 (build file), A20022 (file ref) for LoopToolbarView.swift
  - All 67 tests still pass (pure UI story — no new tests needed)
---

## 2026-02-09 - US-018
- **What was implemented:** Claude Code process manager — ProcessManaging protocol and ClaudeCodeProcessManager that spawns, streams, and kills Claude Code subprocesses
- **Files changed:**
  - `Ridler/Ridler/Protocols/ProcessManaging.swift` — New protocol defining interface: `spawn(prompt:workingDirectory:logFileURL:)`, `kill()`, `isRunning`, `exitPublisher`; plus `ProcessExitResult` struct with exitCode, stderr, command
  - `Ridler/Ridler/Managers/ClaudeCodeProcessManager.swift` — Implementation: spawns Claude Code via `/usr/bin/env claude` with `--dangerously-skip-permissions --output-format stream-json -p <prompt>` flags; streams stdout line-by-line via Combine PassthroughSubject; captures stderr in thread-safe Data buffer; logs raw output to per-PRD claude.log file; clean kill with terminate + 2-second interrupt fallback; termination handler publishes ProcessExitResult on main thread
  - `Ridler/RidlerTests/ProcessManagerTests.swift` — 11 unit tests: ProcessExitResult equality/inequality, manager initial state, spawn-and-kill behavior, log file creation, error reporting with exit code/stderr/command, exit publisher availability, real subprocess test with /bin/echo, no-zombie-on-kill test
  - `Ridler/Ridler.xcodeproj/project.pbxproj` — Added ProcessManaging.swift (A10021/A20023), ClaudeCodeProcessManager.swift (A10022/A20024), ProcessManagerTests.swift (C10004/C20005)
- **Learnings for future iterations:**
  - `let` constants cannot be assigned inside a closure (e.g., `queue.sync { }`) — use `var` with initial value instead, or capture the value via a mutable variable
  - ClaudeCodeProcessManager uses `/usr/bin/env` to find `claude` in PATH — this works regardless of where claude is installed
  - Process termination handler runs on a background thread — dispatch to main thread for UI-safe state updates
  - Stdout line buffering: accumulate data in a buffer, split on newline (0x0A), process complete lines, keep partial data for next read
  - Log file uses `FileHandle.seekToEndOfFile()` to append to existing logs across sessions
  - Process.terminate() sends SIGTERM; Process.interrupt() sends SIGINT — use terminate first, then interrupt as fallback
  - All 78 tests pass (67 existing + 11 new)
---

## 2026-02-09 - US-019
- **What was implemented:** Streaming JSON parser for Claude Code's stream-json output format, with structured log entries and completion signal detection
- **Files changed:**
  - `Ridler/Ridler/Models/LogEntry.swift` — New LogEntry model (Identifiable, Equatable) with id, timestamp, type (LogEntryType enum: assistantText, toolUse, toolResult, error, system), and content string
  - `Ridler/Ridler/Managers/StreamingJSONParser.swift` — StreamingJSONParser class that parses Claude Code's newline-delimited JSON output; identifies message types (assistant, tool_use, tool_result, result, error); publishes LogEntry via Combine; detects `<ridler-complete/>` signal; uses os.Logger for warnings on malformed JSON; supports subscribing to a line publisher from ClaudeCodeProcessManager
  - `Ridler/RidlerTests/StreamingJSONParserTests.swift` — 35 unit tests covering: assistant text parsing (content string, content array, message field, multiple blocks), tool use parsing (Bash, Read, Glob, name field, unknown tool), tool result parsing, error parsing (message string, error object, error string), result parsing, system/unknown type parsing, malformed JSON handling (not JSON, partial JSON, empty lines, whitespace, arrays, missing type field), ridler-complete signal detection (in assistant content, raw text, result), entry publisher, subscribe to line publisher, realistic Claude output sequence, log entry properties (unique IDs, timestamps), edge cases
  - `Ridler/Ridler.xcodeproj/project.pbxproj` — Added LogEntry.swift (A10023/A20025), StreamingJSONParser.swift (A10024/A20026), StreamingJSONParserTests.swift (C10005/C20006)
- **Learnings for future iterations:**
  - Claude Code stream-json format: one JSON object per line, with `type` field indicating message type (assistant, tool_use, tool_result, result, error)
  - Tool use entries can have tool name in either `tool` or `name` field; input details in `input` object with keys like `command`, `file_path`, `pattern`
  - Content can be a string or an array of content blocks with `type` and `text` fields — always handle both formats
  - `<ridler-complete/>` signal can appear in any content field — check raw text, parsed assistant content, and result content
  - StreamingJSONParser uses `@discardableResult` on `parseLine()` to support both synchronous (direct return) and async (publisher subscription) usage patterns
  - os.Logger with subsystem "com.amattn.Ridler" and category "StreamingJSONParser" for structured logging of warnings
  - pbxproj IDs: A10023/A20025 (LogEntry), A10024/A20026 (StreamingJSONParser), C10005/C20006 (StreamingJSONParserTests)
  - All 113 tests pass (78 existing + 35 new)
---

## 2026-02-09 - US-020
- **What was implemented:** Log view with streaming output display — LogPanelView updated to render parsed log entries with type-specific icons, auto-scroll behavior, and manual scroll detection; LogStore ObservableObject for managing per-project log entries
- **Files changed:**
  - `Ridler/Ridler/Managers/LogStore.swift` — New ObservableObject that stores `[LogEntry]` per project ID with append, appendSystem, clear, and entries(for:) methods
  - `Ridler/Ridler/Views/LogPanelView.swift` — Complete rewrite: accepts `entries: [LogEntry]` and `isRunning: Bool`; renders log entries in LazyVStack with ScrollViewReader for auto-scroll; LogEntryRow subview with type-specific icons (bubble for assistant, terminal for Bash, doc for Read, pencil for Edit, etc.); color-coded backgrounds for errors (red) and system messages (blue); auto-scroll indicator in header; bottom sentinel view for scroll detection
  - `Ridler/Ridler/ContentView.swift` — Added `@StateObject logStore` and wired LogPanelView with entries from logStore and isRunning from project state
  - `Ridler/RidlerTests/LogStoreTests.swift` — 10 unit tests: empty store, append, multiple entries, system messages, project isolation, clear, clear isolation, system message types, order preservation, nonexistent project
  - `Ridler/Ridler.xcodeproj/project.pbxproj` — Added LogStore.swift (A10025/A20027) and LogStoreTests.swift (C10006/C20007)
- **Learnings for future iterations:**
  - `onScrollGeometryChange` is macOS 15.0+ only — deployment target is 14.0, so use `onAppear`/`onDisappear` on a bottom sentinel (`Color.clear.frame(height: 1)`) for scroll position detection
  - Tool icons are determined by parsing the `content` field prefix (e.g., "Tool: Bash" → terminal.fill, "Tool: Read" → doc.text.fill)
  - LogPanelView no longer takes zero args — all callers must pass `entries` and `isRunning`
  - LogStore is a separate ObservableObject (not part of PRDProject) because it holds UI state not persisted to JSON
  - pbxproj IDs: A10025/A20027 (LogStore), C10006/C20007 (LogStoreTests)
  - All 123 tests pass (113 existing + 10 new)
---

## 2026-02-09 - US-021
- **What was implemented:** Ralph loop engine — the autonomous execution engine that orchestrates story execution through Claude Code. Implements the full loop: read state → select next story → build prompt → invoke Claude Code → stream output → check completion → repeat.
- **Files changed:**
  - `Ridler/Ridler/Managers/RalphLoopEngine.swift` — New `RalphLoopEngine` class (ObservableObject) implementing the full autonomous loop: story selection (filter passes: false, sort by priority), prompt building with embedded agent instructions, Claude Code subprocess spawning via ProcessManaging, streaming output parsing via StreamingJSONParser, completion detection (`<ridler-complete/>` signal), state transitions (running/paused/stopped/complete/error), pause-after-story support, configurable max iterations, audio notification on completion (NSSound.beep)
  - `Ridler/Ridler/ContentView.swift` — Added `loopEngines: [String: RalphLoopEngine]` dictionary for per-project engines; `getOrCreateEngine(for:)` factory with callbacks for state change, iteration change, log entries, and project updates; `startLoop(for:)`, `pauseLoop(for:)`, `stopLoop(for:)` methods; wired LoopToolbarView with onStart/onPause/onStop callbacks
  - `Ridler/Ridler/Views/LoopToolbarView.swift` — Added `onStart`, `onPause`, `onStop` callback parameters; removed internal `startLoop()`, `pauseLoop()`, `stopLoop()` methods; button actions now delegate to callbacks from ContentView
  - `Ridler/RidlerTests/RalphLoopEngineTests.swift` — 14 unit tests: story selection (highest priority with passes: false), completion when all pass, state transitions (start→running, pause→paused, stop→stopped with kill), iteration count increment, max iterations stop, prompt content (story details, acceptance criteria, completion signal), system log messages, working directory (parent of PRD dir), story inProgress marking, process exit error handling, completion detection via ridler-complete signal, pause-after-story behavior
  - `Ridler/Ridler.xcodeproj/project.pbxproj` — Added RalphLoopEngine.swift (A10026/A20028) and RalphLoopEngineTests.swift (C10007/C20008)
- **Learnings for future iterations:**
  - RalphLoopEngine uses callbacks (`onStateChange`, `onIterationChange`, `onLogEntry`, `onProjectUpdated`) instead of @Published properties — this avoids the complexity of ObservableObject across view hierarchies and simplifies state synchronization with ContentView's `@State` arrays
  - `NSSound.beep()` requires `import AppKit` — Foundation alone is insufficient
  - LoopToolbarView can accept callback closures (onStart/onPause/onStop) to delegate control logic to the parent view — this separates presentation (toolbar) from business logic (engine management in ContentView)
  - The engine's `getOrCreateEngine(for:)` pattern stores engines in a `[String: RalphLoopEngine]` dictionary keyed by project ID — ensures one engine per project for parallel execution support
  - Working directory for Claude Code is set to the parent of the PRD directory (directoryURL.deletingLastPathComponent()) — this matches the expected project root location
  - MockProcessManager is useful for testing — expose `sendLine()` and `sendExit()` helper methods for simulating subprocess behavior
  - pbxproj IDs: A10026/A20028 (RalphLoopEngine), C10007/C20008 (RalphLoopEngineTests)
  - All 137 tests pass (123 existing + 14 new)
---

## 2026-02-09 - US-022
- **What was implemented:** Progress.md updates after each iteration — RalphLoopEngine now appends a structured progress entry to progress.md in the PRD directory after each successful iteration completes
- **Files changed:**
  - `Ridler/Ridler/Managers/RalphLoopEngine.swift` — Added `appendProgress(storyID:exitCode:)` method that appends timestamped progress entries with story ID, title, iteration number, and completion status; called from `handleProcessExit` after successful iteration; uses FileHandle for appending to existing files and atomic write for new files
  - `Ridler/RidlerTests/RalphLoopEngineTests.swift` — Added 4 new tests: progress file creation after iteration (verifies file exists and content includes story ID/title/iteration/status), appending to existing progress files (preserves prior content), non-zero exit code does not create progress entry, progress file stored in PRD directory (not parent)
  - `.chief/prds/ridler/prd.json` — Marked US-022 as passes: true
- **Learnings for future iterations:**
  - Progress is only appended on successful iterations (exit code 0 or completion detected) — error exits return before appendProgress is called
  - `FileHandle(forWritingTo:)` + `seekToEndOfFile()` + `write()` is the pattern for appending to existing files without reading the entire file into memory
  - The engine already includes progress.md content in the prompt via `buildPrompt()` — so Claude Code sessions get context about prior iterations automatically
  - All 141 tests pass (137 existing + 4 new)
---

## 2026-02-09 - US-023
- **What was implemented:** Protected branch detection and warning before starting a loop. When the project is on main/master, a warning dialog appears with three options: create a new ridler/{prd-name} branch (recommended, with editable name), continue on current branch, or cancel.
- **Files changed:**
  - `Ridler/Ridler/Protocols/GitManaging.swift` — New protocol defining git operation interface: `currentBranch(at:)`, `isProtectedBranch(_:)`, `createAndCheckoutBranch(_:at:)` for test mocking
  - `Ridler/Ridler/Managers/GitManager.swift` — Implementation that shells out to `/usr/bin/git` for branch detection (rev-parse) and checkout (-b); errors include command and stderr
  - `Ridler/Ridler/Views/BranchWarningSheet.swift` — Warning dialog with editable branch name field and three action buttons
  - `Ridler/Ridler/ContentView.swift` — Refactored `startLoop` to check protected branch before first start; added `proceedWithStart` and `handleCreateBranch` helpers; added BranchWarningSheet sheet modifier; branch check skipped on resume (paused/stopped/error)
  - `Ridler/RidlerTests/GitManagerTests.swift` — 11 integration tests with real git repos: current branch detection, non-git directory errors, protected branch checks (main, master, feature), create and checkout branch, duplicate branch error, error message contents, full detection integration flow
  - `Ridler/Ridler.xcodeproj/project.pbxproj` — Added GitManaging (A10027/A20029), GitManager (A10028/A20030), BranchWarningSheet (A10029/A20031), GitManagerTests (C10008/C20009)
  - `.chief/prds/ridler/prd.json` — Marked US-023 as passes: true
- **Learnings for future iterations:**
  - GitManager uses `/usr/bin/git` directly (not `/usr/bin/env git`) since git is reliably at that path on macOS
  - Protected branch check uses working directory = `directoryURL.deletingLastPathComponent()` (project root), same as where Claude Code runs
  - Branch check is only done on initial start (`.ready` state), not on resume from paused/stopped/error — avoids redundant checks
  - If git is not available or directory is not a git repo, the error is silently caught and the loop proceeds — graceful degradation
  - BranchWarningSheet uses `@State branchName` initialized to `ridler/{prdName}` — the user can edit this before creating
  - All 152 tests pass (141 existing + 11 new)
---

## 2026-02-09 - US-024
- **What was implemented:** Git commit per completed story — after each successful Claude Code iteration, Ridler creates a git commit with the format `feat: [US-XXX] - Story Title`
- **Files changed:**
  - `Ridler/Ridler/Protocols/GitManaging.swift` — Added `commitAllChanges(message:at:)` method to protocol
  - `Ridler/Ridler/Managers/GitManager.swift` — Implemented `commitAllChanges` using `git add -A` then `git commit -m`
  - `Ridler/Ridler/Managers/RalphLoopEngine.swift` — Added `gitManager: GitManaging` dependency; added `commitStoryChanges()` method called after successful iteration; commit message uses story ID and title from disk
  - `Ridler/RidlerTests/GitManagerTests.swift` — Added 3 integration tests: successful commit, empty commit error, error message contents
  - `Ridler/RidlerTests/RalphLoopEngineTests.swift` — Added `MockGitManager` class and 5 unit tests: commit after success, working directory is project root, no commit on error, commit failure is non-fatal, commit log message emitted
  - `.chief/prds/ridler/prd.json` — Marked US-024 as passes: true
- **Learnings for future iterations:**
  - `commitAllChanges` uses two git commands (`add -A` then `commit -m`) — if `add` succeeds but `commit` fails (e.g., nothing to commit), the error is from the commit step
  - Git commit errors are non-fatal in the loop engine — the loop continues even if the commit fails, which is the right behavior for graceful degradation
  - MockGitManager in tests tracks `commitCallCount`, `lastCommitMessage`, `lastCommitDirectory`, and supports injecting `commitError` for failure testing
  - The commit happens after `appendProgress` but before reloading the project and checking for completion — this ensures progress.md is included in the commit
  - All 160 tests pass (152 existing + 3 git integration + 5 engine tests)
---

## 2026-02-09 - US-025
- **What was implemented:** Status bar at the bottom of the main window that displays the last activity message with state-based coloring (cyan for running, yellow for paused, red for error, gray for other states)
- **Files changed:**
  - `Ridler/Ridler/Views/StatusBarView.swift` — New view showing activity message with state-colored text, fixed height 24pt, separator at top
  - `Ridler/Ridler/ContentView.swift` — Added StatusBarView at bottom of main VStack; added `statusBarMessage(for:)` helper that derives the activity message from project loop state and in-progress story
  - `Ridler/Ridler.xcodeproj/project.pbxproj` — Added StatusBarView.swift (A10030/A20032) to app target and Views group
  - `.chief/prds/ridler/prd.json` — Marked US-025 as passes: true
- **Learnings for future iterations:**
  - StatusBarView derives its message from `PRDProject` state — no separate state tracking needed; `statusBarMessage(for:)` checks `project.userStories.first(where: { $0.inProgress })` for the current story
  - LoopState already has `badgeColor` — StatusBarView uses a similar switch but only colors cyan/yellow/red for running/paused/error, defaulting to `.secondary` for other states
  - pbxproj IDs: A10030 (build file), A20032 (file ref) for StatusBarView.swift
  - All 160 tests still pass (pure UI story — no new tests needed)
---

## 2026-02-09 - US-026
- **What was implemented:** Parallel PRD execution — verified and tested that multiple PRDs can run simultaneously with independent loop state, iteration counts, timing, error tracking, and log entries. Fixed `closeProject` to properly stop engine and clean up when closing a running tab.
- **Files changed:**
  - `Ridler/Ridler/ContentView.swift` — Updated `closeProject()` to stop the engine and remove it from `loopEngines` dictionary before removing the project, preventing orphaned running processes
  - `Ridler/RidlerTests/RalphLoopEngineTests.swift` — Added 6 concurrent execution tests: `testThreeParallelEnginesRunIndependently` (3 engines running with correct story prompts), `testPausingOneEngineDoesNotAffectOthers` (B paused, A and C still running), `testStoppingOneEngineDoesNotAffectOthers` (A stopped with kill, B and C still running), `testParallelIterationCountsAreIndependent` (each engine tracks its own count), `testParallelLogEntriesAreIsolatedByProjectID` (logs tagged with correct project IDs), `testParallelErrorInOneDoesNotAffectOthers` (B errors, A and C still running)
- **Learnings for future iterations:**
  - The parallel execution architecture was mostly already in place from prior stories — `loopEngines: [String: RalphLoopEngine]` dictionary with `getOrCreateEngine(for:)` already provided per-project engine isolation
  - Key fix: `closeProject` must stop the engine and clean up the `loopEngines` dictionary entry, otherwise orphaned engines continue running in the background
  - `createIsolatedTestProject(name:stories:)` helper creates projects in unique subdirectories within `tempDir` — essential for parallel tests that need separate file systems
  - `XCTestExpectation` with `expectedFulfillmentCount = 3` is useful for waiting on multiple parallel events
  - All 166 tests pass (160 existing + 6 new parallel execution tests)
---

## 2026-02-09 - US-027
- **What was implemented:** Runtime iteration adjustment — +/- stepper control in LoopToolbarView that adjusts max iterations by ±5 at runtime, with immediate effect on the running loop engine
- **Files changed:**
  - `Ridler/Ridler/Views/LoopToolbarView.swift` — Added `onMaxIterationsChanged` callback parameter; added +/- buttons (minus and plus icons) next to the iteration counter; added `adjustMaxIterations(by:)` method that updates both the project binding and calls the callback; minus button disabled when max iterations ≤ 5; step size is ±5
  - `Ridler/Ridler/ContentView.swift` — Wired `onMaxIterationsChanged` callback to call `loopEngines[project.id]?.updateMaxIterations(newValue)` for immediate engine update
  - `.chief/prds/ridler/prd.json` — Marked US-027 as passes: true
- **Learnings for future iterations:**
  - RalphLoopEngine already had `updateMaxIterations(_:)` method from US-021 — no engine changes needed
  - The `effectiveMaxIterations` computed property (in LoopToolbarView) handles the case where `project.maxIterations` is 0 by falling back to `defaultMaxIterations`
  - Minimum max iterations is clamped to 5 to prevent setting to 0 or negative values
  - Callback pattern (`onMaxIterationsChanged`) keeps LoopToolbarView decoupled from engine management — consistent with existing onStart/onPause/onStop pattern
  - All 166 tests still pass (pure UI story — no new tests needed)
---

## 2026-02-09 - US-028
- **What was implemented:** Auto-retry on Claude Code crashes with exponential backoff. When enabled, the loop engine automatically retries up to 3 times when Claude Code exits with a non-zero exit code. After retry exhaustion, transitions to Error state.
- **Files changed:**
  - `Ridler/Ridler/Models/PRDProject.swift` — Added `autoRetryEnabled: Bool` runtime-only property (default: false, excluded from Codable)
  - `Ridler/Ridler/Managers/RalphLoopEngine.swift` — Added retry logic: `retryCount`, `maxRetries` (3), `currentStoryID` tracking; `handleProcessExit` now checks `autoRetryEnabled` and retries with exponential backoff (2s, 8s, 18s); `updateAutoRetry()` method for runtime toggle; retry count resets on new story or successful iteration
  - `Ridler/Ridler/Views/LoopToolbarView.swift` — Added "Auto-retry" toggle checkbox in toolbar with `onAutoRetryChanged` callback
  - `Ridler/Ridler/ContentView.swift` — Preserves `autoRetryEnabled` in `reloadAllProjects()` and `onProjectUpdated`; wires `onAutoRetryChanged` to engine's `updateAutoRetry()`
  - `Ridler/RidlerTests/RalphLoopEngineTests.swift` — Added 7 new tests: auto-retry retries on crash when enabled, disabled goes to error immediately, exhaustion transitions to error, retry log messages shown, default off, retry count reset on success, runtime toggle
  - `.chief/prds/ridler/prd.json` — Marked US-028 as passes: true
- **Learnings for future iterations:**
  - Exponential backoff formula: `retryCount^2 * 2` seconds (2s, 8s, 18s for retries 1/2/3)
  - `DispatchQueue.main.asyncAfter` with `[weak self]` prevents retain cycles in retry timers
  - Retry count must be tracked per-story (`currentStoryID`) and reset when a new story starts or iteration succeeds
  - The `autoRetryEnabled` property follows the same pattern as `pauseAfterStory` — runtime-only, preserved in reload, toggled in toolbar
  - Tests with long backoff timers (18s+) can run slowly — the exhaustion test takes ~30s; consider shorter backoff in tests if this becomes an issue
  - All 173 tests pass (166 existing + 7 new auto-retry tests)

## 2026-02-09 - US-029
- **What was implemented:** Audio notification on PRD completion using AVFoundation AVAudioPlayer, with toggle to enable/disable in the toolbar (default: on)
- **Files changed:**
  - `Ridler/Ridler/Models/PRDProject.swift` — Added `audioNotificationsEnabled: Bool` runtime-only property (default: true, excluded from Codable)
  - `Ridler/Ridler/Managers/RalphLoopEngine.swift` — Replaced `import AppKit` with `import AVFoundation`; replaced `NSSound.beep()` with `AVAudioPlayer` playing `/System/Library/Sounds/Glass.aiff`; added `audioNotificationsEnabled` property, `updateAudioNotifications()` method, and `audioPlayer` instance variable; sound only plays when `audioNotificationsEnabled` is true
  - `Ridler/Ridler/Views/LoopToolbarView.swift` — Added "Audio" checkbox toggle with `onAudioNotificationsChanged` callback, positioned before Auto-retry toggle
  - `Ridler/Ridler/ContentView.swift` — Wired `onAudioNotificationsChanged` callback to engine's `updateAudioNotifications()`; preserved `audioNotificationsEnabled` in both `reloadAllProjects()` and `onProjectUpdated`
  - `.chief/prds/ridler/prd.json` — Marked US-029 as passes: true
- **Learnings for future iterations:**
  - `AVAudioPlayer` requires keeping a strong reference to the player instance (stored as `audioPlayer` property) — if the player is a local variable it gets deallocated before playback finishes
  - System sounds are at `/System/Library/Sounds/` — Glass.aiff is a pleasant completion chime; other options include Hero.aiff, Purr.aiff, Funk.aiff
  - `import AVFoundation` replaces `import AppKit` for audio — AVFoundation provides AVAudioPlayer which is the recommended approach for audio playback on macOS
  - The `audioNotificationsEnabled` property follows the same pattern as `autoRetryEnabled` and `pauseAfterStory` — runtime-only, default value, preserved in reload/update, toggled in toolbar, forwarded to engine
  - PRDProject runtime-only properties now include: loopState, iterationCount, pauseAfterStory, autoRetryEnabled, audioNotificationsEnabled, maxIterations, loopStartDate, directoryURL — all must be preserved in `reloadAllProjects()` and `onProjectUpdated`
  - All 173 tests pass (no new tests needed — audio playback is a side effect best verified manually)
---

## 2026-02-09 - US-030
- **What was implemented:** macOS notification on PRD completion using UserNotifications framework. When a PRD reaches Complete state and the app is not frontmost, a native macOS notification is posted with the PRD name.
- **Files changed:**
  - `Ridler/Ridler/Managers/RalphLoopEngine.swift` — Added `import UserNotifications` and `import AppKit`; added `projectName` property to track PRD name; added `postCompletionNotification()` method that checks `NSApplication.shared.isActive` and posts via `UNUserNotificationCenter`; called alongside `playCompletionSound()` at both completion points (all stories pass on iteration start, and all stories pass after process exit)
  - `.chief/prds/ridler/prd.json` — Marked US-030 as passes: true
- **Learnings for future iterations:**
  - `UNUserNotificationCenter.current().requestAuthorization()` is async and returns via callback — authorization is requested inline before each notification post (idempotent after first grant)
  - `NSApplication.shared.isActive` checks if the app is frontmost — only post notification when app is in background
  - `UNNotificationRequest` with `trigger: nil` delivers immediately
  - Notification identifier uses `ridler-complete-\(projectID)` to avoid duplicate notifications for the same PRD
  - No new tests needed — `UNUserNotificationCenter` and `NSApplication` are runtime-only APIs that require a running app context to test meaningfully
  - All 173 tests pass
---

## 2026-02-09 - US-031
- **What was implemented:** Syntax highlighting for code blocks in the log view. When Claude's output contains fenced code blocks (``` markers), they are now rendered with keyword-based syntax highlighting using NSAttributedString and NSTextView.
- **Files changed:**
  - `Ridler/Ridler/Managers/SyntaxHighlighter.swift` — New struct with two main functions: `parseSegments()` splits content into text and code block segments by detecting ``` fences with optional language tags; `highlight()` applies regex-based syntax highlighting for keywords, strings, comments, numbers, and type names using NSAttributedString with language-specific keyword sets
  - `Ridler/Ridler/Views/LogPanelView.swift` — Updated `LogEntryRow` to detect code blocks via `SyntaxHighlighter.parseSegments()`; added `contentView` that renders mixed text/code content; added `HighlightedCodeView` (NSViewRepresentable wrapping NSTextView) for displaying highlighted code with proper sizing via `sizeThatFits`
  - `Ridler/RidlerTests/SyntaxHighlighterTests.swift` — 20 unit tests covering: segment parsing (plain text, single/multiple code blocks, no language, unclosed blocks, empty blocks, language normalization, multiline code), highlighting (Swift, Python, TypeScript, Rust, Go, Bash keywords, unknown/nil language, empty code, content preservation), and supported language coverage
  - `Ridler/Ridler.xcodeproj/project.pbxproj` — Added SyntaxHighlighter.swift (A10031/A20033) and SyntaxHighlighterTests.swift (C10009/C20010)
- **Learnings for future iterations:**
  - `NSViewRepresentable` with `sizeThatFits(_:nsView:context:)` is the correct way to get dynamic sizing for AppKit views embedded in SwiftUI (macOS 14+)
  - NSTextView requires `textContainer?.widthTracksTextView = true` and `isHorizontallyResizable = false` for proper text wrapping
  - Syntax highlighting colors should use explicit RGB values rather than system semantic colors to ensure consistent appearance in code blocks
  - Code block detection splits on ``` fences — unclosed blocks are treated as plain text to avoid rendering errors
  - Language tags in fences are normalized to lowercase for consistent keyword matching
  - Supported languages: Swift, TypeScript/TS/TSX, JavaScript/JS/JSX, Python/Py, Go/Golang, Rust/RS, Bash/Sh/Shell/Zsh, JSON, HTML/XML, CSS/SCSS, plus a generic fallback set
  - pbxproj IDs: A10031/A20033 (SyntaxHighlighter), C10009/C20010 (SyntaxHighlighterTests)
  - All 193 tests pass (173 existing + 20 new)
---

## 2026-02-09 - US-032
- **What was implemented:** Interrupted story detection and warning banner in the sidebar. When a PRD is loaded/reopened and a story has `inProgress: true` from a previously interrupted session (loop is not currently running), a yellow warning banner appears in the stories panel showing which stories were interrupted. The banner includes a dismiss button and an optional "Resume Loop" button to acknowledge and resume.
- **Files changed:**
  - `Ridler/Ridler/Views/SidebarView.swift` — Added `onResume` callback parameter, `interruptedWarningDismissed` state, and `interruptedStoryBanner()` view builder that shows a yellow warning banner when stories have `inProgress: true` while `loopState != .running`; banner includes story ID list, dismiss button, and "Resume Loop" button
  - `Ridler/Ridler/ContentView.swift` — Updated SidebarView initialization to pass `onResume` callback that calls `startLoop(for:)` for the selected project index
  - `.chief/prds/ridler/prd.json` — Marked US-032 as passes: true
- **Learnings for future iterations:**
  - Interrupted story detection logic: `story.inProgress && !story.passes` while `project.loopState != .running` — this covers fresh loads (loopState defaults to `.ready`) and paused/stopped/error states
  - SidebarView now accepts an optional `onResume: (() -> Void)?` closure — nil means no resume button is shown (e.g., in previews)
  - `@State interruptedWarningDismissed` resets naturally when the view is re-created (e.g., switching PRDs) since it's local view state
  - The `selectedProjectIndex.map { idx in { startLoop(for: idx) } }` pattern creates an optional closure from an optional index — clean way to pass conditional callbacks
  - All 193 tests pass (no new tests needed — this is a pure UI feature with straightforward detection logic)
---

## 2026-02-09 - US-033
- **What was implemented:** Keyboard shortcuts for all common actions — Start/Resume (Cmd+R, Cmd+Return), Pause (Cmd+.), Stop (Cmd+Shift+.), Switch tabs (Cmd+1 through Cmd+9), Focus Log Panel (Cmd+L), and Edit current PRD (Cmd+E). Cmd+O and Cmd+N were already implemented in prior stories.
- **Files changed:**
  - `Ridler/Ridler/RidlerApp.swift` — Added new `CommandGroup(after: .newItem)` with menu items for all keyboard shortcuts: Start/Resume Loop (Cmd+R and Cmd+Return), Pause Loop (Cmd+.), Stop Loop (Cmd+Shift+.), Focus Log Panel (Cmd+L), Edit Current PRD (Cmd+E), and Switch to PRD 1-9 (Cmd+1 through Cmd+9); added 6 new Notification.Name extensions (startLoop, pauseLoop, stopLoop, switchToTab, focusLogPanel, editPRD)
  - `Ridler/Ridler/ContentView.swift` — Added 6 `.onReceive` handlers for the new notifications: startLoop calls `startLoop(for:)`, pauseLoop calls `pauseLoop(for:)`, stopLoop calls `stopLoop(for:)`, switchToTab switches `selectedProjectID` by tab position (1-indexed), focusLogPanel sets `columnVisibility = .all`, editPRD selects `.file(.prdMd)` in sidebar
  - `.chief/prds/ridler/prd.json` — Marked US-033 as passes: true
- **Learnings for future iterations:**
  - `CommandGroup(after: .newItem)` appends items after the existing File menu section — use this for additional menu items that don't replace the New/Open group
  - SwiftUI `KeyEquivalent(Character(String(index)))` converts an Int (1-9) to a keyboard shortcut character — used for Cmd+1 through Cmd+9 tab switching
  - `Notification.object` can carry data — used `notification.object as? Int` for the tab number in switchToTab
  - Cmd+Return uses `.keyboardShortcut(.return)` — SwiftUI has predefined `KeyEquivalent` constants for special keys
  - Focus Log Panel is implemented by ensuring `columnVisibility = .all` (showing all three panes) — in a future iteration, a more precise focus mechanism (e.g., FocusState) could be used
  - Edit Current PRD selects `.file(.prdMd)` in sidebar — this will trigger the Claude terminal pane when US-040 is implemented; for now it just shows the prd.md file content
  - All 193 tests pass (pure UI story — no new tests needed)
---

## 2026-02-09 - US-034
- **What was implemented:** Full macOS menu bar with properly organized menus: File (New PRD, Open PRD), View (Focus Log Panel), PRD (Start/Resume, Pause, Stop, Edit Current PRD), and Window (Switch to PRD 1-9). Menu items are enabled/disabled based on current loop state using FocusedValue bindings from ContentView to RidlerApp.
- **Files changed:**
  - `Ridler/Ridler/RidlerApp.swift` — Reorganized commands from two flat CommandGroups into proper menu structure: File menu (CommandGroup replacing .newItem), View menu (CommandGroup after .toolbar), PRD menu (CommandMenu), Window menu (CommandGroup before .windowList); added @FocusedValue for selectedProject and hasProject; menu items disabled based on loop state via `canTransition(to:)`
  - `Ridler/Ridler/Models/FocusedValues.swift` — New file defining FocusedProjectKey and FocusedHasProjectKey for SwiftUI FocusedValue bindings between ContentView and menu commands
  - `Ridler/Ridler/ContentView.swift` — Added `.focusedSceneValue(\.selectedProject, ...)` and `.focusedSceneValue(\.hasProject, ...)` to publish view state to menu commands
  - `Ridler/Ridler.xcodeproj/project.pbxproj` — Added FocusedValues.swift (A10032/A20034) to app target and Models group
- **Learnings for future iterations:**
  - SwiftUI `@FocusedValue` is the proper pattern for communicating view state to menu commands at the App level — replaces the need for a shared ViewModel or more NotificationCenter hacks
  - `CommandMenu("PRD")` creates a custom top-level menu — use this for app-specific menus that don't fit into standard macOS categories
  - `CommandGroup(after: .toolbar)` places items in the View menu after the standard toolbar items
  - `CommandGroup(before: .windowList)` places items in the Window menu before the standard window list
  - Edit menu (Undo/Redo/Cut/Copy/Paste/Select All) is provided automatically by SwiftUI — no custom code needed
  - Help menu is provided automatically by SwiftUI — no custom code needed
  - Menu item enable/disable uses `LoopState.canTransition(to:)` — reuses existing state machine logic rather than duplicating conditions
  - pbxproj IDs: A10032/A20034 (FocusedValues.swift)
  - All 193 tests pass (no new tests needed — menu bar is UI-only and uses existing state machine which is already well-tested)
---

## 2026-02-09 - US-035
- **What was implemented:** Open Recent PRDs feature — remembers recently opened PRDs and displays them in File > Open Recent submenu, persisted across app launches via UserDefaults using URL bookmarks
- **Files changed:**
  - `Ridler/Ridler/Managers/RecentProjectsManager.swift` — New singleton `ObservableObject` that manages recent PRD URLs: stores up to 10 recent URLs as bookmark data in UserDefaults, provides `addRecent()` and `clearRecents()` methods, publishes `recentURLs` for SwiftUI observation
  - `Ridler/Ridler/RidlerApp.swift` — Added `@StateObject recentProjects` reference; added `Menu("Open Recent")` submenu inside File menu after "Open PRD..." with list of recent URLs and "Clear Menu" option; added `.openRecentPRD` notification name
  - `Ridler/Ridler/ContentView.swift` — Updated `addProject()` to call `RecentProjectsManager.shared.addRecent()` when a project is added; added `.onReceive` handler for `.openRecentPRD` notification that loads and opens the recent PRD URL
  - `Ridler/Ridler.xcodeproj/project.pbxproj` — Added RecentProjectsManager.swift (A10033/A20035) to app target and Managers group
  - `.chief/prds/ridler/prd.json` — Marked US-035 as passes: true
- **Learnings for future iterations:**
  - URL bookmarks (`url.bookmarkData()` / `URL(resolvingBookmarkData:)`) are the correct way to persist file URLs across app launches — raw path strings may break if volumes are renamed or files move
  - `RecentProjectsManager.shared` singleton pattern works well for app-wide state that needs to be accessed from both RidlerApp (menu) and ContentView (recording recents)
  - SwiftUI `Menu` inside `CommandGroup` creates a submenu in the File menu — use `ForEach` with `.id(\.absoluteString)` for URL-based iteration
  - `.disabled(recentProjects.recentURLs.isEmpty)` correctly grays out the "Open Recent" submenu when there are no recents
  - pbxproj IDs: A10033/A20035 (RecentProjectsManager.swift)
  - All 193 tests pass (no new tests needed — this is a UI/persistence feature with straightforward UserDefaults storage)
---
