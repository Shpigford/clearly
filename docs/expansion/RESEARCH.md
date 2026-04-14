# Expansion Research: Knowledge Management + AI Integration

## Overview

Transform Clearly from a polished markdown editor into a full knowledge management tool. This means adding cross-file intelligence (wiki-links, backlinks, global search, tags) and AI ecosystem integration (MCP server) — all on top of the existing native macOS foundation.

Scope: Phases 0-3 only. Built-in AI (Phase 4) and monetization (Phase 5) are explicitly out of scope.

## Problem Statement

Clearly's rendering and preview side is strong (math, mermaid, callouts, code highlighting, PDF export). The knowledge management side is entirely missing — no cross-file awareness beyond the file tree. Every file is an island. Users can't link notes, search across their vault, track what references what, or expose their notes to AI agents.

The gap isn't about polish — it's about architecture. Clearly has no persistent index of file contents, no cross-file link tracking, and no way to query across the vault. Everything depends on building that foundation first.

## User Stories / Use Cases

1. **Wiki-linking**: "I'm writing about a concept I've explored in another note. I type `[[` and get a popup suggesting matching files. I select one, and the link is inserted. In preview, clicking it opens that file."
2. **Backlinks**: "I open a note and see a panel showing every other note that links to this one, with context. I discover connections I'd forgotten."
3. **Global search**: "I press Cmd+Shift+F and search for a phrase. Results appear grouped by file with surrounding context. I click one and jump directly to that line."
4. **Quick switcher**: "I press Cmd+O, type a few characters, and instantly find the file I want from hundreds of notes. It's faster than scrolling the sidebar."
5. **Tags**: "I tag notes with `#project/clearly` and `#idea`. The sidebar shows all my tags in a tree. Clicking one filters to matching files."
6. **MCP integration**: "I configure Clearly as an MCP server in Claude Desktop. I ask Claude 'what notes do I have about pricing?' and it searches my vault and answers."

---

## Technical Research

### Phase 0: Cross-File Index (SQLite + FTS5)

#### Approach: GRDB.swift

