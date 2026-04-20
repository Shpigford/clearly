# Mobile Expansion Research

## Overview

Bring Clearly to iPad and iPhone with near-feature-parity to the macOS app (editor, syntax highlighting, wiki-links, backlinks, search, tags) and introduce iCloud Drive as the cross-device sync substrate. Clearly today is macOS-only: a SwiftUI shell wrapping an AppKit core (`NSTextView` editor, `NSSplitViewController` sidebar, custom multi-tab `Window` scene). There is no `DocumentGroup`, no `FileDocument` conformance, no iCloud code.

Target shape: one SwiftUI multiplatform app target, shared logic in a local Swift package (`ClearlyCore`), per-platform UI shells under `#if os(macOS)` / `#if os(iOS)`. iOS 17 minimum. macOS stays at 14. ClearlyMCP, ClearlyQuickLook, the CLI installer, and the scratchpad stay macOS-only.

Explicitly out of scope: Rails backend, billing, built-in AI, web app, developer / cloud MCP API. iCloud is the only sync dependency.

## Problem Statement

A markdown knowledge base lives or dies by where you can use it. A macOS-only app forces users to reach for a laptop whenever they want to write a quick capture, skim a note on the couch, or search their vault at a coffee shop. Competitors either work everywhere (Obsidian, iA Writer, Bear, Apple Notes) or are mobile-first (Drafts, 1Writer). Clearly's Mac-only scope leaves value on the table: the vault exists, the files sync trivially via iCloud, but users can't open them on the devices they use most.

Mobile expansion is also the natural forcing function for two things the desktop app has avoided: a cross-device sync model, and a second UI layer. `NSTextView` does not exist on iOS. The editor, sidebar, window model, and file picker all need iOS-native equivalents.

## User Stories / Use Cases

1. **Mobile capture.** On iPhone in a meeting, a user opens Clearly, taps "New Note" from their daily journal folder, types two bullets, locks the phone. Two minutes later at their Mac, the note is there.

2. **Read on the go.** On iPad in bed, a user opens their vault, browses notes via the sidebar, taps a note linked from another note's wiki-link, reads the preview.

3. **Search without a laptop.** At a coffee shop with iPhone only, a user recalls an idea but not which note. `⌘K`-style quick switcher (or tap-to-search on iPhone), types three characters, sees matching note titles and contents, taps one.

4. **Cross-device continuity.** User is writing a draft on Mac, walks away, picks up iPad, continues typing in the same note where they left off — with cursor position, if possible.

5. **Offline tolerance.** User edits notes on an airplane with no connection. On landing, changes sync to iCloud. If the same note was edited on another device mid-flight, both versions are preserved — no silent overwrite.

6. **Files.app interop.** User opens their vault in the iPad Files.app, drags a file into a chat app, attaches it to an email. The vault is not a black box — it's plain `.md` files where they expect.

7. **Import an existing vault.** User has an Obsidian-style vault in iCloud Drive. Points Clearly at that folder. Notes, wiki-links, and images all resolve correctly.

## Technical Research

### Approach Options

#### Sync layer

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **iCloud Drive ubiquity container** (`.md` files + attachments synced as files via `NSFileCoordinator` + `NSMetadataQuery`) | File-first. Interop with Files.app, Finder, Shortcuts, other editors. Free for users (they already pay for iCloud). No server infrastructure. | Known horror stories (Obsidian forum: stalls, `(1)` duplicates, silent overwrites). Quota shared with user's other iCloud usage. Conflict resolution is manual via `NSFileVersion`. | **Recommended** |
| **CloudKit (`CKSyncEngine`)** | Structured sync, server-record-wins semantics are predictable. `CKSyncEngine` (2023+) simplifies incremental sync. Works well for Bear, Drafts, Apple Notes. | Files become opaque. No interop with Files.app or other editors. Migrates away from a plain-text file-first model. | Rejected — betrays the file-first design. |
| **Hybrid (files in iCloud Drive + metadata in CloudKit)** | Could sync per-device cursor positions, recently-opened, etc. | Adds a second moving part. No v1 feature needs it. | Defer — revisit only if per-device metadata becomes necessary. |
| **Proprietary sync (Rails + Postgres + client auth)** | Full control of conflict semantics, search, cross-platform reach beyond Apple. | Requires a backend we are explicitly not building. Billing. Auth. | Rejected — out of scope. |

