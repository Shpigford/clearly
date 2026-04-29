# List View Implementation Plan

## Overview

Ship a Notes-style 3-pane layout (folder sidebar | note list | editor) on Mac, opt-in via a Settings picker plus `⌥⌘2` / `⌥⌘3` shortcuts. Strategy: each phase ends with a layout that's *usable end-to-end*, not just plumbing — the foundation phase ships a working (if minimal) list, the polish phase makes it feel like Notes, and the keyboard phase makes it feel first-class.

See [docs/list-view/RESEARCH.md](docs/list-view/RESEARCH.md) for the architectural map and decision rationale.

## Prerequisites

- macOS 15 SDK / Xcode 26+ (already required by the project — no changes).
- No new SPM dependencies. `ClearlyCore` (`GRDB`, `cmark-gfm`) already covers everything we need.
- `xcodegen generate` workflow understood (`project.yml` snapshots the file list — adding new files requires a regen).
- All commits use the `[mac]` scope prefix (this is Mac-only — see [CLAUDE.md](CLAUDE.md) "Commit message rule"). The new `NoteSummary` type and `VaultIndex.summaries(...)` query land inside `ClearlyCore` so technically also benefit iOS, but no iOS UI consumes them — these still land under `[mac]` until/unless an iOS phase uses them.

## Phase Summary

| # | Phase | Result the user can test |
|---|-------|--------------------------|
| 1 | **Foundation + minimum viable list** | Toggle 3-pane mode in Settings or with `⌥⌘3`, see a real list of notes for the active folder, click rows to open. |
| 2 | **Notes parity polish** | List rows show title + date + 1-line preview from VaultIndex; per-folder recursion toggle; sort menu; live updates on disk changes. |
| 3 | **Keyboard, edge cases, persistence** | Arrow-key nav, `⌘N` to create in current folder, Cmd-click → new tab, sidebar folder-selection highlight, restored selection on launch, `⌘L` cycles columns sensibly. |
| 4 | **Stretch (optional)** | Folder-scoped search in list header, drag-drop, performance audit on 5K-note vault, fork/PR prep. |

---

## Phase 1: Foundation + minimum viable list

### Objective

End-to-end 3-pane layout works. User can flip to it, see a list of notes in a chosen folder, click any note, and the editor opens it. Visual polish is rough — the goal is an honest, usable slice we can dogfood.

### Rationale

The riskiest plumbing — `NavigationSplitView` 3-column form, `LayoutMode` switch causing view-tree rebuild, sidebar folder-click introducing a new selection axis — is best validated with a working slice rather than scaffolded blind. The list rows can use the existing in-memory `FileNode` tree, deferring `VaultIndex` work to phase 2. The split here is "make the layout real" vs "make the rows pretty".

### Tasks

- [ ] Add `LayoutMode` enum (`.twoPane`, `.threePane`) in a new `Clearly/Native/LayoutMode.swift`.
- [ ] Add `@AppStorage("layoutMode")` in `MacRootView` and propagate as needed.
- [ ] Add `WorkspaceManager.selectedFolderURL: URL?` (published / `@Observable`), defaulted on first 3-pane entry to the first location's root URL.
- [ ] Persist `selectedFolderURL` as a security-scoped bookmark (use existing `BookmarkedLocation` patterns) under UserDefaults key `selectedFolderBookmark`. On load, resolve and validate; on failure, fall back to first location.
- [ ] Switch `MacRootView.body` to a `@ViewBuilder` that picks 2-column or 3-column `NavigationSplitView` from `layoutMode`. Reuse the existing `sidebar` and `detail` view-builders unchanged.
- [ ] Create `Clearly/Native/MacNoteListView.swift` with:
   - Header: folder name (from `selectedFolderURL.lastPathComponent`), note count.
   - Body: `List(notes, id: \.url, selection: $selectedNoteURL)`.
   - Row: filename without `.md` extension + modified date (`url.resourceValues(forKeys: [.contentModificationDateKey])`). One-line subtitle, no preview yet.
   - Recursion is **always-on** in this phase (no toggle yet — phase 2).
   - Source: traverse `BookmarkedLocation.fileTree` for the location containing `selectedFolderURL`, find the matching `FileNode`, recursively flatten its leaves.
   - Sort: modified-desc only (no menu yet).
   - Empty states: "No folder selected" / "No notes here".
