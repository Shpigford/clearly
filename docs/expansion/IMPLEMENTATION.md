# Expansion Implementation Plan

## Overview

Add knowledge management (wiki-links, backlinks, global search, tags, quick switcher) and AI ecosystem integration (MCP server) to Clearly. Built on a SQLite cross-file index using GRDB.swift with FTS5 full-text search.

The index is a derived cache — all data comes from the markdown files. Delete the database, it rebuilds from source. Files remain the source of truth.

## Prerequisites

- Xcode 16+ with Swift 5.9
- XcodeGen installed (`xcodegen generate` after project.yml changes)
- A folder with markdown files to test against

## Phase Summary

| Phase | Title | Delivers |
|-------|-------|----------|
| 1 | Cross-File Index + Quick Switcher | GRDB index of all vault files + Cmd+P fuzzy file finder |
| 2 | Wiki-Links | `[[note]]` syntax highlighting, preview rendering, click navigation |
| 3 | Wiki-Link Auto-Complete | `[[` trigger → popup with file suggestions |
| 4 | Global Search | Cmd+Shift+F full-text search across all vault files |
| 5 | Backlinks Panel | "What links here?" panel below editor |
| 6 | Tags | `#tag` highlighting, indexing, sidebar tag browser |
| 7 | MCP Server | Companion binary exposing vault to AI agents |

---

## Phase 1: Cross-File Index + Quick Switcher

### Objective
Build the complete SQLite index (files, links, tags, headings, FTS5) and the Quick Switcher (Cmd+P) as the first user-visible feature. The index populates everything upfront so later phases just add UI.

### Rationale
Every knowledge management feature depends on the index. Pairing it with the Quick Switcher means Phase 1 delivers something testable — not just plumbing.

### Tasks

- [ ] Add GRDB.swift package to `project.yml` (packages section + Clearly target dependency)
- [ ] Run `xcodegen generate` to update Xcode project
- [ ] Create `Clearly/VaultIndex.swift`:
  - DatabasePool setup with WAL mode
  - Full schema: `files`, `files_fts` (FTS5), `links`, `tags`, `headings` tables
  - DatabaseMigrator for schema creation
  - Index storage in `~/Library/Application Support/Clearly/indexes/` keyed by location path hash
  - Query APIs: `searchFiles(query:)`, `allFiles()`, `resolveWikiLink(name:)`, `linksTo(fileId:)`, `linksFrom(fileId:)`, `allTags()`, `filesForTag(tag:)`
- [ ] Create `Clearly/FileParser.swift`:
  - Extract wiki-links: regex `\[\[([^\]\|#\^]+?)(?:#([^\]\|]+?))?(?:\|([^\]]+?))?\]\]`
  - Extract tags: regex `(?:^|(?<=\s))#([\p{L}\p{N}_\-/]*[\p{L}_\-/][\p{L}\p{N}_\-/]*)`
  - Extract headings: regex `^(#{1,6})\s+(.+)$`
  - Extract frontmatter tags from YAML `tags:` field
  - Strip fenced code blocks before extraction (avoid false positives)
  - Pure function: `parse(content: String) -> ParseResult` (links, tags, headings)
- [ ] Integrate indexer into `WorkspaceManager.swift`:
  - Add `var vaultIndex: VaultIndex?` property
  - On `addLocation()`: create/open VaultIndex, trigger full index
  - On FSEventStream callback: call incremental re-index for changed files
  - On `removeLocation()`: close index
  - Background indexing on `DispatchQueue.global(qos: .utility)`
- [ ] Create `Clearly/QuickSwitcherPanel.swift`:
  - NSPanel (floating, non-activating): `styleMask: [.titled, .fullSizeContentView]`, hidden titlebar
  - NSVisualEffectView with `.popover` material
  - ~580px wide, centered on active window, upper third vertically
  - NSTextField for search (~44px tall), NSTableView for results (~36px rows, max 8-10)
  - Fuzzy matching: sequential character match with gap penalties, bonus for separator matches
  - Return matched character ranges for highlighting in results
  - Default state: show recently opened files when query is empty
  - Create-on-miss: "Create [query].md" at bottom when no results
  - Keyboard: Up/Down navigate, Enter opens, Escape dismisses
