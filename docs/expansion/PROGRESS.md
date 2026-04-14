# Expansion Progress

## Status: Phase 7 - Completed

## Quick Reference
- Research: `docs/expansion/RESEARCH.md`
- Implementation: `docs/expansion/IMPLEMENTATION.md`

---

## Phase Progress

### Phase 1: Cross-File Index + Quick Switcher
**Status:** Completed (2026-04-13)

#### Tasks Completed
- [x] Added GRDB.swift v7+ dependency to `project.yml` (Clearly target only, not QuickLook)
- [x] Created `Clearly/FileParser.swift` — pure markdown parser extracting wiki-links, tags, headings with code-block skip ranges
- [x] Created `Clearly/VaultIndex.swift` — SQLite index via GRDB DatabasePool, FTS5 full-text search, full schema (files, files_fts, links, tags, headings), content-hash-based incremental indexing, all read APIs
- [x] Integrated VaultIndex into `Clearly/WorkspaceManager.swift` — index lifecycle wired to addLocation/removeLocation/refreshTree/restoreLocations/deinit, background indexing on utility queue
- [x] Created `Clearly/QuickSwitcherPanel.swift` — borderless NSPanel with vibrancy, fuzzy matching with highlighted characters, keyboard navigation (Up/Down/Enter/Escape), recent files on empty query, create-on-miss, dynamic resizing to fit content
- [x] Wired Cmd+P shortcut in `Clearly/ClearlyApp.swift` via local event monitor, moved Print to Cmd+Shift+P
- [x] Added Debug-only dev bundle ID (`com.sabotage.clearly.dev`) and product name ("Clearly Dev") for safe side-by-side testing
- [x] VaultIndex uses `Bundle.main.bundleIdentifier` for App Support path, keeping dev/prod indexes isolated

#### Decisions Made
- FTS5 uses standalone storage (not external content mode) — avoids column mismatch bug and supports `snippet()` for Phase 4 global search
- Borderless NSPanel with `KeyablePanel` subclass (overrides `canBecomeKey`) for proper keyboard input without titlebar
- `NSTableView.style = .plain` to eliminate hidden inset padding on macOS 11+
- Panel resizes using `tableView.rect(ofRow:).maxY` for pixel-accurate height instead of manual math
- `@ObservationIgnored` on `vaultIndexes` dictionary to prevent `@Observable` macro expansion issues with GRDB types
- `indexAllFiles()` uses `self.rootURL` (no parameter) to prevent caller/instance URL divergence
- Full schema (links, tags, headings) created in Phase 1 even though UI ships in later phases — avoids schema migrations

#### Blockers
- (none)

---

### Phase 2: Wiki-Links
**Status:** Completed (2026-04-13)

#### Tasks Completed
- [x] Added `wikiLinkColor` (warm green) and `wikiLinkBrokenColor` (orange-red) to `Theme.swift`
- [x] Added `.wikiLink` case to `HighlightStyle` enum in `MarkdownSyntaxHighlighter.swift`
- [x] Added wiki-link regex pattern `(\[\[)([^\]\n]+?)(\]\])` to patterns array (after footnotes, before tables)
- [x] Added `.wikiLink` switch cases to both `highlightAll` and `highlightAround` methods
- [x] Added `processWikiLinks()` to `MarkdownRenderer.swift` pipeline (after processEmoji, before processCallouts)
  - Handles `[[note]]`, `[[note|alias]]`, `[[note#heading]]`, `[[note#heading|alias]]`
  - Uses `clearly://wiki/` custom URL scheme, `escapeHTML` for display text
  - Renderer stays pure — no VaultIndex dependency
- [x] Added `.wiki-link` and `.wiki-link-broken` CSS to `PreviewCSS.swift` in all 4 contexts (light, dark, print, export)
  - Resolved: green with solid bottom border; Broken: orange-red with dashed border
