# Product Requirements Document: Ridler

## Native macOS Autonomous PRD Agent

**Version:** 2.0
**Date:** 2026-03-06
**Platform:** macOS 14.0+ (Sonoma and later), Apple Silicon only
**Language:** Swift / SwiftUI

---

## 1. Overview

Ridler is a native macOS application that transforms Product Requirements Documents into working code by orchestrating Claude Code in an autonomous loop. It is a feature-complete native equivalent of [minicodemonkey/chief](https://github.com/minicodemonkey/chief), replacing the terminal-based Bubble Tea TUI with a native SwiftUI interface.

The app reads PRDs (markdown + JSON), breaks them into iteration definitions, and executes them sequentially through fresh Claude Code sessions — the "Ralph Wiggum loop" pattern. Each iteration starts with a clean context window while persisting progress between runs via three runtime files (`progress.md`, `learnings.md`, `emergent.md`), preventing context overflow while maintaining project continuity.

### 1.1 Design Principles

- **Native-first:** Full SwiftUI interface with proper macOS conventions (menu bar, keyboard shortcuts, window management, drag-and-drop).
- **Feature parity:** Every capability of the original Chief CLI is present — parallel PRD execution, log streaming, protected branch detection, audio notifications.
- **Zero configuration:** No global config files. PRD state lives alongside the PRD files wherever the user stores them. App-wide preferences stored in the app's container.
- **Non-blocking:** Multiple PRDs can run simultaneously with independent loop state. The UI stays responsive during long-running iterations.
- **Transparent:** Real-time streaming of Claude's output with syntax highlighting. Every action is visible and controllable.

---

## 2. User Personas

| Persona | Description | Key Need |
|---------|-------------|----------|
| **Solo Developer** | Indie dev building side projects with Claude | Hands-off execution of well-defined features; watch progress or walk away |
| **Tech Lead** | Manages a team and uses Claude to prototype features | Run multiple PRDs in parallel, review clean git history of commits per iteration definition |
| **AI-Assisted Developer** | Uses Claude daily but hits context limits on large tasks | Break large features into agent-sized iteration definitions that execute reliably without context overflow |
| **Non-Terminal User** | Developer who prefers GUI tools over CLI workflows | Native Mac app with familiar UI patterns instead of terminal commands |

---

## 3. Functional Requirements

### 3.1 PRD Management

| ID | Requirement | Priority |
|----|-------------|----------|
| PM-1 | Open an existing PRD via File > Open (`⌘O`), which presents a picker that accepts a `ridl/` folder or a `.md` file at any location on disk. When a folder is selected, the app looks for `prd.md` inside it. Companion files (`ridl.md`, `ridl.json`) are optional and may not exist yet. If the selected file itself cannot be read (invalid JSON, decoding error), display a native alert with a descriptive error message instead of failing silently | P0 |
| PM-2 | Each opened PRD becomes a tab in the interface; multiple PRDs from different locations can be open simultaneously | P0 |
| PM-3 | Create a new PRD via File > New (`⌘N`), which prompts the user to choose a parent directory and PRD name, then creates a `ridl/` folder there containing an empty `prd.md` file, and opens it as a tab | P0 |
| PM-4 | Edit an existing PRD by clicking an "Edit PRD" button in the UI, which launches Claude Code with the PRD context loaded | P0 |
| PM-5 | Close a PRD tab (removes it from the interface but does not delete files on disk) | P0 |
| PM-6 | Delete a PRD's files on disk (with confirmation dialog) | P1 |
| PM-7 | Display PRD completion status: total stories, passed, in-progress, pending | P0 |
| PM-8 | Watch each opened PRD's files for filesystem changes and auto-reload when files change externally | P0 |
| PM-9 | Support the three-file PRD format: `prd.md` (human-readable PRD), `ridl.md` (agent instructions with iteration definitions and acceptance criteria), and `ridl.json` (machine-readable source of truth), stored in the same directory as the opened file. Each iteration definition contains `AcceptanceCriterion` entries with `CriterionStatus` enum values (`notStarted`, `fail`, `pass`, `error`). An iteration definition is "frozen" (complete) when all its acceptance criteria have status `pass`. JSON decoding must be resilient to both v2 format (`acceptanceCriteria: [String]`, `passes: Bool`, `userStoryTitle`/`userStoryDescription`) and v3 format (`acceptanceCriteria: [{ criterion, status }]`, `title`/`description`). When loading v2 JSON, string criteria are converted to `AcceptanceCriterion(criterion: str, status: .notStarted)` and if `passes: true`, all criteria are set to `.pass` | P0 |
| PM-10 | Auto-convert `prd.md` to `ridl.json` when the markdown source is newer than the JSON | P1 |
| PM-11 | All PRD files (`prd.md`, `ridl.md`, `ridl.json`, `progress.md`, `learnings.md`, `emergent.md`, `ridler.log`) are stored together in a `ridl/` folder | P0 |
| PM-12 | Remember recently opened PRDs and display them in File > Open Recent | P1 |
| PM-13 | Drag-and-drop a `ridl/` folder or a `.md` file onto the app icon to open it as a tab. Show an error alert if the drop target cannot be loaded | P1 |
| PM-14 | JSON decoding errors must include the file name, the missing or invalid key, and the JSON path (e.g., `ridl.json: missing required key "title" in iterationDefinitions.0`) rather than generic system error messages | P0 |

### 3.2 The Ralph Loop (Autonomous Execution Engine)

| ID | Requirement | Priority |
|----|-------------|----------|
| RL-1 | Execute the Ralph Wiggum loop using a two-phase iteration model: read state → select next iteration definition → **implementation phase** (build prompt via `agent_instructions.liquid` + `iteration_context.liquid` → invoke Claude Code → stream output) → **verification phase** (build prompt via `verification.liquid` → invoke Claude Code → stream output) → check completion via harness signals → repeat | P0 |
| RL-2 | Each iteration invokes Claude Code as a fresh subprocess with `--dangerously-skip-permissions --verbose --output-format stream-json` flags (`--verbose` is required when combining `--output-format stream-json` with `-p`) | P0 |
| RL-3 | Select the next iteration definition by filtering for those not yet frozen (i.e., has incomplete acceptance criteria — any criterion with status other than `pass`), sorting by `priority` ascending, and picking the first | P0 |
| RL-4 | Build the prompt by rendering Liquid templates from the project's `ridl/prompts/` folder with iteration definition and project context (see Section 3.10 — Prompt Templates). Context includes: target iteration definition details (ID, title, description, acceptance criteria with per-criterion status), agent instructions, and `progress.md` content | P0 |
| RL-5 | Parse Claude's streaming JSON output in real-time and display in the log view | P0 |
| RL-6 | On iteration definition completion, set all acceptance criteria to `pass` status in `ridl.json`, freezing the iteration definition | P0 |
| RL-7 | On all iteration definitions complete (frozen), transition to the Complete state and play an audio notification | P0 |
| RL-8 | Support configurable max iterations per PRD (default: remaining iteration definitions + 5, minimum 5) | P0 |
| RL-9 | Allow runtime adjustment of max iterations via UI controls (+5 / -5) | P1 |
| RL-11 | Detect harness signals from Claude's output: `<ridler-complete/>` (iteration completed successfully — proceed to next iteration definition), `<ridler-verification-failed/>` (verification found failures — retry the iteration), `<ridler-blocked/>` (agent is stuck — pause loop and surface to user for human intervention) | P0 |
| RL-12 | Create two git commits per completed iteration definition: one for implementation (`implement: [US-001] - Story Title`) and one for verification (`verify: [US-001] verification - Story Title`) | P0 |
| RL-13 | Maintain three runtime files in the PRD directory after each iteration: `progress.md` (implementation progress), `learnings.md` (accumulated learnings across iterations), and `emergent.md` (emergent patterns and insights). Templates `progress_format.liquid`, `learnings_format.liquid`, and `emergent_format.liquid` control the format of these files | P0 |
| RL-14 | Parse all Claude Code `stream-json` message variants correctly: nested `message.content[]` arrays (where content blocks can be `text`, `tool_use`, or `tool_result`), `type="user"` messages containing tool results (string content, array content, and `is_error` blocks with XML tags stripped), `type="system"` with `subtype="init"` (extract model, cwd, version instead of dumping full JSON), and agent sub-prompts (user text blocks with `parent_tool_use_id`). Both the flat format (`{"type":"assistant","content":"text"}`) and the nested format (`{"type":"assistant","message":{"content":[...]}}`) must produce human-readable log entries — no blank entries or raw JSON dumps | P0 |
| RL-15 | Store the raw JSON line on each parsed `LogEntry` (`rawJSON: String?`, nil for system-generated entries) so it is available for verbose/debug display | P1 |
| RL-16 | Persist all log entries to `ridler.log` as newline-delimited JSON (NDJSON). Every line is fully valid JSON. Claude Code output lines have `ridler_story_id` and `ridler_timestamp` injected as top-level fields before writing. System-generated entries (loop start, pause, stop, iteration definition transitions) are serialized as JSON with `ridler_type: "system"`, `ridler_story_id`, `ridler_timestamp`, and `content` fields. The `ridler_` prefix avoids conflicts with Claude Code's own fields | P0 |
| RL-17 | On PRD open, load existing log entries from `ridler.log` on a background thread, parse each JSON line, extract `ridler_story_id` and `ridler_timestamp`, and populate `LogStore` without blocking the main UI thread | P0 |
| RL-18 | Each iteration definition goes through at least two agent invocations: implementation (fresh context) then verification (fresh context). Verification may loop back to implementation if `<ridler-verification-failed/>` is received | P0 |
| RL-19 | The verification agent can add new acceptance criteria to both `ridl/ridl.md` and `ridl/ridl.json` when it discovers issues, ensuring every fix is tracked | P0 |
| RL-20 | Per-criterion status (`not_started`, `fail`, `pass`, `error`) is updated in real time in `ridl/ridl.json` as the agent works, giving the harness fine-grained progress visibility | P0 |

### 3.3 Parallel PRD Execution

| ID | Requirement | Priority |
|----|-------------|----------|
| PX-1 | Support running multiple PRDs simultaneously, each with independent loop state, iteration count, timing, and error tracking | P0 |
| PX-2 | Switching between PRDs in the UI only changes the view — it does not stop other running loops | P0 |
| PX-3 | Loop controls (start, pause, stop) apply to the currently viewed PRD | P0 |
| PX-4 | Display real-time state indicators for all PRDs in the tab bar / sidebar | P0 |

### 3.4 Loop State Machine

| ID | Requirement | Priority |
|----|-------------|----------|
| LS-1 | Support six loop states: Ready, Running, Paused, Stopped, Complete, Error | P0 |
| LS-2 | Ready → Running: User presses Start | P0 |
| LS-3 | Running → Paused: User presses Pause; loop finishes the current phase (implementation or verification) then pauses | P0 |
| LS-4 | Running → Stopped: User presses Stop; loop halts immediately | P0 |
| LS-5 | Running → Complete: All iteration definitions are frozen (all acceptance criteria pass) | P0 |
| LS-6 | Running → Error: Claude Code fails or crashes | P0 |
| LS-7 | Paused/Stopped/Error → Running: User presses Start to resume | P0 |
| LS-8 | Display current state with color-coded badge: Ready (gray), Running (cyan), Paused (yellow), Stopped (gray), Complete (green), Error (red) | P0 |
| LS-9 | Running → Paused: When "Pause after story" is enabled, the loop automatically transitions to Paused after an iteration definition completes its verification phase (same as a manual pause) | P0 |
| LS-10 | Running → Paused: When "Pause after milestone" is enabled and the PRD defines milestones, the loop automatically transitions to Paused after the last iteration definition in a milestone completes | P0 |

### 3.5 Git Integration

| ID | Requirement | Priority |
|----|-------------|----------|
| GI-1 | Detect if the project is on a protected branch (main/master) before starting a loop | P0 |
| GI-2 | Show a warning dialog offering three options: create a `ridler/{prd-name}` branch (recommended), continue on current branch, or cancel | P0 |
| GI-3 | Allow editing the suggested branch name in the warning dialog | P1 |
| GI-4 | Create two commits per completed iteration definition: implementation commit (`implement: [US-001] - Story Title`) and verification commit (`verify: [US-001] verification - Story Title`) | P0 |

### 3.6 User Interface

#### 3.6.1 Window Layout

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│  [PRD Tab 1 ●] [PRD Tab 2 ▶3] [PRD Tab 3 ✓] [+]                                      │
├──────────────────────────────────────────────────────────────────────────────────────┤
│  Toolbar: [▶ Start] [⏸ Pause] [⏹ Stop]  |  Iteration: 3/10  2m34s                    │
├──────────────┬──────────────────────────┬────────────────────────────────────────────┤
│              │                          │                                            │
│  PRD Files   │  Story Detail            │  Log View                                  │
│  ┄┄┄┄┄┄┄┄┄  │  ─ or ─                  │  ─ or ─                                    │
│  📄 prd.md   │  File Content View       │  Claude Code Terminal                      │
│  📄 ridl.md  │                          │                                            │
│  📄 ridl.json│                          │                                            │
│  ──────────  │                          │                                            │
│  Stories     │  Title: Add login endpt  │  ▸ Read src/auth.ts                        │
│              │  Status: ● In Progress   │  ▸ Edit src/auth.ts (lines 12-45)          │
│  ✓ US-001    │  Priority: 2             │  Claude: Adding JWT validation...          │
│  ● US-002    │  ────────────────────    │  ▸ Bash: npm test                          │
│  ○ US-003    │  Description:            │  ✓ 14 tests passed                         │
│  ○ US-004    │  As a user, I want to    │  ▸ Write src/routes/login.ts               │
│              │  log in so that...       │  Claude: Now implementing the              │
│              │                          │  login endpoint handler...                 │
│              │  Acceptance Criteria:    │                                            │
│              │  • POST /login → JWT     │                                            │
│  ──────────  │  • Invalid creds → 401   │                                            │
│  ████░░ 25%  │  • Typecheck passes      │                                            │
│  1/4 stories │                          │                                            │
├──────────────┴──────────────────────────┴────────────────────────────────────────────┤
│  Working on: US-002 - Add login endpoint                                             │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

#### 3.6.2 PRD Tab Bar

| ID | Requirement | Priority |
|----|-------------|----------|
| UI-TB1 | Display a horizontal tab bar above the toolbar showing all currently opened PRDs | P0 |
| UI-TB2 | Each tab shows: PRD name, state indicator icon (● active, ▶ running + iteration count, ⏸ paused, ✓ complete, ✗ error, ■ stopped) | P0 |
| UI-TB3 | Clicking a tab switches the view to that PRD without affecting other running loops | P0 |
| UI-TB4 | A `[+]` button at the end of the tab bar opens a menu with "Open PRD..." and "New PRD..." options | P0 |
| UI-TB5 | Right-click context menu on a tab: Start, Pause, Stop, Edit, Close, Delete | P1 |
| UI-TB6 | Support keyboard shortcuts `⌘1`–`⌘9` to switch to PRD by tab position | P1 |

#### 3.6.3 Toolbar

| ID | Requirement | Priority |
|----|-------------|----------|
| UI-T1 | Display Start/Pause/Stop buttons that are enabled/disabled based on current loop state | P0 |
| UI-T2 | Show iteration counter: current iteration / max iterations | P0 |
| UI-T3 | Show elapsed time since loop started (format: `Xh Ym Zs`) | P0 |
| UI-T4 | Show color-coded state badge: `[Ready]`, `[Running]`, `[Paused]`, `[Stopped]`, `[Complete]`, `[Error]` | P0 |
| UI-T5 | Display +/- stepper control to adjust max iterations at runtime | P1 |
| UI-T6 | Display a toggle (checkbox or switch) labeled "Pause after story" that, when enabled, automatically pauses the loop after each iteration definition completes its verification phase. Default: off | P0 |
| UI-T7 | Display a "Pause after milestone" toggle (checkbox) to the right of "Pause after story". Default: off. Only effective when PRD defines milestones | P0 |

#### 3.6.4 PRD File Browser (Left Pane, above Stories)

| ID | Requirement | Priority |
|----|-------------|----------|
| UI-FB1 | Display three selectable file rows above the stories list: `prd.md`, `ridl.md`, `ridl.json`, grouped under a collapsible "PRD Files" header. Clicking the header toggles the group open/closed. The group is expanded by default. Each row shows a file-type icon and the filename | P0 |
| UI-FB2 | Selecting a file row deselects the currently selected story; selecting a story row deselects the currently selected file row. Only one item (file or story) is selected at a time | P0 |
| UI-FB3 | If `ridl.md` or `ridl.json` does not yet exist on disk, the corresponding row is still selectable but visually distinguished (dimmed text, badge, or "(not yet created)" note) to indicate the file is missing. The visual indicator is removed once the file is created (detected via file watcher) | P1 |
| UI-FB4 | A visual separator (divider line) separates the file rows from the stories list below | P0 |
| UI-FB5 | File rows remain visible and selectable regardless of loop state (Ready, Running, Paused, etc.) | P0 |
| UI-FB6 | Below the PRD files, a collapsible "Prompt Templates" header lists `.liquid` files from `ridl/prompts/` (e.g., `agent_instructions.liquid`, `verification.liquid`, `iteration_context.liquid`, `progress_format.liquid`, `learnings_format.liquid`, `emergent_format.liquid`, `edit_file.liquid`, `create_file.liquid`). Prompt template rows show a template icon and filename. If `ridl/prompts/` does not exist yet, the section shows "(defaults — run once to generate)" | P0 |
| UI-FB7 | Selecting a prompt template file shows its content in the middle pane and enables editing via Claude terminal in the right pane (same behavior as PRD files) | P0 |

#### 3.6.5 Stories Panel (Left Pane)

| ID | Requirement | Priority |
|----|-------------|----------|
| UI-S1 | Display a scrollable list of all iteration definitions for the selected PRD | P0 |
| UI-S2 | Each row shows: status icon (✓ frozen/all criteria pass, ● in-progress/has mixed criteria, ✗ has failures or errors, ○ not started), story ID, and title | P0 |
| UI-S3 | Highlight the currently selected story | P0 |
| UI-S4 | Show a progress bar at the bottom: filled portion, percentage, and count (e.g., `2/4 stories`) | P0 |
| UI-S5 | Clicking a story selects it and shows its detail in the middle pane | P0 |
| UI-S6 | Show a yellow warning banner if an iteration definition has acceptance criteria with mixed statuses (some `pass`, some `fail` or `error`) indicating a previously interrupted session | P1 |
| UI-S7 | If the PRD defines milestones, group iteration definitions under collapsible milestone headers. Each header shows the milestone **name** (short ID, e.g., "v0.1"), not the theme. If the milestone has a theme, display it as a secondary label above the first iteration definition inside the collapsible area (collapses together with the iteration definitions). Each header shows a summary (e.g., `3/5 stories`). Clicking a header toggles the group open/closed. All groups are expanded by default | P0 |
| UI-S8 | If the PRD has no milestones, display iteration definitions as a flat list (no grouping) | P0 |

#### 3.6.6 Story Detail Panel (Middle Pane)

| ID | Requirement | Priority |
|----|-------------|----------|
| UI-D1 | Display the selected story's title (bold) | P0 |
| UI-D2 | Display status badge and priority number | P0 |
| UI-D3 | Display the full description with word wrapping | P0 |
| UI-D4 | Display acceptance criteria as a bulleted list | P0 |
| UI-D5 | When no PRD is loaded, show instructions to create or open a project | P0 |
| UI-D6 | When an error occurs, show error details and a tip to check `ridler.log` | P0 |
| UI-D7 | When a PRD file row is selected (instead of a story), the middle pane displays the file's content: full block-level rendered markdown (headers, tables, code blocks, lists, bold, italic) for `.md` files via MarkdownUI or similar, formatted/pretty-printed JSON for `.json` files. If the selected file does not yet exist on disk, the middle pane is empty | P0 |
| UI-D8 | File content displayed in the middle pane is read-only (no inline editing) | P0 |
| UI-D9 | File changes detected by the file watcher automatically refresh the displayed content in the middle pane | P0 |

#### 3.6.7 Log Panel (Right Pane)

| ID | Requirement | Priority |
|----|-------------|----------|
| UI-L1 | Always visible alongside the story detail panel — no toggle needed | P0 |
| UI-L2 | Display Claude's streaming JSON output parsed into readable entries: assistant text, tool calls, tool results, errors | P0 |
| UI-L3 | Apply syntax highlighting to code blocks in Claude's output | P1 |
| UI-L4 | Display tool call entries with icons per tool type (Read, Edit, Write, Bash, etc.) | P1 |
| UI-L5 | Auto-scroll to follow new output while the loop is running | P0 |
| UI-L6 | Allow manual scrolling; disable auto-scroll when user scrolls up, re-enable when user scrolls to bottom | P0 |
| UI-L7 | Show an indicator for auto-scroll vs. manual-scroll mode | P1 |
| UI-L8 | Show iteration definition transition events, phase transitions (implementation/verification), iteration starts, and completion messages in the log | P0 |
| UI-L9 | When a PRD file row or prompt template row is selected, the right pane switches from log view to an interactive Claude Code terminal session using a terminal emulator library (e.g., SwiftTerm) for full TUI rendering (colors, cursor positioning, selection menus, box drawing). If the file exists, Claude is launched with the file path as the initial prompt context. If the file does not yet exist, Claude is launched with an appropriate prompt to create that file (e.g., "Create ridl.md from the existing prd.md"). For prompt templates, Claude is launched with knowledge of available Liquid variables (iteration, project, progress_content, learnings_content, emergent_content). The terminal environment sets `TERM=xterm-256color` and `COLORTERM=truecolor` | P0 |
| UI-L10 | While the Ralph loop is running, the Claude terminal pane is disabled and displays a message: "Pause the loop to edit this file" | P0 |
| UI-L11 | When the user switches back to a story row, the right pane visually reverts to the log view, but the terminal session remains alive in the background (rendered in a ZStack with opacity toggle so the terminal NSView stays mounted) | P0 |
| UI-L12 | If the user starts the loop while a Claude editing session is alive, the session is terminated (with confirmation dialog if mid-conversation). Closing or deleting a PRD tab also terminates its terminal session | P1 |
| UI-L13 | When the "Verbose log" setting is enabled and a log entry has `rawJSON`, display a collapsible "Raw JSON" disclosure below the parsed content showing pretty-printed JSON in small monospaced dimmed text | P2 |
| UI-L14 | While log entries are loading from disk, show a `ProgressView("Loading logs...")` in the log panel. If entries are partially loaded, show a small spinner in the log panel header. Once loading completes, transition to the normal log view | P1 |
| UI-L15 | Log entries longer than 20 lines are collapsed by default with a disclosure triangle. Clicking the triangle expands/collapses the entry. When collapsed, show the first 5 lines with a muted "(N more lines)" indicator. Exception: prompt entries (content prefixed with `"Prompt:"` or `"[agent prompt]"`) default to expanded | P1 |
| UI-L16 | Prompt log entries (engine prompts starting with `"Prompt:"` and agent prompts starting with `"[agent prompt]"`) are styled with an orange icon (`paperplane.fill`), orange text, and a light orange background — visible in both light and dark mode | P1 |

#### 3.6.8 Status Bar (Bottom)

| ID | Requirement | Priority |
|----|-------------|----------|
| UI-SB1 | Display the last activity message (e.g., "Working on: US-002 - Add login endpoint") | P0 |
| UI-SB2 | Color the activity message based on current state (cyan for running, yellow for paused, red for error) | P1 |

### 3.7 Empty State & New PRD Creation

| ID | Requirement | Priority |
|----|-------------|----------|
| ES-1 | On launch with no previously opened PRDs, show an empty state with "Open PRD..." and "New PRD..." buttons | P0 |
| ES-2 | "New PRD..." prompts for a PRD name (text field, allows letters, numbers, `-`, `_`) and a parent directory (directory picker) | P0 |
| ES-3 | Creates a `ridl/` folder in the chosen parent directory containing an empty `prd.md` file and opens it as a tab | P0 |
| ES-4 | User can then click "Edit PRD" to launch Claude Code interactively and author the PRD content | P0 |

### 3.8 Audio & Notifications

| ID | Requirement | Priority |
|----|-------------|----------|
| AN-1 | Play an audio notification when a PRD reaches the Complete state | P0 |
| AN-2 | Option to disable audio notifications in the app (menu bar toggle or preferences) | P1 |
| AN-3 | Post a macOS notification when a PRD completes (if the app is not frontmost) | P1 |

### 3.9 Menu Bar & Keyboard Shortcuts

| ID | Requirement | Priority |
|----|-------------|----------|
| KB-1 | `⌘N` — Create new PRD | P0 |
| KB-2 | `⌘O` — Open an existing PRD file | P0 |
| KB-3 | `⌘R` or `⌘↩` — Start/Resume loop for current PRD | P0 |
| KB-4 | `⌘.` — Pause loop | P0 |
| KB-5 | `⌘⇧.` — Stop loop | P0 |
| KB-6 | `⌘1`–`⌘9` — Switch to PRD by tab position | P1 |
| KB-7 | `⌘L` — Focus Log Panel | P1 |
| KB-8 | `⌘E` — Edit current PRD (launch Claude Code) | P1 |
| KB-9 | Standard macOS menu bar with File, Edit, View, PRD, Window, Help menus | P0 |

### 3.10 Prompt Templates (Liquid)

| ID | Requirement | Priority |
|----|-------------|----------|
| PT-1 | Add a Swift Liquid templating library as a dependency (e.g., [nicklama/Liqid](https://github.com/nicklama/Liqid) or equivalent) | P0 |
| PT-2 | Default prompt templates bundled in the app as resources (8 total): **Agent loop templates** (`agent_instructions.liquid`, `verification.liquid`, `iteration_context.liquid`) used by `RalphLoopEngine.buildPrompt`, **Runtime file format templates** (`progress_format.liquid`, `learnings_format.liquid`, `emergent_format.liquid`) used for generating runtime files, and **Interactive editing templates** (`edit_file.liquid`, `create_file.liquid`) used by `ClaudeTerminalManager`. `create_file.liquid` uses `{% if %}` branches on `file_name` to provide file-specific instructions | P0 |
| PT-3 | On first loop start for a project, if no templates exist in `ridl/prompts/`, create the directory and copy the bundled defaults there | P0 |
| PT-4 | `buildPrompt(for:project:)` reads `.liquid` files from the project's `ridl/prompts/` folder and renders them with a context dictionary containing: `iteration.id`, `iteration.title`, `iteration.description`, `iteration.priority`, `iteration.acceptance_criteria` (array of `{ criterion, status }` objects), `iteration.prd_references` (optional), `project.universal_context.non_functional_requirements` (optional), `project.universal_context.developer_experience` (optional), `project.universal_context.technical_architecture` (optional), `project.universal_context.testing_and_verification` (optional), `progress_content`, `learnings_content`, `emergent_content`, `phase` (implementation or verification), `file_path`, `file_name`, `file_exists` (for editing templates) | P0 |
| PT-5 | If a template file is missing from `ridl/prompts/`, copy the bundled default before rendering | P0 |
| PT-6 | If a template fails to parse: display an inline error banner in the middle pane (file name, line number, parse error), show a red error icon next to the template filename in the sidebar, and transition loop to Error state | P0 |
| PT-7 | Templates support standard Liquid features: variables (`{{ iteration.id }}`), conditionals (`{% if %}` / `{% endif %}`), loops (`{% for %}` / `{% endfor %}`), filters | P0 |
| PT-8 | Existing hardcoded prompt strings in `RalphLoopEngine.buildPrompt` and `ClaudeTerminalManager.start` are removed and replaced by template rendering | P0 |

### 3.11 Runtime Files

Three runtime files are maintained in the PRD directory (`ridl/`) by the engine and the agent across iterations. Each has a corresponding Liquid format template in `ridl/prompts/`.

| ID | Requirement | Priority |
|----|-------------|----------|
| RF-1 | `progress.md` — Append-only log of implementation and verification results. Updated after each phase with details of what was done, files changed, and outcomes. Template: `progress_format.liquid` | P0 |
| RF-2 | `learnings.md` — Agent-facing accumulated learnings: codebase patterns, tool quirks, debugging tips, and working solutions discovered across iterations. Helps subsequent iterations avoid repeating mistakes. Template: `learnings_format.liquid` | P0 |
| RF-3 | `emergent.md` — Human-facing insights: design decisions made by the agent, requirement gaps discovered, assumptions needing validation, and architectural patterns that emerged during implementation. Template: `emergent_format.liquid` | P0 |

---

## 4. Non-Functional Requirements

### 4.1 Performance

| ID | Requirement | Target |
|----|-------------|--------|
| NF-P1 | App launch to ready state | < 2 seconds |
| NF-P2 | UI responsiveness during active Claude loop (no frame drops) | 60 fps |
| NF-P3 | Memory usage with 10 PRDs loaded, 1 active loop | < 200 MB resident |
| NF-P4 | Log view streaming latency (Claude output to displayed text) | < 100 ms |
| NF-P5 | File watcher detection of external PRD file changes | < 1 second |

### 4.2 Privacy & Security

| ID | Requirement |
|----|-------------|
| NF-S1 | No telemetry, analytics, or crash reporting that transmits data externally |
| NF-S2 | PRD-specific data (ridl.json, progress.md, learnings.md, emergent.md, ridler.log) stays alongside the PRD file. App-wide preferences stored in the app's container via UserDefaults |
| NF-S3 | Claude Code authentication is delegated to the Claude Code CLI — the app does not store API keys |


### 4.3 Compatibility

| ID | Requirement |
|----|-------------|
| NF-C1 | macOS 14.0 (Sonoma) and later |
| NF-C2 | Apple Silicon only (M1, M2, M3, M4 families) |
| NF-C3 | Requires Claude Code CLI installed and authenticated (`claude` command available in PATH) |

---

## 5. Technical Architecture

### 5.1 High-Level Component Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                      SwiftUI App                              │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────┐ │
│  │ PRD Tab Bar  │  │ Stories List  │  │ Detail / Log View   │ │
│  └──────┬──────┘  └──────┬───────┘  └──────────┬──────────┘ │
│         └────────────┬───┘                      │            │
│                 ViewModel Layer                  │            │
│         ┌────────────┴───────────────┐          │            │
│         │       PRD Manager          │          │            │
│         │  (parallel loop tracking)  │          │            │
│         └────────────┬───────────────┘          │            │
│    ┌─────────────────┼─────────────────┐        │            │
│    ▼                 ▼                 ▼        ▼            │
│ ┌────────┐   ┌─────────────┐   ┌───────────────────┐       │
│ │ PRD    │   │ Ralph Loop  │   │ Log Stream Parser  │       │
│ │ Store  │   │ Engine      │   │ (JSON → entries)   │       │
│ │(JSON/MD│   │             │   └───────────────────┘       │
│ │ r/w)   │   │ ┌─────────┐│                                │
│ └────────┘   │ │ Claude  ││                                │
│              │ │ Process ││                                │
│              │ │ Manager ││                                │
│              │ └─────────┘│                                │
│              └─────────────┘                                │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ File Watcher │  │ Git Manager  │  │ Audio / Notif.   │  │
│  │ (FSEvents)   │  │              │  │ Manager          │  │
│  └──────────────┘  └──────────────┘  └──────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

### 5.2 Key Dependencies

| Component | Library / Framework | Notes |
|-----------|-------------------|-------|
| UI framework | SwiftUI (macOS 14+) | NavigationSplitView, TabView, toolbar modifiers |
| Process management | Foundation `Process` | Launch and stream Claude Code CLI subprocess |
| JSON streaming | Foundation `JSONDecoder` | Line-by-line parsing of Claude's `stream-json` output |
| File watching | FSEvents / DispatchSource | Monitor each opened PRD's directory for external changes |
| Git operations | `Process` calling `git` CLI | Branch detection, commit creation |
| Terminal emulation | SwiftTerm (SPM, 1.0.0+) | `LocalProcessTerminalView` wrapping for Claude Code interactive sessions; handles colors, cursor positioning, box drawing natively |
| Liquid templating | Liqid or equivalent (SPM) | Render `.liquid` prompt templates with iteration/project context variables |
| Markdown rendering | MarkdownUI (SPM, 2.0.0+) | Full block-level markdown rendering (headers, tables, code blocks, lists) for prd.md and ridl.md in the detail pane |
| Syntax highlighting | Native or swift-syntax | Code block highlighting in log view |
| Audio playback | AVFoundation `AVAudioPlayer` | Completion notification sound |
| Notifications | UserNotifications framework | macOS notification center integration |
| Persistence | FileManager + Codable | PRD JSON/Markdown read/write, no database needed |

### 5.3 Claude Code Invocation Pipeline

```
PRD Manager selects next iteration definition
  │
  ▼
══════════════════════════════════════
  PHASE 1: IMPLEMENTATION
══════════════════════════════════════
Build prompt (agent_instructions.liquid + iteration_context.liquid + progress.md)
  │
  ▼
Spawn Process: claude --dangerously-skip-permissions --verbose --output-format stream-json
  │
  ▼
Read stdout line-by-line (streaming JSON)
  │
  ├── Parse message type: text, tool_use, tool_result, error
  │     │
  │     ▼
  │   Append to Log View entries
  │
  ▼
Process exits → git commit: implement: [US-001] - Story Title
  │
  ▼
══════════════════════════════════════
  PHASE 2: VERIFICATION
══════════════════════════════════════
Build prompt (verification.liquid + acceptance criteria)
  │
  ▼
Spawn Process: claude --dangerously-skip-permissions --verbose --output-format stream-json
  │
  ▼
Read stdout line-by-line (streaming JSON)
  │
  ▼
Detect harness signal:
  │
  ├── <ridler-complete/>       → update ridl.json (all criteria → pass), git commit: verify: [US-001] verification - Story Title, update runtime files
  │
  ├── <ridler-verification-failed/> → retry iteration (loop back to implementation)
  │
  ├── <ridler-blocked/>        → transition to Paused state for human intervention
  │
  └── Process failure          → transition to Error state
```

---

## 6. Settings

Ridler provides a standard macOS Settings window (`⌘,`) for app-wide preferences. Per-PRD settings such as max iterations are also accessible inline via toolbar controls.

### 6.1 Settings Reference

#### App-Wide Settings (Settings Window)

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| Audio notifications | Toggle | On | Play sound on PRD completion |
| Verbose log | Toggle | Off | Show raw Claude JSON in log view |
| Debug mode | Toggle | Off | Enable debug information overlays and the Debug window (see Section 7 — Developer Experience) |
| Claude Config Dir | Directory path | Empty (system default) | Custom `CLAUDE_CONFIG_DIR` path passed to Claude Code subprocesses; validated on save, surfaces `claudeConfigNotFound` error if path does not exist |

#### Per-PRD Settings (Toolbar / Inline)

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| Max iterations | Stepper (integer) | Remaining iteration definitions + 5 | Per-PRD iteration limit; adjustable at runtime |

---

## 7. Developer Experience

Ridler is built and maintained by both human developers and AI coding agents. The codebase, error surfaces, and debugging tools must be equally effective for both audiences. Clear error messages, structured logging, and accessible debug state reduce the time from "something is wrong" to "here is the fix" — whether the person investigating is a human reading a stack trace or an agent parsing log output.

### 7.1 Error Presentation

| ID | Requirement | Priority |
|----|-------------|----------|
| DX-1 | All user-facing errors must be displayed in a native alert dialog with a clear, specific message (never silently swallowed) | P0 |
| DX-2 | Error alerts must include a "Copy" button that copies the full error message to the clipboard for easy pasting into bug reports, chat, or agent prompts | P0 |
| DX-3 | JSON decoding errors must identify the file name, the problematic key or field, and the JSON path (e.g., `ridl.json: missing required key "title" in iterationDefinitions.0`) | P0 |
| DX-4 | File-not-found errors must include the full path that was searched and, for companion file lookups, list which filenames were tried (e.g., "No ridl.json or prd.md found in /path/to/dir") | P0 |
| DX-5 | Process errors (Claude Code crashes, non-zero exit codes) must include the exit code, stderr output (if any), and the command that was run | P1 |
| DX-6 | Git errors must include the git command that failed and its stderr output | P1 |

### 7.2 Debug Mode

When the "Debug mode" toggle is enabled in Settings, additional diagnostic information becomes available throughout the app.

| ID | Requirement | Priority |
|----|-------------|----------|
| DX-10 | A "Debug" menu item (Window > Debug Info) opens a dedicated Debug window showing live internal state | P1 |
| DX-11 | The Debug window displays: current loop state per PRD, engine iteration count, file watcher status, active process PIDs, last error per tab, and memory usage | P1 |
| DX-12 | In debug mode, the status bar expands to show internal state: loop state enum value, current iteration definition ID, current phase (implementation/verification), and elapsed time per iteration | P2 |
| DX-13 | In debug mode, log entries include raw JSON alongside the parsed representation (equivalent to "Verbose log" but scoped to the debug overlay) | P2 |
| DX-14 | Debug mode state is persisted across launches via UserDefaults | P2 |

### 7.3 Logging and Diagnostics

| ID | Requirement | Priority |
|----|-------------|----------|
| DX-20 | All errors, state transitions, and significant events are logged to the unified macOS logging system (`os_log`) with appropriate log levels (`.error`, `.info`, `.debug`) | P1 |
| DX-21 | Log messages include structured metadata (PRD name, story ID, iteration number) so they can be filtered in Console.app | P1 |
| DX-22 | The per-PRD `ridler.log` file captures all log entries as newline-delimited JSON (NDJSON), including both Claude Code output (with injected `ridler_story_id` and `ridler_timestamp`) and system-generated entries, for post-mortem debugging and log persistence across app restarts | P0 |

### 7.4 Code Readability and Agent Compatibility

| ID | Requirement | Priority |
|----|-------------|----------|
| DX-30 | Swift source files are organized into clearly named groups (Models, Views, Managers, Protocols) matching Xcode's project navigator structure | P0 |
| DX-31 | Public types and non-obvious methods include concise documentation comments describing purpose and contracts | P1 |
| DX-32 | Error types conform to `LocalizedError` with human-readable `errorDescription` values that are suitable for both UI display and log output | P0 |
| DX-33 | Test files mirror the source structure and use descriptive test method names that read as specifications (e.g., `testOpenInvalidPathThrows`, `testMaxIterationsStopsLoop`) | P1 |
| DX-34 | Protocols are used for external dependencies (process spawning, git operations, file system access) to enable test mocking and make the dependency graph explicit for agents navigating the codebase | P0 |

---

## 8. User Flows

### 8.1 First Launch — Creating a New PRD

1. User opens Ridler for the first time. App shows empty state with "Open PRD..." and "New PRD..." buttons.
2. User clicks "New PRD...". A dialog prompts for a PRD name and a save location.
3. User enters a name and picks a directory. App creates an empty `prd.md` file there and opens it as a tab.
4. User clicks "Edit PRD" in the UI. App launches Claude Code interactively with the PRD context.
5. User describes the project. Claude populates the `prd.md` and generates `ridl.json`.
6. Claude Code exits. App detects the file changes, loads the PRD and iteration definitions, and displays them.

### 8.2 Opening an Existing PRD

1. User clicks File > Open (`⌘O`). A file picker appears filtering for `prd.md` / `ridl.json` files.
2. User selects a PRD file from any location on disk.
3. App opens it as a new tab, loads the iteration definitions, and displays them in the main window.
4. User can repeat to open additional PRDs from different locations — each becomes its own tab.

### 8.3 Running the Loop

1. User has one or more PRD tabs open.
2. User clicks Start (or presses `⌘R`). App detects protected branch → shows warning dialog.
3. User chooses "Create branch". App creates `ridler/{prd-name}` branch.
4. Loop begins. Iteration definitions execute one by one in two phases (implementation then verification). Log view streams Claude's output.
5. User monitors iteration definition detail in the middle pane and Claude's streaming output in the log pane simultaneously.
6. All iteration definitions complete (frozen). App transitions to Complete state and plays a sound.

### 8.4 Parallel PRDs

1. User has three PRD tabs open: auth, dashboard, api (each from different directories).
2. User starts the auth loop, switches to the dashboard tab, starts that loop too.
3. Both loops run independently. Tab bar shows `▶2` on auth and `▶1` on dashboard.
4. Auth completes first → tab shows `✓`. Dashboard continues running.
5. User clicks the auth tab to review its completed iteration definitions while dashboard continues.

### 8.5 Resuming After Interruption

1. User quits the app while a loop was running.
2. User re-opens Ridler. App restores previously opened PRD tabs (from Open Recent / persisted state).
3. App detects US-003 has acceptance criteria with mixed statuses (partially complete). Stories panel shows a yellow warning banner.
4. User clicks Start. Loop resumes from US-003.

---

## 9. Release Milestones

### v0.1 — PRD Management & Tab Bar

- Open PRD via folder or .md file from any location on disk
- Create new PRD (ridl/ folder convention with prd.md)
- PRD tab bar with state indicators
- PRD file browser (prd.md, ridl.md, ridl.json rows, prompt templates)
- Edit PRD files and prompt templates via Claude Code terminal in right pane
- File watcher for external PRD changes
- Empty state with Open/New PRD buttons
- Error alerts with descriptive messages and copy-to-clipboard for all open/load failures

### v0.2 — Core Loop & Minimal UI

- Display iteration definitions list and story detail
- Start/Pause/Stop loop controls
- Ralph loop execution (single PRD)
- Liquid prompt templates stored per project (`ridl/prompts/`)
- Claude Code subprocess management with streaming JSON parsing
- Log view with streaming output and NDJSON persistence (`ridler.log`)
- Two git commits per iteration definition (implementation + verification)
- Protected branch detection and warning dialog

### v0.3 — Parallel Execution & Polish

- Parallel PRD execution with independent loop state
- Runtime iteration adjustment (+/-)
- Audio notifications on completion
- macOS notifications when app is backgrounded
- Syntax highlighting in log view
- Interrupted iteration definition detection and warning

### v0.4 — Release Ready

- Keyboard shortcuts (`⌘R`, `⌘.`, `⌘1`–`⌘9`, etc.)
- Full menu bar (File, Edit, View, PRD, Window, Help)
- Open Recent PRDs
- Right-click context menus on PRD tabs
- Debug mode toggle in Settings with Debug window (Window > Debug Info)
- os_log integration with structured metadata for Console.app filtering
- App icon, notarization, DMG distribution

---

## 10. Resolved Questions

| # | Question | Decision |
|---|----------|----------|
| 1 | Should the app support remote execution (SSH) like the original Chief CLI? | **No, never.** Local-only is the permanent design. No plans for remote support. |
| 2 | Should the app include a built-in PRD text editor? | **No.** PRD editing is done via Claude Code interactive sessions (same as the original Chief CLI). The app is an execution dashboard, not an editor. |
| 3 | Should settings be in a dedicated Settings window? | **Yes.** A dedicated macOS Settings/Preferences window (`⌘,`) for app-wide configuration. |
| 4 | Should the app store any state outside the PRD's directory? | **Yes — app-wide preferences.** Open Recent, audio settings, window state, and defaults are stored in the app's preferences file. PRD-specific state (ridl.json, progress.md, ridler.log) stays alongside the PRD file. |
| 5 | Should the responsive layout from the TUI (stacked vs. side-by-side) be replicated? | **No.** SwiftUI's NavigationSplitView handles window resizing natively. The sidebar collapses automatically on narrow windows. |
| 6 | Should the app auto-retry when Claude Code crashes? | **Yes, optionally.** Auto-retry is supported but disabled by default (toggle in Settings). After retry exhaustion, the engine transitions to Error state. Users can always manually resume via Start/Resume. |

## 11. Open Questions

| # | Question | Notes |
|---|----------|-------|
| 1 | Distribution strategy? | Options: DMG only, DMG first with Mac App Store later, Mac App Store only, or both from day one. |

---

## 12. Critical Test Areas

| Area | Risk if broken | Suggested test approach |
|------|---------------|----------------------|
| Ralph Loop engine (iteration definition selection, two-phase iteration cycle, state transitions) | Core functionality — the entire app exists to run this loop correctly. Wrong iteration definition selection, skipped iteration definitions, or stuck loops make the app useless | Unit tests for iteration definition selection algorithm, state machine transition tests for all 6 states and every valid transition, two-phase flow tests (implementation → verification), harness signal handling tests, integration tests with mock Claude process |
| Claude Code process management (spawn, stream, kill) | Zombie processes, lost output, app hangs on process crash | Integration tests with mock processes that simulate: normal exit, crash, hang, slow output. Verify cleanup on app quit |
| Streaming JSON parser | Garbled log view, missed completion signals, crashes on malformed input | Unit tests with captured real Claude output. Fuzz testing with malformed JSON lines. Test partial reads and buffer boundaries |
| PRD JSON read/write (`ridl.json` state updates) | Data loss — iteration definitions marked as frozen when they aren't, or completed work lost. Silent failures when opening invalid PRD files | Unit tests for every field update including per-criterion status transitions. Round-trip tests (read → modify → write → read). Concurrent access tests (file watcher + loop writing simultaneously). Verify error alerts appear for missing companion JSON, malformed JSON, and missing required fields. Verify `AcceptanceCriterion` status tracking with `CriterionStatus` enum values |
| Git integration (branch detection, commit creation) | Commits to wrong branch (main/master), malformed commits, data loss from bad git state | Integration tests with real git repos. Test protected branch detection on main, master, and custom branches. Verify commit message format |
| Parallel PRD execution | Race conditions — loops interfering with each other, state corruption, UI showing wrong PRD's data | Concurrent execution tests with 3+ PRDs. Verify independent state isolation. Test rapid tab switching during active loops |

---

## 13. Success Metrics

| Metric | Target |
|--------|--------|
| Feature parity with original Chief CLI | 100% of core features (loop, PRD management, parallel execution, git integration) |
| Test suite | All tests pass with zero failures on every commit |
| Compiler warnings | Zero warnings in Release builds; warnings treated as errors in CI |
| App crash rate | < 0.1% of sessions |
| Loop reliability (iteration definitions complete without manual intervention) | > 95% of iteration definitions (matching the original Chief CLI's rate) |
| Cold start to ready state | < 2 seconds |
| Log streaming latency | < 100 ms from Claude output to displayed entry |