- [ ] Add Cmd+P shortcut in `ClearlyApp.swift` (Cmd+O is taken by "Open…")
- [ ] Wire quick switcher: result selection → `WorkspaceManager.openFile(at:)`

### Success Criteria
- Open a vault with 500+ markdown files. Index completes in <5 seconds.
- Cmd+P opens quick switcher. Type characters → fuzzy-matched results appear instantly.
- Select result → file opens in editor. Escape dismisses.
- Modify a file externally → index updates within 1 second.
- Delete index file → app recreates it on next launch.

### Files Likely Affected
- `project.yml` (GRDB dependency)
- New: `Clearly/VaultIndex.swift`
- New: `Clearly/FileParser.swift`
- New: `Clearly/QuickSwitcherPanel.swift`
- Modified: `Clearly/WorkspaceManager.swift` (index lifecycle, re-index triggers)
- Modified: `Clearly/ClearlyApp.swift` (Cmd+P shortcut)

---

## Phase 2: Wiki-Links

### Objective
Support `[[note]]` syntax in editor (highlighting) and preview (rendering + click navigation). The foundational primitive for all cross-file linking.

### Rationale
Wiki-links are the core knowledge management feature. Every other cross-file feature (backlinks, auto-complete, graph) builds on this.

### Tasks

- [ ] Add wiki-link colors to `Clearly/Theme.swift`:
  - `wikiLinkColor` (NSColor + SwiftUI wrapper) — distinct from regular link color
  - `wikiLinkBrokenColor` — for unresolved links (dimmed/red)
- [ ] Add wiki-link regex to `Clearly/MarkdownSyntaxHighlighter.swift`:
  - Pattern: `\[\[([^\]\|#]+?)(?:#[^\]\|]+?)?(?:\|[^\]]+?)?\]\]`
  - New `.wikiLink` case in `HighlightStyle` enum
  - Insert after footnote markers (~line 83), before table rows
  - Existing `cachedProtectedRanges` code-block exclusion handles protection automatically
- [ ] Add `processWikiLinks()` to `Shared/MarkdownRenderer.swift`:
  - Insert after `processEmoji()` (line 29), before `processCallouts()` (line 30)
  - Follow `protectCodeRegions`/`restoreProtectedSegments` pattern
  - Convert `[[note]]` → `<a href="clearly://wiki/note" class="wiki-link">note</a>`
  - Convert `[[note|alias]]` → `<a href="clearly://wiki/note" class="wiki-link">alias</a>`
  - Convert `[[note#heading]]` → `<a href="clearly://wiki/note#heading" class="wiki-link">note > heading</a>`
  - Keep renderer pure — no VaultIndex dependency (QuickLook compatibility)
- [ ] Add wiki-link CSS to `Shared/PreviewCSS.swift`:
  - `.wiki-link` styling (distinct from regular links — e.g., dotted underline or different color)
  - `.wiki-link-broken` styling (dimmed/strikethrough for unresolved)
  - Cover light, dark, print, and export contexts
- [ ] Add wiki-link click handler to `Clearly/PreviewView.swift`:
  - JavaScript: intercept clicks on `a[href^="clearly://wiki/"]`, send target via `window.webkit.messageHandlers.wikiLinkClicked.postMessage(targetName)`
  - Register `"wikiLinkClicked"` in `userContentController(_:didReceive:)` (follows `"linkClicked"` pattern at line 511)
  - Resolve target name via `VaultIndex.resolveWikiLink(name:)`
  - Open resolved file via `WorkspaceManager.openFile(at:)`
  - Handle heading anchor: scroll to heading after file opens