#### Target / code architecture

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **Single SwiftUI multiplatform target** (one app target, `destinations: [mac, iPad, iPhone]`, shared code + `#if os()` switches) | Max code sharing. Apple's current guidance for new SwiftUI apps. Keeps native AppKit on Mac, native UIKit on iOS. One archive scheme per platform produces App Store builds. | Still requires per-platform UI siblings for non-trivial views (editor, sidebar). One `Info.plist` / entitlements story to manage. | **Recommended** |
| **Mac Catalyst** (iPad app compiled for Mac) | Maximum code share between Mac + iPad. | "iPad-ish" on Mac — loses native feel. Clearly's existing AppKit-heavy Mac experience (multi-tab window, custom chrome, NSTextView, Sparkle) would degrade. Apple 2025-2026 guidance: Catalyst is for iPad apps being ported to Mac, not new universal apps. | Rejected. |
| **"Designed for iPad" on Mac** | Ship iOS binary unchanged on Apple Silicon. | `userInterfaceIdiom` returns `.pad`; sidebar, menus, keyboard-first interaction feel wrong. No Mac-native feel. | Fallback only, not a shipping strategy. |
| **Separate native macOS + iOS targets sharing an SPM package** | Highest native feel per platform. | Overkill — Clearly is already SwiftUI at the outer layer. Extra ceremony for little marginal gain. | Rejected. |

#### Editor

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **Shared `MarkdownSyntaxHighlighter` + `PlatformTextView` typealias** (`NSTextView` on Mac, `UITextView` on iOS, both backed by `NSTextStorage`) | ~95% of highlighter code is already portable. `NSTextStorage`, `NSRegularExpression`, `NSAttributedString.Key` exist identically on both platforms. Keeps the cursor-jump fix (`pendingBindingUpdates`), regex highlighter, and block-delimiter logic. | A handful of `NSFont` / `NSColor` / `NSFontManager` shims needed. `NSTextFinder` has no UIKit equivalent — custom find overlay required. | **Recommended** |
| **Runestone** (third-party iOS code editor, tree-sitter based) | Built for iOS, MIT. | Catalyst "mostly works but not tested." Would require rewriting the highlighter as tree-sitter grammars. Abandons Mac parity. | Rejected. |
| **STTextView** (cross-platform text view) | Modern. | GPL-3.0 — closed-source apps need a commercial license. The author's own 2025 blog post calls TextKit 2 "frustrating for real-world apps." | Rejected. |
| **TextKit 2 migration** | Apple's modern text system, unified across UIKit + AppKit. | Four years in, still has documented scrolling and viewport height bugs on large documents. Current code touches `layoutManager`, forcing TK1 compatibility. | Defer — revisit when Apple ships fixes. Stay on TextKit 1 on both platforms. |

### Recommended Approach

1. **Sync:** iCloud Drive ubiquity container (`iCloud.com.sabotage.clearly`) exposed in Files.app via `NSUbiquitousContainers` with `NSUbiquitousContainerIsDocumentScopePublic = YES`. Users can also point at any iCloud Drive folder outside the container as an advanced option, via security-scoped bookmarks (Obsidian-compat import path).

2. **Index:** FTS5 SQLite database is rebuilt per device on first vault attach. Never synced — Apple's guidance and SQLite's own corruption guide warn that WAL/SHM separation from the main DB file under iCloud Drive causes corruption. iA Writer uses the same rebuild-per-device model.

3. **Conflicts:** Detected via `NSFileVersion.unresolvedVersionsOfItem(at:)`. Conflicting version is written as sibling `note (conflict 2026-04-20 josh-iphone).md`, marked resolved via `NSFileVersion.removeOtherVersionsOfItem(at:)`. Non-modal banner in the editor links to a diff view. No auto-merge — line-based merge on markdown fails destructively often enough that Obsidian's forum is still cataloging the damage.

4. **File I/O:** All reads and writes through `NSFileCoordinator`, with an `NSFilePresenter` per open document. Non-negotiable for ubiquity containers.

5. **Target architecture:** One SwiftUI multiplatform app target. Promote `Shared/` to a local Swift Package `ClearlyCore`. Per-platform UI behind `#if os(macOS)` / `#if os(iOS)` guards. macOS keeps its `Window` scene + custom tab model; iOS uses `DocumentGroup` + `FileDocument`.

