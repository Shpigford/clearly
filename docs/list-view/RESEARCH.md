# List View (Notes-style 3-pane layout) Research

## Overview

Add an optional Notes-style three-pane layout to Clearly on Mac:

```
┌──────────────┬─────────────────┬──────────────────────────────┐
│ Folder       │ Note list       │ Editor / Preview             │
│ sidebar      │ (notes in       │                              │
│              │  selected       │                              │
│              │  folder)        │                              │
└──────────────┴─────────────────┴──────────────────────────────┘
```

The current 2-pane layout (sidebar → editor) stays as the default. Users pick between layouts in **Settings → General**, plus a keyboard shortcut (and corresponding menu item) for fast switching.

iOS is out of scope.

## Problem Statement

Clearly's left sidebar shows a recursive folder/file tree (all locations expanded together). For users coming from Apple Notes, this is unfamiliar — Notes uses a dedicated middle column that lists notes in the currently-selected folder, with title + date + first-line preview, and arrow keys flick between notes. That column is the primary "scanning" surface in Notes, and several users (Nathan, the brief author) miss it in Clearly.

A 3-pane mode lets long-time Notes users feel at home, while keeping the existing 2-pane mode for users who prefer the dense tree.

## User Stories

1. **As a Notes refugee**, I want a middle list of notes in the folder I just clicked, so I can scan recent edits the way I do in Notes.
2. **As a power user**, I want to switch layouts with a keyboard shortcut so I can collapse to the dense tree when I'm searching, then return to the list view for browsing.
3. **As an existing Clearly user**, I want the default to stay 2-pane so nothing changes for me unless I opt in.
4. **As a new user**, I want to discover the option in Settings → General without hunting.
5. **As a keyboard-driven user**, I want arrow keys in the middle list to move between notes and immediately swap the editor (Notes parity).

## Decisions Locked In (from brief)

These were validated with the user up front; the rest of the doc treats them as fixed.

| Decision | Choice | Notes |
|----------|--------|-------|
| What populates the middle list | **Any folder** (locations + nested folders) | PINNED / RECENTS / TAGS keep their existing sidebar UI and do **not** drive the list pane |
| Recursion | **User-toggle per folder, default recursive** | Toggle lives in the list pane header, persists per folder |
| Row content | **Title + modified date + 1-line preview** | Match Notes' visual density |
| Layout switching | **Settings picker + keyboard shortcut + menu item** | No toolbar button — keep toolbar uncluttered |

## Current Architecture (from codebase exploration)

Mapped in detail by an Explore subagent. Key file:line references:

### Window scene
- [Clearly/ClearlyApp.swift:742](Clearly/ClearlyApp.swift) — single `Window("Clearly", id: "main")` hosting `MacRootView(workspace:)`. Not a `DocumentGroup`. `defaultSize: 1100×720`.
- Settings scene at [Clearly/ClearlyApp.swift:958](Clearly/ClearlyApp.swift) routes to `SettingsView`.

### 2-pane layout root
- [Clearly/Native/MacRootView.swift:36](Clearly/Native/MacRootView.swift) — `NavigationSplitView(columnVisibility: $columnVisibility) { sidebar } detail: { editor }`.
- Sidebar column: `MacFolderSidebar` (220 / 260 / 360 width).
- Detail column: `VStack { MacTabBar; MacDetailColumn }` with toolbar attached at root.
- `selectedFileURL` binding flows: sidebar tag → `MacRootView.onChange(of: selectedFileURL)` → `workspace.openFile(at:)`. Reverse sync: `onChange(of: workspace.currentFileURL)` → `selectedFileURL`.

### Sidebar
- [Clearly/Native/MacFolderSidebar.swift](Clearly/Native/MacFolderSidebar.swift) — SwiftUI `List` with `.sidebar` style; sections PINNED, LOCATIONS, RECENTS, TAGS.
- File-tree rows render `FileNode` items recursively, tagged with `.tag(node.url)` for selection.
- Folder expansion state in `workspace.expandedFolderPaths: Set<String>` (UserDefaults `expandedFolderPaths`).
- Location collapse state in `workspace.collapsedLocationIDs: Set<String>` (UserDefaults `collapsedLocationIDs`).
- **No current concept of a "selected folder"** — every visible row is a leaf file or an expanded folder header. Adding 3-pane mode means introducing a new selection axis: the active folder.