- [ ] Add JavaScript for link resolution in preview:
  - Inject file list from VaultIndex into preview page
  - Mark unresolved links with `.wiki-link-broken` class
  - This runs client-side so MarkdownRenderer stays pure
- [ ] Add Cmd+click wiki-link navigation in editor:
  - Detect click on wiki-link range in `EditorView.swift`
  - Resolve and navigate (same path as preview click)

### Success Criteria
- Type `[[My Note]]` in editor → highlighted with wiki-link color.
- Switch to preview → link is rendered and clickable.
- Click wiki-link in preview → target file opens in editor.
- Cmd+click wiki-link in editor → same navigation.
- `[[nonexistent]]` → styled as broken link (dimmed/red).
- `[[note|display text]]` → shows "display text" in preview, navigates to "note".
- Wiki-links inside code blocks are NOT processed.

### Files Likely Affected
- Modified: `Clearly/Theme.swift` (new colors)
- Modified: `Clearly/MarkdownSyntaxHighlighter.swift` (wiki-link pattern + style)
- Modified: `Shared/MarkdownRenderer.swift` (processWikiLinks)
- Modified: `Shared/PreviewCSS.swift` (wiki-link styles)
- Modified: `Clearly/PreviewView.swift` (click handler + JS injection)
- Modified: `Clearly/EditorView.swift` (Cmd+click)

---

## Phase 3: Wiki-Link Auto-Complete

### Objective
When user types `[[` in the editor, show a popup with fuzzy-matched file suggestions from the vault index.

### Rationale
Wiki-links without auto-complete are tedious — you have to remember exact file names. This is the feature that makes wiki-linking feel effortless.

### Tasks

- [ ] Create `Clearly/WikiLinkCompletionWindow.swift`:
  - Borderless `NSWindow` (child of editor window, `.above` ordering)
  - Position below cursor via `NSTextView.firstRect(forCharacterRange:actualRange:)`
  - ~300px wide, max 8 rows
  - `NSTableView` with file name + folder path (dimmed)
  - Fuzzy matching with highlighted match characters (reuse Phase 1 fuzzy matcher)
- [ ] Add trigger detection in `Clearly/EditorView.swift`:
  - In `textDidChange` delegate, detect `[[` was just typed
  - Check character isn't inside a code block (use `cachedProtectedRanges`)
  - Show completion window, seeded with all files (or recents for large vaults)
- [ ] Wire completion lifecycle:
  - As user types after `[[`, filter results via fuzzy match
  - Up/Down: navigate results
  - Enter/Tab: insert `selectedFileName]]` (completing the link)
  - Escape: dismiss popup
  - Backspace past `[[`: dismiss popup
  - `]]` typed manually: dismiss popup
  - Click outside: dismiss popup
  - Pipe `|` typed: keep popup open (user is adding alias)
- [ ] Handle edge cases:
  - Vault with 10,000+ files: show top 50 fuzzy matches, not all files
  - File names with special characters
  - Cursor at end of document
  - Multiple monitors / different window positions

### Success Criteria
- Type `[[` → popup appears below cursor with file suggestions.
- Type characters → results filter in real-time with fuzzy matching.
- Select file → `[[filename]]` inserted, popup dismissed.
- Escape → popup dismissed, `[[` remains in editor.
- Popup doesn't appear inside code blocks.
- Works smoothly with 1,000+ files in vault.

### Files Likely Affected
- New: `Clearly/WikiLinkCompletionWindow.swift`
- Modified: `Clearly/EditorView.swift` (trigger detection, popup management)

---

## Phase 4: Global Search

### Objective
Full-text search across all vault files with results in the sidebar. Cmd+Shift+F activates.

### Rationale
Search is the most immediately useful knowledge management feature for existing users. Even without wiki-links, people want to find things across their notes.

### Tasks