- [x] Added `onWikiLinkClicked` callback and `wikiFileNames` property to `PreviewView.swift`
- [x] Modified `handleLinkClick` to detect `clearly://wiki/` scheme and call callback
- [x] Injected broken-link detection JS: compares wiki-link targets against known file names, adds `.wiki-link-broken` class
- [x] Wired `onWikiLinkClicked` and `wikiFileNames` in `ContentView.swift` previewPane
- [x] Added Cmd+click wiki-link navigation to `ClearlyTextView.swift` (mouseDown override + regex detection)
- [x] Added `.navigateWikiLink` notification for editor-to-ContentView communication
- [x] Wired `onWikiLinkClicked` from ClearlyTextView via NotificationCenter in `EditorView.swift`

#### Decisions Made
- Wiki-link color is warm green (distinct from blue standard links) — visually signals "internal/connected"
- Broken-link color is orange-red — signals "needs attention" without being alarm-red
- Editor highlighting uses single color for all wiki-link content (no sub-parsing of heading/alias) — simpler, consistent
- No broken-link coloring in editor (would require VaultIndex in hot path) — preview handles it via JS
- Reuse existing `linkClicked` JS handler rather than adding new message handler — `clearly://wiki/` scheme detection in `handleLinkClick` is simpler
- Editor Cmd+click uses regex scan on 400-char window around click point — avoids complex attribute/range tracking
- File name comparison is case-insensitive (lowercased set) matching VaultIndex.resolveWikiLink behavior
- Wiki-link JS broken detection skips marking when knownFiles set is empty (no vault index yet)

#### Blockers
- (none)

---

### Phase 3: Wiki-Link Auto-Complete
**Status:** Completed (2026-04-13)

#### Tasks Completed
- [x] Created `Clearly/WikiLinkCompletionWindow.swift` — `WikiLinkCompletionManager` singleton with borderless NSPanel, NSTableView, fuzzy-matched file suggestions
- [x] Panel uses `.borderless, .nonactivatingPanel` style (does NOT steal key focus from editor), `.floating` level, `NSVisualEffectView` with `.popover` material
- [x] Positioned below cursor via `firstRect(forCharacterRange:actualRange:)` with screen-edge clamping and flip-above fallback
- [x] Reuses `FuzzyMatcher.match()` from QuickSwitcherPanel for consistent matching behavior
- [x] Cell view: doc icon + filename with highlighted match ranges (bold + accent color) + dimmed folder path
- [x] `ClickableTableView` subclass with `acceptsFirstMouse` for click-to-select on non-key panel
- [x] Added `isInsideProtectedRange(at:)` public method to `MarkdownSyntaxHighlighter.swift`
- [x] Added `keyDown` override in `ClearlyTextView.swift` — intercepts Down/Up/Return/Tab/Escape when popup visible
- [x] Added dismiss in `ClearlyTextView.mouseDown` — click anywhere in editor dismisses popup
- [x] Added `handleWikiLinkCompletion` in `EditorView.swift` Coordinator — trigger detection (`[[` typed), query extraction, popup lifecycle
- [x] Trigger detection checks actual text (two chars before cursor) — handles rapid typing, paste
- [x] Protected range check prevents triggering inside code blocks, math blocks, frontmatter
- [x] Completion insertion via `insertText(_:replacementRange:)` — integrates with undo system
- [x] Dismiss on: Escape, `]]` typed, backspace past `[[`, click outside, newline in query

#### Decisions Made
- Panel does NOT become key (plain NSPanel, not KeyablePanel) — user keeps typing in editor, keyboard intercept in ClearlyTextView.keyDown
- Child window via `addChildWindow(_:ordered:)` — moves with editor window, auto-hides on deactivation
- Removed `@MainActor` from WikiLinkCompletionManager — Coordinator isn't `@MainActor`, and all NSView work is main-thread anyway
- Dismiss before insertText in `insertSelectedCompletion` — prevents textDidChange from re-triggering popup
- No pipe `|` special handling — query includes pipe, results go empty. Acceptable for v1
- 300px wide panel, 32px rows, max 8 visible rows — narrower and smaller than QuickSwitcher's 580px/36px

#### Blockers
- (none)

---

### Phase 4: Global Search
**Status:** Completed (2026-04-13)

