# List View Progress

## Status: Phase 3 - Completed

## Quick Reference
- Brief: [nathan-docs/List-View-Brief.md](nathan-docs/List-View-Brief.md)
- Research: [docs/list-view/RESEARCH.md](docs/list-view/RESEARCH.md)
- Implementation: [docs/list-view/IMPLEMENTATION.md](docs/list-view/IMPLEMENTATION.md)

---

## Phase Progress

### Phase 1: Foundation + minimum viable list
**Status:** Completed (2026-04-29)

**Goal:** Toggle 3-pane mode in Settings or with `⌥⌘3`, see a real list of notes for the active folder, click rows to open. **Verified end-to-end in Debug build.**

#### Tasks
- [x] `LayoutMode` enum + `@AppStorage("layoutMode")` ([Clearly/Native/LayoutMode.swift](Clearly/Native/LayoutMode.swift))
- [x] `WorkspaceManager.selectedFolderURL` + persistence — stored as a path string (not security-scoped bookmark — see decision below)
- [x] `MacRootView` switches between 2-col / 3-col `NavigationSplitView` via `@AppStorage("layoutMode")`
- [x] `MacNoteListView` ([Clearly/Native/MacNoteListView.swift](Clearly/Native/MacNoteListView.swift)) — FileNode-driven, modified-desc, recursive, title + relative-time row
- [x] Sidebar folder-click sets `selectedFolderURL` — `.simultaneousGesture` on both location-section header and nested folder rows
- [x] Settings → General "Layout" picker with description text + ⌥⌘2/⌥⌘3 hint
- [x] View menu items "Two-Pane Layout" `⌥⌘2` / "Three-Pane Layout" `⌥⌘3`
- [x] Vault-removal clears stale `selectedFolderURL`
- [x] `xcodegen generate` + Debug build green
- [x] Manual smoke test: layout toggle, picker, folder selection, row click → editor

#### Decisions Made
- **Stored `selectedFolderURL` as path string, not security-scoped bookmark.** It's always a subpath of an already-bookmarked location whose bookmark grants subtree access — a separate bookmark adds no security benefit and complicates failure modes. Pattern matches existing `expandedFolderPaths`.
- **Default folder = first location's URL at render time, not at persist time.** `selectedFolderURL` only persists when the user explicitly clicks a folder. The middle pane falls back to `locations.first?.url` when nil, so first entry to 3-pane mode shows real content immediately.
- **Folder click uses `.simultaneousGesture(TapGesture())`** rather than replacing DisclosureGroup behavior. Selection works alongside the existing expand/collapse toggle without breaking it.
- **Layout switch uses a `Group { switch ... }` conditional.** SwiftUI rebuilds the `NavigationSplitView` from scratch on toggle — minor flash is acceptable; not worth the complexity of dual-rendering with opacity tricks.
- **Verified in Debug (`com.sabotage.clearly.dev`) — App Store / Sparkle paths untouched.**

#### Verification screenshots
- 3-pane empty state: "No folder selected / Select a folder" — confirmed
- 3-pane populated: docs folder showing 16 notes, sorted modified-desc — confirmed
- Folder-click in sidebar: middle list updated to show only 3 notes in `list-view/` — confirmed
- Row-click opens note in editor — confirmed
- Settings → General → Layout picker — confirmed
- View menu Two-Pane / Three-Pane items with shortcuts — confirmed

#### Blockers
- (none — phase complete)

---

### Phase 2: Notes parity polish
**Status:** Completed (2026-04-29)

**Goal:** Two-line rows with title + (date · preview) from VaultIndex, sort menu, per-folder recursion toggle, live updates. **Verified end-to-end in Debug build.**