6. **Editor:** `typealias PlatformTextView = NSTextView` on Mac / `UITextView` on iOS. Share `MarkdownSyntaxHighlighter.swift` verbatim with `PlatformFont` / `PlatformColor` shims in `Theme.swift`. Stay on TextKit 1 on both platforms.

7. **Attachments:** Mac keeps its home-relative-path entitlement exception (render images from anywhere on disk). iOS restricts image resolution to vault-relative paths — App Store hard-rejects temporary exceptions on mobile.

8. **Distribution:** Sparkle stays macOS-only behind `#if canImport(Sparkle)`. iOS ships App Store only. Universal purchase across macOS + iOS App Store via the same bundle ID.

9. **ClearlyMCP:** Stays macOS-only. Not ported to mobile.

### Required Technologies

- **Foundation / FileManager**: `url(forUbiquityContainerIdentifier:)`, `startDownloadingUbiquitousItem(at:)`, `NSUbiquityIdentityDidChange`.
- **`NSFileCoordinator` + `NSFilePresenter`**: All vault I/O, including reads, to avoid racing with cloud delivery.
- **`NSMetadataQuery`** scoped to `NSMetadataQueryUbiquitousDocumentsScope`: file discovery + change monitoring. Powers a new `VaultWatcher` that invalidates `VaultIndex` entries.
- **`NSFileVersion`**: conflict detection and resolution.
- **`UIDocumentPickerViewController`** (iOS only): lets users pick an iCloud Drive folder outside the default container.
- **Security-scoped bookmarks**: `.withSecurityScope` on Mac, `.minimalBookmark` on iOS. Persist user-picked iCloud folder across app launches.
- **`DocumentGroup` + `ReferenceFileDocument`** (iOS only): scene plumbing for document-based iOS app. macOS keeps its existing `Window` scene.
- **`UITextView` + `NSTextStorage` (TextKit 1)**: editor on iOS. Scribble for Apple Pencil is automatic.
- **`UIKeyCommand`** and SwiftUI `.keyboardShortcut`: hardware keyboard shortcuts on iPad.
- **`WKWebView`** (cross-platform, already used): preview. iOS needs `text-size-adjust: 100%` forced in CSS.
- **GRDB + SQLite FTS5** (already in use): unchanged, cross-platform. Database URL pinned to `URL.cachesDirectory` on both platforms — never the ubiquity container.
- **XcodeGen**: `project.yml` extended with a new iOS target and a local SPM package declaration.

### Data Requirements

| Data | Location | Synced? | Notes |
|---|---|---|---|
| `.md` files | iCloud Drive ubiquity container `iCloud.com.sabotage.clearly/Documents/` (default) or user-picked iCloud folder via security-scoped bookmark (advanced) | **Yes** via iCloud Drive | Source of truth |
| Attachments (images, etc.) referenced by relative path from a `.md` | Inside the vault folder | **Yes** | Relative-path references resolve identically across devices |
| FTS5 SQLite index (`vault.sqlite` + WAL files) | App's caches directory (`URL.cachesDirectory/indexes/`) | **Never** | Rebuilt per-device from synced `.md` files |
| User preferences (theme, font size, etc.) | `UserDefaults` | No | Per-device by design — users want different settings on phone vs desktop |
| Security-scoped bookmark for user-picked iCloud folder | `UserDefaults` | No | Bookmark must be re-created per device via `UIDocumentPickerViewController` |
| Recent files, pinned files, open tabs | `UserDefaults` (today) | No | Per-device state; no sync value |
| Last edited timestamp per note | Filesystem metadata | Yes (iCloud handles it) | Used for conflict detection via `NSFileVersion` |
| Cursor position per note | Not currently persisted | Future | Per-device, ephemeral; if we ever sync, CloudKit private DB is the path |
| `NSMetadataQuery` state | In-memory, per-session | N/A | Stateless — watches live |

No CloudKit records in v1. No new schema beyond what already exists for the FTS5 index. The one format-compatibility concern: the vault layout must remain compatible across devices, so folder paths, wiki-link targets, and attachment references all use POSIX-style relative paths (which they already do).

## UI/UX Considerations

