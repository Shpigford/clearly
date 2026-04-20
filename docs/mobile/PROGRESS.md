# Mobile Progress

## Status: Phase 1 - Complete

## Quick Reference
- Research: `docs/mobile/RESEARCH.md`
- Implementation: `docs/mobile/IMPLEMENTATION.md`

---

## Phase Progress

### Phase 1: `ClearlyCore` package extraction (Mac-only)
**Status:** Complete (2026-04-20)

#### Tasks Completed
- [x] Created `Packages/ClearlyCore/Package.swift` (macOS 14 / iOS 17 platforms, cmark + GRDB deps)
- [x] Added `Packages/ClearlyCore/Sources/ClearlyCore/Platform/Platform.swift` with `PlatformFont`/`PlatformColor`/`PlatformImage`/`PlatformPasteboard` typealiases
- [x] Moved 8 files from `Shared/` into `Packages/ClearlyCore/Sources/ClearlyCore/Rendering/`: `MarkdownRenderer`, `PreviewCSS`, `MermaidSupport`, `TableSupport`, `SyntaxHighlightSupport`, `EmojiShortcodes`, `LocalImageSupport`, `FrontmatterSupport`
- [x] Moved 12 files from `Clearly/` into `Packages/ClearlyCore/Sources/ClearlyCore/` (subdirs `Vault/`, `State/`, `Diagnostics/`)
- [x] Rewired `project.yml`: added `ClearlyCore` local package; removed `Shared/` glob + explicit file entries from all four targets; added `package: ClearlyCore` dep on `Clearly`, `ClearlyQuickLook`, `ClearlyCLI`, `ClearlyCLIIntegrationTests`
- [x] Added `import ClearlyCore` to 52 consumer files across `Clearly/`, `ClearlyQuickLook/`, `ClearlyCLI/`, `ClearlyCLIIntegrationTests/`
- [x] Marked all cross-module API surfaces `public` (types + members consumed externally)
- [x] `xcodegen generate` clean
- [x] `xcodebuild -scheme Clearly build` green
- [x] `xcodebuild -scheme ClearlyQuickLook build` green
- [x] `xcodebuild -scheme ClearlyCLI build` green
- [x] `xcodebuild -scheme ClearlyCLIIntegrationTests test` — 23 tests pass

#### Decisions Made
- **Resources stayed in place.** `Shared/Resources/*` (katex, mermaid, highlight, fonts, demo.md, getting-started.md) remain at their original paths; `project.yml` resource buildPhase entries preserved for `Clearly` + `ClearlyQuickLook`. `Bundle.main.url(...)` in `MermaidSupport.swift` and `SyntaxHighlightSupport.swift` continues to resolve to the app bundle. Avoided a `Bundle.module` migration; can happen later if needed.
- **`PlatformTextView` deferred.** `NSTextView` and `UITextView` have divergent APIs that aren't typealias-compatible; that shim lands in Phase 5 with the iOS editor.
- **`Platform.swift` scaffolding added now.** Not consumed by any Phase 1 file (all 20 are Foundation/GRDB/WebKit/cmark-clean) but lands the cross-platform pattern so Phase 5 won't need to rewire `Package.swift`.

#### Blockers
- (none)

---

### Phase 2: iOS target scaffolding + placeholder app
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 3: iCloud ubiquity plumbing + entitlements on all three builds
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 4: Read-only iOS vault browsing
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 5: iOS syntax-highlighted editor (read-only save path)
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 6: Coordinated writes + keyboard accessory bar
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 7: iOS preview + wiki-link navigation
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 8: Index rebuild + `.icloud` placeholder coordination
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 9: Quick switcher + global search UIs on iOS
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 10: Backlinks + outline + tags surfaces on iOS
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 11: Conflict detection + sibling-file + banner + diff view
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 12: iPad 3-column layout + multi-document tab bar port
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 13: Release — polish + CI matrix + App Store submission
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

## Session Log

### 2026-04-20
- Research reviewed (`docs/mobile/RESEARCH.md`)
- Implementation plan written (`docs/mobile/IMPLEMENTATION.md`) — 13 phases
- Distribution model locked in: same bundle ID `com.sabotage.clearly` across direct / MAS / iOS; Universal Purchase between MAS + iOS; direct-build participates in iCloud sync
- Progress tracking set up
- **Phase 1 executed and verified.** 20 Swift files relocated into `Packages/ClearlyCore`; all four Mac schemes build clean; all 23 `ClearlyCLIIntegrationTests` pass. Mac behavior unchanged — no functional changes, no UI changes.

---

## Files Changed

### Phase 1 (2026-04-20)
- **New:** `Packages/ClearlyCore/Package.swift`, `Packages/ClearlyCore/Sources/ClearlyCore/Platform/Platform.swift`
- **Moved (20 files, history preserved via `git mv`):** `Shared/{MarkdownRenderer,PreviewCSS,MermaidSupport,TableSupport,SyntaxHighlightSupport,EmojiShortcodes,LocalImageSupport,FrontmatterSupport}.swift` → `Packages/ClearlyCore/Sources/ClearlyCore/Rendering/`; `Clearly/{VaultIndex,FileParser,FileNode,IgnoreRules,BookmarkedLocation}.swift` → `Vault/`; `Clearly/{OpenDocument,OutlineState,FindState,JumpToLineState,BacklinksState,PositionSync}.swift` → `State/`; `Clearly/DiagnosticLog.swift` → `Diagnostics/`
- **Modified:** `project.yml` (all four targets re-wired); 52 consumer files across `Clearly/`, `ClearlyQuickLook/`, `ClearlyCLI/`, `ClearlyCLIIntegrationTests/` got `import ClearlyCore` + types inside moved files made public where accessed cross-module.

## Architectural Decisions

### 2026-04-20 — Universal Purchase with shared bundle ID across all three channels
Direct (Sparkle), Mac App Store, and iOS App Store all use `com.sabotage.clearly`. Universal Purchase links the two App Store SKUs; direct distribution is outside the App Store and unaffected. On a single Mac a user installs direct OR MAS, not both (same bundle ID collision). iCloud container `iCloud.com.sabotage.clearly` provisioned once against the Team ID and shared.

### 2026-04-20 — Direct Mac build participates in iCloud sync
Direct-download users sync with iOS via iCloud too. Costs nothing extra; avoids a two-tier "MAS users get sync, direct users don't" story.

### 2026-04-20 — iPad multi-document tabs in v1 (research default overridden)
Research recommended single-document-per-scene on iPad to match `DocumentGroup` semantics. Overridden to port the Mac tab bar because Clearly's Mac experience is defined by tabs, and iPad hardware is similar enough that users will expect parity. Implementation keeps `DocumentGroup` as the scene root and manages multiple `OpenDocument` instances inside a custom container in the detail column.

### 2026-04-20 — 13 phases rather than 8
First draft had 8 phases but several were 2–3 days of work each. Split to 13 phases sized so each can be completed and verified on-device in one focused session (half-day to full-day).

## Lessons Learned
(What worked, what didn't, what to do differently)