#### Tasks
- [x] `NoteSummary` value type in ClearlyCore ([Packages/ClearlyCore/Sources/ClearlyCore/Vault/NoteSummary.swift](Packages/ClearlyCore/Sources/ClearlyCore/Vault/NoteSummary.swift))
- [x] `VaultIndex.summaries(folderRelativePath:recursive:sort:)` query ([Packages/ClearlyCore/Sources/ClearlyCore/Vault/VaultIndex+Summaries.swift](Packages/ClearlyCore/Sources/ClearlyCore/Vault/VaultIndex+Summaries.swift))
- [x] Frontmatter / H1 / preview parsing — `extractTitleAndPreview(content:fallbackTitle:)` strips YAML/TOML frontmatter, picks first H1 as title (fallback to filename), and extracts first non-empty non-H1 line as preview (200-char cap)
- [x] `WorkspaceManager.nonRecursiveFolders` + `noteListSortOrder` (persisted) — recursion default is *on*, store the exception set; sort persists as raw String under `@AppStorage`-style key
- [x] `MacNoteListView` switched to `[NoteSummary]` driven off `VaultIndex.summaries(...)` — query runs off-main via `Task.detached(priority: .userInitiated)`
- [x] `NoteListRow` two-line view: title (semibold, primary) + secondary line with date + tertiary preview
- [x] List header: sort menu (`arrow.up.arrow.down`) + recursion toggle (`rectangle.stack.fill` ↔ `rectangle`)
- [x] Live updates via `treeRevision` and `vaultIndexRevision` triggers — `task(id: reloadKey)` re-fires on any input change
- [x] Empty / loading states (ContentUnavailableView for "No folder", "No notes"; ProgressView during initial load)
- [x] Theme tokens for the list pane — **deferred**: kept `.primary`/`.secondary`/`.tertiary` SwiftUI semantic colors. Adding asset-catalog tokens for this phase wasn't worth the friction (resource-bundle edits, light/dark variants for 4+ tokens) when the SwiftUI defaults already match the existing sidebar's treatment. Revisit if Phase 4 polish surfaces a contrast issue.
- [x] `xcodegen generate` + Debug build green
- [x] Manual smoke test: title from H1 ("List View Progress" not "PROGRESS"), preview shows first H2 line ("## Status: Phase 1 - Completed"), recursion toggle flips icon and re-queries, sort menu reorders alphabetically by *derived* title (so docs/expansion/IMPLEMENTATION.md sorts as "Expansion Implementation Plan", not "IMPLEMENTATION")

#### Decisions Made
- **Made `dbPool` internal (was private)** so the `VaultIndex+Summaries.swift` extension in the same module can run additional read transactions. Comment in VaultIndex.swift documents this is not part of the public API.
- **`substr(content, 1, 1024)`** — only grab the first 1k bytes of FTS5 content for preview extraction. Covers frontmatter + a generous lookahead for the first body line on every realistic note. Avoids fetching multi-MB content columns into Swift just to throw most of it away.
- **Title-* sorts post-process in Swift, not SQL.** SQL sorts on `filename`, but the displayed title may be derived from H1 — a stable Swift sort against the resolved title gives correct alphabetic order without re-running the FTS5 join.
- **Recursion toggle stores the exception set (`nonRecursiveFolders`).** Default = recursive; the set holds folders the user explicitly turned off. Cheaper to persist than a per-folder boolean, and matches the user's "most folders show everything" mental model.
- **Theme tokens deferred** (see task above). Pulled out of phase-2 scope; semantic-color SwiftUI tokens carry the row visually for now.
- **Preview format = `[date · preview]` on one line**, not `date` and `preview` on separate lines. Two-line row (title + meta) reads cleaner at the chosen row height than three lines and matches Notes' visual density.

#### Verification screenshots
- 3-pane with rich list rows: docs folder showing 16 notes with H1-derived titles + 1-line previews
- Recursion icon toggling between filled `rectangle.stack.fill` (blue accent) and outline `rectangle` (secondary gray)
- Sort menu opened with all 4 options + checkmark on current selection
- Sort by Title reordering by derived H1: "Expansion Implementation Plan", "Expansion Progress", "List View ...", "Live Editor ...", "Markdown Rendering Architecture", "Mobile ...", "Test"

#### Blockers
- (none — phase complete)

---

### Phase 3: Keyboard, edge cases, persistence
**Status:** Completed (2026-04-29)

**Goal:** First-class polish for the 3-pane: ⌘N targets the active folder, Cmd-click opens in a new tab, the selected folder is visually distinct, and sidebar file-click keeps the middle pane in sync.