### iPad

- **Primary layout:** `NavigationSplitView` three-column on iPad Pro (sidebar | file list | editor); two-column on 11" or portrait iPad (sidebar+list combined | editor).
- **Preview toggle:** toolbar item that swaps the detail column between editor and `WKWebView` preview. Same `ViewMode` enum as Mac, fewer states to rebuild.
- **Tabs:** iPad can support multi-document tabs via a custom toolbar bar similar to Mac's, but cleanly within a single `DocumentGroup` scene. Defer to phase work — v1 could be single-document-per-window.
- **Keyboard shortcuts:** `UIKeyCommand` + `.keyboardShortcut` for `⌘K` (quick switcher), `⌘F` (find), `⌘P` (preview toggle), `⌘B/⌘I/⌘K` (bold/italic/link) when a hardware keyboard is attached.
- **Apple Pencil:** Scribble works for free on `UITextView`. Don't over-invest.
- **Context menus:** long-press on files in the sidebar for rename/delete/move. SwiftUI `.contextMenu` modifier replaces macOS `NSMenu`.

### iPhone

- **Primary layout:** `NavigationStack` with sidebar as root view; tapping a note pushes the editor.
- **Quick switcher:** a full-screen sheet (no `⌘K` modifier; triggered via toolbar button).
- **Keyboard accessory view:** inline above the software keyboard with buttons for `[[`, `#`, heading cycling, code fence, checkbox. Without this, iPhone is unusable as an editor.
- **Preview:** toolbar toggle, full-screen overlay (no editor side-by-side on a phone).
- **Backlinks / outline:** sheets accessed via toolbar buttons, not persistent panels.
- **Find-in-document:** custom overlay (no `NSTextFinder` equivalent on iOS). Minimal — match count + prev/next, no replace in v1.

### Shared across iPad + iPhone

- **Conflict banner:** appears at the top of the editor when a note has an unresolved conflict. "This note had an offline conflict" + link to diff view.
- **Download progress for `.icloud` placeholders:** inline progress indicator when tapping a file that hasn't downloaded yet. User sees it's working; no confusing "file not found" error.
- **Vault selection on first launch:** default is "Use Clearly's iCloud Drive folder." Secondary is "Choose a different folder…" (launches `UIDocumentPickerViewController`, scoped to iCloud Drive). Tertiary is "Use a local folder" for users not signed into iCloud.
- **Settings:** a new "Sync" tab shared across Mac + iOS in `SettingsView.swift`. Shows current vault location, last sync time, iCloud account state, disk usage.
- **Dark mode:** automatic via `Theme.swift` once `PlatformColor` shim is in place. No new dark-mode work needed beyond `NSColor` → `UIColor` dynamic-provider migration.

### macOS-only surfaces (explicitly not on mobile)

- Scratchpad menu bar extra, CLI installer, PDF export via hidden `NSWindow`, Sparkle update UI, MCP server configuration. These stay behind `#if os(macOS)` gates.

## Integration Points

### Code moves into `ClearlyCore` (new local Swift Package)

All of `Shared/` (`MarkdownRenderer.swift`, `PreviewCSS.swift`, `MermaidSupport.swift`, `MathSupport.swift`, `TableSupport.swift`, `FrontmatterSupport.swift`, `SyntaxHighlightSupport.swift`, `EmojiShortcodes.swift`, `LocalImageSupport.swift`) plus platform-agnostic files from `Clearly/`: `VaultIndex.swift`, `FileParser.swift`, `FileNode.swift`, `IgnoreRules.swift`, `DiagnosticLog.swift`, `BookmarkedLocation.swift`, `OpenDocument.swift`, `OutlineState.swift`, `FindState.swift`, `JumpToLineState.swift`, `BacklinksState.swift`, `PositionSync.swift`.

### Code that gets a UIKit sibling alongside the AppKit original