- [ ] Create search mode in sidebar:
  - Add `isSearchMode` state to `SidebarViewController.swift`
  - When active: show search field at top + results below, hide file tree
  - When deactivated: return to file tree
  - Cmd+Shift+F toggles search mode (add shortcut in `ClearlyApp.swift`)
  - Escape in search field exits search mode
- [ ] Create `Clearly/SearchResultsView.swift`:
  - AppKit-based (consistent with `FileExplorerView`)
  - Search field with 150ms debounce, starts after 2+ characters
  - Results grouped by file: file name header with match count badge
  - Under each file: indented match excerpts with 1 line context before/after
  - Matched terms highlighted in results
  - Two sections: file name matches first, then content matches
- [ ] Wire search to VaultIndex:
  - FTS5 `MATCH` query with `bm25()` ranking
  - `snippet()` function for context extraction
  - Also search `files.filename` for name matches (separate from content)
- [ ] Wire result clicks:
  - Click file header → open file via `WorkspaceManager.openFile(at:)`
  - Click match excerpt → open file AND scroll to match line
  - Scrolling to line: need to pass line number through to `EditorView`
- [ ] Add Cmd+Shift+F shortcut in `ClearlyApp.swift`

### Success Criteria
- Cmd+Shift+F → sidebar switches to search mode with focused search field.
- Type "keyword" → results appear grouped by file with highlighted matches.
- Click a result → file opens and scrolls to the matching line.
- Escape → returns to file tree.
- Search across 1,000 files completes in <100ms.
- Quoted phrases work: `"exact phrase"` matches only that phrase.

### Files Likely Affected
- Modified: `Clearly/SidebarViewController.swift` (search mode toggle)
- New: `Clearly/SearchResultsView.swift`
- Modified: `Clearly/ClearlyApp.swift` (Cmd+Shift+F shortcut)
- Modified: `Clearly/VaultIndex.swift` (search query with snippets)
- Modified: `Clearly/EditorView.swift` (scroll-to-line support)

---

## Phase 5: Backlinks Panel

### Objective
Show all files that link TO the current file in a collapsible panel below the editor.

### Rationale
Backlinks surface connections you didn't know existed. This is the feature that turns a collection of files into a knowledge graph.

### Tasks

- [ ] Create `Clearly/BacklinksState.swift`:
  - `@Observable` class (follows `OutlineState` pattern)
  - `isVisible: Bool`, `backlinks: [Backlink]`, `unlinkedMentions: [Backlink]`
  - `struct Backlink`: source file name, path, context line, line number
  - `update(for fileURL: URL, using index: VaultIndex)` method
- [ ] Create `Clearly/BacklinksView.swift`:
  - SwiftUI view (simpler than AppKit for a read-only panel)
  - "Backlinks" header with count badge
  - **Linked mentions** section: file name (clickable) + 1-2 lines of context with `[[link]]` highlighted
  - **Unlinked mentions** section (collapsed by default): plain text matches of file name in other files. "Link" button to convert to `[[wiki-link]]`
  - Empty state: "No other documents link to this file"
- [ ] Integrate into `Clearly/ContentView.swift`:
  - Add `@StateObject private var backlinksState = BacklinksState()`
  - Add backlinks panel below `bottomBar()` in `mainContent` VStack (follows `FindBarView` pattern)
  - Collapsible with divider line
  - Height: ~200px default, or use draggable divider
- [ ] Add toggle:
  - Button in `bottomBar()` right-side button group (follows outline toggle pattern at lines 190-198)
  - Cmd+Shift+B shortcut in `ClearlyApp.swift`
- [ ] Update backlinks on active document change:
  - Watch `WorkspaceManager.currentFileURL` changes
  - Re-query VaultIndex for backlinks to current file
- [ ] "Link" button for unlinked mentions:
  - Convert plain text mention to `[[wiki-link]]` in source file
  - Update the source file's content and save
  - Re-index affected files