### Workspace state
- [Clearly/.../WorkspaceManager.swift](Clearly/) — `@Observable` class:
  - `openDocuments: [OpenDocument]`, `activeDocumentID: UUID?`
  - `currentFileURL: URL?`, `currentFileText: String`, `isDirty: Bool`
  - `locations: [BookmarkedLocation]`
- `openFile(at:)` / `openFileInNewTab(at:)` are the choke points the sidebar uses today; the middle list pane will use the same calls.

### Folder model
- [Packages/ClearlyCore/Sources/ClearlyCore/Vault/FileNode.swift](Packages/ClearlyCore/Sources/ClearlyCore/Vault/FileNode.swift) — recursive `FileNode { name, url, isHidden, children: [FileNode]? }`. Built via `FileNode.buildTree(at:showHiddenFiles:)` (must run off main thread — see `WorkspaceManager.loadTree(for:at:reindex:)`).
- [Packages/ClearlyCore/Sources/ClearlyCore/Vault/BookmarkedLocation.swift](Packages/ClearlyCore/Sources/ClearlyCore/Vault/BookmarkedLocation.swift) — vault entry with `id: UUID`, `url`, `bookmarkData`, `fileTree: [FileNode]`, `kind: VaultKind`.

### Vault index (FTS5 / GRDB)
- [Packages/ClearlyCore/Sources/ClearlyCore/Vault/VaultIndex.swift](Packages/ClearlyCore/Sources/ClearlyCore/Vault/VaultIndex.swift) — SQLite at `~/.clearly/indexes/{hash}.sqlite`.
- Tables: `files` (path, filename, content_hash, modified_at, indexed_at), `files_fts` (FTS5), `links`, `tags`, `headings`.
- **The `content` column on `files_fts` already holds full file content** — we can derive the 1-line preview from it without re-reading from disk.

### Settings
- [Clearly/SettingsView.swift](Clearly/SettingsView.swift) — TabView: General, Sync, Command Line, Wiki, About.
- All settings use `@AppStorage`. Existing keys include `editorFontSize`, `themePreference`, `launchBehavior`, `sidebarSize`.
- The General tab is the natural home for a new "Layout" picker.

### iOS isolation
- iOS files all live under `Clearly/iOS/`, with a separate `Clearly-iOS` target. Root is `WindowGroup` + `SidebarView_iOS`, never touched by anything in `Clearly/Native/*`. **No iOS changes needed.**

## Technical Approach

### Recommended: 3-column `NavigationSplitView`

SwiftUI `NavigationSplitView` has a 3-column form (`{ sidebar } content: { middle } detail: { editor }`) available since macOS 13. The current 2-column form would be replaced by a `@ViewBuilder` switch that picks the 2-column or 3-column variant based on the layout-mode `@AppStorage` value.

```swift
@AppStorage("layoutMode") private var layoutMode: LayoutMode = .twoPane

var body: some View {
    switch layoutMode {
    case .twoPane:
        NavigationSplitView { sidebar } detail: { editorStack }
    case .threePane:
        NavigationSplitView { sidebar } content: { noteList } detail: { editorStack }
    }
}
```

Switching `layoutMode` triggers a full `NavigationSplitView` rebuild. That's acceptable — it happens at most a handful of times per session and the user explicitly initiated it.

#### Rejected alternatives

- **Manual `HStack` with three children + draggable dividers.** Loses all the platform polish that `NavigationSplitView` ships for free: column collapse via Cmd+L, fullscreen behavior, sidebar toolbar slot styling, restore of column widths, Liquid Glass treatment on macOS 26. We already use `NavigationSplitView` for the 2-pane layout — staying consistent costs us nothing.
- **Keep `NavigationSplitView` 2-column and shoehorn the list into the sidebar via internal `HSplitView`.** Defeats the purpose — the user wants a real, resizable middle column with its own toolbar slot, not a nested split inside the sidebar.

### New state additions

In `WorkspaceManager`:

| Property | Type | Purpose | Persistence |
|----------|------|---------|-------------|
| `selectedFolderURL` | `URL?` | The folder whose contents drive the middle list. `nil` = no selection (empty state). | UserDefaults bookmark, restored on launch |
| `recursiveFolders` | `Set<String>` | Folder URLs (as bookmarked path strings) where the user toggled "show subfolder contents". Default for any folder = recursive on. So this is actually `nonRecursiveFolders` — folders the user explicitly flipped off. Cheaper to store the exception set. | UserDefaults |
| `noteListSortOrder` | enum | Modified-desc (default), modified-asc, title-asc, title-desc. | UserDefaults |

In `MacRootView` / new `MacNoteListView`:

- `selectedNoteURL: URL?` — bound to the middle list's selection. Bidirectional sync with `workspace.currentFileURL`, same pattern as the existing `selectedFileURL` for the sidebar.

### New components

1. **`MacNoteListView`** (new, `Clearly/Native/MacNoteListView.swift`)
   - Receives `workspace: WorkspaceManager` and `selectedNoteURL: Binding<URL?>`.
   - Body: `List(notes, id: \.url, selection: $selectedNoteURL) { note in NoteListRow(note: note) }`.
   - Header (in `.safeAreaInset(edge: .top)`): folder name, note count, recursive toggle, sort menu, search field.
   - Drives `workspace.openFile(at:)` on selection change.
   - Cmd-click delegates to `workspace.openFileInNewTab(at:)`.
2. **`NoteListRow`** (private inside `MacNoteListView.swift`)
   - Three lines: title (bold, 1 line, truncate), preview (1 line, secondary color), date (caption, tertiary).
   - Pinned-icon badge for pinned notes.
   - Highlighted-row treatment matches Notes' yellow selection.
3. **`NoteSummary`** (new value type in `ClearlyCore/Vault/NoteSummary.swift`)
   - `{ url, title, modifiedAt, preview }`.
   - Built by a new `VaultIndex.summaries(folderURL:recursive:)` query that pulls `path`, `filename`, `modified_at`, and `substr(content, 1, 200)` from `files_fts`. First non-empty non-frontmatter line is extracted in Swift.

### Data flow for the middle list

```
selectedFolderURL changes
    └─→ MacNoteListView.task { reload summaries }
            └─→ VaultIndex.summaries(folderURL:recursive:)
                    └─→ [NoteSummary] → list rows

selectedNoteURL changes (user clicks row / arrow-keys)
    └─→ workspace.openFile(at: url)
            └─→ activeDocumentID updates → editor swaps content

External edit (file modified on disk)
    └─→ FileWatcher fires (existing) → VaultIndex.ingest → reload summaries (debounced)
```

### Sidebar behaviour in 3-pane mode

The sidebar still renders the current tree. In 3-pane mode, **clicking a folder row** sets `workspace.selectedFolderURL` instead of (only) toggling its expansion. The folder row gets a "selected" highlight. Clicking a file row still opens the file *and* sets `selectedFolderURL` to the parent folder so the middle list scrolls to and highlights that file.