- `EditorView.swift` → + `EditorView_iOS.swift` (`UIViewRepresentable<UITextView>`)
- `ClearlyTextView.swift` (`NSTextView` subclass) → + `ClearlyUITextView.swift` (`UITextView` subclass)
- `MarkdownSyntaxHighlighter.swift` → shared in `ClearlyCore` with `PlatformFont`/`PlatformColor` shim
- `PreviewView.swift` (`WKWebView` + `DraggableWKWebView` for window drag) → + `PreviewView_iOS.swift` (no drag handling)
- `SidebarViewController.swift` (AppKit `NSOutlineView`) → + `SidebarView_iOS.swift` (SwiftUI `List`)
- `FileExplorerView.swift` (50+ `NSMenu` items) → + `FileExplorerView_iOS.swift` (SwiftUI `.contextMenu`)
- `QuickSwitcherPanel.swift` (floating `NSWindow`) → + `QuickSwitcherSheet.swift` (SwiftUI `.sheet`)
- `WikiLinkCompletionWindow.swift` (floating `NSWindow`) → + `WikiLinkCompletion_iOS.swift` (popover/menu)
- `CopyActions.swift` (`NSMenu` builder) → `#if os(iOS)` branch returning `UIMenu`
- `Theme.swift` (`NSColor` / `NSFont`) → `PlatformColor` / `PlatformFont` typealiases
- `WorkspaceManager.swift` (Mac) → complemented by `VaultSession.swift` (iOS) in `ClearlyCore`

### Code that stays macOS-only (excluded from iOS target)

- `ScratchpadManager.swift`, `PDFExporter.swift`, `CLIInstaller.swift`, `LineNumberRulerView.swift` (AppKit `NSRulerView` subclass)
- `ClearlyMCP` target (entire CLI + MCP server)
- `ClearlyQuickLook` target (macOS QuickLook extension)
- Sparkle, KeyboardShortcuts package dependencies

### New files in `ClearlyCore`

- `Sync/CloudVault.swift` — resolves ubiquity container URL, exposes availability publisher.
- `Sync/CoordinatedFileIO.swift` — `NSFileCoordinator`-wrapped read/write/move/delete.
- `Sync/VaultWatcher.swift` — `NSMetadataQuery` for vault change detection.
- `Sync/ConflictResolver.swift` — `NSFileVersion` handling, sibling-file writing.
- `Platform/Platform.swift` — `PlatformFont`, `PlatformColor`, `PlatformImage`, `PlatformPasteboard`, `PlatformTextView` typealiases.
- `Documents/AnyDocumentBinding.swift` — adapter so shared views accept either a macOS `OpenDocument` or iOS `MarkdownDocument` binding.
- `Vault/VaultSession.swift` — iOS-side equivalent of `WorkspaceManager.shared`.

### Build system changes

- `project.yml`: register `Packages/ClearlyCore` as a local package, add a `Clearly-iOS` target with `platform: iOS`, `deploymentTarget: "17.0"`, exclusions for macOS-only sources.
- New entitlements file `Clearly-iOS.entitlements` with iCloud container + CloudDocuments service.
- New `Info-iOS.plist`.
- Add `com.apple.developer.icloud-container-identifiers = iCloud.com.sabotage.clearly` to both `Clearly.entitlements` and `Clearly-AppStore.entitlements`.
- Add `NSUbiquitousContainers` dict to the Mac `Info.plist`.
- `.github/workflows/test.yml`: add `build-app-macos` and `build-app-ios` jobs (today only the CLI is built in CI).
- New `scripts/release-ios.sh` for App Store Connect submissions.

### Integration with existing features

- **`MarkdownDocument.swift`** today is a 9-line `UTType` extension. Gets promoted to a real `ReferenceFileDocument` with UTF-8 read/write via `NSFileCoordinator`. Used by the iOS `DocumentGroup` scene. Mac path continues through `WorkspaceManager` + custom `Window` scene.
- **`ClearlyApp.swift`** keeps `Window("Clearly", id: "main")` under `#if os(macOS)`, adds `#if os(iOS) DocumentGroup(...)` as a second scene. No shared scene structure.
- **`SettingsView.swift`** gains a "Sync" tab. On Mac this tab is visible when iCloud is configured; on iOS it's always visible.
- **`WelcomeView.swift`** gets platform-conditional location options: Mac shows local folder + iCloud; iOS shows iCloud default + iCloud picker + local fallback.

## Risks and Challenges

1. **`.icloud` placeholder race.** iOS does not auto-download vault files. Tapping a placeholder throws `NSFileReadNoSuchFileError`. Mitigation: always call `FileManager.default.startDownloadingUbiquitousItem(at:)` and observe `NSMetadataUbiquitousItemDownloadingStatusKey == NSMetadataUbiquitousItemDownloadingStatusCurrent` before opening. Show inline progress. Indexing on fresh devices has to trigger downloads explicitly or search silently misses evicted notes.