### Success Criteria
- Open a note that other notes link to → backlinks panel shows linking files with context.
- Click a backlink → opens the linking file.
- Switch to a different file → backlinks panel updates.
- Cmd+Shift+B toggles panel visibility.
- File with no backlinks → "No other documents link to this file".
- Unlinked mentions section shows plain-text matches, collapsed by default.

### Files Likely Affected
- New: `Clearly/BacklinksState.swift`
- New: `Clearly/BacklinksView.swift`
- Modified: `Clearly/ContentView.swift` (panel integration + toggle)
- Modified: `Clearly/ClearlyApp.swift` (Cmd+Shift+B shortcut)
- Modified: `Clearly/VaultIndex.swift` (unlinked mentions query)

---

## Phase 6: Tags

### Objective
`#tag` syntax highlighting in editor, tag indexing, and a sidebar tag browser for filtering files by tag.

### Rationale
Tags complement wiki-links as an organizational tool. Wiki-links create specific connections; tags create categories.

### Tasks

- [ ] Add tag color to `Clearly/Theme.swift`:
  - `tagColor` (NSColor + SwiftUI wrapper) — distinct from wiki-links and regular links
- [ ] Add tag regex to `Clearly/MarkdownSyntaxHighlighter.swift`:
  - Pattern: `(?:^|(?<=\s))#([\p{L}\p{N}_\-/]*[\p{L}_\-/][\p{L}\p{N}_\-/]*)`
  - New `.tag` case in `HighlightStyle` enum
  - Must NOT match headings (`# ` with space) — regex handles this via no-space requirement
  - Must NOT match inside code blocks (protected by `cachedProtectedRanges`)
- [ ] Add `processTags()` to `Shared/MarkdownRenderer.swift`:
  - Convert `#tag` → `<span class="tag" data-tag="tag">#tag</span>`
  - Follow `protectCodeRegions`/`restoreProtectedSegments` pattern
  - Add click handler in JavaScript: sends tag name via message handler
- [ ] Add tag CSS to `Shared/PreviewCSS.swift`:
  - `.tag` styling: subtle background, rounded, clickable appearance
  - Light + dark mode variants
- [ ] Add tag click handler in `Clearly/PreviewView.swift`:
  - Register `"tagClicked"` message handler
  - On click → activate sidebar search filtered to tag (or dedicated tag filter)
- [ ] Create tag browser section in sidebar:
  - New section in `FileExplorerView.swift` below Locations
  - Collapsible tree for nested tags (`#project/clearly` → `project` > `clearly`)
  - Each tag shows file count badge
  - Click tag → filter file tree to files with that tag
  - Query `VaultIndex.allTags()` for tag list with counts
- [ ] Handle frontmatter tags:
  - FileParser already extracts YAML `tags: [foo, bar]` (from Phase 1)
  - Display alongside inline tags in tag browser (no distinction needed)

### Success Criteria
- Type `#project` in editor → highlighted with tag color.
- Tags inside code blocks are NOT highlighted.
- `#123` (all digits) is NOT treated as a tag.
- `# Heading` (with space) is NOT treated as a tag.
- Sidebar shows tag browser with all tags from vault.
- Nested tags shown as tree: `#project/clearly` under `project`.
- Click tag → file tree filters to matching files.
- Frontmatter `tags:` field values appear in tag browser.

### Files Likely Affected
- Modified: `Clearly/Theme.swift` (tag color)
- Modified: `Clearly/MarkdownSyntaxHighlighter.swift` (tag pattern + style)
- Modified: `Shared/MarkdownRenderer.swift` (processTags)
- Modified: `Shared/PreviewCSS.swift` (tag styles)
- Modified: `Clearly/PreviewView.swift` (tag click handler)
- Modified: `Clearly/FileExplorerView.swift` (tag browser section)

---

## Phase 7: MCP Server

### Objective
Ship a companion CLI binary that exposes the vault to AI agents via the Model Context Protocol. Direct download includes it automatically; App Store users install separately.

