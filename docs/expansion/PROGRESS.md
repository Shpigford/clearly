# Expansion Progress

## Status: Phase 1 - Completed

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
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 3: Wiki-Link Auto-Complete
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 4: Global Search
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 5: Backlinks Panel
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

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
