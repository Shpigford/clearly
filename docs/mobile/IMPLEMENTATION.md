# Mobile Implementation Plan

## Overview

Bring Clearly to iPad and iPhone with near-feature-parity to the macOS app, using iCloud Drive as the cross-device sync substrate. One SwiftUI multiplatform app target, shared logic in a local Swift package (`ClearlyCore`), per-platform UI shells under `#if os(macOS)` / `#if os(iOS)`. iOS 17 minimum; macOS stays at 14.

Source of truth vault: `.md` files + attachments in an iCloud ubiquity container exposed to Files.app. Index (SQLite FTS5) is rebuilt per-device — never synced. Conflicts are detected via `NSFileVersion` and written as sibling files with a visible banner; no auto-merge.

Plan is split into 13 phases sized so each can be completed and verified on-device in one focused session (half-day to full-day). Every phase after `ClearlyCore` extraction produces something a user can see or test.

## Prerequisites

- Xcode 16+ with Swift 5.9
- XcodeGen installed (`xcodegen generate` after every `project.yml` change)
- Apple Developer Program membership; iCloud container `iCloud.com.sabotage.clearly` provisioned for all three bundle-ID variants (direct Mac, MAS Mac, iOS)
- iCloud account signed into the test Mac and test iPhone / iPad (or simulator with iCloud account)

## Distribution & Universal Purchase

Three shipping channels, all using the same bundle ID `com.sabotage.clearly`:

1. **Direct / Sparkle (Mac).** Lives outside the App Store. Sparkle code stays wrapped in `#if canImport(Sparkle)`. Ships with iCloud entitlements so direct-download users sync with iOS too.
2. **Mac App Store.** Existing `release-appstore.sh` path, no Sparkle. iCloud entitlements present.
3. **iOS App Store (new).** Universal Purchase pair with MAS via the shared bundle ID.

iCloud container provisioned once against the Team ID and shared by all three. On a single Mac, a user installs direct OR MAS (same bundle ID collides in `/Applications`) — same pattern as Things / 1Password.

## Resolved defaults for research open questions

| # | Question | Decision |
|---|----------|----------|
| 1 | Bundle ID | Universal Purchase — `com.sabotage.clearly` on direct, MAS, and iOS |
| 2 | iOS without iCloud | Allow local vault via `UIDocumentPickerViewController` |
| 3 | Keyboard-shortcuts library | SwiftUI `.keyboardShortcut` + `UIKeyCommand` only; `sindresorhus/KeyboardShortcuts` stays Mac-only |
| 4 | iOS QuickLook extension | Out of scope for v1 |
| 5 | iPhone backlinks / outline surface | Toolbar-button sheets |
| 6 | iPad multi-document tabs | Port the Mac tab bar to iPad in v1 |
| 7 | Cursor-position sync | Out of scope for v1 |
| 8 | Direct-build iCloud sync | Yes — direct / MAS / iOS all share the same iCloud container |

## Phase Summary

| # | Title | Shippable result |
|---|-------|------------------|
| 1 | `ClearlyCore` package extraction (Mac-only) | Mac app identical behavior; shared code lives in a local SPM package |
| 2 | iOS target scaffolding + placeholder app | `xcodebuild -scheme Clearly-iOS` green; app boots on simulator |
| 3 | iCloud ubiquity plumbing + entitlements on all three builds | Files.app shows "Clearly" folder; direct/MAS/iOS all resolve same container |
| 4 | Read-only iOS vault browsing | Browse & read `.md` files on iPhone/iPad |
| 5 | iOS syntax-highlighted editor (reads; writes deferred) | Editor renders markdown with full highlighting; no save |
| 6 | Coordinated writes + keyboard accessory bar | Edit on iPhone → changes propagate to Mac via iCloud |
| 7 | iOS preview + wiki-link navigation | Toggle preview; tap `[[wiki-links]]` to navigate |
| 8 | Index rebuild + `.icloud` placeholder coordination | Vault indexed on first attach; evicted notes download on demand |
| 9 | Quick switcher + global search UIs on iOS | `⌘K` / toolbar quick switcher; Cmd+Shift+F search; FTS5-backed |
| 10 | Backlinks + outline + tags surfaces on iOS | Parity with Mac's KM features on both form factors |
| 11 | Conflict detection + sibling-file + banner + diff view | Offline edits from two devices produce a visible conflict, never a silent overwrite |
| 12 | iPad 3-column layout + multi-document tab bar port | iPad feels like the Mac app with real tabs |
| 13 | Release: iPhone polish, find overlay, Settings "Sync", CI matrix, App Store submission | Shipped to App Store; Universal Purchase live |