- [ ] Wire `MacNoteListView` into `MacRootView` `content:` slot of the 3-column variant. Bind selection bidirectionally to `workspace.currentFileURL` via `selectedNoteURL`.
- [ ] In `MacFolderSidebar`, add folder-row click handling: clicking a folder row sets `workspace.selectedFolderURL` *and* toggles expansion (current behavior). No visual highlight yet — phase 3.
- [ ] Add Settings picker (General tab in [Clearly/SettingsView.swift](Clearly/SettingsView.swift)):
  ```
  Layout: [ Two pane (sidebar + editor) ▾ ]
          (description text below)
  ```
  Bound to the same `@AppStorage("layoutMode")`.
- [ ] Add menu items in `ClearlyAppDelegate` or wherever `View` menu commands live:
  - **View → Two-Pane Layout** (`⌥⌘2`)
  - **View → Three-Pane Layout** (`⌥⌘3`)
  Both write to `UserDefaults` under `layoutMode` so the `@AppStorage` reflects.
- [ ] `xcodegen generate` after adding new source files; commit the regenerated `.xcodeproj`.
- [ ] Manual test: launch app, flip to 3-pane via shortcut, click a folder, click a note, verify editor opens. Flip back to 2-pane, confirm everything looks identical to before. Quit, relaunch, confirm `layoutMode` persists.

### Success Criteria

- Settings picker switches layouts cleanly (no crash, no broken state).
- `⌥⌘2` / `⌥⌘3` switch layouts.
- In 3-pane mode, the middle column shows real notes from a real folder.
- Clicking a list row opens that note in the editor (or the active tab).
- Layout choice persists across launches.
- No regression in 2-pane mode (sidebar selection, tabs, editor).
- All Sparkle / App Store builds compile (`#if canImport(Sparkle)` not affected).

### Files Likely Affected

- `Clearly/Native/LayoutMode.swift` (new)
- `Clearly/Native/MacNoteListView.swift` (new)
- `Clearly/Native/MacRootView.swift`
- `Clearly/Native/MacFolderSidebar.swift`
- `Clearly/SettingsView.swift`
- `Clearly/ClearlyApp.swift` (menu commands)
- `Clearly/.../WorkspaceManager.swift` (new property + persistence)
- `project.yml` only if a new directory needs explicit listing (xcodegen globs should pick up new files in `Clearly/Native/`)

---

## Phase 2: Notes parity polish

### Objective

The middle pane *feels* like Notes. Three-line rows with title + 1-line preview + date, reading from `VaultIndex` (no extra disk I/O). Per-folder recursion toggle. Sort menu. Live updates when files change on disk. Selection styling matches Clearly's theme.

### Rationale

Phase 1 proved the layout works; phase 2 makes it actually nice to use. We pull preview + metadata from the FTS5 index instead of re-reading files, which keeps even 5K-note folders snappy.

### Tasks

- [ ] Add `NoteSummary` value type in `Packages/ClearlyCore/Sources/ClearlyCore/Vault/NoteSummary.swift`:
  ```swift
  public struct NoteSummary: Hashable, Identifiable {
      public let id: URL          // same as url
      public let url: URL
      public let title: String    // H1 if present, else filename without ext
      public let modifiedAt: Date
      public let preview: String  // first non-empty non-frontmatter line, ~120 chars
  }
  ```
- [ ] Add `VaultIndex.summaries(folderURL: URL, recursive: Bool, sort: SortOrder) -> [NoteSummary]`:
  - SQL: `SELECT path, modified_at, substr(content, 1, 800) FROM files JOIN files_fts ON ... WHERE path LIKE ?` with the right pattern depending on `recursive`.
  - Compute `title` and `preview` in Swift from the content chunk.
  - Frontmatter detection: if content starts with `---\n`, skip until the next `---\n`.
  - First H1 detection: scan first ~10 non-empty non-frontmatter lines for `# `.
  - Preview: first non-empty non-H1 non-frontmatter line, trimmed.
