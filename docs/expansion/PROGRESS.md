# Expansion Progress

## Status: Phase 5 - Completed

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
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 7: MCP Server
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

## Session Log

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