Open question: does folder-click in 3-pane mode also toggle expansion (one click = both)? Recommendation: **yes**, mirroring Finder column-view feel — but the click should *select* on first click and *toggle expansion* on subsequent clicks, or always toggle (Notes' sidebar always expands on click). This is a minor UI polish call to make in the implementation phase.

### Settings UI

Add to General tab in [Clearly/SettingsView.swift](Clearly/SettingsView.swift):

```swift
Picker("Layout:", selection: $layoutMode) {
    Text("Two pane (sidebar + editor)").tag(LayoutMode.twoPane)
    Text("Three pane (Notes-style list)").tag(LayoutMode.threePane)
}
```

Plus a one-line description below it explaining what the 3-pane mode adds.

### Keyboard shortcut + menu item

Add to `View` menu (or wherever `Toggle Sidebar` lives in `ClearlyAppDelegate.commands`):

- **View → Two-Pane Layout** (`⌥⌘2`)
- **View → Three-Pane Layout** (`⌥⌘3`)

These call `setLayoutMode(.twoPane)` / `.threePane` which writes the `@AppStorage` key. The `MacRootView` rebuilds in response.

`⌘L` (toggle sidebar) keeps working; it sends the responder-chain message to the underlying `NSSplitViewController`, which handles 3-column splits identically to 2-column.

## Data Requirements

### Preview extraction

Per row we need a 1-line preview. Two viable sources:

1. **Read from disk on demand** — simple, accurate, but spins up I/O for every row when scrolling a 1000-note folder. Bad.
2. **Use `files_fts.content` (already indexed)** — fast, in-process SQLite query, single transaction.

**Recommended: source 2.** `VaultIndex` already stores file content in the FTS5 virtual table. Add a `summaries(folderURL:recursive:)` method that returns rows of `(path, modified_at, content_first_chunk)` in one query, and extract the preview line in Swift:

```swift
func extractPreview(from content: String) -> String {
    // skip frontmatter (--- ... ---) if present, then return first non-empty
    // line that isn't an H1 used as title
}
```

Title selection rule:
1. First H1 in the body (if it doesn't match the filename) → title.
2. Otherwise filename without extension.

Match the existing `MarkdownDocument` / outline-title heuristics so the list-pane title matches the editor's title bar.

### Recursive vs flat query

Both shapes covered by a single `LIKE 'folder/%'` (recursive) or `path LIKE 'folder/%' AND path NOT LIKE 'folder/%/%'` (flat) on the indexed relative path. Cheap.

### Live updates

Existing `FileWatcher` + `VaultIndex.ingest` chain handles disk changes. The middle list re-queries on:

- `workspace.selectedFolderURL` change
- `workspace.recursiveFolders` change for the active folder
- `workspace.noteListSortOrder` change
- `VaultIndex` change-publisher fires (need to verify one exists; if not, hook into the existing post-ingest path)

## UI/UX Considerations

### Notes parity, not Notes clone

Match Notes' **visual density and interactions** but stay within Clearly's design language:

- Selected row uses Clearly's accent color, not Notes' yellow (Notes' yellow is a brand mark, not a usability signal).
- Typography: `.body` (semibold) for title, `.callout` for preview, `.caption` for date — matches Clearly's sidebar typography scale.
- Row height: ~58–64pt to fit 3 lines comfortably without feeling cramped.
- Spacing: 12pt horizontal padding, 8pt vertical, 1pt separator.

### Header

```
┌──────────────────────────────────┐
│ Folder Name             [⇅] [⋯] │  ← sort menu, recursive toggle
│ 24 Notes                         │
│ ┌──────────────────────────┐    │
│ │ 🔍 Search in folder       │    │  ← scoped search (later phase, optional)
│ └──────────────────────────┘    │
├──────────────────────────────────┤
│ Note rows...                      │
```

Phase-1 ships header without the search field. Folder-scoped search is a phase-2 candidate.

### Keyboard nav

- ↑ / ↓: move selection.
- ↩ / Space: focus editor.
- ⌘N: new note in current folder.
- ⌘⌫: move note to trash (defer to existing delete handler in `WorkspaceManager`).
- ⌘F: focus list-pane search (when added).

### Empty / error states

- **No folder selected:** "Select a folder to see its notes." Centered in middle pane.
- **Folder is empty:** "No notes in {folder name}. ⌘N to create one."
- **Folder lost (security bookmark stale):** Reuse the existing `BookmarkedLocation.isAccessible` flag and show "Folder unavailable. Re-authorize in sidebar."

### Drag & drop

- Drag a list row to the sidebar to move the file (defer to existing move handlers).
- Drag a file from Finder onto the list to import to the current folder.

Both are nice-to-haves; phase out if scope tightens.

## Integration Points

| Existing system | How list-view interacts |
|-----------------|-------------------------|
| `WorkspaceManager.openFile(at:)` | List row click → openFile. No change to `WorkspaceManager` API. |
| `WorkspaceManager.openFileInNewTab(at:)` | Cmd-click row. |
| `FileWatcher` | Triggers VaultIndex.ingest → list reload. |
| `VaultIndex` | New `summaries(folderURL:recursive:)` method. Read-only — the WAL-mode multi-process access is already proven by `ClearlyCLI`. |
| `MacFolderSidebar` | Add folder-row "selected" highlight when `workspace.selectedFolderURL == folderURL`. Click handler updates `selectedFolderURL`. |
| `Theme` | New colors: list selection, list separator, list preview text. Match existing `Theme` semantics (light/dark dynamic). |
| `MacTabBar` | Unchanged. Tabs continue to drive the editor; selecting a row in the list pane updates the active tab. |
| Settings | New `LayoutMode` enum + `@AppStorage("layoutMode")`. New picker in General. |
| `ClearlyAppDelegate.commands` | Two new menu items + `⌥⌘2` / `⌥⌘3` shortcuts. |

## Risks and Challenges

### 1. Sidebar selection model gets a new axis

The sidebar today has two axes: expansion (per folder) and selection (per file). 3-pane mode adds a third: selected folder. Users could be confused if folder-click means "select" sometimes (3-pane) and "toggle expansion" other times (2-pane), or both at once.

**Mitigation:** In 3-pane, folder-click does **both** (select + toggle expansion). Keep behaviour identical in 2-pane (just toggle expansion). Document this in the doc-coauthoring `sidebar` overview.

### 2. Restore-on-launch ambiguity

If the user's last selected folder is in a vault whose security bookmark fails to resolve, the middle list shows the empty-state "select a folder" message rather than crashing. `selectedFolderURL` should be persisted as a bookmark, not a raw path.

### 3. Performance on large vaults

A vault with 5,000 notes recursive-loaded should still feel instant. The FTS5 query returns 5K rows in <50ms on a Mac mini M1; SwiftUI `List` virtualizes the rendering. Watch for: in-Swift preview extraction over 5K rows. Mitigation: extract preview lazily inside the row view, not eagerly during query.

### 4. Tab-vs-list selection conflict

If three notes are open in tabs and the user clicks a fourth note in the list pane, we want it to either replace the active tab (current `openFile` behavior) or open in a new tab. Match the sidebar's existing rule (Cmd-click = new tab; plain click = replace active). Don't introduce new behavior.

### 5. CSS / Theme drift

Adding a new pane means new colors. Adding them only to `Theme` and `PreviewCSS` (where relevant) per CLAUDE.md convention. Avoid hardcoded `Color(...)` calls inside the new view.

### 6. `NavigationSplitView` 3-column collapse behaviour

Cmd+L collapses the sidebar today. In 3-pane mode the user might want to collapse the middle column too. `NavigationSplitView` exposes this via `NavigationSplitViewVisibility` (`.all`, `.doubleColumn`, `.detailOnly`). Wire `⌘L` to cycle those states in 3-pane mode; keep current behaviour in 2-pane.

### 7. Conditional view-tree replacement

Switching `layoutMode` causes SwiftUI to throw away one `NavigationSplitView` and build a new one. This may briefly flash the editor and the middle pane. Tested approach: render both and use `.opacity` + `.allowsHitTesting` toggles. Probably not necessary — switching layouts is a deliberate user action and a brief flash is acceptable. Default to the simple conditional.

### 8. CLAUDE.md states `DocumentGroup`

CLAUDE.md says the app is `DocumentGroup`-based (line 26). Codebase reality: it's a single `Window` with a custom workspace. The Explore subagent flagged this as outdated. Not a blocker, but should be fixed when CLAUDE.md is next touched (out of scope for this feature; flag in a separate spawn task at end of implementation).

## Open Questions

1. **Should PINNED / RECENTS be reachable from the middle list at all?** User answer: no — they keep their existing sidebar UI. But should the list-pane header show "PINNED" / "RECENTS" as virtual folders if the sidebar treats them visually like folders? Recommendation: no, keep them separate to avoid muddying the model.
2. **Folder selection persistence across vault adds/removes:** if the user deletes the active vault, the middle pane should fall back to "no folder selected". Confirm this in implementation Phase 2.
3. **Tags as a list source — explicitly out, but worth a phase-3 idea?** Notes-equivalent would be tag-as-smart-folder. Park.
4. **Folder-scoped search in the list-pane header:** phase-1 ships without; revisit after dogfooding.

## Recommended Approach Summary

1. Add `LayoutMode` enum + `@AppStorage("layoutMode")` (default `.twoPane`).
2. Extend `WorkspaceManager` with `selectedFolderURL`, `nonRecursiveFolders`, `noteListSortOrder` (persisted).
3. Add `VaultIndex.summaries(folderURL:recursive:)` returning `[NoteSummary]`.
4. Build `MacNoteListView` + `NoteListRow` rendering off `[NoteSummary]`, bidirectionally bound to `workspace.currentFileURL`.
5. Switch `MacRootView` body on `layoutMode` between 2-column and 3-column `NavigationSplitView`.
6. Sidebar gets a "selected folder" highlight + folder-click sets `selectedFolderURL`.
7. New General-tab Settings picker; new menu items + shortcuts (`⌥⌘2`, `⌥⌘3`).

## References

- Notes Mac app reference screenshots: [nathan-docs/Notes.png](nathan-docs/Notes.png), [nathan-docs/Clearly.png](nathan-docs/Clearly.png).
- SwiftUI `NavigationSplitView` 3-column form: available since macOS 13.0; Clearly targets macOS 15.0 minimum.
- Existing patterns to follow: [Clearly/Native/MacFolderSidebar.swift](Clearly/Native/MacFolderSidebar.swift) for List-style sidebars, [Clearly/Native/MacRootView.swift](Clearly/Native/MacRootView.swift) for split-view composition, [Clearly/SettingsView.swift](Clearly/SettingsView.swift) for `@AppStorage`-backed pickers.
- CLAUDE.md guidance on cross-platform code: only `Clearly/` is Mac-only here; no `ClearlyCore` rules apply except for the new `NoteSummary` type and `VaultIndex` query, which must compile on iOS too.