2. **`pendingBindingUpdates` cursor-jump regression on UIKit.** The fix in `EditorView.swift` depends on `NSTextStorageDelegate` timing. `UITextView` delegate callbacks (`textViewDidChange`) fire on a different schedule. Mitigation: keep highlighter `@MainActor`, add explicit debounce, stress-test 1 MB `.md` before Phase 3 ships.

3. **Obsidian-class iCloud Drive horror stories.** Sync stalls, `(1)` duplicates, silent overwrites are well-documented on Obsidian's forum through 2025. Mitigation: strict `NSFileCoordinator` discipline everywhere; treat conflict detection as a first-class UI state, not a hidden edge case; never use `NSFileCoordinator` around `evictUbiquitousItem(at:)` (known deadlock).

4. **DocumentGroup doesn't match Clearly's multi-tab window model.** Mac's custom tab bar allows N documents in one window. `DocumentGroup` is one-document-per-scene. Mitigation: macOS keeps its existing `Window` scene; only iOS adopts `DocumentGroup`. Scenes diverge cleanly behind `#if os()`.

5. **Entitlement drift across direct / MAS / iOS.** Adding iCloud to all three entitlements could fail MAS validation if provisioning profiles aren't aligned. Mitigation: provision `iCloud.com.sabotage.clearly` for all three bundle-ID variants; dry-run `release-appstore.sh` before Phase 1 ships; verify entitlements on the *exported* app with `codesign -d --entitlements :-`.

6. **Free iCloud tier is 5 GB.** Attachment-heavy vaults fill it fast, and the user blames the app. Mitigation: Settings exposes vault size; honest "attachments local only" opt-out (breaks cross-device images but is transparent).

7. **CI build time explosion.** Adding macOS app build + iOS simulator build to a CLI-only CI on `macos-latest` pushes runs from ~3 min to ~25 min. Mitigation: gate iOS build to PRs touching `Clearly/iOS/**` / `Packages/ClearlyCore/**` / `project.yml`. Cache `DerivedData`. Full matrix only on main + release tags.

8. **Bookmark invalidation on iOS.** Security-scoped bookmarks for user-picked iCloud folders don't survive app reinstalls on iOS. Mitigation: on launch, if the bookmark fails to resolve, prompt the user to re-select the folder; don't silently break.

9. **Find-on-iOS is bespoke.** `NSTextFinder` has no UIKit equivalent — custom overlay required. ~1-2 days of work. Scope: match count + prev/next, no replace in v1.

10. **Universal Purchase vs separate SKUs.** Same bundle ID = single App Store listing + Universal Purchase. Different bundle IDs = independent release cadence + separate reviews. Decision affects iCloud provisioning and App Store Connect setup. Recommend Universal Purchase (same bundle ID across Mac App Store + iOS App Store) but Mac direct-distribution keeps its own identity.

## Open Questions

1. **Bundle ID strategy.** Universal Purchase with `com.sabotage.clearly` shared across all SKUs, or `com.sabotage.clearly.ios` split? Shared is user-friendlier; split gives independent release cadence.
2. **First-launch behavior on iOS without iCloud signed in.** Hard gate ("please sign in") or allow purely local vault via `UIDocumentPickerViewController`? Research recommends allow-local, but it changes onboarding flow.
3. **KeyboardShortcuts library.** `sindresorhus/KeyboardShortcuts` is macOS-only. Do we want a cross-platform abstraction, or is SwiftUI `.keyboardShortcut` + `UIKeyCommand` enough for iPad hardware keyboards?
4. **iOS QuickLook extension.** iOS has `QLPreviewExtension`. Worth a later phase for Files.app markdown previews, or out of scope entirely?
5. **iPhone outline / backlinks surface.** Sheet, tab, or iPad-only? Affects IA on small screens.
6. **Multi-document tabs on iPad.** Mac has a custom tab bar; iPad could replicate it or stay single-document-per-scene in v1. Lean v1 = single-document.
7. **Cursor position sync across devices.** Nice-to-have; requires CloudKit or sidecar file. Out of scope for v1 — revisit once files sync reliably.