- [ ] Add `WorkspaceManager.nonRecursiveFolders: Set<String>` (URL `path` strings), persisted in UserDefaults. Helper: `isRecursive(folderURL:) -> Bool` defaulting to `true` unless in the set.
- [ ] Add `WorkspaceManager.noteListSortOrder: NoteListSortOrder` (`.modifiedDesc`, `.modifiedAsc`, `.titleAsc`, `.titleDesc`), persisted.
- [ ] Update `MacNoteListView` to use `[NoteSummary]` instead of `[FileNode]`:
  - On `selectedFolderURL` / recursion / sort change: `Task { let summaries = await vaultIndex.summaries(...); await MainActor.run { self.summaries = summaries } }`.
  - Debounce reloads at 100ms to coalesce bursts during indexing.
- [ ] Refresh on `VaultIndex` change. If `VaultIndex` doesn't already publish a "did change" signal, hook into the existing `WorkspaceManager.reindexAllVaults` post-step or add a `Notification.Name` it posts. Keep it simple — coarse-grained "something changed in this vault" is enough; the list re-queries.
- [ ] Build a real `NoteListRow` view:
  - Title: `.body.weight(.semibold)`, single line, truncate.
  - Preview: `.callout`, secondary color, single line, truncate.
  - Date: `.caption`, tertiary color (relative format for today/yesterday, short date otherwise — match Notes).
  - Row height: ~62pt; horizontal padding: 12pt.
  - Selection: filled rounded rectangle in `Theme.accentColor` at low opacity (light) / accent at higher opacity (dark). Match the existing sidebar selection treatment in `MacFolderSidebar`.
- [ ] Add list-pane header controls:
  - Folder name + count (already there from phase 1).
  - **Sort menu** (Menu with chevron icon): "Date Modified" (default), "Date Modified (oldest first)", "Title", "Title (Z-A)".
  - **Recursion toggle** button: a "show subfolders" toggle whose state mirrors `workspace.isRecursive(folderURL:)` for the current folder. Tooltip: "Include subfolders".
- [ ] Empty / loading states:
  - Folder selected but query in flight: subtle progress indicator.
  - Folder empty: "No notes in {folder}. ⌘N to create one." (⌘N is wired in phase 3 — message appears now, key works in phase 3.)