#### Tasks Completed
- [x] Added `MatchExcerpt` and `SearchFileGroup` types to `VaultIndex.swift`
- [x] Added `searchFilesGrouped(query:)` to `VaultIndex.swift` — FTS5 MATCH with bm25 ranking, filename LIKE matching, line-level excerpt extraction (capped at 5 per file), quoted phrase support
- [x] Enhanced `QuickSwitcherPanel.swift` with FTS5 content search below fuzzy filename matches
  - Content matches shown with `text.magnifyingglass` icon + context snippet
  - Filename matches (fuzzy) shown first, content matches (FTS5) appended after
  - Deduplication: files already matched by name are skipped in content results
  - Content results capped at 30, filename results capped at 20
  - Selecting a content match opens file + scrolls to matching line via `.scrollEditorToLine`
- [x] Added Cmd+Shift+F shortcut in `Clearly/ClearlyApp.swift` — opens Quick Switcher (same as Cmd+P)
- [x] Added "Search All Files…" menu item in View menu via `injectGlobalSearchIfNeeded()`
- [x] Scroll-to-line reuses existing `.scrollEditorToLine` notification (no EditorView changes needed)
- [x] Build verified: `xcodebuild -scheme Clearly -configuration Debug build` succeeded

#### Decisions Made
- Integrated into existing Quick Switcher (Cmd+P) instead of separate sidebar search — simpler, unified search surface
- Cmd+Shift+F opens the same Quick Switcher as Cmd+P (common "search in project" shortcut)
- Content search requires 2+ character query (FTS5 is pointless for single chars)
- Line numbers extracted by scanning file content from FTS `content` column — avoids disk I/O, stays in SQLite read
- Quoted phrases preserved as FTS5 phrase queries, bare terms get prefix matching (`"term"*`)
- Scroll-to-line uses 0.15s delay after `openFile` to let document load — matches wiki-link navigation pattern
- Content match items use `text.magnifyingglass` icon to distinguish from filename matches

#### Blockers
- (none)

---

### Phase 5: Backlinks Panel
**Status:** Completed (2026-04-13)

#### Tasks Completed
- [x] Created `Clearly/BacklinksState.swift` — `ObservableObject` with `@Published` isVisible/backlinks/unlinkedMentions, debounced update on utility queue, reads source files for context lines
- [x] Created `Clearly/BacklinksView.swift` — SwiftUI view with "BACKLINKS" header + count badge, linked mentions list, collapsible unlinked mentions DisclosureGroup, empty state, hover-highlight rows (matches OutlineView patterns)
- [x] Added `file(forURL:)` helper to `VaultIndex.swift` — resolves file URL to IndexedFile via relative path
- [x] Added `unlinkedMentions(for:excludingFileId:)` to `VaultIndex.swift` — FTS5 phrase search → line scan → wiki-link bracket filtering, capped at 20 results, skips filenames < 3 chars
- [x] Integrated BacklinksView into `ContentView.swift` — panel between editor ZStack and bottomBar, max 200px height, separator line, animated toggle
- [x] Added toggle button in `bottomBar()` using `link` SF Symbol with `ClearlyToolbarButtonStyle(isActive:)` pattern
- [x] Added `BacklinksStateKey` FocusedValueKey + extended FocusedValues + updated FocusedValuesModifier
- [x] Backlinks update on: `.onAppear`, `activeDocumentID` change, `vaultIndexRevision` change
- [x] Added Cmd+Shift+B shortcut in `ClearlyApp.swift` NSEvent monitor
- [x] Added "Toggle Backlinks" menu item in View menu via `injectViewCommandsIfNeeded()`
- [x] Added `toggleBacklinksAction` objc method for menu item
- [x] Build verified: `xcodebuild -scheme Clearly -configuration Debug build` succeeded