### Rationale
MCP makes Clearly visible to the AI ecosystem (Claude Desktop, ChatGPT, Cursor). Most note apps don't have native MCP support — this is a first-class differentiator. The binary is a thin wrapper over VaultIndex — marginal effort on top of existing infrastructure.

### Tasks

- [x] Add `init(locationURL:bundleIdentifier:)` to `VaultIndex.swift` — lets CLI binary open the sandboxed app's index
- [x] Add `@unchecked Sendable` to `VaultIndex` — needed for MCP SDK's `@Sendable` closures
- [x] Add `persistVaultsConfig()` to `WorkspaceManager.swift` — writes `~/.config/clearly/vaults.json`
- [x] Add MCP Swift SDK (`from: "0.11.0"`) to `project.yml` packages
- [x] Add `ClearlyMCP` tool target to `project.yml` — sources: `ClearlyMCP/`, `VaultIndex.swift`, `FileParser.swift`, `FileNode.swift`, `DiagnosticLog.swift`, `FrontmatterSupport.swift`
- [x] Create `ClearlyMCP/main.swift` — entry point with `--vault` and `--test` flags
- [x] Create `ClearlyMCP/Tools.swift` — 3 MCP tools only:
  - `search_notes(query, limit?)` → FTS5 ranked search with BM25, snippets
  - `get_backlinks(note_path)` → linked mentions + unlinked mentions
  - `get_tags(tag?)` → all tags with counts, or files for a tag
  - Cut: `read_note`, `list_notes`, `create_note`, `update_note`, `get_metadata` (thin wrappers over file system access)
- [x] Add MCP Settings tab to `SettingsView.swift` — status, vault selector, copy config, test connection
- [x] Add `installMCPHelperIfNeeded()` to `ClearlyApp.swift` — auto-installs binary on launch (direct distribution)
- [x] Add `postCompileScripts` to Clearly target — copies ClearlyMCP binary into app bundle
- [x] Run `xcodegen generate` and verify both targets build

### Success Criteria
- Direct download build: MCP binary auto-installed to App Support on first launch. No user action needed.
- App Store build: Settings panel shows install instructions.
- Configure in Claude Desktop config JSON.
- In Claude Desktop: "What notes do I have?" → lists vault files.
- "Search for notes about [topic]" → returns matching files with context.
- "Read the note at [path]" → returns full content.
- "Test Connection" button in Settings → shows success.

### Files Likely Affected
- `project.yml` (MCP SDK dependency + ClearlyMCP target)
- New: `ClearlyMCP/main.swift`
- New: `ClearlyMCP/MCPTools.swift`
- Modified: `Clearly/SettingsView.swift` (MCP settings panel)
- Modified: `Clearly/ClearlyApp.swift` (binary installation on launch for direct download)

---

## Post-Implementation

- [ ] Update `Shared/Resources/demo.md` with wiki-link, tag, and backlink examples
- [ ] Update `website/index.html` feature list with knowledge management + MCP
- [ ] Update `CLAUDE.md` with new architecture (VaultIndex, FileParser, MCP)
- [ ] Performance testing with 5,000+ file vault
- [ ] Update `Clearly/Info.plist` if new URL schemes needed

## Notes

- **Index is a derived cache**: all data comes from markdown files. Delete it, it rebuilds. Stored in App Support, not inside the vault. No portability concern.
- **Cmd+P for quick switcher** (not Cmd+O which is taken by "Open…"). Matches VS Code convention.
- **MarkdownRenderer stays pure**: no VaultIndex dependency. Wiki-link resolution happens in JavaScript on the PreviewView side. This keeps QuickLook compatibility.
- **FileParser extracts everything in Phase 1** (links, tags, headings) even though some UI doesn't ship until later phases. Avoids re-indexing and schema migrations.
- **GRDB.swift v7.x**: provides DatabasePool (concurrent reads), FTS5 support, DatabaseMigrator, and raw sqlite3* handle for future sqlite-vec.