#### Tasks
- [x] Arrow-key nav + Enter/Space to focus editor — already works via SwiftUI `List(selection:)`. No additional code needed.
- [x] `⌘N` creates note in `selectedFolderURL` (new `WorkspaceManager.createNewNoteInActiveContext()` helper, called from both the `File → New Document` menu binding *and* the `MacDetailColumn` toolbar button — both have `keyboardShortcut("n")` and the toolbar binding wins for the keyboard shortcut, so both must call the same helper)
- [x] Cmd-click row → new tab — added a second `SidebarClickModifierWatcher` to the list pane in `MacRootView`, sharing the same modifier-state with the sidebar; the existing `onChange(of: selectedFileURL)` handler routes cmd-clicks to `openFileInNewTab`
- [x] Sidebar selected-folder highlight — folder rows in `MacFolderSidebar.outlineRow(node:)` now compute `isSelected = workspace.selectedFolderURL == node.url`, and `SelectionPill` renders a subtle gray pill background. Distinguishable from file selection (uses default neutral pill, not the bright accent file selection gets)
- [ ] `⌘L` cycles `NavigationSplitViewVisibility` in 3-pane mode — **deferred to phase 4**. Existing AppDelegate routing of `⌘L` to `NSSplitViewController.toggleSidebar(_:)` already handles the leftmost column collapse correctly in 3-pane; cycling through middle-pane visibility is nice-to-have polish, not a blocker.
- [x] Restore selection on launch — `selectedFolderURL` persists via UserDefaults path string (phase 1), `layoutMode` persists via `@AppStorage` (phase 1), `noteListSortOrder` and `nonRecursiveFolders` persist (phase 2). All four restore correctly on relaunch. Verified live.
- [x] Sidebar file-click syncs `selectedFolderURL` to parent — added to `MacRootView.onChange(of: selectedFileURL)`: when a file URL becomes the active selection, set `selectedFolderURL` to its parent directory if that parent lives inside a registered vault. Cheap no-op in 2-pane mode, makes the middle list "follow" sidebar navigation in 3-pane.
- [x] Vault-removal degrades gracefully — already done in phase 1 via `clearSelectedFolderIfInside(_:)` hook in `WorkspaceManager.removeLocation`.
- [ ] Layout-switch animation polish — **deferred to phase 4**. The simple conditional rebuild flashes briefly; not worth fighting SwiftUI for now.
- [x] `CHANGELOG.md` entry under Unreleased: "Notes-style 3-pane layout: optional middle column listing notes…"

#### Decisions Made
- **Centralized ⌘N logic in `WorkspaceManager.createNewNoteInActiveContext()`** rather than duplicating the conditional across the menu binding and the toolbar button. *Critical*: there are TWO `⌘N` keyboard shortcut bindings — one in `ClearlyApp.commands` (File menu) and one in `MacDetailColumn`'s toolbar item. The toolbar binding wins for keyboard activation, so both call sites must route through the same helper. Discovered the hard way during smoke testing — initial fix only updated the menu binding and Cmd+N kept hitting the legacy `createUntitledDocument` path until `MacDetailColumn` was also updated.
- **Read `layoutMode` straight from `UserDefaults` inside `createNewNoteInActiveContext`** instead of via `@AppStorage`. The keyboard shortcut closure can fire with a stale `@AppStorage` projection if the host view's body hasn't refreshed since the user toggled layout. `UserDefaults.standard.string(forKey:)` is always current.
- **Folder-click in sidebar always sets `selectedFolderURL`**, regardless of layout mode. Harmless in 2-pane (the value just persists, nothing visible changes); useful in 3-pane. Avoids the complexity of a layout-aware click handler.
- **`⌘L` cycle and layout-switch animation deferred to phase 4** — both are polish. The feature is fully usable without them.
- **Sidebar file-click sync uses `vaultIndexAndRelativePath` as a sanity check** before setting `selectedFolderURL`. Pinned/Recents files that span vaults won't accidentally point the middle list at a folder outside any registered vault.