#### Decisions Made
- Panel sits below editor, above bottom bar (not an inspector) — it's document-contextual, not a navigation tool
- Fixed maxHeight 200px with ScrollView — no draggable divider (simpler, adequate for typical 0-10 backlinks)
- SwiftUI for BacklinksView (read-only list, no AppKit bridging needed)
- Context lines read from disk at stored lineNumber (the `context` column in links table is unpopulated)
- Unlinked mentions deduplicated: files already in linked results are skipped
- One unlinked mention per file (first match) — prevents noisy results
- "Link" button for unlinked mentions deferred — it's a write operation that deserves focused work
- Visibility persisted to UserDefaults ("backlinksVisible") matching OutlineState pattern
- Debounce 0.3s on utility queue (matches OutlineState's 0.4s debounce pattern)

#### Blockers
- (none)

---

### Phase 6: Tags
**Status:** Completed (2026-04-13)

#### Tasks Completed
- [x] Added `tagColor` (soft blue) to `Theme.swift` — distinct from wiki-link green and regular link blue
- [x] Added `.tag` case to `HighlightStyle` enum in `MarkdownSyntaxHighlighter.swift`
- [x] Added tag regex pattern `(?:^|(?<=\s))#(tag_name)` to patterns array (after wiki-links, before tables)
- [x] Added `.tag` switch cases to both `highlightAll` and `highlightAround` methods — `#` in syntax color, name in tag color
- [x] Added `processTags()` to `MarkdownRenderer.swift` pipeline (after processWikiLinks, before processCallouts)
  - Uses `clearly://tag/` URL scheme, protects `<pre>`, `<code>`, `<a>`, `<script>`, `<style>`, `<span>` blocks
  - Renders as `<a href="clearly://tag/name" class="md-tag">#name</a>`
- [x] Added `.md-tag` CSS to `PreviewCSS.swift` in all 4 contexts (light, dark, print, export)
  - Pill-like appearance: subtle background, rounded corners, blue color
- [x] Added `onTagClicked` callback and `clearly://tag/` URL handling to `PreviewView.swift`
- [x] Wired `onTagClicked` in `ContentView.swift` — posts `ClearlyFilterByTag` notification
- [x] Added `tags` section to `FileExplorerView.swift` sidebar (between LOCATIONS and RECENTS)
  - New `Section.tags` enum case, `OutlineItem.Kind.tagEntry(tag:count:)`
  - Tag items cache, `refreshCachedTags()` aggregates across all vault indexes
  - Data source: numberOfChildren, child, isExpandable, shouldSelect all handle tags
  - Delegate: viewFor renders `#tagname count` with `number` SF Symbol
  - Selection opens Quick Switcher with `#tag` query
  - Autosave persistence for tag expansion state
  - Context menu: no actions for tags (intentional for v1)
- [x] Added `show(withQuery:)` to `QuickSwitcherManager` for pre-filled search
- [x] Added tag-based filtering in Quick Switcher: `#` prefix triggers `VaultIndex.filesForTag()` lookup
- [x] Added `ClearlyFilterByTag` notification observer in `ClearlyApp.swift`
- [x] Build verified: `xcodebuild -scheme Clearly -configuration Debug build` succeeded

#### Decisions Made
- Tag color is soft blue (distinct from green wiki-links) — visually signals "category/label"
- CSS class is `.md-tag` (not `.tag`) to avoid collision with generic HTML tag names
- `clearly://tag/` URL scheme matches `clearly://wiki/` pattern — reuses existing `linkClicked` handler
- Tags section in sidebar between LOCATIONS and RECENTS — knowledge-layer grouping
- Tag click opens Quick Switcher pre-filled with `#tag` (not inline file tree filtering) — simpler, reuses existing infrastructure
- No keyboard shortcut for tag toggle — tags are always visible in sidebar; toggle via sidebar visibility (Cmd+Shift+L)
- No context menu for tags in v1 — no clear actions needed yet
- Tag protection in MarkdownRenderer includes `<span>` to avoid re-processing already-rendered tags
- Vault revision change triggers tag cache refresh in sidebar coordinator

#### Blockers
- (none)

---

### Phase 7: MCP Server
**Status:** Completed (2026-04-13)

#### Tasks Completed
- [x] Added `init(locationURL:bundleIdentifier:)` and `indexDirectory(bundleIdentifier:)` to `VaultIndex.swift` — lets CLI binary open the same SQLite index the sandboxed app creates
- [x] Added `@unchecked Sendable` to `VaultIndex` — safe because `DatabasePool` handles concurrency; needed for MCP SDK's `@Sendable` closure requirements
- [x] Added `persistVaultsConfig()` to `WorkspaceManager.swift` — writes `~/.config/clearly/vaults.json` with active vault paths for AI agent discovery
- [x] Added MCP Swift SDK (`modelcontextprotocol/swift-sdk` v0.11.0+) to `project.yml` packages
- [x] Added `ClearlyMCP` tool target to `project.yml` — sources: `ClearlyMCP/`, plus `VaultIndex.swift`, `FileParser.swift`, `FileNode.swift`, `DiagnosticLog.swift`, `FrontmatterSupport.swift`
- [x] Created `ClearlyMCP/main.swift` — CLI entry point with `--vault <path>` and `--test` flags, opens VaultIndex with explicit bundle ID
- [x] Created `ClearlyMCP/Tools.swift` — MCP server with 3 tools:
  - `search_notes(query, limit?)` — FTS5 ranked search via `searchFilesGrouped()`, BM25 ranking, context snippets
  - `get_backlinks(note_path)` — linked mentions via `linksTo()` + unlinked mentions via `unlinkedMentions()`, resolves paths and wiki-link names
  - `get_tags(tag?)` — all tags with counts via `allTags()`, or files for a tag via `filesForTag()`
- [x] Added MCP Settings tab to `SettingsView.swift` — binary status indicator, vault selector, "Copy Claude Desktop Config" button, "Test Connection" button
- [x] Added `installMCPHelperIfNeeded()` to `ClearlyApp.swift` — copies bundled binary to `~/Library/Application Support/Clearly/ClearlyMCP` on launch (direct distribution only, `#if canImport(Sparkle)`)
- [x] Added `postCompileScripts` to Clearly target in `project.yml` — copies ClearlyMCP binary to `Contents/Resources/Helpers/`
- [x] Build verified: both `xcodebuild -scheme ClearlyMCP` and `xcodebuild -scheme Clearly` succeed
- [x] Binary verified: `./ClearlyMCP --vault /path --test` prints file/tag counts and exits 0

#### Decisions Made
- **Only 3 tools, not 6+**: Cut `read_note`, `list_notes`, `create_note`, `update_note`, `get_metadata` — all thin wrappers over file system operations agents already have. Only expose computed knowledge (ranked search, link graph, tag aggregation) that agents can't derive from raw files.
- **Read-only index access**: CLI opens the app's SQLite database via WAL mode. No write tools → no concurrent write contention.
- **Sandbox container resolution**: `indexDirectory(bundleIdentifier:)` tries `~/Library/Containers/{id}/Data/...` first (where sandboxed app stores index), falls back to `~/Library/Application Support/`.
- **Swift 6.0 for ClearlyMCP target only**: MCP SDK requires Swift 6.0. Main app stays Swift 5.9. `SWIFT_STRICT_CONCURRENCY: minimal` avoids Sendable issues with shared source files.
- **`vaults.json` for zero-MCP discovery**: Written to `~/.config/clearly/vaults.json` — any AI agent with file access can find vault paths without MCP.
- **Direct distribution bundles automatically**: Binary copied from `Contents/Resources/Helpers/` to App Support on launch. No user action.
- **No App Store download flow in v1**: Settings tab shows status for both builds, but one-click download from GitHub Releases deferred.

#### Blockers
- (none)

---

## Session Log

### 2026-04-13 — Phase 7 Implementation
- Added `init(locationURL:bundleIdentifier:)` overload to VaultIndex.swift for CLI database access
- Added `@unchecked Sendable` to VaultIndex (thread-safe via DatabasePool)
- Added sandbox container path resolution in `indexDirectory(bundleIdentifier:)`
- Added `persistVaultsConfig()` to WorkspaceManager.swift — writes ~/.config/clearly/vaults.json
- Added MCP Swift SDK package + ClearlyMCP tool target to project.yml (Swift 6.0, SWIFT_STRICT_CONCURRENCY: minimal)
- Created ClearlyMCP/main.swift — CLI entry point with --vault/--test args
- Created ClearlyMCP/Tools.swift — 3 MCP tools (search_notes, get_backlinks, get_tags) using VaultIndex read APIs
- Added MCP tab to SettingsView.swift — status, vault picker, copy config, test connection
- Added installMCPHelperIfNeeded() to ClearlyApp.swift — auto-installs binary on launch (Sparkle builds)
- Added postCompileScripts to project.yml — copies ClearlyMCP into app bundle Helpers/
- Build verified: both ClearlyMCP and Clearly schemes succeed
- Binary verified: ./ClearlyMCP --vault /path --test outputs file/tag counts

### 2026-04-13 — Phase 6 Implementation
- Added `tagColor` to Theme.swift (soft blue, light/dark adaptive)
- Added `.tag` pattern + enum case + 2 switch cases to MarkdownSyntaxHighlighter.swift
- Added `processTags()` with protect/restore helpers to MarkdownRenderer.swift (~50 lines)
- Added `.md-tag` CSS in all 4 contexts (light, dark, print, export) in PreviewCSS.swift
- Added `onTagClicked` callback + `clearly://tag/` handling in PreviewView.swift
- Wired `onTagClicked` from ContentView.swift via `ClearlyFilterByTag` notification
- Added TAGS section to FileExplorerView.swift sidebar: Section.tags, OutlineItem.Kind.tagEntry, full data source/delegate, vault revision tracking, cached tags refresh
- Added `show(withQuery:)` to QuickSwitcherManager + tag-based filtering when query starts with `#`
- Added `ClearlyFilterByTag` notification observer in ClearlyApp.swift → opens Quick Switcher with `#tag`
- Build verified: `xcodebuild -scheme Clearly -configuration Debug build` succeeded

### 2026-04-13 — Phase 5 Implementation
- Created BacklinksState.swift (~100 lines): ObservableObject with debounced update, linked + unlinked mention resolution, disk-based context line reading
- Created BacklinksView.swift (~115 lines): SwiftUI panel with header, linked/unlinked sections, hover-highlighted clickable rows, DisclosureGroup for unlinked
- Added `file(forURL:)` and `unlinkedMentions(for:excludingFileId:)` to VaultIndex.swift — FTS5 phrase search + wiki-link bracket filtering
- Integrated into ContentView.swift: state object, layout between editor and bottomBar, toggle button, FocusedValueKey, notification listeners, vaultIndexRevision watcher
- Added Cmd+Shift+B shortcut and "Toggle Backlinks" View menu item in ClearlyApp.swift
- Build verified: `xcodebuild -scheme Clearly -configuration Debug build` succeeded

### 2026-04-13 — Phase 4 Implementation
- Added `MatchExcerpt`, `SearchFileGroup` types and `searchFilesGrouped(query:)` to VaultIndex.swift (~100 lines)
- Enhanced QuickSwitcherPanel.swift: content matches via FTS5 appended below fuzzy filename matches, scroll-to-line on selection
- Added Cmd+Shift+F shortcut (opens Quick Switcher) and "Search All Files…" View menu item in ClearlyApp.swift
- Initially built sidebar-based search, then pivoted to Quick Switcher integration (simpler, unified UX)
- Build verified: `xcodebuild -scheme Clearly -configuration Debug build` succeeded

### 2026-04-13 — Phase 3 Implementation
- Created WikiLinkCompletionWindow.swift (~280 lines): manager, panel, table, cell views, positioning, completion insertion
- Added isInsideProtectedRange(at:) to MarkdownSyntaxHighlighter for code-block detection
- Added keyDown override in ClearlyTextView for popup keyboard interception (Down/Up/Return/Tab/Escape)
- Added mouseDown dismiss in ClearlyTextView
- Added handleWikiLinkCompletion in EditorView Coordinator with trigger detection and query lifecycle
- Fixed @MainActor isolation: removed from WikiLinkCompletionManager since Coordinator isn't @MainActor
- Build verified: `xcodebuild -scheme Clearly -configuration Debug build` succeeded

### 2026-04-13 — Phase 2 Implementation
- Implemented full wiki-link support across 8 files: Theme, Highlighter, Renderer, CSS, PreviewView, ContentView, ClearlyTextView, EditorView
- Editor syntax highlighting: `[[brackets]]` in syntax color, content in green wiki-link color
- Preview rendering: `[[note]]` → `<a href="clearly://wiki/note" class="wiki-link">note</a>` with code-block protection
- Preview click handling: `clearly://wiki/` scheme detected in handleLinkClick, resolved via VaultIndex, opens via workspace.openFile
- Broken-link detection: JS injected with known file names set, marks unresolved links with `.wiki-link-broken` class
- Editor Cmd+click: mouseDown override on ClearlyTextView with regex-based wiki-link detection at click point
- Build verified: `xcodebuild -scheme Clearly -configuration Debug build` succeeded

### 2026-04-13 — Phase 1 Implementation
- Built all 6 tasks: GRDB dep → FileParser → VaultIndex → WorkspaceManager integration → QuickSwitcherPanel → Cmd+P shortcut
- Fixed FTS5 external content bug (content='files' referenced non-existent column) — switched to standalone FTS
- Fixed borderless NSPanel keyboard input (canBecomeKey override)
- Fixed NSTableView hidden inset padding (.style = .plain)
- Fixed panel sizing to use rect(ofRow:).maxY instead of manual pixel math
- Added dev bundle ID separation for safe testing alongside production
- Verified: 11 files indexed, 73 headings extracted, Quick Switcher functional with fuzzy search

---

## Files Changed
- `project.yml` — MCP Swift SDK package, ClearlyMCP tool target, postCompileScripts for bundling, ClearlyMCP dependency on Clearly
- `ClearlyMCP/main.swift` (new) — CLI entry point with --vault/--test args, VaultIndex init with explicit bundle ID
- `ClearlyMCP/Tools.swift` (new) — MCP server setup, 3 tool handlers (search_notes, get_backlinks, get_tags), Value extensions
- `Clearly/VaultIndex.swift` — `@unchecked Sendable`, `init(locationURL:bundleIdentifier:)`, `indexDirectory(bundleIdentifier:)` with sandbox container resolution
- `Clearly/WorkspaceManager.swift` — `persistVaultsConfig()` writes ~/.config/clearly/vaults.json, called from persistLocations() and restoreLocations()
- `Clearly/SettingsView.swift` — MCP tab with status indicator, vault selector, copy config, test connection
- `Clearly/ClearlyApp.swift` — `installMCPHelperIfNeeded()` copies binary to App Support on launch
- `Clearly/Theme.swift` — `tagColor` (soft blue, light/dark)
- `Clearly/MarkdownSyntaxHighlighter.swift` — `.tag` enum case, regex pattern, 2 switch cases (highlightAll + highlightAround)
- `Shared/MarkdownRenderer.swift` — `processTags()`, `protectTagRegions()`, `restoreTagRegions()` in pipeline
- `Shared/PreviewCSS.swift` — `.md-tag` styles in light, dark, print, export contexts
- `Clearly/PreviewView.swift` — `onTagClicked` callback, `clearly://tag/` URL handling in `handleLinkClick`
- `Clearly/ContentView.swift` — `onTagClicked` wired to `ClearlyFilterByTag` notification
- `Clearly/FileExplorerView.swift` — `tags` Section, `tagEntry` OutlineItem.Kind, tag cache, data source/delegate methods, context menu, persistence
- `Clearly/QuickSwitcherPanel.swift` — `show(withQuery:)`, tag-based filtering when query starts with `#`
- `Clearly/ClearlyApp.swift` — `ClearlyFilterByTag` notification observer → Quick Switcher
- `Clearly/BacklinksState.swift` (new) — ObservableObject with debounced update, linked/unlinked mention queries
- `Clearly/BacklinksView.swift` (new) — SwiftUI panel with linked/unlinked sections, hover rows, empty state
- `Clearly/VaultIndex.swift` — `file(forURL:)`, `unlinkedMentions(for:excludingFileId:)` methods
- `Clearly/ContentView.swift` — BacklinksStateKey, FocusedValues, BacklinksView layout, toggle button, notification listeners
- `Clearly/ClearlyApp.swift` — Cmd+Shift+B shortcut, "Toggle Backlinks" menu item, toggleBacklinksAction
- `Clearly/VaultIndex.swift` — `MatchExcerpt`, `SearchFileGroup` types, `searchFilesGrouped(query:)` method
- `Clearly/QuickSwitcherPanel.swift` — content match support (FTS5 results, scroll-to-line, snippet display)
- `Clearly/ClearlyApp.swift` — Cmd+Shift+F shortcut, `injectGlobalSearchIfNeeded()` View menu item
- `Clearly/WikiLinkCompletionWindow.swift` (new) — WikiLinkCompletionManager, panel, table, cell views
- `Clearly/MarkdownSyntaxHighlighter.swift` — `isInsideProtectedRange(at:)` public method
- `Clearly/ClearlyTextView.swift` — `keyDown` override, mouseDown dismiss
- `Clearly/EditorView.swift` — `lastReplacementString`, `handleWikiLinkCompletion`, wired in textDidChange
- `Clearly/Theme.swift` — `wikiLinkColor`, `wikiLinkBrokenColor`
- `Clearly/MarkdownSyntaxHighlighter.swift` — `.wikiLink` enum case, pattern, two switch cases
- `Shared/MarkdownRenderer.swift` — `processWikiLinks()` in pipeline
- `Shared/PreviewCSS.swift` — `.wiki-link`, `.wiki-link-broken` CSS in 4 contexts
- `Clearly/PreviewView.swift` — `onWikiLinkClicked` callback, `wikiFileNames`, broken-link JS, scheme handling
- `Clearly/ContentView.swift` — wiki file names computation, callbacks, `.navigateWikiLink` notification handler
- `Clearly/ClearlyTextView.swift` — `onWikiLinkClicked`, mouseDown override, regex detection
- `Clearly/EditorView.swift` — wire onWikiLinkClicked via notification
- `project.yml` — GRDB dependency, dev bundle IDs for Debug config
- `Clearly/FileParser.swift` (new) — markdown parser for wiki-links, tags, headings
- `Clearly/VaultIndex.swift` (new) — SQLite index with GRDB, FTS5, full schema
- `Clearly/QuickSwitcherPanel.swift` (new) — NSPanel, fuzzy matching, keyboard nav
- `Clearly/WorkspaceManager.swift` — VaultIndex lifecycle integration
- `Clearly/ClearlyApp.swift` — Cmd+P shortcut, Print → Cmd+Shift+P

## Architectural Decisions
- **GRDB over raw SQLite or SwiftData**: DatabasePool gives concurrent WAL reads, DatabaseMigrator for schema versioning, raw sqlite3* handle available for future sqlite-vec embeddings
- **FTS5 standalone (not external content)**: External content mode requires matching columns in the content table. Standalone stores its own copy but supports snippet() and is simpler to maintain
- **Borderless NSPanel over .titled**: Eliminates the ~28pt invisible titlebar that was impossible to work around with fullSizeContentView. Requires KeyablePanel subclass for keyboard input
- **Index stored in App Support by bundle ID**: `~/Library/Containers/{bundleID}/Data/Library/Application Support/{bundleID}/indexes/` — sandbox-safe, dev/prod isolated
- **FileParser extracts everything upfront**: Links, tags, headings all parsed in Phase 1 even though wiki-link UI, tag browser, etc. ship in later phases. Avoids re-indexing and schema migrations

## Lessons Learned
- NSTableView.style defaults to .inset on macOS 11+, adding hidden vertical padding that breaks manual height calculations. Always set .plain for precise sizing
- Borderless NSPanel can't become key by default — must subclass and override canBecomeKey
- FTS5 external content mode (content='table') requires the referenced table to have columns matching the FTS column names — easy to miss
- xcodegen must be re-run after adding new Swift files, not just after changing project.yml
- @Observable macro expansion fails on properties whose types come from external packages — use @ObservationIgnored for non-observable state