**Recommendation: Use [GRDB.swift](https://github.com/groue/GRDB.swift) (v7.x).**

Why GRDB over alternatives:
- **vs raw `import SQLite3`**: GRDB gives you `DatabasePool` (concurrent reads via WAL mode), `DatabaseMigrator`, `Codable` record mapping, and `ValueObservation` for reactive SwiftUI — you'd rebuild half of this manually with raw C.
- **vs SQLite.swift**: GRDB is 3-12x faster on fetches and supports concurrent reads. SQLite.swift uses a single serialized connection.
- **vs SwiftData/CoreData**: Need direct FTS5 access and later sqlite-vec for embeddings. Apple's abstractions add overhead without benefit.

GRDB exposes the raw `sqlite3*` handle for loading C extensions (sqlite-vec later).

**FTS5 availability**: Enabled in macOS's bundled SQLite since macOS 10.13. Works out of the box on our deployment target (macOS 14.0). GRDB's Swift FTS5 wrappers require a custom build flag, but raw SQL `CREATE VIRTUAL TABLE ... USING fts5(...)` works immediately.

**Threading**: `DatabasePool` handles everything. WAL mode is automatic — multiple threads read simultaneously, writes are serialized. One pool instance shared app-wide. Sub-10ms queries at 10,000+ documents.

#### Schema Design

```sql
-- Core file metadata
CREATE TABLE files (
    id INTEGER PRIMARY KEY,
    path TEXT UNIQUE NOT NULL,        -- relative to vault root
    filename TEXT NOT NULL,            -- just the filename without extension
    content_hash TEXT NOT NULL,        -- for incremental re-indexing
    modified_at REAL NOT NULL,         -- file modification date
    indexed_at REAL NOT NULL           -- when we last indexed this
);

-- Full-text search index
CREATE VIRTUAL TABLE files_fts USING fts5(
    filename,                          -- searchable filename
    content,                           -- full file content for FTS
    content=files,                     -- external content table
    content_rowid=id,
    tokenize='porter unicode61'        -- stemming + unicode support
);

-- Wiki-links between files
CREATE TABLE links (
    id INTEGER PRIMARY KEY,
    source_file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    target_name TEXT NOT NULL,          -- raw link text (e.g., "My Note")
    target_file_id INTEGER REFERENCES files(id) ON DELETE SET NULL, -- resolved target (nullable if unresolved)
    line_number INTEGER,               -- source line for context
    display_text TEXT,                  -- alias text if [[note|alias]]
    context TEXT                        -- surrounding text for backlinks display
);

-- Tags
CREATE TABLE tags (
    id INTEGER PRIMARY KEY,
    file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    tag TEXT NOT NULL,                  -- normalized: lowercase, no #
    line_number INTEGER,
    source TEXT NOT NULL DEFAULT 'inline'  -- 'inline' or 'frontmatter'
);
CREATE INDEX idx_tags_tag ON tags(tag);
CREATE INDEX idx_tags_file ON tags(file_id);

-- Headings (for [[note#heading]] resolution and outline)
CREATE TABLE headings (
    id INTEGER PRIMARY KEY,
    file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    text TEXT NOT NULL,
    level INTEGER NOT NULL,            -- 1-6
    line_number INTEGER NOT NULL
);
```

#### Index Storage Location

Store in `~/Library/Application Support/Clearly/indexes/` keyed by vault path hash. Not inside the vault (`.clearly/` pollutes user files, causes git noise). App Support is the standard macOS location for derived data.

#### Indexing Pipeline

1. **Initial index**: On location bookmark add, walk all markdown files, parse each, insert into SQLite. Use `DispatchQueue.global(qos: .utility)` with batch inserts (GRDB's `inTransaction` for performance).
2. **Incremental updates**: FSEventStream (already exists in WorkspaceManager) fires on file changes. Compare `content_hash` — only re-parse changed files. Re-resolve links affected by renames/deletes.
3. **File parsing**: For each file, extract:
   - Content for FTS
   - Wiki-links: regex `\[\[([^\]\|#\^]+?)(?:#([^\]\|]+?))?(?:\|([^\]]+?))?\]\]`
   - Tags: regex `(?:^|(?<=\s))#([\p{L}\p{N}_\-/]*[\p{L}_\-/][\p{L}\p{N}_\-/]*)` (must contain at least one non-digit)
   - Headings: regex `^(#{1,6})\s+(.+)$`
   - Frontmatter tags from YAML `tags:` field
4. **Code block exclusion**: Strip fenced code blocks before extracting links/tags (same pattern as MarkdownSyntaxHighlighter's cachedProtectedRanges).
5. **Performance target**: Index 1,000 files in <5 seconds. Re-index single file in <50ms.

#### Integration with WorkspaceManager

```
WorkspaceManager.swift changes:
- Add `var vaultIndex: VaultIndex?` property
- On addLocation(): create/open VaultIndex for that location, trigger initial index
- On FSEventStream callback: call vaultIndex.reindexChangedFiles(paths:)
- On removeLocation(): close and optionally delete index
```

New file: `Clearly/VaultIndex.swift` — wraps GRDB DatabasePool, provides query APIs:
- `searchFiles(query:) -> [SearchResult]` (FTS5)
- `allFiles() -> [FileRecord]`
- `linksFrom(fileId:) -> [Link]`
- `linksTo(fileId:) -> [Link]` (backlinks)
- `tagsForFile(fileId:) -> [Tag]`
- `filesForTag(tag:) -> [FileRecord]`
- `allTags() -> [(tag: String, count: Int)]`
- `resolveWikiLink(name:) -> FileRecord?`

New file: `Clearly/FileParser.swift` — extracts links, tags, headings from markdown content. Pure function, no side effects. Testable.

Dependency: Add GRDB.swift to `project.yml`:
```yaml
GRDB:
  url: https://github.com/groue/GRDB.swift.git
  from: "7.0.0"
```

---

### Phase 1: Knowledge Primitives

#### 1a. Wiki-Links

**Editor Highlighting** (`MarkdownSyntaxHighlighter.swift`):

Add to the `patterns` array (after footnote markers, before table rows — line ~83):
```swift
// Wiki-links: [[note]] or [[note|alias]] or [[note#heading]]
add(#"\[\[([^\]\|#]+?)(?:#[^\]\|]+?)?(?:\|[^\]]+?)?\]\]"#, .wikiLink)
```

Add `.wikiLink` to the `HighlightStyle` enum. Style with `Theme.wikiLinkColor` — a distinct color (not the same as regular links). The `cachedProtectedRanges` mechanism already protects code blocks from highlighting.

**Preview Rendering** (`MarkdownRenderer.swift`):

Add `processWikiLinks()` in the post-processing pipeline after `processEmoji()` (line 29) and before `processCallouts()` (line 30). Follows the same `protectCodeRegions`/`restoreProtectedSegments` pattern:

```swift
html = processWikiLinks(html)
```

The transform converts `[[note]]` → `<a href="clearly://wiki/note" class="wiki-link">note</a>` and `[[note|alias]]` → `<a href="clearly://wiki/note" class="wiki-link">alias</a>`. Unresolved links get a `.wiki-link-broken` class (styled red/dimmed).

**Link resolution** needs the VaultIndex. Two options:
- Pass the index to `renderHTML()` (changes the API, affects QuickLook too)
- Resolve links client-side in JavaScript after render (simpler, keeps renderer pure)

Recommendation: **JavaScript resolution**. Keep `MarkdownRenderer` pure (shared with QuickLook where there's no index). In `PreviewView`, inject a script that resolves `clearly://wiki/` links against a file list passed from Swift. This matches the existing pattern of JS injection for interactivity.

**Preview Click Handling** (`PreviewView.swift`):

Add a `"wikiLinkClicked"` message handler (same pattern as `"linkClicked"` at line 511). When a wiki-link is clicked:
1. JavaScript sends the link target name via `window.webkit.messageHandlers.wikiLinkClicked.postMessage(targetName)`
2. Coordinator receives it, resolves via VaultIndex
3. Calls `WorkspaceManager.openFile(at: resolvedURL)`

**Editor Click Handling**:

Cmd+click on a `[[wiki-link]]` in the editor should navigate too. Detect via `NSTextView.clicked(onLink:in:at:characterIndex:)` or a gesture recognizer that checks if the click is within a wiki-link range.

#### 1b. Quick Switcher (Cmd+O)

**UI Pattern: NSPanel** (floating, non-activating)

- `styleMask: [.titled, .fullSizeContentView]`, hidden titlebar
- `NSVisualEffectView` with `.popover` material for vibrancy
- ~580px wide, centered horizontally on active window, upper third vertically
- Search field: ~44px tall, placeholder "Search notes..."
- Results: `NSTableView` with ~36px rows, max 8-10 visible
- Keyboard: Up/Down navigate results, Enter opens, Escape dismisses
- Dismiss on: Escape, click outside, focus loss

**Fuzzy matching**: Sequential character matching with gap penalties. Bonus for matches after separators (`/`, `.`, `_`, space) and consecutive matches. Return matched ranges for highlighting. This is <16ms for 70K files.

**Default state**: When query is empty, show recently opened files. Immediately useful.

**Results display**: File name (primary, bold matched characters), folder path (dimmed secondary text).

**Create-on-miss**: If no results, show "Create [query].md" option at bottom. Enter creates the file and opens it.

**File**: New `Clearly/QuickSwitcherPanel.swift`

**Shortcut**: Cmd+P (consistent with VS Code's quick file finder). Register in `ClearlyApp.swift` menu commands.

#### 1c. Global Search (Cmd+Shift+F)

**UI Pattern: Sidebar search panel**

When activated, a search field appears at top of sidebar. Results replace the file tree below.

**Results layout**: Grouped by file — file name header with match count badge, then indented match excerpts below. Each match shows the matching line with matched term highlighted. 1 line of context before/after. File groups are collapsible.

**Two-section results**: File name matches first (from `files.filename` column), content matches second (from FTS5). This distinguishes "I know the name" from "I remember what it said."

**Search behavior**: Real-time with 150ms debounce. Start after 2+ characters. Keyboard: Down arrow moves to results, Enter opens file at match line.

**FTS5 query**: Use `MATCH` with `bm25()` ranking. Support quoted phrases and boolean operators naturally (FTS5 handles this).

**Integration**: New `Clearly/SearchView.swift` (AppKit, like FileExplorerView). Toggle between file tree and search results in the sidebar. Modified `FileExplorerView.swift` to add search activation.

**Shortcut**: Cmd+Shift+F. Register in `ClearlyApp.swift`.

---

### Phase 2: Knowledge Graph

#### 2a. Backlinks Panel

**UI Pattern: Bottom panel, collapsible**

Horizontal divider below editor content area. "Backlinks" header with count badge. Toggle via menu/shortcut.

**Two subsections**:
- **Linked mentions**: Files with explicit `[[this-file]]` wiki-links. Show: source file name (clickable → opens file), 1-2 lines of context with the `[[link]]` highlighted.
- **Unlinked mentions**: Files containing this file's title as plain text (not inside a `[[]]`). Show same format + subtle "Link" button to convert to `[[wiki-link]]`. Collapsed by default.

**Query**: `SELECT l.*, f.path, f.filename FROM links l JOIN files f ON l.source_file_id = f.id WHERE l.target_file_id = ?`

**Updates**: Refresh when active document changes. Use GRDB's `ValueObservation` to reactively watch for link changes.

**Layout integration**: Add below the editor in `ContentView.swift`. Similar to how the outline panel works — a collapsible section. Use `NSSplitView` or a simple VStack with a draggable divider.

**File**: New `Clearly/BacklinksView.swift`

**Shortcut**: Cmd+Shift+B (toggle backlinks panel).

#### 2b. Tags

**Parsing rules** (important edge cases):
- `#tag` is a tag. `# heading` (hash-space) is a heading.
- Tags must contain at least one non-digit: `#2024` is NOT a tag, `#year-2024` IS.
- Nested tags: `#parent/child` indexes both `parent` and `parent/child`.
- Don't parse inside code blocks, inline code, URLs, or HTML.
- Frontmatter `tags: [foo, bar]` are also indexed (no `#` prefix in YAML).
- Store normalized (lowercase, no `#` prefix).

**Tag regex**: `(?:^|(?<=\s))#([\p{L}\p{N}_\-/]*[\p{L}_\-/][\p{L}\p{N}_\-/]*)`

**Editor highlighting** (`MarkdownSyntaxHighlighter.swift`):
Add `.tag` style to patterns array. Color: distinct from wiki-links and regular links.

**Preview rendering** (`MarkdownRenderer.swift`):
`processWikiLinks` can also transform `#tag` → `<span class="tag" data-tag="tag">#tag</span>` with click handler.

**Sidebar tag browser** (`FileExplorerView.swift`):
New section below Locations. Collapsible tree for nested tags. Each tag shows file count badge. Click → filter file tree to files with that tag.

**Query**: `SELECT DISTINCT tag, COUNT(*) FROM tags GROUP BY tag ORDER BY tag`

#### 2c. Link Auto-Complete

**DO NOT use `NSTextView.complete(_:)`.** It's word-boundary based and wrong for `[[` triggers.

**Custom popup**:
- Borderless `NSWindow` child of editor window, positioned below cursor via `firstRect(forCharacterRange:actualRange:)`
- ~300px wide, max 8 rows, `NSTableView` with file names
- Keyboard: Up/Down navigate, Enter/Tab inserts `filename]]`, Escape dismisses

**Trigger lifecycle**:
1. In `textDidChange` (EditorView.swift), detect `[[` was just typed
2. Show popup with all files (or recents if vault is large)
3. As user types after `[[`, filter results via fuzzy match
4. On select: insert `filename]]` (completing the link)
5. Dismiss on: Escape, `]]` typed manually, backspace past `[[`, click outside
6. Don't trigger inside code blocks (check `cachedProtectedRanges`)

**File**: New `Clearly/WikiLinkCompletionWindow.swift`

---

### Phase 3: MCP Server

#### Architecture: Standalone Companion Binary

Clearly is sandboxed. The MCP protocol uses stdio (client spawns server as subprocess). A sandboxed app can't be spawned this way. Solution: **ship a standalone CLI binary** that lives outside the app bundle.

The companion binary (`clearly-mcp`) is a tiny CLI (~2MB) that reads the same SQLite index via WAL mode (concurrent reads are safe). It does NOT need sandbox entitlements.

**Distribution:**
- **Direct download (DMG)**: Binary bundled inside the app bundle at `Contents/Helpers/ClearlyMCP`. On first launch (or on update), the app copies it to `~/Library/Application Support/Clearly/ClearlyMCP`. Zero user interaction — MCP just works.
- **App Store**: One-click "Install MCP Helper" button in Settings. Downloads the binary from GitHub Releases via `URLSession`, writes to `~/Library/Application Support/Clearly/ClearlyMCP`, sets executable permission. No terminal needed.

#### Settings → MCP Setup Panel (All Builds)

A dedicated MCP section in Settings, present in **both** direct and App Store builds:

**Direct download build:**
- MCP binary is already installed. Show green checkmark + version.
- Vault path selector (defaults to active bookmarked location).
- **"Copy Claude Desktop Config"** button — generates correct JSON with resolved binary path and vault path, copies to clipboard.
- **"Test Connection"** button — runs the binary with `--test` flag, confirms it can read the index.
- **Auto-detect Claude Desktop** — if `~/Library/Application Support/Claude/claude_desktop_config.json` exists, offer to add the config automatically (with confirmation).

**App Store build:**
- Same panel, but detection shows "Not installed" initially.
- One-click "Install MCP Helper" button (downloads + installs automatically).
- Once installed, same setup flow as direct download (config copy, test, auto-detect).

Direct download users never think about MCP installation. It's just there. App Store users click one button. One install path, no terminal.

#### MCP Swift SDK

Official SDK exists: [modelcontextprotocol/swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) (v0.11.0+). Requires Swift 6.0 / Xcode 16+.

```swift
import MCP

let server = Server(
    name: "clearly",
    version: "1.0.0"
)

server.withMethodHandler(ListTools.self) { _ in
    return .init(tools: [
        Tool(name: "search_notes", description: "Full-text search across all notes",
             inputSchema: .object(properties: ["query": .string(description: "Search query")])),
        Tool(name: "read_note", description: "Read a note's content",
             inputSchema: .object(properties: ["path": .string(description: "Note path")])),
        Tool(name: "list_notes", description: "List all notes in the vault",
             inputSchema: .object(properties: [:])),
    ])
}
```

#### Tools to Expose (Priority Order)

**P0 (ship with MCP):**
- `search_notes` — FTS5 search, returns matching files + context
- `read_note` — get full content of a note by path
- `list_notes` — list all notes with optional folder filter

**P1 (add after backlinks/tags):**
- `get_backlinks` — backlinks for a note
- `get_tags` — all tags or files for a tag
- `create_note` — create a new note
- `update_note` — update note content

**P2 (future):**
- `get_metadata` — frontmatter for a note
- `search_by_tag` — notes with specific tag
- `get_outgoing_links` — wiki-links from a note

#### Claude Desktop Configuration

The Settings panel generates and copies this config for the user:
```json
{
  "mcpServers": {
    "clearly": {
      "command": "~/Library/Application Support/Clearly/ClearlyMCP",
      "args": ["--vault", "/path/to/vault"]
    }
  }
}
```
The vault path is auto-populated from the active bookmarked location.

#### Files

- New target in `project.yml`: `ClearlyMCP` (command-line tool)
- New: `ClearlyMCP/main.swift` — MCP server entry point
- Shared: `Clearly/VaultIndex.swift` (read-only access to the index)
- Dependency: Add MCP Swift SDK to `project.yml`

---

## UI/UX Considerations

### Quick Switcher
- Appears instantly (no animation). Fast animations feel slow.
- Match characters highlighted in accent color (the #1 delight detail).
- Recently opened files shown when query is empty.
- Path truncated from middle: `~/Docs/.../nested/file.md`
- "No results — press Enter to create [query].md" empty state.

### Global Search
- Real-time, no enter-to-search. 150ms debounce.
- File name matches separated from content matches.
- Keyboard-navigable: arrow keys move between results, Enter opens.
- Match term highlighted in results.

### Backlinks Panel
- Collapsed by default for notes with no backlinks.
- "No other documents link to this file" empty state (brief, not educational).
- Unlinked mentions collapsed by default (can be noisy).
- Clickable file names open the linking note.

### Wiki-Link Auto-Complete
- Appears below cursor, no arrow chrome.
- Fuzzy matching with highlighted match characters.
- Keyboard-first: Tab/Enter to select, Escape to dismiss.
- Shows file icon + name + folder path.

### Tags Browser
- Collapsible tree for nested tags.
- Count badge per tag.
- Click → filter file tree (simpler than triggering search).
- "Use #tag in your documents to organize them" empty state.

### General
- Every feature fully keyboard-operable.
- Smart recency: recently opened files first everywhere.
- No slow animations — panels appear/disappear immediately.

---

## Integration Points

### MarkdownRenderer.swift (Shared/)
- **Wiki-link processing**: New `processWikiLinks()` method, inserted after `processEmoji()` (line 29), before `processCallouts()` (line 30). Uses existing `protectCodeRegions`/`restoreProtectedSegments` pattern.
- Renderer stays pure — no VaultIndex dependency. Link resolution happens in JavaScript on the PreviewView side.

### MarkdownSyntaxHighlighter.swift (Clearly/)
- **Wiki-link pattern**: Add to `patterns` array after footnote markers (~line 83). New `.wikiLink` style.
- **Tag pattern**: Add to `patterns` array. New `.tag` style.
- Both are protected by existing `cachedProtectedRanges` code-block exclusion.

### PreviewView.swift (Clearly/)
- **Wiki-link click handler**: New `"wikiLinkClicked"` message handler in `userContentController(_:didReceive:)` (~line 504). Follows `"linkClicked"` pattern at line 511.
- **JavaScript injection**: Script to resolve `clearly://wiki/` links and handle tag clicks.

### WorkspaceManager.swift (Clearly/)
- **VaultIndex integration**: New `var vaultIndex: VaultIndex?` property.
- **Index lifecycle**: Create on `addLocation()`, update on FSEventStream changes, close on `removeLocation()`.
- **Navigation**: `openFile(at:)` at line 235 is the API for all "open this file" actions.

### EditorView.swift (Clearly/)
- **Auto-complete trigger**: In `textDidChange` delegate, detect `[[` and show completion popup.
- **Cmd+click navigation**: Detect click on wiki-link range, resolve, navigate.

### FileExplorerView.swift (Clearly/)
- **Search section**: New mode that replaces file tree with search results.
- **Tags section**: New sidebar section below Locations showing tag tree.

### ContentView.swift (Clearly/)
- **Backlinks panel**: New collapsible bottom panel below editor.
- **Shortcut wiring**: Cmd+O (quick switcher), Cmd+Shift+F (search), Cmd+Shift+B (backlinks).

### Theme.swift (Clearly/)
- New colors: `wikiLinkColor`, `wikiLinkBrokenColor`, `tagColor`.

### project.yml
- New dependency: GRDB.swift
- New dependency: MCP Swift SDK (for ClearlyMCP target)
- New target: ClearlyMCP (command-line tool)

---

## Risks and Challenges

1. **Index corruption/staleness**: SQLite can become out of sync if files are modified outside the app while it's not running. Mitigation: compare `content_hash` on launch, re-index stale files. Provide manual "Rebuild Index" command.

2. **Large vault performance**: 10,000+ files need efficient batch indexing. GRDB's `inTransaction` + batch inserts help. FTS5 queries are fast (sub-10ms). The bottleneck is initial file parsing, not search.

3. **Link resolution ambiguity**: Multiple files with the same name in different folders. Resolve by shortest path (most intuitive) and show disambiguation in auto-complete when ambiguous.

4. **Sandboxing vs MCP**: Companion binary can't be sandboxed. Direct distribution only. App Store build won't have MCP — acceptable tradeoff (same as Sparkle).

5. **GRDB dependency size**: GRDB is a substantial dependency (~50 Swift files). Acceptable given it replaces building our own connection pool, migrations, FTS5 wrappers, and threading.

6. **Renderer purity**: Adding VaultIndex awareness to MarkdownRenderer would break QuickLook (which has no index). Keeping resolution in JavaScript is the right call but adds complexity.

7. **Tag false positives**: CSS colors (`#fff`), heading markers (`# `), and issue references (`#123`) can be confused with tags. The regex requires at least one non-digit character, but edge cases will exist.

## Open Questions

1. **Index storage**: App Support (recommended) vs inside vault (`.clearly/`). App Support is cleaner but means index is per-machine — if you open the same vault on another Mac, it re-indexes. This is acceptable.

2. **Unlinked mentions**: Should the backlinks panel show unlinked mentions (plain text matching the file name)? Useful for discovering implicit connections but can be noisy. Recommendation: yes, but collapsed by default.

3. **Tag click behavior**: Filter file tree vs show search results? Filter is simpler for v1. Search results offer more context. Start with filter, revisit if users want more.

4. **MCP config auto-write**: The Settings panel can detect Claude Desktop and offer to write the config automatically (with confirmation). Low risk since it's additive (adds a key, doesn't overwrite). Fall back to clipboard copy if user declines.

5. **`[[note#heading]]` support**: Should wiki-links resolve to specific headings? Medium effort — requires heading index (which we have) and scroll-to-heading after navigation. Include in Phase 2 or defer?

## References

- **GRDB.swift**: https://github.com/groue/GRDB.swift — SQLite toolkit for Swift
- **MCP Swift SDK**: https://github.com/modelcontextprotocol/swift-sdk — Official Model Context Protocol SDK
- **MCP Specification**: https://modelcontextprotocol.io/specification — Protocol spec
- **SQLite FTS5**: https://www.sqlite.org/fts5.html — Full-text search documentation
- **Wiki-link syntax reference**: https://help.obsidian.md/Linking+notes+and+files/Internal+links — Common `[[link]]` format spec
- **Tag syntax reference**: https://help.obsidian.md/Editing+and+formatting/Tags — Common `#tag` syntax rules
- **Backlinks UX reference**: https://help.obsidian.md/Plugins/Backlinks — Backlinks panel patterns