## References

### Apple primary sources
- [Configuring a multiplatform app target](https://developer.apple.com/documentation/xcode/configuring-a-multiplatform-app-target)
- [WWDC22: Use Xcode to develop a multiplatform app](https://developer.apple.com/videos/play/wwdc2022/110371/)
- [WWDC23: Build better document-based apps](https://developer.apple.com/videos/play/wwdc2023/10056/)
- [DocumentGroup reference](https://developer.apple.com/documentation/swiftui/documentgroup)
- [Resolving Document Version Conflicts](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/DocumentBasedAppPGiOS/ResolveVersionConflicts/ResolveVersionConflicts.html)
- [TN2336: Handling iCloud version conflicts](https://developer.apple.com/library/archive/technotes/tn2336/_index.html)
- [iCloud File Management guide](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/iCloud/iCloud.html)
- [Apple Developer Forums: SQLite WAL/SHM in iCloud](https://developer.apple.com/forums/thread/14200)
- [Enabling Security-Scoped Bookmark Access](https://developer.apple.com/documentation/professional-video-applications/enabling-security-scoped-bookmark-and-url-access)
- [NSTextStorage (UIKit)](https://developer.apple.com/documentation/uikit/nstextstorage)
- [Managing Info.plist values](https://developer.apple.com/documentation/BundleResources/managing-your-app-s-information-property-list)
- [WWDC21: Meet TextKit 2](https://developer.apple.com/videos/play/wwdc2021/10061/)
- [WWDC22: What's new in TextKit and text views](https://developer.apple.com/videos/play/wwdc2022/10090/)
- [Apple Forums: The State of Mac Catalyst in 2026](https://developer.apple.com/forums/thread/811728)
- [Designing for iPadOS HIG](https://developer.apple.com/design/human-interface-guidelines/designing-for-ipados)

### Competitor behavior
- [iA Writer iCloud help](https://ia.net/writer/support/help/icloud) — file-first, local index, iCloud-only sync
- [Bear FAQ: Syncing & Privacy](https://bear.app/faq/syncing-privacy/) — CloudKit rationale (not file-first)
- [Awkward Hare: Choosing CloudKit (Drafts)](http://awkwardhare.com/post/96104947635/choosing-cloudkit)
- [Obsidian forum: iCloud sync issues](https://forum.obsidian.md/t/icloud-sync-issues/28320)
- [Obsidian forum: iCloud sync stuck](https://forum.obsidian.md/t/icloud-sync-stuck/64088)
- [Obsidian forum: Understanding iCloud Sync issues](https://forum.obsidian.md/t/understanding-icloud-sync-issues/78186)

### Community / implementation
- [Tietze: SwiftUI DocumentGroups Are Terribly Limited (2025)](https://christiantietze.de/posts/2025/07/swiftui-documentgroups-limited/)
- [Timac: State of AppKit, Catalyst, SwiftUI (2023)](https://blog.timac.org/2023/1128-state-of-appkit-catalyst-swift-swiftui-mac)
- [Krzyżanowski: TextKit 2 — the promised land (2025)](https://blog.krzyzanowskim.com/2025/08/14/textkit-2-the-promised-land/)
- [Indie Stack: opting out of TextKit 2](https://indiestack.com/2022/11/opting-out-of-textkit2-in-nstextview/)
- [SwiftLee: Sparkle distribution in and out of MAS](https://www.avanderlee.com/xcode/sparkle-distribution-apps-in-and-out-of-the-mac-app-store/)
- [objc.io: Mastering the iCloud Document Store](https://www.objc.io/issues/10-syncing-data/icloud-document-store/)
- [fatbobman: Advanced iCloud Documents](https://fatbobman.com/en/posts/advanced-icloud-documents/)
- [sqlite.org: How To Corrupt An SQLite Database](https://sqlite.org/howtocorrupt.html)
- [sqlite.org: Write-Ahead Logging](https://www.sqlite.org/wal.html)

### Rejected third-party editor engines (for completeness)
- [Runestone](https://github.com/simonbs/Runestone) — MIT, tree-sitter, iOS-first; Catalyst not tested.
- [STTextView](https://github.com/krzyzanowskim/STTextView) — GPL-3.0 (commercial license required for closed-source).