---

## Phase 1: `ClearlyCore` package extraction (Mac-only)

### Objective
Move platform-agnostic code into a local Swift Package. Mac behavior is bit-for-bit unchanged.

### Rationale
Every later phase leans on this. Doing it in isolation keeps the diff surface small enough to review and regression-test before an iOS target is even in the picture.

### Tasks
- [ ] Create `Packages/ClearlyCore/Package.swift` (macOS 14 / iOS 17 platforms, only macOS target consumed yet)
- [ ] Move all of `Shared/*.swift` into `Packages/ClearlyCore/Sources/ClearlyCore/`
- [ ] Move platform-agnostic files from `Clearly/`: `VaultIndex.swift`, `FileParser.swift`, `FileNode.swift`, `IgnoreRules.swift`, `DiagnosticLog.swift`, `BookmarkedLocation.swift`, `OpenDocument.swift`, `OutlineState.swift`, `FindState.swift`, `JumpToLineState.swift`, `BacklinksState.swift`, `PositionSync.swift`
- [ ] Add `ClearlyCore/Platform/Platform.swift` with typealiases: `PlatformFont`, `PlatformColor`, `PlatformImage`, `PlatformPasteboard`, `PlatformTextView`, all behind `#if os(macOS) / #if os(iOS)`
- [ ] Ensure no `import AppKit` inside `ClearlyCore` (fix up any surface drift)
- [ ] `project.yml`: register `Packages/ClearlyCore` as a local package; add as dependency of `Clearly`, `ClearlyQuickLook`, `ClearlyCLI`; remove moved files from old target source lists
- [ ] `xcodegen generate`; confirm Xcode project builds and all existing Mac tests pass

### Success Criteria
- `xcodebuild -scheme Clearly -configuration Debug build` succeeds
- Running the Mac app shows no functional change
- ClearlyCLI still builds; ClearlyQuickLook still previews markdown

### Files Likely Affected
- New: `Packages/ClearlyCore/Package.swift` + moved sources
- New: `Packages/ClearlyCore/Sources/ClearlyCore/Platform/Platform.swift`
- Modified: `project.yml`

---

## Phase 2: iOS target scaffolding + placeholder app

### Objective
`xcodebuild -scheme Clearly-iOS` builds. iOS simulator launches the app and shows a placeholder view. Universal Purchase bundle ID set up; no iCloud yet.

### Rationale
Get the iOS target into CI-buildable shape before writing any iOS UI that matters. A clean scaffold surfaces `project.yml` source-exclusion issues immediately.

### Tasks
- [ ] `project.yml`: add `Clearly-iOS` target (`platform: iOS`, `deploymentTarget: "17.0"`, same `PRODUCT_BUNDLE_IDENTIFIER: com.sabotage.clearly` for Universal Purchase)
- [ ] Configure target sources: `Clearly/iOS/**` + `ClearlyCore` package dependency; explicit exclusions of macOS-only files under `Clearly/` via per-target `sources` globs in `project.yml` (not `#if` sprinkled through every file)
- [ ] New `Clearly/iOS/ClearlyApp_iOS.swift` with a SwiftUI `App` and one `WindowGroup` showing a "Clearly — iOS scaffolding" view
- [ ] New `Clearly/iOS/Info-iOS.plist` with minimal keys (`UILaunchScreen` dict, supported orientations)
- [ ] New `Clearly/iOS/Clearly-iOS.entitlements` — empty shell for now
- [ ] Gate Mac `ClearlyApp.swift` and its `Window("Clearly", id: "main")` scene behind `#if os(macOS)`

### Success Criteria
- `xcodebuild -scheme Clearly-iOS -destination 'platform=iOS Simulator,name=iPhone 15' build` green
- App launches in simulator and shows placeholder
- Mac build still green

### Files Likely Affected
- Modified: `project.yml`, `Clearly/ClearlyApp.swift`
- New: `Clearly/iOS/ClearlyApp_iOS.swift`, `Info-iOS.plist`, `Clearly-iOS.entitlements`

