# PRD: Ridler

## Introduction

Ridler is a native macOS application (Swift/SwiftUI, macOS 14+, Apple Silicon only) that transforms Product Requirements Documents into working code by orchestrating Claude Code in an autonomous loop. It reads PRDs (markdown + JSON), breaks them into user stories, and executes them sequentially through fresh Claude Code sessions — the "Ralph Wiggum loop" pattern. Each iteration starts with a clean context window while persisting progress between runs via a `progress.md` file.

PRDs can live anywhere on disk. Users open existing PRD files or create new ones at any location. Each opened PRD becomes a tab in the interface. Companion files (`ridl.json`, `progress.md`, `claude.log`) are stored alongside the `prd.md` in the same directory.

Ridler is built and maintained by both human developers and AI coding agents. The codebase, error surfaces, and debugging tools must be equally effective for both audiences.

## Goals

- Feature-complete native macOS equivalent of [minicodemonkey/chief](https://github.com/minicodemonkey/chief)
- Full SwiftUI interface with proper macOS conventions (menu bar, keyboard shortcuts, window management, drag-and-drop)
- Parallel PRD execution with independent loop state per PRD
- Real-time streaming of Claude's output with syntax highlighting
- One git commit per completed story
- Standard macOS Settings window for app-wide preferences
- PRDs stored anywhere on disk — no fixed project directory structure
- Clear, actionable error messages for both human developers and AI coding agents
- Debug tooling that makes internal state visible on demand

## User Stories

### US-001: Create Xcode Project and App Shell
**Description:** As a developer, I want a properly configured Xcode project so that I have the foundation for building Ridler.

**Acceptance Criteria:**
- [ ] Xcode project created with SwiftUI App lifecycle targeting macOS 14.0+, Apple Silicon only
- [ ] App launches and displays an empty window with the title "Ridler"
- [ ] Project builds and runs without warnings or errors
- [ ] Bundle identifier and app name configured
- [ ] Typecheck passes

---

### US-002: PRD Data Models and JSON Parsing
**Description:** As a developer, I want Swift data models for the PRD format so that the app can read and write `ridl.json` files from any location on disk.

**Acceptance Criteria:**
- [ ] `PRDProject` model with fields: project (string), description (string), branchName (string, optional), user stories array
- [ ] `UserStory` model with fields: id (e.g. "US-001"), title, description, acceptanceCriteria (string array), priority (integer), passes (bool), inProgress (bool), lastPrompt (string, optional), notes (string, optional)
- [ ] Models conform to `Codable` for JSON serialization/deserialization
- [ ] JSON decoding is resilient: `passes` defaults to `false` and `inProgress` defaults to `false` when missing from JSON
- [ ] Can round-trip read → decode → encode → write a `ridl.json` without data loss
- [ ] Given a `prd.md` or `ridl.json` file path, can locate and load companion files from the same directory
- [ ] JSON decoding errors include the file name, missing/invalid key, and JSON path (e.g., `ridl.json: missing required key "title" in userStories.0`)
- [ ] File-not-found errors include the full path searched and which filenames were tried (e.g., "No ridl.json or prd.json found in /path/to/dir")
- [ ] Error types conform to `LocalizedError` with human-readable `errorDescription`
- [ ] Unit tests for decoding, encoding, round-trip fidelity, and error messages
- [ ] Typecheck passes

---

### US-003: Loop State Machine
**Description:** As a developer, I want a state machine that manages the Ralph Loop lifecycle so that loop transitions are predictable and correct.

**Acceptance Criteria:**
- [ ] `LoopState` enum with six cases: ready, running, paused, stopped, complete, error
- [ ] State machine enforces valid transitions only: ready→running, running→paused, running→stopped, running→complete, running→error, paused→running, stopped→running, error→running
- [ ] Invalid transitions are rejected (no-op or error)
- [ ] Each state exposes a color property: ready (gray), running (cyan), paused (yellow), stopped (gray), complete (green), error (red)
- [ ] Each state exposes a display label: "Ready", "Running", "Paused", "Stopped", "Complete", "Error"
- [ ] State machine is observable (publishes changes for SwiftUI binding)
- [ ] Unit tests for every valid transition and confirming invalid transitions are rejected
- [ ] Typecheck passes

---

### US-004: Claude Code Process Manager
**Description:** As a developer, I want a process manager that spawns Claude Code as a subprocess and streams its JSON output so that the Ralph Loop can execute stories.

**Acceptance Criteria:**
- [ ] `ClaudeProcessManager` class that spawns `claude` with `--dangerously-skip-permissions --output-format stream-json` flags
- [ ] Accepts a prompt string and working directory as input
- [ ] Reads stdout line-by-line and publishes each line as it arrives
- [ ] Detects process exit and reports success (exit code 0) or failure (non-zero)
- [ ] Supports cancellation — can terminate a running process immediately
- [ ] Does not block the main thread (runs on a background thread/task)
- [ ] Cleans up child process on dealloc or app quit (no zombie processes)
- [ ] `ProcessSpawning` protocol for test mocking
- [ ] Unit tests with a mock process that simulates normal exit, crash, and slow output
- [ ] Typecheck passes

---

### US-005: Streaming JSON Log Parser
**Description:** As a developer, I want a parser that converts Claude Code's streaming JSON output into structured log entries so that the UI can display them.

**Acceptance Criteria:**
- [ ] `LogEntry` model with types: assistantText, toolUse (tool name, input), toolResult (output), error, system
- [ ] Parser consumes raw JSON lines from Claude's `stream-json` output and emits `LogEntry` values
- [ ] Handles malformed or incomplete JSON lines gracefully (logs a warning, does not crash)
- [ ] Detects the `<ridler-complete/>` signal in assistant text output
- [ ] Unit tests with captured real Claude `stream-json` output samples
- [ ] Unit tests for malformed input (partial JSON, empty lines, garbage data)
- [ ] Typecheck passes

---

### US-006: Ralph Loop Engine
**Description:** As a developer, I want the core Ralph Loop engine that orchestrates story execution so that PRDs can be processed autonomously.

**Acceptance Criteria:**
- [ ] `RalphLoopEngine` that takes a `ridl.json` file path, working directory, and max iterations as input
- [ ] Selects the next story by filtering `passes == false`, sorting by `priority` ascending, picking the first
- [ ] Builds the prompt from: story details (ID, title, description, acceptance criteria), agent instructions, and `progress.md` content
- [ ] After building the prompt, stores it in the story's `lastPrompt` field in `ridl.json` before invoking Claude
- [ ] Invokes `ClaudeProcessManager` with the built prompt
- [ ] On story completion: sets `passes: true` and `inProgress: false` in `ridl.json`, writes to disk
- [ ] On iteration start: sets `inProgress: true` on the current story
- [ ] Appends implementation summary to `progress.md` after each iteration
- [ ] Transitions to complete state when all stories pass or `<ridler-complete/>` is detected
- [ ] Respects max iterations limit
- [ ] Integrates with `LoopState` state machine for all transitions
- [ ] Supports pause (finishes current iteration then pauses) and stop (halts immediately)
- [ ] Typecheck passes

---

### US-007: Git Manager
**Description:** As a developer, I want a Git manager that handles branch detection and per-story commits so that the loop produces a clean git history.

**Acceptance Criteria:**
- [ ] `GitManager` class that shells out to the `git` CLI via `GitOperating` protocol for test mocking
- [ ] Detects current branch name
- [ ] Detects if current branch is protected (main or master)
- [ ] Creates a new branch with a given name (e.g. `ridler/{prd-name}`)
- [ ] Creates a commit with all staged and unstaged changes using the format `feat: [US-001] - Story Title`
- [ ] `GitError` enum with descriptive error messages including the failed git command and stderr
- [ ] Unit tests for branch detection and protected branch check
- [ ] Typecheck passes

---

### US-008: File Watcher
**Description:** As a developer, I want a file watcher that monitors each opened PRD's directory so that the app auto-reloads when PRD files are changed externally.

**Acceptance Criteria:**
- [ ] `FileWatcher` class using FSEvents or DispatchSource to monitor directories
- [ ] Can watch multiple directories simultaneously (one per opened PRD)
- [ ] Detects file creation, modification, and deletion within each watched directory
- [ ] `FileWatcherDelegate` protocol publishes `FileChangeEvent` (directory, path, timestamp)
- [ ] Debounces rapid changes (configurable interval, e.g. 500ms)
- [ ] Starts and stops watching individual directories cleanly
- [ ] No leaked file descriptors or watchers
- [ ] Typecheck passes

---

### US-009: PRD Manager (ViewModel Layer)
**Description:** As a developer, I want a PRD Manager that manages opened PRD tabs and ties together the data models, loop engine, and file watcher so that the UI has a single source of truth.

**Acceptance Criteria:**
- [ ] `PRDManager` as an `@Observable` class that the SwiftUI views bind to
- [ ] Maintains a list of currently opened PRD tabs, each referencing a file path on disk
- [ ] Opens a PRD from any file path (prd.md or ridl.json) and adds it as a tab
- [ ] All open errors surface via `showOpenError`/`openErrorMessage` for UI alert display (never silently swallowed)
- [ ] Creates a new PRD at a user-specified location (creates empty `prd.md`, opens as tab)
- [ ] Closes a PRD tab (stops its engine, watcher, removes tab, selects another)
- [ ] Exposes each opened PRD's current loop state, story progress, and iteration count
- [ ] Tracks the currently selected PRD tab and currently selected story
- [ ] Provides start/pause/stop actions that delegate to `RalphLoopEngine` for the selected PRD
- [ ] Subscribes to `FileWatcher` events and reloads affected PRDs when files change externally
- [ ] Supports multiple simultaneous running loops with independent state per PRD
- [ ] Calculates default max iterations (remaining stories + 5, minimum 5)
- [ ] Persists the list of opened PRD file paths so they can be restored on next launch
- [ ] Typecheck passes

---

### US-010: Main Window Layout with Three-Pane Split
**Description:** As a user, I want the main window to display stories, story detail, and log output in a three-pane layout so that I can see everything at once.

**Acceptance Criteria:**
- [ ] Main window uses `NavigationSplitView` with three panes: stories list (left), story detail (middle), log view (right)
- [ ] Panes resize with the window — sidebar collapses automatically on narrow windows
- [ ] Window has a reasonable default size (e.g. 1200x700)
- [ ] Window title shows the current PRD name
- [ ] When no PRD is loaded, the middle pane shows an empty state with "Open PRD..." and "New PRD..." buttons
- [ ] Error alert dialog displayed when PRD open/load fails (with descriptive error message)
- [ ] Typecheck passes

---

### US-011: Toolbar with Loop Controls
**Description:** As a user, I want Start/Pause/Stop buttons and status indicators in the toolbar so that I can control and monitor the loop.

**Acceptance Criteria:**
- [ ] Toolbar displays Start, Pause, and Stop buttons
- [ ] Buttons are enabled/disabled based on current loop state (e.g. Pause disabled when not running)
- [ ] Toolbar shows iteration counter: current iteration / max iterations
- [ ] Toolbar shows elapsed time since loop started (format: `Xh Ym Zs`)
- [ ] Toolbar shows color-coded state badge: Ready (gray), Running (cyan), Paused (yellow), Stopped (gray), Complete (green), Error (red)
- [ ] Buttons trigger the corresponding actions on `PRDManager` for the currently selected PRD
- [ ] Typecheck passes

---

### US-012: Stories Panel (Left Pane)
**Description:** As a user, I want a scrollable list of user stories with status icons and a progress bar so that I can see overall progress at a glance.

**Acceptance Criteria:**
- [ ] Scrollable list displays all user stories for the selected PRD
- [ ] Each row shows: status icon (✓ passed, ● in-progress, ○ pending), story ID, and title
- [ ] Clicking a story selects it and updates the detail pane
- [ ] Currently selected story is visually highlighted
- [ ] Progress bar at the bottom shows: filled portion, percentage, and count (e.g. `2/4 stories`)
- [ ] Yellow warning banner shown on stories with `inProgress: true` from a previously interrupted session
- [ ] Typecheck passes

---

### US-013: Story Detail Panel (Middle Pane)
**Description:** As a user, I want to see the full details of a selected story so that I can understand what the loop is working on.

**Acceptance Criteria:**
- [ ] Displays the selected story's title in bold
- [ ] Displays status badge and priority number
- [ ] Displays the full description with word wrapping
- [ ] Displays acceptance criteria as a bulleted list
- [ ] When no story is selected, shows a placeholder message
- [ ] When an error occurs, shows error details and a tip to check `claude.log`
- [ ] Typecheck passes

---

### US-014: Log Panel (Right Pane)
**Description:** As a user, I want a real-time streaming log of Claude's output so that I can see exactly what the agent is doing.

**Acceptance Criteria:**
- [ ] Always visible alongside the story detail panel — no toggle needed
- [ ] Displays parsed `LogEntry` values as readable entries: assistant text, tool calls (with tool name), tool results, errors
- [ ] Tool call entries show an icon per tool type (Read, Edit, Write, Bash, etc.)
- [ ] Shows story transition events, iteration starts, completion messages, and retry events
- [ ] Auto-scrolls to follow new output while the loop is running
- [ ] Disables auto-scroll when user scrolls up manually; re-enables when user scrolls to bottom
- [ ] Shows an indicator for auto-scroll vs. manual-scroll mode
- [ ] Typecheck passes

---

### US-015: PRD Tab Bar
**Description:** As a user, I want a tab bar showing all currently opened PRDs so that I can switch between them and see their status.

**Acceptance Criteria:**
- [ ] Horizontal tab bar displayed below the toolbar showing all currently opened PRDs
- [ ] Each tab shows: PRD name and state indicator icon (● ready, ▶ running + iteration count, ⏸ paused, ✓ complete, ✗ error, ■ stopped)
- [ ] Clicking a tab switches the view to that PRD without affecting other running loops
- [ ] A `[+]` button at the end of the tab bar opens a menu with "Open PRD..." and "New PRD..."
- [ ] Right-click context menu on a tab: Start, Pause, Stop, Edit, Close, Delete
- [ ] Typecheck passes

---

### US-016: Status Bar (Bottom)
**Description:** As a user, I want a status bar at the bottom of the window showing the current activity so that I always know what the loop is doing.

**Acceptance Criteria:**
- [ ] Displays the last activity message (e.g. "Working on: US-002 - Add login endpoint")
- [ ] Activity message color changes based on current state: cyan for running, yellow for paused, red for error
- [ ] Updates in real-time as the loop progresses
- [ ] Typecheck passes

---

### US-017: Open Existing PRD
**Description:** As a user, I want to open an existing PRD file from any location on disk so that I can work with PRDs stored anywhere.

**Acceptance Criteria:**
- [ ] File > Open (`⌘O`) presents a file picker dialog filtering for `prd.md` and `ridl.json` files
- [ ] Selecting a file opens it as a new tab and loads its stories
- [ ] If opening fails, a native alert displays the specific error message (never silent failure)
- [ ] Drag-and-drop a `prd.md` or `ridl.json` file onto the window opens it as a tab, with error alert on failure
- [ ] Recently opened PRDs are stored and displayed in File > Open Recent, with error alert if a recent file can't be loaded
- [ ] Opening a PRD that is already open switches to its existing tab
- [ ] Typecheck passes

---

### US-018: Create New PRD
**Description:** As a user, I want to create a new PRD at any location so that I can start a new project.

**Acceptance Criteria:**
- [ ] File > New (`⌘N`) or empty state "New PRD..." button triggers the creation flow
- [ ] Prompts for a PRD name (text field, allows letters, numbers, `-`, `_`) and a save location (directory picker)
- [ ] Validates the PRD name — rejects empty or invalid names
- [ ] Creates an empty `prd.md` file at the chosen location and opens it as a tab
- [ ] User can then click "Edit PRD" to launch Claude Code interactively and author the PRD content
- [ ] Typecheck passes

---

### US-019: Protected Branch Warning Dialog
**Description:** As a user, I want a warning when starting the loop on main/master so that I don't accidentally commit directly to a protected branch.

**Acceptance Criteria:**
- [ ] When the user presses Start and the current branch is main or master, show a warning dialog
- [ ] Dialog offers three options: create a `ridler/{prd-name}` branch (recommended), continue on current branch, or cancel
- [ ] Branch name is editable in the dialog before confirming
- [ ] If "Create branch" is chosen, the branch is created and checked out before the loop starts
- [ ] If "Continue" is chosen, the loop starts on the current branch
- [ ] If "Cancel" is chosen, the loop does not start
- [ ] Typecheck passes

---

### US-020: Edit PRD via Claude Code
**Description:** As a user, I want to edit an existing PRD by launching an interactive Claude Code session from the app.

**Acceptance Criteria:**
- [ ] "Edit PRD" button visible in the UI for the currently selected PRD
- [ ] Clicking "Edit PRD" (or `⌘E`) launches Claude Code in a Terminal window with the PRD context loaded
- [ ] After Claude Code exits, the app reloads the PRD data (via file watcher)
- [ ] Typecheck passes

---

### US-021: Close and Delete PRD
**Description:** As a user, I want to close a PRD tab or delete its files so that I can manage my workspace.

**Acceptance Criteria:**
- [ ] Close tab via right-click context menu, `⌘W`, or close button on the tab
- [ ] Closing a tab removes it from the interface but does not delete files on disk
- [ ] If a loop is running for that PRD, prompt confirmation before closing and stop the loop
- [ ] Delete option via right-click context menu on a PRD tab
- [ ] Delete shows a confirmation dialog before removing files
- [ ] On confirm, deletes the PRD directory and all its contents
- [ ] After close or delete, switches to another open tab or shows the empty state
- [ ] Typecheck passes

---

### US-022: Audio and macOS Notifications
**Description:** As a user, I want audio and system notifications when a PRD completes so that I know when the work is done without watching the screen.

**Acceptance Criteria:**
- [ ] Plays an audio notification sound when a PRD reaches the Complete state
- [ ] Audio can be disabled via the Settings window
- [ ] Posts a macOS notification when a PRD completes and the app is not frontmost
- [ ] Notification shows the PRD name and completion status
- [ ] Typecheck passes

---

### US-023: Settings Window
**Description:** As a user, I want a standard macOS Settings window so that I can configure app-wide preferences.

**Acceptance Criteria:**
- [ ] Settings window opens via `⌘,` or Ridler > Settings menu item
- [ ] Contains toggles for: Audio notifications (default: On), Auto-retry on crash (default: Off), Verbose log (default: Off)
- [ ] `SettingsManager` singleton backed by UserDefaults
- [ ] Settings changes take effect immediately without restart
- [ ] Typecheck passes

---

### US-024: Keyboard Shortcuts and Menu Bar
**Description:** As a user, I want standard macOS keyboard shortcuts and a full menu bar so that I can control the app efficiently.

**Acceptance Criteria:**
- [ ] `⌘N` — Create new PRD
- [ ] `⌘O` — Open an existing PRD file
- [ ] `⌘W` — Close current PRD tab
- [ ] `⌘R` or `⌘↩` — Start/Resume loop for current PRD
- [ ] `⌘.` — Pause loop
- [ ] `⌘⇧.` — Stop loop
- [ ] `⌘1`–`⌘9` — Switch to PRD by tab position
- [ ] `⌘L` — Focus Log Panel
- [ ] `⌘E` — Edit current PRD (launch Claude Code)
- [ ] Standard macOS menu bar with File, Edit, View, PRD, Window, Help menus
- [ ] Menu items are enabled/disabled appropriately based on app state
- [ ] Typecheck passes

---

### US-025: Syntax Highlighting in Log View
**Description:** As a user, I want code blocks in Claude's output to be syntax highlighted so that the log view is easier to read.

**Acceptance Criteria:**
- [ ] `CodeHighlighter` applies keyword-based coloring to log entries
- [ ] Code fence detection (triple backtick blocks) applies monospace styling
- [ ] Common keywords (func, class, import, return, etc.) colored distinctly
- [ ] Highlighting does not degrade scroll performance
- [ ] Typecheck passes

---

### US-026: Auto-Retry on Claude Code Crashes
**Description:** As a user, I want the option to automatically retry when Claude Code crashes so that transient failures don't stop my progress.

**Acceptance Criteria:**
- [ ] When enabled in Settings (default: Off), automatically retries on Claude Code process failure
- [ ] Progressive backoff delays: 0s, 5s, 15s
- [ ] Maximum 3 retry attempts before transitioning to Error state
- [ ] `autoRetryOverride` property for test control
- [ ] Retry events are shown in the log panel
- [ ] Intentional stops (user pressing Stop) are never retried
- [ ] Typecheck passes

---

### US-027: Copy Button on Error Alerts
**Description:** As a developer, I want a "Copy" button on error alert dialogs so I can quickly paste error details into bug reports, chat, or agent prompts.

**Acceptance Criteria:**
- [ ] The "Failed to Open PRD" alert includes a "Copy Error" button alongside the "OK" button
- [ ] Clicking "Copy Error" copies the full error message string to the system clipboard via `NSPasteboard`
- [ ] The clipboard content matches the error text displayed in the alert body
- [ ] Typecheck passes

---

### US-028: Process and Git Error Details
**Description:** As a developer, I want process and git errors to include the command, exit code, and stderr so I can diagnose failures without guessing.

**Acceptance Criteria:**
- [ ] `ClaudeProcessManager` errors include the exit code and stderr output (if any) in the error description
- [ ] `GitError` cases include the git command arguments that were run and stderr output
- [ ] Error descriptions are suitable for both UI display and log output (single-line summary with detail on next line)
- [ ] Existing tests still pass with updated error types
- [ ] Typecheck passes

---

### US-029: Debug Mode Setting
**Description:** As a developer, I want a "Debug mode" toggle in Settings that enables diagnostic overlays and the Debug window.

**Acceptance Criteria:**
- [ ] `SettingsManager` gains a `debugMode` property backed by UserDefaults (default: false)
- [ ] `SettingsView` shows the Debug mode toggle in a "Developer" section of the form
- [ ] Debug mode state persists across app launches
- [ ] When debug mode is off, all debug UI elements are hidden
- [ ] Typecheck passes

---

### US-030: Debug Window
**Description:** As a developer, I want a Debug window (Window > Debug Info) that shows live internal state so I can inspect the app while it runs.

**Acceptance Criteria:**
- [ ] `DebugWindowView` displays: loop state per PRD tab, engine iteration count per tab, file watcher watched directories, active Claude process PIDs, last error message per tab, app memory usage (resident size)
- [ ] Window > Debug Info menu item opens the debug window (enabled only when debug mode is on)
- [ ] Debug window updates in real-time as state changes (uses @Observable bindings)
- [ ] Debug window does not affect main window behavior or performance
- [ ] Typecheck passes

---

### US-031: Debug Status Bar Expansion
**Description:** As a developer, I want the status bar to show additional internal state when debug mode is enabled.

**Acceptance Criteria:**
- [ ] When debug mode is on, `StatusBarView` shows an additional line below the activity message
- [ ] Debug line includes: loop state enum raw value, current story ID (or "none"), engine retry count, elapsed time for current iteration
- [ ] When debug mode is off, the extra line is hidden
- [ ] Typecheck passes

---

### US-032: os_log Integration
**Description:** As a developer, I want structured logging via os_log so I can filter and inspect events in Console.app.

**Acceptance Criteria:**
- [ ] `Logger` instances created with subsystem `com.amattn.ridler` and categories: "loop", "prd", "process", "git"
- [ ] All errors logged at `.error` level, state transitions at `.info`, verbose details at `.debug`
- [ ] Log messages include structured metadata: PRD name, story ID, iteration number where applicable
- [ ] Logs are visible and filterable in Console.app by subsystem and category
- [ ] Typecheck passes

---

## Functional Requirements

- FR-1: Open existing PRDs via file picker, drag-and-drop, or Open Recent with error alerts on failure
- FR-2: Multi-tab PRD management with independent loop state per tab
- FR-3: Create new PRDs with name validation and directory picker
- FR-4: Edit PRDs by launching Claude Code interactively in Terminal
- FR-5: Close tabs (with running-loop confirmation) and delete PRDs from disk
- FR-6: Ralph Wiggum loop: read state → select next story → build prompt → invoke Claude Code → stream output → check completion → repeat
- FR-7: Each Claude invocation is a fresh subprocess with streaming JSON output
- FR-8: Six-state loop state machine: Ready, Running, Paused, Stopped, Complete, Error
- FR-9: Protected branch detection with warning dialog before starting loops
- FR-10: One git commit per completed story with format `feat: [US-001] - Story Title`
- FR-11: Auto-retry on Claude Code crashes with progressive backoff
- FR-12: Audio and macOS notifications on PRD completion
- FR-13: Settings window for app-wide preferences
- FR-14: Full keyboard shortcuts and menu bar
- FR-15: Syntax highlighting in log view
- FR-16: File watcher for auto-reload on external changes
- FR-17: JSON decoding resilient to missing `passes` and `inProgress` fields
- FR-18: Descriptive error messages with file name, key, and JSON path for decoding failures
- FR-19: Copy-to-clipboard on error alerts
- FR-20: Debug mode with dedicated Debug window showing live internal state
- FR-21: Structured logging via os_log with Console.app filtering

## Non-Goals (Out of Scope)

- Remote execution via SSH — local-only is the permanent design
- Built-in PRD text editor — editing is done via Claude Code sessions
- App Sandbox — not required
- Mac App Store distribution (for now — open question)
- Intel Mac support — Apple Silicon only
- Fixed project directory structure — PRDs can live anywhere

## Technical Considerations

- **Platform:** macOS 14.0+ (Sonoma), Apple Silicon only
- **Language:** Swift / SwiftUI
- **Process management:** Foundation `Process` for spawning Claude Code CLI
- **JSON streaming:** Line-by-line parsing of Claude's `stream-json` output via `JSONDecoder`
- **File watching:** FSEvents / DispatchSource for monitoring each opened PRD's directory
- **Git operations:** Shell out to `git` CLI via `Process`
- **Audio:** AVFoundation `AVAudioPlayer` for completion sounds
- **Notifications:** UserNotifications framework for macOS notification center
- **Persistence:** FileManager + Codable for PRD JSON/Markdown read/write; UserDefaults for app-wide preferences
- **Protocols:** `ProcessSpawning`, `GitOperating`, `FileWatcherDelegate` for dependency injection and test mocking
- **Error types:** All conform to `LocalizedError` with human-readable `errorDescription` values
- **Logging:** `os_log` with subsystem `com.amattn.ridler` and per-component categories
- **Test target:** Hosted tests via BUNDLE_LOADER/TEST_HOST in Ridler.app, using `-scheme Ridler` with `test` action
- **No database needed** — all state is file-based

## Success Metrics

- Feature parity with original Chief CLI: 100% of core features
- App crash rate: < 0.1% of sessions
- Loop reliability: > 95% of stories complete without manual intervention
- Cold start to ready state: < 2 seconds
- Log streaming latency: < 100 ms from Claude output to displayed entry