#### Verification screenshots
- Selected-folder highlight: `expansion` folder row visibly highlighted with selection pill while siblings (list-view, mobile, wiki) are not — confirmed by zoomed inspection
- ⌘N keyboard shortcut: created `docs/expansion/untitled.md` (verified on filesystem) and opened it in a new tab as `untitled.md`
- Cmd-click on a list row: opened "Expansion Implementation Plan" in a NEW tab adjacent to the existing `untitled.md` tab, instead of replacing the active tab
- Sidebar file-click sync: clicking a file in the sidebar moved the middle list to its parent folder (auto-sync verified by re-launching with state restored)

#### Blockers
- (none — phase complete; ⌘L cycle and animation polish deferred to phase 4 stretch)

---

### Phase 4: Stretch (optional)
**Status:** Not Started

**Goal:** Polish + future-proofing; pull tasks individually based on dogfood feedback.

#### Tasks
- [ ] Folder-scoped search field
- [ ] Drag list row → sidebar folder (move)
- [ ] Drag Finder file → list (import)
- [ ] 5K-note vault perf audit
- [ ] Font-size scaling
- [ ] Localized date formatting
- [ ] Fix CLAUDE.md `DocumentGroup` reference
- [ ] Fork / upstream PR prep

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

## Session Log

### 2026-04-29 — Planning
- Read brief at `nathan-docs/List-View-Brief.md` and screenshots.
- Mapped current 2-pane architecture via Explore subagent.
- Validated 4 scope decisions with the user (list source = any folder, recursion = user-toggle default-on, rows = title+date+preview, toggle = settings + shortcut).
- Wrote `RESEARCH.md` and `IMPLEMENTATION.md`.
- 3 medium phases + 1 stretch phase agreed.

### 2026-04-29 — Phase 3 implemented
- Added selected-folder highlight in `MacFolderSidebar.outlineRow(node:)` for nested folders. Top-level location section headers don't yet highlight (deferred — section header styling is its own can of worms).
- Centralized ⌘N logic in `WorkspaceManager.createNewNoteInActiveContext()`, called from both the App menu binding and `MacDetailColumn` toolbar button. Discovered during testing that two ⌘N bindings exist; toolbar wins for keyboard activation, so both must route through the same helper.
- `MacRootView.onChange(of: selectedFileURL)` now sets `selectedFolderURL = url.deletingLastPathComponent()` so the middle list follows sidebar/recents file selection.
- Added second `SidebarClickModifierWatcher` to the list pane, sharing modifier-state with the sidebar. Existing onChange handler routes cmd-clicks through `openFileInNewTab` for the list pane the same way it does for the sidebar.
- CHANGELOG.md entry added under Unreleased.
- Build clean. Smoke-tested ⌘N (creates `expansion/untitled.md`), Cmd-click on list row (opens new tab), folder highlight (visible pill on `expansion`), session restore (layoutMode + sort + selectedFolderURL all return).

### 2026-04-29 — Phase 2 implemented
- Created `Packages/ClearlyCore/Sources/ClearlyCore/Vault/NoteSummary.swift` (value type + `NoteListSortOrder` enum, both `Sendable`).
- Created `Packages/ClearlyCore/Sources/ClearlyCore/Vault/VaultIndex+Summaries.swift` with `summaries(folderRelativePath:recursive:sort:)` and frontmatter/H1/preview parsing.
- Relaxed `dbPool` from `private` to internal so the same-module extension can run reads.
- Added `nonRecursiveFolders: Set<String>`, `isFolderRecursive(_:)`, `setFolderRecursive(_:for:)`, `noteListSortOrder`, `setNoteListSortOrder(_:)`, and `vaultIndexAndRelativePath(for:)` to `WorkspaceManager`. All persist via UserDefaults.
- Rewrote `MacNoteListView` to drive off `[NoteSummary]` from VaultIndex, with a `Task.detached(priority: .userInitiated)` query, debounced via `task(id: reloadKey)`, and reload triggers on `treeRevision`, `vaultIndexRevision`, location changes, sort change, recursion change.
- New `NoteListRow` view: bold title + secondary date · tertiary preview; relative date formatting (`HH:mm` for today, "Yesterday", weekday for last 7 days, abbreviated date older).
- Added header controls: recursion-toggle button (filled stack icon when on, outline rectangle when off) and sort menu with checkmark on current order.
- Build clean in Debug. Smoke-tested in `Clearly Dev` against the worktree's `docs/` folder: 16 notes with H1-derived titles, previews from first non-H1 body line, sort menu reorders correctly, recursion toggle flips state per folder.