---

## Phase 3: iCloud ubiquity plumbing + entitlements on all three builds

### Objective
iCloud container provisioned for direct, MAS, and iOS. Each build resolves the same ubiquity container URL. Files.app shows "Clearly". No app-level UI yet — this phase is about the platform contract.

### Rationale
Entitlement and provisioning drift across three bundle-ID variants is the most common Apple-side failure mode (research risk #5). Nail it once, verify with a script, then build UI on a known-good foundation.

### Tasks
- [ ] Add `com.apple.developer.icloud-container-identifiers = iCloud.com.sabotage.clearly` and `com.apple.developer.icloud-services = [CloudDocuments]` to:
  - `Clearly.entitlements` (direct / Sparkle)
  - `Clearly-AppStore.entitlements` (MAS)
  - `Clearly-iOS.entitlements` (iOS)
- [ ] Add `NSUbiquitousContainers` dict to Mac `Info.plist` (`NSUbiquitousContainerIsDocumentScopePublic = YES`, display name, icon name)
- [ ] Provision `iCloud.com.sabotage.clearly` in Apple Developer Portal for all three bundle-ID variants
- [ ] Add `ClearlyCore/Sync/CloudVault.swift`:
  - `ubiquityContainerURL()` wrapping `FileManager.default.url(forUbiquityContainerIdentifier:)` on a background queue
  - `isAvailablePublisher` watching `NSUbiquityIdentityDidChange`
  - First-call bootstrap creates `.../Documents/` if missing
- [ ] Add `ClearlyCore/Sync/CoordinatedFileIO.swift`: `read(at:)`, `write(_:to:)`, `move(from:to:)`, `delete(at:)` all via `NSFileCoordinator`; `presenter(for:) -> NSFilePresenter` factory
- [ ] Add `scripts/verify-entitlements.sh` that runs `codesign -d --entitlements :- <path>` on exported builds and asserts the iCloud key is present (research risk #5 — Xcode strips entitlements during archive)
- [ ] Update `scripts/release.sh` and `scripts/release-appstore.sh` to call the verifier before continuing

### Success Criteria
- Install any of the three build variants; Files.app on the Mac / iOS shows a "Clearly" folder under iCloud Drive
- `CloudVault.ubiquityContainerURL()` returns a non-nil URL on Mac and on iOS simulator signed into iCloud
- Verifier script passes on exported Mac builds

### Files Likely Affected
- Modified: `Clearly.entitlements`, `Clearly-AppStore.entitlements`, `Clearly-iOS.entitlements`, `Clearly/Info.plist`, `scripts/release.sh`, `scripts/release-appstore.sh`
- New: `Packages/ClearlyCore/Sources/ClearlyCore/Sync/CloudVault.swift`, `CoordinatedFileIO.swift`, `scripts/verify-entitlements.sh`

---

## Phase 4: Read-only iOS vault browsing

### Objective
On iPhone and iPad, launch the app → see sidebar of `.md` files in the iCloud Clearly folder → tap a file → read raw markdown (no highlighting yet). Vault picker lets the user choose: default container / pick iCloud folder / local folder.

### Rationale
First user-visible iOS milestone. Proves the ubiquity plumbing works end-to-end and gives a running surface to iterate the editor against in Phase 5.

### Tasks
- [ ] Add `ClearlyCore/Sync/VaultWatcher.swift` — `NSMetadataQuery` scoped to `NSMetadataQueryUbiquitousDocumentsScope` on iOS (with Mac fallback scope). Publishes added / removed / changed file events
- [ ] Add `ClearlyCore/Vault/VaultSession.swift` — iOS-side vault manager mirroring the surface of `WorkspaceManager` that the iOS UI needs (list files, open file, subscribe to changes). Mac continues to use `WorkspaceManager`
- [ ] Promote `Clearly/MarkdownDocument.swift` to a real `ReferenceFileDocument` with UTF-8 `read()` via `CoordinatedFileIO.read(at:)`. Write still unimplemented — `throw` for now
- [ ] `Clearly/iOS/ClearlyApp_iOS.swift`: replace placeholder with `DocumentGroup(newDocument: { MarkdownDocument() }) { … }` scene, plus a `WindowGroup` for the welcome flow on first launch
- [ ] `Clearly/iOS/WelcomeView_iOS.swift` — three options: default iCloud container / pick iCloud folder via `UIDocumentPickerViewController` / local folder via security-scoped bookmark
- [ ] `Clearly/iOS/SidebarView_iOS.swift` — SwiftUI `List` backed by `VaultSession`; tap a file → pushes a raw-text detail view
- [ ] `Clearly/iOS/RawTextDetailView_iOS.swift` — read-only `Text` in a `ScrollView` (placeholder for Phase 5 editor)
- [ ] Persist security-scoped bookmarks in `UserDefaults`; resolve on launch; prompt re-select if invalidated (research risk #8 — not full polish yet, just don't silently break)

### Success Criteria
- iPhone + iPad: launch → welcome flow → pick default → see sidebar of the Clearly folder
- Add a `.md` via Files.app → appears in sidebar within a second
- Tap a file → see its raw text
- Mac unchanged

### Files Likely Affected
- New: `Packages/ClearlyCore/Sources/ClearlyCore/Sync/VaultWatcher.swift`, `Packages/ClearlyCore/Sources/ClearlyCore/Vault/VaultSession.swift`, `Clearly/iOS/WelcomeView_iOS.swift`, `SidebarView_iOS.swift`, `RawTextDetailView_iOS.swift`
- Modified: `Clearly/MarkdownDocument.swift`, `Clearly/iOS/ClearlyApp_iOS.swift`

---

## Phase 5: iOS syntax-highlighted editor (read-only save path)

### Objective
Replace the raw-text detail with a real editor showing full markdown syntax highlighting. Save path intentionally deferred to Phase 6 so the editor can be verified visually without touching files yet.

### Rationale
The highlighter is 95% portable; isolating the visual validation from the write path makes the cursor-jump fix easy to verify before any real save logic is in the mix.

### Tasks
- [ ] Move `MarkdownSyntaxHighlighter.swift` and `Theme.swift` into `ClearlyCore`. Migrate `NSColor(name:)` dynamic-provider calls to `PlatformColor` with explicit light/dark branches
- [ ] Add `PlatformTextView = UITextView` branch to `Platform.swift`
- [ ] `Clearly/iOS/ClearlyUITextView.swift` — `UITextView` subclass. Kept for iOS v1: `NSTextStorage` delegate highlighting, autocorrect / smart-quote disable inside code fences, basic toolbar hooks. Explicitly dropped: line-number ruler, find panel (Phase 13), drag-to-reorder selection
- [ ] `Clearly/iOS/EditorView_iOS.swift` — `UIViewRepresentable<UITextView>`. Port the `pendingBindingUpdates` counter fix from `EditorView.swift` verbatim (research risk #2 — cursor-jump guard)
- [ ] Stress-test: 1 MB `.md` in the simulator; cursor position stable during rapid typing
- [ ] Replace `RawTextDetailView_iOS` with `EditorView_iOS` in `SidebarView_iOS` navigation
- [ ] Editor is read-only this phase — bind to a let-value; changes visible locally but discarded on navigation away. Show a small "Editing disabled — saving lands in next build" footer

### Success Criteria
- Open a `.md` on iPhone or iPad → editor renders with headings / bold / italic / code / wiki-link / tag / blockquote / list highlighting matching the Mac
- 1 MB test file: no cursor jumps, no frame drops during typing
- Navigate away + back → file re-reads from disk

### Files Likely Affected
- Moved into `ClearlyCore`: `MarkdownSyntaxHighlighter.swift`, `Theme.swift`
- New: `Clearly/iOS/ClearlyUITextView.swift`, `EditorView_iOS.swift`
- Modified: `Packages/ClearlyCore/Sources/ClearlyCore/Platform/Platform.swift`, `Clearly/iOS/SidebarView_iOS.swift`

---

## Phase 6: Coordinated writes + keyboard accessory bar

### Objective
iOS users edit a note, app saves via `NSFileCoordinator`, changes propagate to Mac via iCloud. Keyboard accessory bar surfaces the mobile-specific typing helpers.

### Rationale
This is the "app becomes useful" phase — mobile capture now works. Bundling writes with the keyboard accessory means users can actually author new notes on iPhone, not just edit existing ones.

### Tasks
- [ ] Implement `MarkdownDocument.write(content:to:contentType:)` via `CoordinatedFileIO.write(_:to:)`
- [ ] `NSFilePresenter` instance per open document; register on open, deregister on close. Handles remote-edit detection
- [ ] Autosave: on inactive / backgrounded scene phase, on document close, debounced during typing (~2 s idle)
- [ ] Dirty-state indicator in the nav bar (`•` next to the document title)
- [ ] `Clearly/iOS/KeyboardAccessoryBar.swift` — `UIToolbar`-backed bar above the software keyboard. Buttons: `[[`, `#`, heading cycle (`#`…`######`), code fence, checkbox toggle, dismiss-keyboard. Wire buttons to the text view's storage via helpers in `ClearlyCore`
- [ ] Conflict-banner UI stub — non-dismissable banner at the top of the editor when `NSFileVersion.unresolvedVersionsOfItem(at:)` returns non-empty. Banner shows "This note has an offline conflict" + a disabled "Resolve" button (real resolver lands in Phase 11)
- [ ] Do NOT call `NSFileCoordinator` around `evictUbiquitousItem(at:)` (research risk #3 — known deadlock)

### Success Criteria
- Edit a note on iPhone → lock phone → open on Mac → see changes within seconds
- Mac edit → switch to iPhone → refresh → see Mac's changes
- Kill the app mid-edit → relaunch → no half-written files
- VoiceOver can focus and activate every accessory-bar button

### Files Likely Affected
- Modified: `Clearly/MarkdownDocument.swift`, `Packages/ClearlyCore/Sources/ClearlyCore/Sync/CoordinatedFileIO.swift`
- New: `Clearly/iOS/KeyboardAccessoryBar.swift`, conflict-banner stub view

---

## Phase 7: iOS preview + wiki-link navigation

### Objective
Toolbar toggle between editor and rendered preview (same `ViewMode` enum as Mac). Tap a `[[wiki-link]]` → target note opens (creates an empty one if missing).

### Rationale
Preview is the second half of the document experience. Wiki-link tap navigation is the first cross-file feature on mobile; it exercises the `VaultSession.openOrCreate(name:)` path that later phases (backlinks, quick switcher) will also use.

### Tasks
- [ ] Audit / move remaining renderer files into `ClearlyCore`: `MarkdownRenderer.swift`, `PreviewCSS.swift`, `MathSupport.swift`, `MermaidSupport.swift`, `TableSupport.swift`, `SyntaxHighlightSupport.swift`, `EmojiShortcodes.swift`, `LocalImageSupport.swift` (some may already have moved with `Shared/` in Phase 1)
- [ ] CSS tweak in `PreviewCSS.swift`: add iOS-only branch with `-webkit-text-size-adjust: 100%`
- [ ] `Clearly/iOS/PreviewView_iOS.swift` — `UIViewRepresentable<WKWebView>`; no `DraggableWKWebView` (Mac-only). Register the same `WKScriptMessageHandler`s the Mac preview uses
- [ ] Wiki-link tap → `WKScriptMessageHandler` callback → `VaultSession.openOrCreate(name:)`. Empty-body creation uses coordinated write
- [ ] Toolbar preview toggle: iPhone = full-screen swap; iPad = swap within the detail column (no split yet — split comes in Phase 12)
- [ ] Respect image-attachment sandboxing: on iOS, only vault-relative paths render (Mac's home-relative temporary exception is iOS-forbidden)

### Success Criteria
- Preview renders for a note with headings / code / math / mermaid / tables / inline images under the vault
- Tap a `[[link]]` → target opens (or is created)
- Kill app + reopen → preview still works

### Files Likely Affected
- Moved into `ClearlyCore`: renderer files listed above
- New: `Clearly/iOS/PreviewView_iOS.swift`
- Modified: `Packages/ClearlyCore/Sources/ClearlyCore/PreviewCSS.swift`

---

## Phase 8: Index rebuild + `.icloud` placeholder coordination

### Objective
FTS5 SQLite index rebuilds per-device on first vault attach. `.icloud` placeholder files auto-download when entering a search result or when tapped. Index never lives in the ubiquity container.

### Rationale
Search on mobile requires an index, and an index on mobile requires solving placeholder download coordination. These two are inseparable and must ship together to make Phase 9's search UIs real rather than decorative.

### Tasks
- [ ] Confirm `VaultIndex.swift` / `FileParser.swift` are clean of Mac-only imports (should be after Phase 1)
- [ ] Pin index URL to `URL.cachesDirectory/indexes/<vault-path-hash>/vault.sqlite` on both platforms (never in the ubiquity container — SQLite WAL/SHM corruption risk)
- [ ] `VaultSession.beginIndexing()`:
  - Enumerate vault via `VaultWatcher`
  - For each `.icloud` placeholder, call `FileManager.default.startDownloadingUbiquitousItem(at:)` and wait on `NSMetadataUbiquitousItemDownloadingStatusCurrent`
  - Parse + insert on `DispatchQueue.global(qos: .utility)`
  - Publish progress (`@Published var indexProgress: Double?`)
- [ ] UI: inline progress indicator on the sidebar when indexing; tapping an unresolved placeholder in the sidebar shows a spinner + triggers download
- [ ] Incremental re-index driven by `VaultWatcher` change events
- [ ] Index invalidation on vault-location change (new user-picked folder → new index)

### Success Criteria
- Cold launch with 200-note vault rebuilds the index in <10 s on iPhone 15 simulator
- Manually evict a note via Files.app → tap it in sidebar → inline spinner → opens
- Force-delete the index DB file → next launch rebuilds it; no user-visible error

### Files Likely Affected
- Modified: `Packages/ClearlyCore/Sources/ClearlyCore/VaultIndex.swift`, `VaultSession.swift`
- Modified: `Clearly/iOS/SidebarView_iOS.swift` (progress UI)

---

## Phase 9: Quick switcher + global search UIs on iOS

### Objective
Parity with Mac's Cmd+P quick switcher and Cmd+Shift+F global search, adapted for touch and hardware keyboards.

### Rationale
Search is the highest-leverage feature for capture-and-retrieve mobile use. With the index in place from Phase 8, this is mostly UI.

### Tasks
- [ ] `Clearly/iOS/QuickSwitcherSheet.swift` — SwiftUI `.sheet` with `TextField` + `List`. Fuzzy matching reuses the algorithm from `QuickSwitcherPanel.swift`. Recent-files default state; "Create `<query>`.md" bottom option when no results
- [ ] Trigger: toolbar button (iPhone + iPad), plus `⌘K` via `.keyboardShortcut` on iPad hardware keyboards
- [ ] `Clearly/iOS/GlobalSearchView_iOS.swift`:
  - iPhone: scoped above the sidebar list with a search bar
  - iPad: inspector panel on the right side of the detail column
  - Queries `VaultIndex.searchFiles(query:)`; renders filename + snippet with highlighted match
  - Keyboard shortcut `⌘⇧F` on iPad
- [ ] Tap result → open in editor; quick switcher dismisses its sheet

### Success Criteria
- Type a query in quick switcher → matches in <200 ms on 200-note vault
- Global search finds body-text hits, not just filenames
- Hardware-keyboard shortcuts fire on iPad without focus games

### Files Likely Affected
- New: `Clearly/iOS/QuickSwitcherSheet.swift`, `GlobalSearchView_iOS.swift`

---

## Phase 10: Backlinks + outline + tags surfaces on iOS

### Objective
KM surfaces reachable from both iPhone and iPad. iPhone uses toolbar-button sheets; iPad uses inspector panels that can coexist with the editor.

### Rationale
Backlinks + outline + tags are the knowledge-management payoff. Putting them on mobile completes the "Clearly on your phone" story and exercises `VaultIndex` query paths beyond simple search.

### Tasks
- [ ] `Clearly/iOS/BacklinksSheet_iOS.swift` — iPhone: bottom sheet. iPad: right inspector. Reuses shared `BacklinksState`. Supports linked + unlinked mentions
- [ ] `Clearly/iOS/OutlineSheet_iOS.swift` — same pattern, reuses shared `OutlineState`. Tap a heading → scroll the editor to that range
- [ ] `Clearly/iOS/TagsBrowser_iOS.swift` — sidebar section listing `VaultIndex.allTags()`; tap a tag → filtered file list
- [ ] Long-press context menu on the sidebar for rename / delete / move (SwiftUI `.contextMenu`). Wire move to `CoordinatedFileIO.move(from:to:)`

### Success Criteria
- Parity with Mac's backlinks / outline / tag browser on both iPhone and iPad
- Editor scroll-to-heading from outline works
- Renaming a file updates backlinks on re-index

### Files Likely Affected
- New: `Clearly/iOS/BacklinksSheet_iOS.swift`, `OutlineSheet_iOS.swift`, `TagsBrowser_iOS.swift`
- Modified: `Clearly/iOS/SidebarView_iOS.swift`

---

## Phase 11: Conflict detection + sibling-file + banner + diff view

### Objective
Real-world offline edits on two devices produce a sibling conflict file and a visible banner. No silent overwrite.

### Rationale
Every Obsidian-on-iCloud horror story traces back to silent overwrites. Making conflicts first-class UI is the only defensible position for a file-first sync model.

### Tasks
- [ ] `ClearlyCore/Sync/ConflictResolver.swift`:
  - On file open and on each `VaultWatcher` change event for an open file, call `NSFileVersion.unresolvedVersionsOfItem(at:)`
  - If non-empty: write sibling `note (conflict YYYY-MM-DD device).md`; mark other versions resolved via `NSFileVersion.removeOtherVersionsOfItem(at:)`
  - Emit a `ConflictEvent` the editor can react to
- [ ] Real banner replacing the Phase 6 stub — action button opens the diff view
- [ ] `DiffView` implementations:
  - Mac + iPad: side-by-side, read-only, basic line diff
  - iPhone: tab-toggle "original" / "conflict", read-only
  - Resolution = user manually edits the chosen file. No auto-merge
- [ ] End-to-end test: two iOS simulators (or sim + device) both signed into same iCloud account, airplane-mode both, edit same note, go online → verify sibling file + banner on both devices
- [ ] Second test: Mac + iOS, same flow

### Success Criteria
- Offline-edit test produces a readable conflict sibling plus a banner on both devices
- No version is silently lost
- No deadlock on eviction (research risk #3)

### Files Likely Affected
- New: `Packages/ClearlyCore/Sources/ClearlyCore/Sync/ConflictResolver.swift`, `DiffView` (shared)
- Modified: editor banner views on Mac + iOS

---

## Phase 12: iPad 3-column layout + multi-document tab bar port

### Objective
iPad gets Mac-app-class ergonomics: 3-column split on iPad Pro, 2-column on smaller iPads / portrait, and a real multi-document tab bar.

### Rationale
Research default was single-document-per-scene on iPad. Overridden in favor of tabs because Clearly's Mac experience is defined by its tab model, and iPad users expect near-parity on hardware that's physically similar.

### Tasks
- [ ] Replace iPad detail column with `NavigationSplitView` three-column layout (sidebar | file list | editor) on iPad Pro; two-column (sidebar+list | editor) on 11"+portrait. iPhone continues with `NavigationStack`
- [ ] Port `TabBarView.swift` tab model to iPad:
  - Keep `DocumentGroup` as the scene root; manage an array of `OpenDocument` instances in a custom container view inside the detail column of the split view
  - Each tab binds to one `.md` file URL; close tab = release the document
  - Tab reordering via drag; overflow via horizontal scroll
  - Persist tab set (URLs + active index) in `UserDefaults` per vault
- [ ] Hardware-keyboard shortcuts on iPad: `⌘T` new tab, `⌘W` close tab, `⌘1…9` jump to tab; plus previously-wired `⌘K`, `⌘⇧F`, `⌘P`, `⌘B`, `⌘I`, `⌘K` (markdown link)
- [ ] iPhone: tabs explicitly NOT shown. `NavigationStack` push/pop stays the interaction model

### Success Criteria
- Open 5 notes into 5 tabs on iPad Pro simulator → scroll, reorder, close middle tab with `⌘W`, jump with `⌘3`
- Kill + relaunch → tabs restored
- iPhone unchanged: push/pop navigation only

### Files Likely Affected
- New: `Clearly/iOS/TabBarView_iOS.swift`, `iPadSplitView.swift`
- Modified: shared `OpenDocument` state model if extended

---

## Phase 13: Release — polish + CI matrix + App Store submission

### Objective
iOS build live on App Store; CI green for Mac + iOS; release scripts documented.

### Rationale
Ship.

### Tasks
- [ ] `Clearly/iOS/FindOverlay_iOS.swift` — custom in-document find (match count + prev/next, no replace). No `NSTextFinder` on UIKit. Toolbar button + `⌘F` on iPad
- [ ] iPhone polish: keyboard-accessory spacing, sidebar swipe actions for delete / rename, safe-area handling, dynamic type
- [ ] `SettingsView.swift` cross-platform "Sync" tab (Mac + iOS): vault location path, last sync time, iCloud account state, vault disk usage, "attachments local only" toggle (research risk #6)
- [ ] Bookmark-invalidation polish: if `UserDefaults`-stored security-scoped bookmark fails to resolve on launch, show a clear prompt to re-pick the folder instead of silent failure (research risk #8)
- [ ] `.github/workflows/test.yml`: add `build-app-macos` and `build-app-ios` jobs. Gate `build-app-ios` to paths `Clearly/**`, `Packages/ClearlyCore/**`, `project.yml`, `Shared/**`. Cache `DerivedData`. Full matrix on `main` + release tags only (research risk #7 — CI time explosion)
- [ ] New `scripts/release-ios.sh` — archive + `notarytool`/`altool` upload to App Store Connect; auto-bump `CFBundleVersion`; mirrors `release-appstore.sh` structure
- [ ] App Store Connect setup: iOS listing, iPhone + iPad screenshots, privacy labels ("no data collected"), Universal Purchase link to the existing MAS SKU, TestFlight build submitted
- [ ] `CLAUDE.md` gets an "iOS development" section covering the package layout, `Platform.swift` shims, iOS-only entitlements. `docs/ROADMAP.md` marks `mobile` shipped

### Success Criteria
- CI green on `main` for both platforms
- TestFlight build accepted by Review
- Universal Purchase verified: buying the MAS app unlocks iOS and vice versa
- iOS build in App Store

### Files Likely Affected
- New: `Clearly/iOS/FindOverlay_iOS.swift`, `scripts/release-ios.sh`
- Modified: `Clearly/SettingsView.swift`, `.github/workflows/test.yml`, `CLAUDE.md`, `docs/ROADMAP.md`

---

## Post-Implementation

- [ ] Documentation: iOS development section in `CLAUDE.md` covering the package layout, `Platform.swift` shims, iOS-only entitlements
- [ ] Test strategy: `ClearlyCore` unit tests run on both macOS and iOS simulator; manual on-device iCloud sync verification checklist in `docs/mobile/`
- [ ] Performance validation: 200-note cold-start index benchmark (Phase 8) and 1 MB editor smoothness check (Phase 5) kept as recurring CI checks

## Verification workflow (end-to-end)

1. `xcodegen generate` after every `project.yml` change
2. Mac build: `xcodebuild -scheme Clearly -configuration Debug build`
3. iOS build: `xcodebuild -scheme Clearly-iOS -destination 'platform=iOS Simulator,name=iPhone 15' build`
4. Manual iCloud test: two simulators or a sim + real device signed into the same iCloud account; edit on one, watch propagation on the other; toggle airplane mode to force conflicts for Phase 11
5. Entitlement check on every Mac release build: `scripts/verify-entitlements.sh` (added in Phase 3) against the exported `.app`

## Critical files to touch (across phases)

- `project.yml` — phases 1, 2, 13
- `Packages/ClearlyCore/**` — phases 1, 3, 5, 7, 8, 11
- `Clearly.entitlements`, `Clearly-AppStore.entitlements`, `Clearly-iOS.entitlements` — phase 3 (all three), phase 13 (audit)
- `Clearly/Info.plist` — phase 3
- `Clearly/iOS/**` — new; phases 2, 4, 5, 6, 7, 9, 10, 11, 12, 13
- `Clearly/MarkdownDocument.swift` — phases 4, 6
- `scripts/release.sh`, `scripts/release-appstore.sh`, `scripts/release-ios.sh`, `scripts/verify-entitlements.sh` — phases 3, 13
- `.github/workflows/test.yml` — phase 13

## Notes

- Sparkle stays wrapped in `#if canImport(Sparkle)` throughout. Direct Mac build participates in iCloud sync alongside MAS and iOS
- ClearlyMCP, ClearlyQuickLook, ScratchpadManager, CLIInstaller, PDFExporter, LineNumberRulerView remain macOS-only via per-target source exclusions
- `NSFileCoordinator` discipline is non-negotiable everywhere that touches vault files (research risk #3)
- Next step after approval of this plan: run `/build progress mobile` to set up progress tracking; then `/build phase 1 mobile` to start Phase 1
