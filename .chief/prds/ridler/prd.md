# Ridler — Native macOS Autonomous PRD Agent

## Overview

Ridler is a native macOS SwiftUI application (macOS 14+, Apple Silicon only) that transforms Product Requirements Documents into working code by orchestrating Claude Code in an autonomous loop. It is a feature-complete native equivalent of [minicodemonkey/chief](https://github.com/minicodemonkey/chief), replacing the terminal-based Bubble Tea TUI with a native SwiftUI interface.

The app reads PRDs (markdown + JSON), breaks them into user stories, and executes them sequentially through fresh Claude Code sessions — the "Ralph Wiggum loop" pattern. Each iteration starts with a clean context window while persisting progress between runs via a `progress.md` file. Prompt templates use the Liquid templating format and are stored per-project in the `ridl/` folder, allowing customization without code changes.

**Key Design Principles:** Native-first SwiftUI, feature parity with Chief CLI, zero configuration (PRD state lives alongside PRD files), non-blocking parallel execution, transparent real-time streaming.

**Platform:** macOS 14.0+ (Sonoma), Apple Silicon only, Swift/SwiftUI.

## User Stories

---

### Milestone: v0.1 — PRD Management & Tab Bar

---

### US-001: Create Xcode project with SwiftUI app target
**Priority:** 1
**Description:** As a developer, I want a properly configured Xcode project so that I can build Ridler as a native macOS application.

**Acceptance Criteria:**
- [ ] Xcode project created with SwiftUI lifecycle for macOS
- [ ] Deployment target set to macOS 14.0 (Sonoma)
- [ ] Architecture restricted to Apple Silicon (arm64)
- [ ] App builds and launches showing an empty window
- [ ] Bundle identifier and app name set to "Ridler"
- [ ] Project organized into groups: Models, Views, ViewModels, Managers, Protocols

---

### US-002: Define core data models
**Priority:** 2
**Description:** As a developer, I want well-defined data models so that the app can represent PRDs, user stories, and loop state throughout the codebase.

**Acceptance Criteria:**
- [ ] `PRDProject` model representing an opened PRD with: directory URL, name, list of user stories, loop state, iteration count
- [ ] `UserStory` model with fields: id (string, e.g. "US-001"), title, description, priority (Int), acceptanceCriteria ([String]), passes (Bool, default false), inProgress (Bool, default false)
- [ ] `LoopState` enum with cases: ready, running, paused, stopped, complete, error
- [ ] `Milestone` model with name and list of story IDs
- [ ] All models conform to `Codable` for JSON serialization
- [ ] JSON decoding is resilient: `passes` defaults to `false` and `inProgress` defaults to `false` when omitted
- [ ] Error types conform to `LocalizedError` with human-readable `errorDescription`
- [ ] Unit tests verify round-trip JSON encoding/decoding including missing optional fields

---

### US-003: Parse PRD files (prd.md, ridl.md, ridl.json)
**Priority:** 3
**Description:** As a developer, I want to read and parse the three-file PRD format so that the app can load PRD data from disk.

**Acceptance Criteria:**
- [ ] `PRDStore` protocol defines read/write interface for PRD files
- [ ] Reads `ridl.json` and decodes into `PRDProject` with user stories
- [ ] Reads `prd.md` and `ridl.md` as raw markdown strings
- [ ] Supports the `ridl/` folder convention: all PRD files stored together in a directory
- [ ] When given a folder, looks for `prd.md` inside it
- [ ] `ridl.md` and `ridl.json` are optional companion files (may not exist yet)
- [ ] JSON decoding errors include file name, problematic key, and JSON path (e.g., `ridl.json: missing required key "title" in userStories.0`)
- [ ] File-not-found errors include the full path searched and filenames tried
- [ ] Unit tests for: valid JSON, missing optional fields, malformed JSON, missing files

---

### US-004: Write PRD state updates to ridl.json
**Priority:** 4
**Description:** As a developer, I want to write updated story state back to ridl.json so that progress persists on disk.

**Acceptance Criteria:**
- [ ] `PRDStore` can write updated `ridl.json` with modified story states
- [ ] Writing preserves all existing fields (no data loss on round-trip)
- [ ] Concurrent read/write is safe (no file corruption)
- [ ] Pretty-printed JSON output for human readability
- [ ] Unit tests verify round-trip: read → modify passes/inProgress → write → read

---

### US-005: App window with three-pane layout
**Priority:** 5
**Description:** As a user, I want a three-pane window layout so that I can see my PRD files, story details, and logs simultaneously.

**Acceptance Criteria:**
- [ ] Main window uses NavigationSplitView or equivalent three-column layout
- [ ] Left pane: file browser + stories list (sidebar)
- [ ] Middle pane: story detail or file content
- [ ] Right pane: log view or Claude terminal
- [ ] Window resizes properly with panes adjusting
- [ ] Sidebar collapses automatically on narrow windows

---

### US-006: Empty state view
**Priority:** 6
**Description:** As a new user launching Ridler for the first time, I want to see clear instructions so that I know how to get started.

**Acceptance Criteria:**
- [ ] On launch with no previously opened PRDs, show an empty state
- [ ] Empty state displays "Open PRD..." and "New PRD..." buttons
- [ ] Clicking "Open PRD..." triggers File > Open flow
- [ ] Clicking "New PRD..." triggers File > New flow
- [ ] When no PRD is loaded, middle pane shows instructions to create or open a project

---

### US-007: Open existing PRD via File > Open
**Priority:** 7
**Description:** As a user, I want to open an existing PRD from anywhere on disk so that I can view and manage it in Ridler.

**Acceptance Criteria:**
- [ ] File > Open (`Cmd+O`) presents a file/folder picker
- [ ] Picker accepts a `ridl/` folder or a `.md` file at any location on disk
- [ ] When a folder is selected, the app looks for `prd.md` inside it
- [ ] If the selected file cannot be read (invalid JSON, decoding error), display a native alert with a descriptive error message
- [ ] Opened PRD appears as a tab in the interface
- [ ] Multiple PRDs from different locations can be open simultaneously

---

### US-008: Create new PRD via File > New
**Priority:** 8
**Description:** As a user, I want to create a new PRD so that I can start a new project from scratch.

**Acceptance Criteria:**
- [ ] File > New (`Cmd+N`) prompts for a PRD name and a parent directory
- [ ] PRD name validation: allows letters, numbers, `-`, `_`
- [ ] Creates a `ridl/` folder in the chosen parent directory containing an empty `prd.md` file
- [ ] Opens the new PRD as a tab in the interface

---

### US-009: PRD tab bar with state indicators
**Priority:** 9
**Description:** As a user, I want a tab bar showing all opened PRDs so that I can switch between them and see their status at a glance.

**Acceptance Criteria:**
- [ ] Horizontal tab bar displayed above the toolbar showing all opened PRDs
- [ ] Each tab shows: PRD name and state indicator icon (dot for active, play icon + iteration count for running, pause icon for paused, checkmark for complete, X for error, square for stopped)
- [ ] Clicking a tab switches the view to that PRD without affecting other running loops
- [ ] A `[+]` button at the end opens a menu with "Open PRD..." and "New PRD..." options
- [ ] Close tab removes PRD from interface but does not delete files on disk

---

### US-010: PRD file browser in left pane
**Priority:** 10
**Description:** As a user, I want to see the PRD's constituent files so that I can view their contents.

**Acceptance Criteria:**
- [ ] Three selectable file rows above the stories list: `prd.md`, `ridl.md`, `ridl.json`, under a collapsible "PRD Files" header
- [ ] Clicking the header toggles the group open/closed; expanded by default
- [ ] Each row shows a file-type icon and filename
- [ ] Selecting a file row deselects the currently selected story (mutual exclusion)
- [ ] If `ridl.md` or `ridl.json` does not exist on disk, the row is visually distinguished (dimmed or "(not yet created)" note)
- [ ] Below the PRD files, a collapsible "Prompt Templates" header lists `.liquid` files from `ridl/prompts/` (e.g., `prompt.liquid`, `story.liquid`, `progress_report.liquid`)
- [ ] Prompt template rows show a template icon and filename; if `ridl/prompts/` does not exist yet, the section shows "(defaults — run once to generate)"
- [ ] Selecting a prompt template file shows its content in the middle pane (same behavior as PRD files)
- [ ] A visual divider separates file rows from the stories list below
- [ ] File rows remain visible and selectable regardless of loop state

---

### US-011: Stories list in left pane
**Priority:** 11
**Description:** As a user, I want to see all user stories for a PRD so that I can track progress and select stories to view.

**Acceptance Criteria:**
- [ ] Scrollable list of all user stories for the selected PRD
- [ ] Each row shows: status icon (checkmark passed, dot in-progress, circle pending), story ID, and title
- [ ] Highlight the currently selected story
- [ ] Progress bar at the bottom: filled portion, percentage, and count (e.g., `2/4 stories`)
- [ ] Clicking a story selects it and shows its detail in the middle pane
- [ ] If PRD defines milestones, group stories under collapsible milestone headers with summary (e.g., `3/5 stories`)
- [ ] Milestone header displays the milestone **name** (short ID, e.g., "v0.1"), not the theme
- [ ] If the milestone has a theme, display it as a secondary label above the first iteration definition inside the collapsible area (collapses together with the stories)
- [ ] If no milestones, display as flat list

---

### US-012: Story detail panel in middle pane
**Priority:** 12
**Description:** As a user, I want to see full details of a selected story so that I understand what needs to be implemented.

**Acceptance Criteria:**
- [ ] Display the selected story's title in bold
- [ ] Display status badge and priority number
- [ ] Display the full description with word wrapping
- [ ] Display acceptance criteria as a bulleted list
- [ ] When an error occurs, show error details and a tip to check `claude.log`

---

### US-013: File content view in middle pane
**Priority:** 13
**Description:** As a user, I want to view PRD file contents when a file row is selected so that I can review the PRD without leaving the app.

**Acceptance Criteria:**
- [ ] When a PRD file row is selected (instead of a story), the middle pane displays the file's content
- [ ] Rendered markdown for `.md` files
- [ ] Formatted/pretty-printed JSON for `.json` files
- [ ] If the selected file does not yet exist on disk, the middle pane shows empty content
- [ ] File content displayed is read-only (no inline editing)

---

### US-014: File watcher for external PRD changes
**Priority:** 14
**Description:** As a user, I want the app to detect when PRD files change externally so that the UI stays up to date.

**Acceptance Criteria:**
- [ ] Watch each opened PRD's directory for filesystem changes using FSEvents or DispatchSource
- [ ] Auto-reload PRD data when files change externally
- [ ] Detection latency < 1 second
- [ ] File changes refresh the displayed content in the middle pane
- [ ] Missing file indicators update when files are created or deleted externally

---

### US-015: Error alerts with descriptive messages
**Priority:** 15
**Description:** As a user or developer debugging issues, I want clear, specific error messages so that I can understand and fix problems quickly.

**Acceptance Criteria:**
- [ ] All user-facing errors displayed in native alert dialog with clear, specific message (never silently swallowed)
- [ ] Error alerts include a "Copy" button that copies the full error message to clipboard
- [ ] JSON decoding errors identify: file name, problematic key/field, and JSON path
- [ ] File-not-found errors include: full path searched and filenames tried
- [ ] Error types conform to `LocalizedError` with human-readable `errorDescription`

---

### Milestone: v0.2 — Core Loop & Minimal UI

---

### US-016: Loop state machine
**Priority:** 16
**Description:** As a developer, I want a well-defined state machine for the execution loop so that state transitions are predictable and correct.

**Acceptance Criteria:**
- [ ] Support six loop states: Ready, Running, Paused, Stopped, Complete, Error
- [ ] Valid transitions: Ready→Running, Running→Paused, Running→Stopped, Running→Complete, Running→Error, Paused→Running, Stopped→Running, Error→Running
- [ ] Running→Paused: loop finishes current iteration then pauses
- [ ] Running→Stopped: loop halts immediately
- [ ] Running→Complete: all stories pass
- [ ] Running→Error: Claude Code fails after retry exhaustion
- [ ] Display current state with color-coded badge: Ready (gray), Running (cyan), Paused (yellow), Stopped (gray), Complete (green), Error (red)
- [ ] "Pause after story" mode: when enabled, auto-transitions Running→Paused after a story completes
- [ ] "Pause after milestone" mode: when enabled, auto-transitions Running→Paused after the last story in a milestone completes (only applies when PRD defines milestones)
- [ ] Unit tests for all valid state transitions and rejection of invalid transitions

---

### US-017: Toolbar with loop controls
**Priority:** 17
**Description:** As a user, I want Start/Pause/Stop controls so that I can manage the execution loop.

**Acceptance Criteria:**
- [ ] Toolbar displays Start/Pause/Stop buttons
- [ ] Buttons are enabled/disabled based on current loop state
- [ ] Show iteration counter: current iteration / max iterations
- [ ] Show elapsed time since loop started (format: `Xh Ym Zs`)
- [ ] Show color-coded state badge
- [ ] "Pause after story" toggle (checkbox or switch), default off
- [ ] "Pause after milestone" toggle (checkbox) to the right of "Pause after story", default off; only effective when PRD defines milestones

---

### US-018: Claude Code process manager
**Priority:** 18
**Description:** As a developer, I want a process manager that spawns and controls Claude Code subprocesses so that the loop engine can execute stories.

**Acceptance Criteria:**
- [ ] `ProcessManaging` protocol defines interface for spawning, streaming, and killing processes
- [ ] Spawn Claude Code as subprocess with `--dangerously-skip-permissions --output-format stream-json` flags
- [ ] Stream stdout line-by-line in real-time
- [ ] Capture stderr for error reporting
- [ ] Kill the subprocess cleanly when Stop is pressed
- [ ] No zombie processes left behind on app quit or process termination
- [ ] Process errors include: exit code, stderr output, and the command that was run
- [ ] Capture full raw stdout/stderr to per-PRD `claude.log` file

---

### US-019: Streaming JSON parser
**Priority:** 19
**Description:** As a developer, I want to parse Claude Code's streaming JSON output so that I can display structured log entries in real-time.

**Acceptance Criteria:**
- [ ] Parse Claude's `stream-json` output line-by-line
- [ ] Identify message types: assistant text, tool_use, tool_result, error
- [ ] Create structured log entries from parsed messages
- [ ] Handle malformed JSON lines gracefully (log warning, don't crash)
- [ ] Handle partial reads and buffer boundaries correctly
- [ ] Detect the `<ridler-complete/>` signal in Claude's output
- [ ] Streaming latency < 100ms from Claude output to parsed entry
- [ ] Parse all Claude Code `stream-json` message variants correctly: nested `message.content[]` arrays (text, tool_use, tool_result), `type="user"` messages with tool results (string, array, `is_error` with XML stripped), `type="system"` with `subtype="init"` (extract model/cwd/version), and agent sub-prompts (user text blocks with `parent_tool_use_id`). Both flat and nested formats must produce human-readable log entries
- [ ] Store the raw JSON line on each parsed `LogEntry` (`rawJSON: String?`, nil for system-generated entries) for verbose/debug display
- [ ] Unit tests with captured real Claude output and malformed JSON

---

### US-020: Log view with streaming output
**Priority:** 20
**Description:** As a user, I want to see Claude's real-time output so that I can monitor what the agent is doing.

**Acceptance Criteria:**
- [ ] Log panel always visible alongside the story detail panel (right pane)
- [ ] Display parsed log entries: assistant text, tool calls, tool results, errors
- [ ] Tool call entries show icons per tool type (Read, Edit, Write, Bash, etc.)
- [ ] Auto-scroll to follow new output while loop is running
- [ ] Manual scrolling: disable auto-scroll when user scrolls up, re-enable when user scrolls to bottom
- [ ] Show story transition events, iteration starts, completion messages in the log
- [ ] Persist all log entries to `ridler.log` as newline-delimited JSON (NDJSON). Claude Code output lines have `ridler_story_id` and `ridler_timestamp` injected. System-generated entries serialized with `ridler_type: "system"`. The `ridler_` prefix avoids conflicts with Claude Code's own fields
- [ ] On PRD open, load existing log entries from `ridler.log` on a background thread without blocking the main UI thread
- [ ] When "Verbose log" setting is enabled and a log entry has `rawJSON`, display a collapsible "Raw JSON" disclosure below the parsed content
- [ ] While log entries are loading from disk, show a `ProgressView("Loading logs...")` in the log panel
- [ ] Log entries longer than 20 lines are collapsed by default with a disclosure triangle; when collapsed, show the first 5 lines with a muted "(N more lines)" indicator
- [ ] Prompt log entries (engine prompts starting with "Prompt:" and agent prompts starting with "[agent prompt]") are styled with an orange icon, orange text, and a light orange background

---

### US-021: Ralph loop engine
**Priority:** 21
**Description:** As a user, I want the autonomous execution engine so that stories are executed sequentially through Claude Code without manual intervention.

**Acceptance Criteria:**
- [ ] Execute the Ralph Wiggum loop: read state → select next story → build prompt → invoke Claude Code → stream output → check completion → repeat
- [ ] Select next story by filtering `passes: false`, sorting by `priority` ascending, picking the first
- [ ] Build prompt by rendering Liquid templates from the `ridl/` folder with story and project context (see US-045)
- [ ] Each iteration invokes Claude Code as a fresh subprocess
- [ ] On story completion, set `passes: true` and `inProgress: false` in `ridl.json`
- [ ] On all stories complete, transition to Complete state and play audio notification
- [ ] Support configurable max iterations per PRD (default: remaining stories + 5, minimum 5)
- [ ] Detect `<ridler-complete/>` signal to exit loop early

---

### US-022: Progress.md updates after each iteration
**Priority:** 22
**Description:** As a developer or agent, I want implementation details appended to progress.md so that subsequent iterations have context about what was already done.

**Acceptance Criteria:**
- [ ] After each iteration, append implementation details, file changes, and learnings to `progress.md`
- [ ] `progress.md` is stored alongside the other PRD files in the `ridl/` directory
- [ ] Content is human-readable and provides useful context for subsequent Claude Code sessions

---

### US-023: Protected branch detection and warning
**Priority:** 23
**Description:** As a user, I want the app to warn me before running on a protected branch so that I don't accidentally commit to main/master.

**Acceptance Criteria:**
- [ ] Detect if the project is on a protected branch (main/master) before starting a loop
- [ ] Show a warning dialog with three options: create a `ridler/{prd-name}` branch (recommended), continue on current branch, or cancel
- [ ] Allow editing the suggested branch name in the dialog
- [ ] `GitManaging` protocol defines interface for git operations (enables test mocking)
- [ ] Git errors include the git command that failed and its stderr output
- [ ] Integration tests with real git repos for branch detection

---

### US-024: Git commit per completed story
**Priority:** 24
**Description:** As a user, I want one git commit per completed story so that I have a clean, traceable git history.

**Acceptance Criteria:**
- [ ] Create one commit per completed story
- [ ] Commit message format: `feat: [US-001] - Story Title`
- [ ] Commit is created after story passes and ridl.json is updated
- [ ] Git errors are reported clearly with the failed command and stderr

---

### US-025: Status bar
**Priority:** 25
**Description:** As a user, I want a status bar showing the current activity so that I know what the app is doing.

**Acceptance Criteria:**
- [ ] Status bar at the bottom of the window
- [ ] Display the last activity message (e.g., "Working on: US-002 - Add login endpoint")
- [ ] Color the activity message based on current state (cyan for running, yellow for paused, red for error)

---

### Milestone: v0.3 — Parallel Execution & Polish

---

### US-026: Parallel PRD execution
**Priority:** 26
**Description:** As a power user, I want to run multiple PRDs simultaneously so that I can work on several features in parallel.

**Acceptance Criteria:**
- [ ] Support running multiple PRDs simultaneously, each with independent loop state, iteration count, timing, and error tracking
- [ ] Switching between PRDs in the UI only changes the view — does not stop other running loops
- [ ] Loop controls (start, pause, stop) apply to the currently viewed PRD
- [ ] Display real-time state indicators for all PRDs in the tab bar
- [ ] No race conditions or state corruption between parallel loops
- [ ] Concurrent execution tests with 3+ PRDs verifying independent state isolation

---

### US-027: Runtime iteration adjustment
**Priority:** 27
**Description:** As a user, I want to adjust the max iteration count while a loop is running so that I can extend or shorten execution without restarting.

**Acceptance Criteria:**
- [ ] +/- stepper control in toolbar to adjust max iterations at runtime
- [ ] Adjustments take effect immediately on the current loop
- [ ] Step size: +5 / -5

---

### US-028: Auto-retry on Claude Code crashes
**Priority:** 28
**Description:** As a user, I want the app to automatically retry when Claude Code crashes so that transient failures don't stop my progress.

**Acceptance Criteria:**
- [ ] Auto-retry on Claude Code crashes with backoff
- [ ] Configurable: can be enabled/disabled in Settings (default: off)
- [ ] After retry exhaustion, transition to Error state
- [ ] Retry events shown in the log view

---

### US-029: Audio notification on completion
**Priority:** 29
**Description:** As a user, I want an audio notification when a PRD completes so that I know when to come back and review.

**Acceptance Criteria:**
- [ ] Play audio notification when a PRD reaches Complete state
- [ ] Use AVFoundation `AVAudioPlayer` for playback
- [ ] Option to disable audio notifications in Settings (default: on)

---

### US-030: macOS notification on completion
**Priority:** 30
**Description:** As a user, I want a macOS notification when a PRD completes and the app is in the background so that I don't miss completions.

**Acceptance Criteria:**
- [ ] Post a macOS notification when a PRD completes and the app is not frontmost
- [ ] Use UserNotifications framework
- [ ] Notification includes the PRD name

---

### US-031: Syntax highlighting in log view
**Priority:** 31
**Description:** As a user, I want syntax highlighting in code blocks shown in the log so that code is easier to read.

**Acceptance Criteria:**
- [ ] Apply syntax highlighting to code blocks in Claude's output in the log view
- [ ] Support common languages (Swift, TypeScript, Python, etc.)

---

### US-032: Interrupted story detection and warning
**Priority:** 32
**Description:** As a user, I want to be warned about stories that were in progress when the app was interrupted so that I know to review them before continuing.

**Acceptance Criteria:**
- [ ] Show a yellow warning banner in the stories panel if a story has `inProgress: true` from a previously interrupted session
- [ ] Warning is visible when the PRD is loaded/reopened
- [ ] User can acknowledge the warning and resume the loop

---

### US-045: Liquid prompt templates stored per project
**Priority:** 45
**Description:** As a developer or power user, I want agent prompt templates stored as Liquid files in each project's `ridl/` folder so that I can customize agent behavior per project without modifying app code.

**Acceptance Criteria:**
- [ ] Add a Swift Liquid templating library as a dependency (e.g., [nicklama/Liqid](https://github.com/nicklama/Liqid) or equivalent)
- [ ] Default prompt templates bundled in the app as resources:
  - **Agent loop templates** (used by `RalphLoopEngine.buildPrompt`):
    - `agent_instructions.liquid` — main agent instructions (task steps, quality requirements, stop condition)
    - `story_context.liquid` — target story details (ID, title, description, acceptance criteria, PRD references, universal context)
    - `progress_report.liquid` — progress.md append format
  - **Interactive editing templates** (used by `ClaudeTerminalManager`):
    - `edit_file.liquid` — prompt for editing an existing PRD or template file
    - `create_file.liquid` — prompt for creating a missing file; uses `{% if %}` branches on `file_name` to provide file-specific instructions (e.g., `ridl.md` reads from `prd.md`, `ridl.json` reads from `ridl.md` or `prd.md`, all others get generic instructions)
- [ ] On first loop start for a project, if no templates exist in `ridl/prompts/`, create the directory and copy the bundled defaults there
- [ ] `buildPrompt(for:project:)` reads `.liquid` files from the project's `ridl/prompts/` folder and renders them with a context dictionary containing:
  - `story.id`, `story.title`, `story.description`, `story.priority`, `story.acceptance_criteria`
  - `story.prd_references` (optional)
  - `project.universal_context.non_functional_requirements` (optional)
  - `project.universal_context.developer_experience` (optional)
  - `project.universal_context.technical_architecture` (optional)
  - `progress_content` (contents of `progress.md` if it exists)
  - `file_path`, `file_name`, `file_exists` (for interactive editing templates)
- [ ] If a template file is missing, copy the bundled default into `ridl/prompts/` before rendering
- [ ] If a template fails to parse: display an inline error banner above the template preview in the middle pane showing the file name, line number, and parse error message; show a red error icon next to the template filename in the sidebar; transition loop to Error state and prevent running until the template is fixed
- [ ] Templates support standard Liquid features: variables (`{{ story.id }}`), conditionals (`{% if %}` / `{% endif %}`), loops (`{% for %}` / `{% endfor %}`), filters
- [ ] Existing hardcoded prompt strings in `RalphLoopEngine.buildPrompt` are removed and replaced by template rendering
- [ ] Existing hardcoded prompt strings in `ClaudeTerminalManager.start` are removed and replaced by template rendering
- [ ] Unit tests: render default templates with mock story/project data and verify output matches expected prompt structure
- [ ] Unit tests: custom templates in `ridl/prompts/` folder are used instead of bundled defaults
- [ ] Unit tests: malformed template produces a clear error and prevents loop start
- [ ] Each template render emits log entries visible in the log panel (right pane) and persisted to `ridler.log`, listing the template names and path, a summary of the context keys and values, and the rendered output size

---

### Milestone: v0.4 — Release Ready

---

### US-033: Keyboard shortcuts
**Priority:** 33
**Description:** As a power user, I want keyboard shortcuts for common actions so that I can work efficiently without the mouse.

**Acceptance Criteria:**
- [ ] `Cmd+N` — Create new PRD
- [ ] `Cmd+O` — Open existing PRD
- [ ] `Cmd+R` or `Cmd+Return` — Start/Resume loop for current PRD
- [ ] `Cmd+.` — Pause loop
- [ ] `Cmd+Shift+.` — Stop loop
- [ ] `Cmd+1` through `Cmd+9` — Switch to PRD by tab position
- [ ] `Cmd+L` — Focus Log Panel
- [ ] `Cmd+E` — Edit current PRD (launch Claude Code)

---

### US-034: Full macOS menu bar
**Priority:** 34
**Description:** As a macOS user, I want a standard menu bar so that the app follows platform conventions and all actions are discoverable.

**Acceptance Criteria:**
- [ ] Standard macOS menu bar with File, Edit, View, PRD, Window, Help menus
- [ ] All keyboard shortcuts reflected in menu items
- [ ] Menu items enabled/disabled based on current state

---

### US-035: Open Recent PRDs
**Priority:** 35
**Description:** As a returning user, I want to quickly reopen recently used PRDs so that I don't have to navigate to them every time.

**Acceptance Criteria:**
- [ ] Remember recently opened PRDs
- [ ] Display them in File > Open Recent submenu
- [ ] Persisted across app launches via UserDefaults

---

### US-036: Tab context menus
**Priority:** 36
**Description:** As a user, I want right-click context menus on PRD tabs so that I can quickly access common actions.

**Acceptance Criteria:**
- [ ] Right-click on a tab shows context menu: Start, Pause, Stop, Edit, Close, Delete
- [ ] Menu items enabled/disabled based on the tab's current loop state

---

### US-037: Settings window
**Priority:** 37
**Description:** As a user, I want a Settings window so that I can configure app-wide preferences.

**Acceptance Criteria:**
- [ ] Standard macOS Settings window accessible via `Cmd+,`
- [ ] Audio notifications toggle (default: on)
- [ ] Auto-retry on crash toggle (default: off)
- [ ] Verbose log toggle (default: off) — show raw Claude JSON in log view
- [ ] Debug mode toggle (default: off)
- [ ] Claude Config Dir setting (directory path, default empty/system default) — custom `CLAUDE_CONFIG_DIR` path passed to Claude Code subprocesses; validated on save
- [ ] Settings persisted via UserDefaults

---

### US-038: Debug mode and Debug window
**Priority:** 38
**Description:** As a developer, I want a debug mode with a dedicated Debug window so that I can inspect internal state when troubleshooting.

**Acceptance Criteria:**
- [ ] When Debug mode is enabled in Settings, Window > Debug Info opens a Debug window
- [ ] Debug window shows: current loop state per PRD, engine iteration count, file watcher status, active process PIDs, last error per tab, memory usage
- [ ] In debug mode, status bar expands to show: loop state enum value, current story ID, retry count, elapsed time per iteration
- [ ] Debug mode state persisted across launches via UserDefaults

---

### US-039: os_log integration
**Priority:** 39
**Description:** As a developer, I want structured logging via os_log so that I can filter and diagnose issues using Console.app.

**Acceptance Criteria:**
- [ ] All errors, state transitions, and significant events logged via `os_log`
- [ ] Appropriate log levels: `.error`, `.info`, `.debug`
- [ ] Log messages include structured metadata: PRD name, story ID, iteration number
- [ ] Logs filterable in Console.app by subsystem and category

---

### US-040: Claude Code terminal for PRD and template editing
**Priority:** 40
**Description:** As a user, I want to edit PRD files and prompt templates via an interactive Claude Code session so that I can author and modify project configuration without leaving Ridler.

**Acceptance Criteria:**
- [ ] When a PRD file row or prompt template row is selected in the sidebar, right pane switches to an interactive Claude Code terminal
- [ ] If the file exists, Claude is launched with the file path as context
- [ ] If the file does not exist, Claude is launched with a prompt to create it (e.g., "Create ridl.md from the existing prd.md")
- [ ] For prompt templates, Claude is launched with the template file path and knowledge of available Liquid variables (story, project, progress_content)
- [ ] While the Ralph loop is running, the Claude terminal pane is disabled with message: "Pause the loop to edit this file"
- [ ] Switching back to a story row reverts the right pane to log view
- [ ] If a Claude session is active and user starts the loop, the session is terminated (with confirmation dialog if mid-conversation)

---

### US-041: Delete PRD files
**Priority:** 41
**Description:** As a user, I want to delete a PRD's files from disk so that I can clean up projects I no longer need.

**Acceptance Criteria:**
- [ ] Delete option available in UI (tab context menu or PRD menu)
- [ ] Confirmation dialog before deleting files on disk
- [ ] Deletes the PRD's `ridl/` folder and all contents
- [ ] Removes the tab from the interface after deletion

---

### US-042: Drag-and-drop to open PRD
**Priority:** 42
**Description:** As a user, I want to drag a PRD folder onto the app to open it so that I have a quick way to load projects.

**Acceptance Criteria:**
- [ ] Drag-and-drop a `ridl/` folder or `.md` file onto the app icon to open it as a tab
- [ ] Show an error alert if the drop target cannot be loaded
- [ ] Works with Finder drag-and-drop

---

### US-043: Auto-scroll indicator in log view
**Priority:** 43
**Description:** As a user, I want to know whether the log is auto-scrolling or in manual mode so that I understand the scrolling behavior.

**Acceptance Criteria:**
- [ ] Show a visual indicator for auto-scroll vs. manual-scroll mode
- [ ] Indicator updates in real-time as user scrolls

---

### US-044: App icon and distribution
**Priority:** 44
**Description:** As a user, I want a polished app icon and easy installation so that Ridler feels like a professional macOS application.

**Acceptance Criteria:**
- [ ] Custom app icon designed for Ridler
- [ ] App notarized for macOS distribution
- [ ] DMG installer for distribution