### 2026-04-29 — Phase 1 implemented
- Created `Clearly/Native/LayoutMode.swift` (enum, storageKey constant).
- Added `selectedFolderURL` + `setSelectedFolder(_:)` + `restoreSelectedFolder()` + `clearSelectedFolderIfInside(_:)` to `WorkspaceManager`.
- Created `Clearly/Native/MacNoteListView.swift` with header, ContentUnavailable empty states, recursive FileNode flatten, modified-desc sort, title + relative-time row.
- Refactored `MacRootView` to extract `sidebarColumn` / `detailColumn` and conditionally render 2-col vs 3-col `NavigationSplitView`.
- Added `.simultaneousGesture` folder-click handlers in `MacFolderSidebar` for location headers and nested folder rows.
- Added Layout picker to `SettingsView` General tab with helper text.
- Added View menu commands "Two-Pane Layout" `⌥⌘2` and "Three-Pane Layout" `⌥⌘3`.
- `xcodegen generate` + `xcodebuild` Debug build clean.
- Smoke-tested in `Clearly Dev`: layout toggle both ways, Settings picker, View menu items, sidebar folder click changes middle list, list row click opens file in editor, recursive listing of `docs/` correctly shows 16 notes sorted modified-desc.

---

## Files Changed

Phase 1:
- `Clearly/Native/LayoutMode.swift` (new)
- `Clearly/Native/MacNoteListView.swift` (new)
- `Clearly/Native/MacRootView.swift` — split into 2/3-col conditional
- `Clearly/Native/MacFolderSidebar.swift` — folder-click handlers
- `Clearly/WorkspaceManager.swift` — `selectedFolderURL` + persistence + cleanup
- `Clearly/SettingsView.swift` — Layout picker
- `Clearly/ClearlyApp.swift` — View menu items + shortcuts
- `Clearly.xcodeproj/` — regenerated by xcodegen

Phase 2:
- `Packages/ClearlyCore/Sources/ClearlyCore/Vault/NoteSummary.swift` (new)
- `Packages/ClearlyCore/Sources/ClearlyCore/Vault/VaultIndex+Summaries.swift` (new)
- `Packages/ClearlyCore/Sources/ClearlyCore/Vault/VaultIndex.swift` — `dbPool` access relaxed from `private` to internal
- `Clearly/WorkspaceManager.swift` — added `nonRecursiveFolders`, `noteListSortOrder`, `isFolderRecursive`, `setFolderRecursive`, `setNoteListSortOrder`, `vaultIndexAndRelativePath`
- `Clearly/Native/MacNoteListView.swift` — rewritten to use `NoteSummary` + `VaultIndex.summaries`, added sort menu and recursion toggle in header

Phase 3:
- `Clearly/WorkspaceManager.swift` — added `createNewNoteInActiveContext()` helper
- `Clearly/Native/MacFolderSidebar.swift` — folder rows compute `isSelected` against `workspace.selectedFolderURL`
- `Clearly/Native/MacRootView.swift` — list pane gets `SidebarClickModifierWatcher`; `onChange(of: selectedFileURL)` syncs `selectedFolderURL` to parent
- `Clearly/Native/MacDetailColumn.swift` — toolbar `⌘N` button calls `createNewNoteInActiveContext()`
- `Clearly/ClearlyApp.swift` — File menu `⌘N` button calls `createNewNoteInActiveContext()`
- `CHANGELOG.md` — entry under Unreleased

## Architectural Decisions
- **3-column `NavigationSplitView`** chosen over manual `HStack` for platform polish.
- **Layout-switch causes view rebuild** — accepted, brief flash OK.
- **Preview source = `files_fts.content`** — no new schema, in-process SQLite, ~800 bytes per row read.
- **Default recursion = on**, persist the *exception* set (`nonRecursiveFolders`) rather than every visited folder.
- **Mac-only** — iOS uses `WindowGroup` with its own sidebar; no shared UI.

## Lessons Learned
(none yet)