- [ ] Update `Theme.swift`: add semantic tokens `noteListSelectionBackground`, `noteListPreviewText`, `noteListDateText`, `noteListSeparator`. Light / dark resolution via existing `NSColor(name:)` pattern.
- [ ] Manual test on a real vault (Nathan's main vault):
  - Switch sort orders, confirm rows reorder.
  - Toggle recursion on a folder with subfolders, confirm rows include / exclude.
  - Edit a note in the editor, save, watch the row's preview / date update.
  - Create a file outside the app (e.g. `touch foo.md` in Finder), confirm it appears within ~1s.

### Success Criteria

- Each row shows title + preview + date, accurately matching the file content.
- Preview correctly skips frontmatter and uses H1 → title heuristic.
- Sort menu changes order without a flicker.
- Recursion toggle persists per folder.
- External file edits appear in the list within a couple of seconds.
- A 1,000-note recursive folder loads in <100ms (timed locally — not a CI target).
- Visual treatment matches Clearly's existing sidebar (no jarring style break).

### Files Likely Affected

- `Packages/ClearlyCore/Sources/ClearlyCore/Vault/NoteSummary.swift` (new)
- `Packages/ClearlyCore/Sources/ClearlyCore/Vault/VaultIndex.swift`
- `Clearly/Native/MacNoteListView.swift`
- `Clearly/.../WorkspaceManager.swift`
- `Clearly/Theme.swift`
- `project.yml` if `Packages/ClearlyCore/Sources/ClearlyCore/Vault/NoteSummary.swift` isn't covered by glob (it should be).

---

## Phase 3: Keyboard, edge cases, persistence

### Objective

The feature feels first-class. Arrow keys move through the list and live-update the editor. `⌘N` creates a note in the active folder. Sidebar shows a "selected folder" highlight. State restores cleanly on launch including across vault changes. `⌘L` cycles column visibilities sensibly in 3-pane mode.

### Rationale

After phase 2 the feature is shippable, but small frictions remain — the kind a user notices on day 3 of using it ("why doesn't `⌘N` go in this folder?"). Phase 3 is the pass that takes it from "working" to "good".

### Tasks

- [ ] **Keyboard nav.** SwiftUI `List` with `selection:` already handles ↑/↓. Verify focus / tab order is sane and that arrow keys don't fall through to the sidebar. Add `.focusable(true)` or move focus rings as needed.
- [ ] **Enter / Space → focus editor.** Add a key handler on the list that calls `NSApp.keyWindow?.makeFirstResponder(...)` on the underlying text view.
- [ ] **`⌘N` in current folder.** Wire the existing "New Note" command (or a new variant) so that when the list pane has focus, the new note is created at `workspace.selectedFolderURL` rather than the default location. If a "New Note" already targets a folder, just confirm it picks up `selectedFolderURL`.
- [ ] **Cmd-click row → new tab.** Match the sidebar's existing pattern. The List's selection binding doesn't differentiate modifier keys; intercept with an `NSEvent` modifier check inside the row's `onTapGesture` or use a `.simultaneousGesture(TapGesture().modifiers(.command))` if available, else a fallback.
- [ ] **Sidebar "selected folder" highlight.** Update `MacFolderSidebar` folder-row rendering to apply a subtle background when the row's URL matches `workspace.selectedFolderURL`. Different from the file-selection highlight (which is brighter). Test in light + dark mode.
- [ ] **`⌘L` cycle column visibilities** in 3-pane mode. Bind `NavigationSplitViewVisibility` state and on `⌘L` cycle: `.all → .doubleColumn (sidebar+content) → .detailOnly → .all`. In 2-pane keep current behavior (toggle sidebar only).
- [ ] **Restore selection on launch.** On app launch, if `selectedFolderURL` resolves successfully, the middle list shows it and selects the most-recently-edited note inside (if no other selection is restored from tabs).
- [ ] **Sidebar selection of a file in 3-pane** — sets `selectedFolderURL` to the parent folder if it's not already, so the middle list scrolls to and highlights that file.
- [ ] **Edge case: active folder vault is removed.** If the user removes the bookmarked vault containing `selectedFolderURL`, fall back to the first remaining location's root, or `nil` if no locations. Don't crash, don't show stale data.
- [ ] **Edge case: layout flip with no locations.** If 3-pane is on but no vaults are bookmarked, show "Open a folder to get started" in the middle pane (not an empty list).
- [ ] **Layout-switch animation polish.** Test the perceived flicker of switching between 2-pane and 3-pane. If noticeable, wrap the conditional in a `withAnimation(.easeInOut(duration: 0.18))`. If still distracting, defer the actual switch by 1 frame to let the existing pane fade out. Don't over-engineer — a brief flash is acceptable.
- [ ] **CHANGELOG.md** entry under unreleased (Mac scope): "Add Notes-style 3-pane layout (Settings → General → Layout, or `⌥⌘3`)".
- [ ] Manual test pass on a fresh vault, an existing vault, and after removing a vault. Confirm no crashes, no orphan state.

### Success Criteria

- Arrow keys, `Enter`, `⌘N`, Cmd-click all behave correctly without surprises.
- Selected folder is visually distinguishable in the sidebar.
- Quitting and relaunching restores the layout, the selected folder, and the selected note.
- Removing a vault while in 3-pane mode degrades gracefully.
- `⌘L` cycle is intuitive (try with another user / dogfood for a day).
- CHANGELOG mentions the feature.

### Files Likely Affected

- `Clearly/Native/MacRootView.swift`
- `Clearly/Native/MacNoteListView.swift`
- `Clearly/Native/MacFolderSidebar.swift`
- `Clearly/.../WorkspaceManager.swift`
- `Clearly/ClearlyApp.swift` (menu commands, `⌘N` rerouting)
- `CHANGELOG.md`

---

## Phase 4: Stretch (optional)

### Objective

Polish + future-proofing. Run only if there's appetite after phase 3 ships. Each task is independent.

### Rationale

These are nice-to-haves identified in research that didn't make the cut for "minimum great version". Listed here so they don't get lost; pull individually based on dogfood feedback.

### Tasks

- [ ] **Folder-scoped search field** in the list-pane header. Filters the displayed `[NoteSummary]` against title + preview + (optionally) full content via `files_fts MATCH`.
- [ ] **Drag a list row to another folder in sidebar** → moves the file. Reuse existing move handlers.
- [ ] **Drag a `.md` file from Finder onto the list** → imports to current folder.
- [ ] **Performance audit** with a 5K-note vault. Profile FTS5 query, Swift preview extraction, SwiftUI `List` virtualization. Set a perceived-instant target (<100ms folder switch).
- [ ] **Font size respect** — middle list rows should scale with the user's editor font size if `Settings → General → Editor font size` changes (or pick a separate "List density" control).
- [ ] **Localized date formatting** — confirm the row date format respects system locale and 12/24-hour preference.
- [ ] **Fix CLAUDE.md outdated `DocumentGroup` reference** (line 26 says document-based; codebase is `Window`-based). Trivial doc fix; flag here so it's not lost.
- [ ] **Fork / upstream PR prep.** Update README screenshot, draft PR description, branch off a clean base, share with original author per the brief.

### Success Criteria

(Each task has its own pass/fail. Phase 4 is "done" when the team decides not to pull more from it.)

### Files Likely Affected

Various — depends on which tasks pull.

---

## Post-Implementation

- [ ] Take updated screenshots of 3-pane mode for the marketing site / README.
- [ ] Confirm `[mac]` commit scope discipline held — `/release` skill should pick up the changelog entry cleanly.
- [ ] Verify the App Store build (`scripts/release-appstore.sh` dry run) compiles without Sparkle. Nothing in this feature touches Sparkle, so it should — but check anyway.
- [ ] Verify Debug build still launches and signs cleanly (no entitlement drift).
- [ ] Spawn task: `nathan-docs/List-View-Brief.md` can be archived or moved into `docs/list-view/BRIEF.md` since the brief lives outside the repo currently.

## Notes

### Decisions baked in (from research)

- **List source = any folder** (locations + nested folders). PINNED / RECENTS / TAGS keep their existing sidebar UI and don't drive the list pane.
- **Recursion = user-toggle per folder, default recursive.** Toggle in list-pane header.
- **Row content = title + modified date + 1-line preview.** Preview from `files_fts.content`.
- **Toggle scope = Settings + keyboard shortcut + menu items.** No toolbar button.

### Architectural decisions made during planning

- **Use `NavigationSplitView` 3-column form, not manual `HStack`** — see RESEARCH.md "Rejected alternatives". Loses platform polish if we hand-roll.
- **Layout switch causes a `NavigationSplitView` rebuild** — tested approach; brief flash acceptable. Don't over-engineer animation.
- **Use existing `files_fts.content` for previews** — no new column / index. Read first 800 bytes per row, parse in Swift.
- **Default `recursive = true` per folder, store the exception set (`nonRecursiveFolders`)** — cheaper to store the few folders the user explicitly turned off than every folder they've visited.

### Things explicitly out of scope for v1

- Tags / Pinned / Recents as middle-list sources (user said no).
- Multi-folder selection in sidebar.
- Note creation/move/rename UX changes beyond `⌘N`.
- iOS layout work — iOS uses its own `WindowGroup` flow and is unaffected.

### Risks deferred to phase 3

- Sidebar selection-axis confusion (folder click means "select" + "expand").
- Restore-on-launch with stale security bookmarks.

### Risks deferred to phase 4 (stretch)

- 5K-note perf headroom.
- Drag-drop interactions with the new pane.
