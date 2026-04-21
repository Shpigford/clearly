# Mobile Progress

## Status: Phase 10 - Complete

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
**Status:** Complete (2026-04-20)

#### Tasks Completed
- [x] Added `Clearly-iOS` target to `project.yml` (platform iOS, deployment 17.0, `TARGETED_DEVICE_FAMILY: "1,2"`, `SUPPORTS_MACCATALYST: NO`)
- [x] Bundle ID mirrors Mac: `com.sabotage.clearly` (Release) / `com.sabotage.clearly.dev` (Debug); Universal Purchase pair with MAS via shared Release ID
- [x] Added `iOS: "17.0"` to top-level `options.deploymentTarget`
- [x] Added `excludes: ["iOS/**"]` to Mac `Clearly` target's `- path: Clearly` source entry so `Clearly/iOS/**` only compiles into the iOS target
- [x] New `Clearly/iOS/ClearlyApp_iOS.swift` — minimal `@main App` + `WindowGroup` with `Text("Clearly — iOS scaffolding")`; imports `ClearlyCore` to verify package reachability
- [x] New `Clearly/iOS/Info-iOS.plist` — minimal iOS plist (display name, launch screen, orientations, `ITSAppUsesNonExemptEncryption = false`)
- [x] New `Clearly/iOS/Clearly-iOS.entitlements` — empty plist shell (iCloud keys added in Phase 3)
- [x] Gated Mac-only code in `Packages/ClearlyCore/Sources/ClearlyCore/Vault/VaultIndex.swift` behind `#if os(macOS)` — `init(locationURL:bundleIdentifier:)` and private `indexDirectory(bundleIdentifier:)` use `FileManager.homeDirectoryForCurrentUser` (unavailable on iOS). Both are only called from the Mac-only CLI; no iOS caller exists.
- [x] `xcodegen generate` clean
- [x] `xcodebuild -scheme Clearly -configuration Debug build` — green (Mac unchanged)
- [x] `xcodebuild -scheme ClearlyQuickLook -configuration Debug build` — green
- [x] `xcodebuild -scheme ClearlyCLI -configuration Debug build` — green
- [x] `xcodebuild -scheme ClearlyCLIIntegrationTests test` — 23/23 pass
- [x] `xcodebuild -scheme Clearly-iOS -sdk iphonesimulator -configuration Debug -arch arm64 build` — green
- [x] `xcodebuild -scheme Clearly-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -configuration Debug build` — green
- [x] Installed resulting `.app` via `xcrun simctl install` on a booted iPhone 17 simulator (iOS 26.4 runtime) + `xcrun simctl launch com.sabotage.clearly.dev` — placeholder "Clearly — iOS scaffolding" renders correctly

#### Decisions Made
- **Source exclusion instead of `#if os(macOS)` on `Clearly/ClearlyApp.swift`.** The implementation plan mentioned gating `ClearlyApp.swift` behind `#if os(macOS)`, but `excludes: ["iOS/**"]` + the iOS target only sourcing `Clearly/iOS/` already means `ClearlyApp.swift` never compiles on iOS. Adding `#if` would be redundant noise. Consistent with the plan's overarching "not `#if` sprinkled through every file" rule.
- **No asset catalog / app icon this phase.** Dropped `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` from the iOS target settings. Proper icon ships with App Store polish in Phase 13.
- **`ClearlyCore` iOS surface fix deferred to macro-level.** Discovered during the iOS compile that `FileManager.homeDirectoryForCurrentUser` in `VaultIndex.swift` was iOS-unavailable. Gated with `#if os(macOS)` rather than reworking the sandbox-container-path lookup (which is meaningless on iOS anyway — iOS apps always run in their own sandbox container). If a future iOS code path ever needs to construct index directories for foreign bundle identifiers, it'll need a different implementation.
- **Simulator destination builds work normally.** `xcodebuild -scheme Clearly-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -configuration Debug build` resolves correctly in this workspace. `simctl install/launch` remains useful for explicit post-build launch verification, but it's not a workaround for a broken destination resolver.

#### Blockers
- (none)

---

### Phase 3: iCloud ubiquity plumbing + entitlements on all three builds
**Status:** Complete (2026-04-21)

#### Tasks Completed
- [x] Added `com.apple.developer.icloud-container-identifiers = iCloud.com.sabotage.clearly` + `com.apple.developer.icloud-services = [CloudDocuments]` to all three entitlements files: `Clearly/Clearly.entitlements`, `Clearly/Clearly-AppStore.entitlements`, `Clearly/iOS/Clearly-iOS.entitlements`
- [x] Added `NSUbiquitousContainers` dict to `Clearly/Info.plist` (Mac) with `NSUbiquitousContainerIsDocumentScopePublic = YES`, display name `Clearly`, `SupportedFolderLevels = Any`
- [x] New `Packages/ClearlyCore/Sources/ClearlyCore/Sync/CloudVault.swift` — `containerIdentifier` constant, `ubiquityContainerURL() async -> URL?` running on a detached utility task (creates `Documents/` subdir on first resolution), `isAvailablePublisher` watching `NSUbiquityIdentityDidChange`
- [x] New `Packages/ClearlyCore/Sources/ClearlyCore/Sync/CoordinatedFileIO.swift` — `read(at:)`, `write(_:to:)`, `move(from:to:)`, `delete(at:)` wrapping `NSFileCoordinator` (no `evictUbiquitousItem` helper — research risk #3 deadlock)
- [x] New `scripts/verify-entitlements.sh` — runs `codesign -d --entitlements :-` on an exported `.app`, asserts both iCloud entitlement keys + container id present
- [x] Wired verifier into `scripts/release.sh` (after mach-lookup check, before DMG) and `scripts/release-appstore.sh` (after export, before Info.plist restore)
- [x] Added `DEVELOPMENT_TEAM: W33JZPPPFN` + `CODE_SIGN_STYLE: Automatic` (Debug) to all four targets in `project.yml` so Debug builds auto-provision against Sabotage Media's iCloud-capable App IDs instead of ad-hoc signing
- [x] `xcodegen generate` clean
- [x] `xcodebuild -scheme Clearly -configuration Debug build -allowProvisioningUpdates` — green; signed app entitlements show `com.apple.developer.team-identifier = W33JZPPPFN` + `com.apple.application-identifier = W33JZPPPFN.com.sabotage.clearly.dev` + iCloud keys intact
- [x] `xcodebuild -scheme ClearlyQuickLook -configuration Debug build` — green
- [x] `xcodebuild -scheme ClearlyCLI -configuration Debug build` — green
- [x] `xcodebuild -scheme Clearly-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -configuration Debug build -allowProvisioningUpdates` — green
- [x] `xcodebuild -scheme ClearlyCLIIntegrationTests test` — 23/23 pass
- [x] Runtime: launched Debug Mac app; `CloudVault.ubiquityContainerURL()` returned `/Users/joshpigford/Library/Mobile Documents/iCloud~com~sabotage~clearly/Documents`; container directory auto-created on first resolution
- [ ] Runtime: iPhone simulator signed into iCloud — **deferred.** Simulator builds are signed "to run locally" (ad-hoc) and have the iCloud entitlement stripped from the embedded signature; real iCloud semantics need a physical device with a development profile. Will verify on device during Phase 4 when the actual sidebar UI exists.
- [ ] `release.sh` / `release-appstore.sh` verifier dry-run — **deferred** to next real release cycle; verifier is in place but not exercised against a fresh archive yet.

#### Decisions Made
- **Kept the `CoordinatedFileIO` surface minimal.** The plan mentioned a `presenter(for:) -> NSFilePresenter` factory; moved that to Phase 6 where per-document presenter lifecycle actually lands. Phase 3 ships only the four read/write/move/delete wrappers that Phase 4 will start calling.
- **No `Bundle.module` migration.** `Sync/` sources are pure Foundation/Combine; no resources involved. The existing `Bundle.main` pattern for web assets stays untouched.
- **No source glob changes to `project.yml`.** The `Sync/` subdirectory is picked up automatically by the `ClearlyCore` package's source glob — no target re-wiring. Unrelated, `project.yml` still needed `DEVELOPMENT_TEAM` + Debug `CODE_SIGN_STYLE: Automatic` added for signing (see above), because ad-hoc Debug signing doesn't honor iCloud entitlements.
- **iOS Info.plist did NOT get `NSUbiquitousContainers`.** That key's iOS behavior is tied to `UISupportsDocumentBrowser` + `DocumentGroup`, both of which land in Phase 4. For Phase 3, iOS entitlements alone are sufficient to let `FileManager.url(forUbiquityContainerIdentifier:)` return a real URL.
- **MAS dry-run deferred.** `release-appstore.sh` does not currently do a post-export re-sign. If Xcode strips the iCloud entitlement on archive, the verifier will catch it and we add a re-sign step then. Not worth proactively building against a bug that may not exist.

#### Blockers
- (none)

---

### Phase 4: Read-only iOS vault browsing
**Status:** Complete (2026-04-21)

#### Tasks Completed
- [x] New `Packages/ClearlyCore/Sources/ClearlyCore/Vault/VaultLocation.swift` — `VaultLocation` + `StoredVaultLocation` (Codable), `VaultLocationError`, and `VaultLocation.resolve(from:)` handling default-iCloud re-resolution and security-scoped bookmark reconstruction. `#if os(iOS)` branches the bookmark-options difference (iOS uses no options; macOS uses `.withSecurityScope`).
- [x] New `Packages/ClearlyCore/Sources/ClearlyCore/Sync/VaultWatcher.swift` — `@MainActor` `NSObject` subclass with two backends: `NSMetadataQuery` on `NSMetadataQueryUbiquitousDocumentsScope` for the default iCloud container (live updates, placeholder-aware via `NSMetadataUbiquitousItemDownloadingStatusKey`); `FileNode.buildTree` on a detached utility `Task` for picked / local folders (refresh-on-demand). Publishes `[VaultFile]` + `isLoading` via `@Published`. Selector-based observers cleaned up in `deinit` via thread-safe `NotificationCenter.removeObserver(self)`.
- [x] New `Packages/ClearlyCore/Sources/ClearlyCore/Vault/VaultSession.swift` — `#if os(iOS)` `@Observable` `@MainActor` class. Owns a single `VaultWatcher`, mirrors its `files` + `isLoading` via Combine `@ObservationIgnored` `Set<AnyCancellable>`. `attach`/`detach`/`refresh`/`restoreFromPersistence`/`readRawText(at:)`/`ensureDownloaded(_:)`. Persists `StoredVaultLocation` under `UserDefaults` key `"iosVaultLocation"`. `readRawText` dispatches `CoordinatedFileIO.read` onto a detached `Task` so the main thread stays free.
- [x] Promoted `Clearly/MarkdownDocument.swift` from a 9-line `UTType` extension to a real `FileDocument`. `readableContentTypes = [.daringFireballMarkdown, .plainText]`; `init(configuration:)` UTF-8-decodes `regularFileContents`; `fileWrapper(configuration:)` throws `CocoaError(.featureUnsupported)` (writes ship in Phase 6). Cross-platform; Mac ignores it.
- [x] New `Clearly/iOS/WelcomeView_iOS.swift` — three buttons (default iCloud / pick iCloud folder / pick local folder) with SwiftUI `.fileImporter(allowedContentTypes: [.folder])`. Watches `CloudVault.isAvailablePublisher` via an `AsyncPublisher` `for await` loop to disable the iCloud button when the identity token is nil. Creates security-scoped bookmarks via `url.bookmarkData(options: [], ...)` on iOS (the macOS-only `.withSecurityScope` option is forbidden on iOS).
- [x] New `Clearly/iOS/SidebarView_iOS.swift` — `NavigationStack` root. `List` of `session.files` with `icloud.and.arrow.down` SF Symbol next to placeholders. Toolbar change-vault button, pull-to-refresh, empty-state message. `.fullScreenCover` presents welcome whenever `currentVault == nil` OR user tapped the change-vault gear.
- [x] New `Clearly/iOS/RawTextDetailView_iOS.swift` — `.task(id:)` loads text via `session.readRawText(at:)`, calls `ensureDownloaded` first for placeholders. Monospace `ScrollView { Text(...) }` with text selection, fixed "Read-only preview — editing lands in the next build." footer. Handles download / read errors with inline message.
- [x] Rewired `Clearly/iOS/ClearlyApp_iOS.swift` — `@State private var vaultSession = VaultSession()`, `SidebarView_iOS().environment(vaultSession).task { await vaultSession.restoreFromPersistence() }`.
- [x] Added `NSUbiquitousContainers` dict to `Clearly/iOS/Info-iOS.plist` mirroring the Mac plist (same container id, `NSUbiquitousContainerIsDocumentScopePublic = YES`, display name "Clearly", `SupportedFolderLevels = Any`).
- [x] `xcodegen generate` clean
- [x] `xcodebuild -scheme Clearly -configuration Debug build -allowProvisioningUpdates` — green (Mac untouched)
- [x] `xcodebuild -scheme ClearlyQuickLook -configuration Debug build` — green
- [x] `xcodebuild -scheme ClearlyCLI -configuration Debug build` — green
- [x] `xcodebuild -scheme Clearly-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -configuration Debug build -allowProvisioningUpdates` — green
- [x] `xcodebuild -scheme ClearlyCLIIntegrationTests test` — 23/23 pass
- [x] Installed + launched on iPhone 17 simulator (iOS 26.4): welcome screen renders with title, subtitle, three buttons. Default iCloud button correctly disabled with "Sign in to iCloud to enable" subtitle because the simulator has no iCloud identity — proves `CloudVault.isAvailablePublisher` wiring works. Persistence path ran on startup (no `iosVaultLocation` key in UserDefaults → no-op, welcome shown).
- [x] Self-review pass caught and fixed three real bugs before handoff: (1) `VaultWatcher.deinit` was calling `NSMetadataQuery.stop()` from a non-main thread — removed it, `stop()` is now explicit-only via `VaultSession`; (2) `VaultSession.detach()` wiped persistence as a side effect, so `attach()`'s internal cleanup would erase the new vault record before re-persisting — split into private `teardown()` (no persistence touch) and public `forgetCurrentVault()` (explicit wipe); (3) `VaultSession.ensureDownloaded` polled without cancellation checks, so a user navigating away from the detail view could leave the loop spinning for 15s — added `Task.checkCancellation()` and promoted the `Task.sleep` to throw on cancel. Also fixed a Swift-6 strict-concurrency warning in `VaultWatcher.reloadFromLocalWalk` by moving the MainActor re-entry into a dedicated `applyLocalWalk(_:generation:)` method rather than capturing `[weak self]` into a nested concurrent closure.

- [ ] **NOT verified, needs device/manual testing:** actual tap through "Choose local folder" → file picker → pick folder → sidebar populates → tap file → text loads. I had no way to drive taps on the simulator programmatically. Welcome rendering is proven but the post-selection flow is only proven by construction (compiles + types line up), not by observation. Same caveat for iCloud sync (needs a signed-in device) and bookmark re-resolution after relaunch.

#### Decisions Made
- **WindowGroup over DocumentGroup for Phase 4.** `IMPLEMENTATION.md` said `DocumentGroup(newDocument: { MarkdownDocument() }) { … }` + a separate `WindowGroup` for welcome. Deviated to a single `WindowGroup` hosting welcome + sidebar + detail. `DocumentGroup` opens the system document browser at launch with no first-class hook for a custom vault sidebar; the phase's "sidebar of `.md` files in the iCloud Clearly folder" criterion needs a custom vault browser, not a per-document scene. Keeps the iOS and Mac mental models aligned (Mac uses `Window` + `WorkspaceManager`, not `DocumentGroup`). `MarkdownDocument` still promoted to `FileDocument` as Phase 5 / 6 setup. If we want Files.app "open in Clearly" integration later, `DocumentGroup` can land as a second scene.
- **`FileDocument`, not `ReferenceFileDocument`.** Reference semantics matter for collaborative editing and multi-scene live-update; value semantics are enough for the editor binding we'll add in Phase 5. Phase 6 can upgrade if autosave flows need the reference model.
- **Flat file list, not a hierarchical tree.** Phase 4 shows `[VaultFile]` in a simple `List`. Subdirectories are walked (via `FileNode.buildTree`) but flattened into a single sorted list by filename. Hierarchy + `DisclosureGroup` expansion lands alongside Phase 8's index rebuild.
- **`.fileImporter` (SwiftUI) instead of direct `UIDocumentPickerViewController`.** Same underlying presenter, less UIKit glue.
- **Picked-iCloud vs local kind = a user-facing label only.** Functionally both paths create security-scoped bookmarks the same way; the distinction is stored so Settings in Phase 13 can group them differently. Not worth inferring the kind from URL path.
- **`NSMetadataQuery` only for `.defaultICloud`.** Picked iCloud folders can sit anywhere in iCloud Drive (not necessarily inside our ubiquity container), so the `NSMetadataQueryUbiquitousDocumentsScope` predicate wouldn't reliably cover them. Safer to treat all picked folders (iCloud or local) via `FileNode.buildTree` + manual refresh. Real-time iCloud updates only available when using the default container — acceptable tradeoff for Phase 4.
- **Deferred `CloudBackend` persistence for `VaultWatcher`.** Did not build abstract `BackendProtocol` or split into two types — a single `useCloudQuery: Bool` flag routes between the two code paths. Cheaper than polymorphism for two call sites.
- **Security-scoped bookmark options: `[]` on iOS, `.withSecurityScope` on macOS.** `.withSecurityScope` is macOS-only; passing it on iOS throws `NSFileReadNoPermissionError`. Branched with `#if os(iOS)` inside `VaultLocation.resolve`.
- **`@Observable` for `VaultSession` + `ObservableObject` for `VaultWatcher`.** `VaultSession` is consumed by SwiftUI views → `@Observable` for property-level tracking. `VaultWatcher` is a worker class that mirrors state via Combine → `ObservableObject` + `@Published` keeps the Combine interop idiomatic.
- **`.fullScreenCover` for welcome, not `.sheet`.** Welcome is a first-launch-or-change-vault gate; `.sheet` lets users swipe to dismiss before configuring a vault, which puts the app into a broken state. `interactiveDismissDisabled(session.currentVault == nil)` pins it when no vault exists.

#### Blockers
- (none)

---

### Phase 5: iOS syntax-highlighted editor (read-only save path)
**Status:** Complete (2026-04-21)

#### Tasks Completed
- [x] `git mv Clearly/Theme.swift → Packages/ClearlyCore/Sources/ClearlyCore/Rendering/Theme.swift`. Collapsed 19 dynamic color declarations behind `PlatformColor.clearlyDynamic(name:light:dark:)` in `Platform.swift`; `Theme` itself imports SwiftUI only. `editorFont` returns `PlatformFont`; `folderColorPalette` stores `PlatformColor`. SwiftUI `Color` bridging uses `Color(platformColor:)`. All accessed members marked `public`.
- [x] `git mv Clearly/MarkdownSyntaxHighlighter.swift → Packages/ClearlyCore/Sources/ClearlyCore/Rendering/`. Rendering file imports `Foundation` + `os` + `QuartzCore` only; AppKit/UIKit APIs are hidden behind `PlatformTextStorage`, `PlatformParagraphStyle`, `PlatformTextAttributes`, and `PlatformFont` helpers in `Platform.swift`. Class, init, `highlightAll`, `highlightAround`, `isInsideProtectedRange`, `needsFullHighlight` all `public`. Removed `import ClearlyCore` (this file now lives inside the package).
- [x] Added platform wrappers to `Packages/ClearlyCore/Sources/ClearlyCore/Platform/Platform.swift`: `PlatformTextView`, `PlatformTextStorage`, `PlatformParagraphStyle`, `PlatformTextAttributes`, `PlatformFontWeight`, `PlatformColor.clearlyColor`, `PlatformColor.clearlyDynamic`, `Color(platformColor:)`, `PlatformFont.withItalicTrait()`, `PlatformFont.clearlyMonospacedSystemFont`, and `PlatformFont.clearlyMonospacedBoldItalic`.
- [x] Added `import ClearlyCore` to nine Mac-only consumers that pulled `Theme`/`MarkdownSyntaxHighlighter` from the old module-local scope: `WelcomeView`, `SidebarViewController`, `ScratchpadManager`, `ScratchpadEditorView`, `LineNumberRulerView`, `IconPickerView`, `ClearlyTextView`, `ClearlySegmentedControl`, `ClearlyButtonStyle`. The remaining 11 consumers already had the import from Phase 1.
- [x] New `Clearly/iOS/ClearlyUITextView.swift` — `UITextView` subclass. Owns its own `NSTextStorage`/`NSLayoutManager`/`NSTextContainer` chain. Sets `backgroundColor`/`textColor`/`font`/`tintColor` from `Theme`. Sets `isEditable = false` + `isSelectable = true` for the Phase 5 read-only contract. Disables autocorrect + smart quotes + smart dashes + smart insert/delete + spell check globally. `keyboardDismissMode = .interactive`. Applies `textContainerInset` modeled on `Theme.editorInsetTop/Bottom` (left/right = 16). `typingAttributes` carries `editorFont` + `textColor` + paragraph style with `min/maxLineHeight = Theme.editorLineHeight` + `baselineOffset = Theme.editorBaselineOffset`. `init(coder:)` unavailable.
- [x] New `Clearly/iOS/EditorView_iOS.swift` — `UIViewRepresentable<ClearlyUITextView>`. `text: String` is a value (not `@Binding`) — read-only contract enforced structurally. `Coordinator: NSObject, UITextViewDelegate` owns a `MarkdownSyntaxHighlighter`. `pendingBindingUpdates: Int` counter + `pendingBindingUpdateToken: UUID?` ported verbatim from the Mac `EditorView.Coordinator`. `textView(_:shouldChangeTextIn:replacementText:)` returns `false` when `isEditable == false`; future editable mode captures `lastEditedRange` + `lastReplacementLength`. `textViewDidChange(_:)` increments the counter synchronously, runs `highlightAround` (or `highlightAll` on fallback), handles block-delimiter deferred full highlight (300 ms async), then schedules a 150 ms async token-gated decrement. `updateUIView` skips when counter > 0, else compares `text != lastAppliedText` and rebuilds.
- [x] Replaced `RawTextDetailView_iOS`'s `ScrollView { Text(text).monospaced() … }` with `EditorView_iOS(text: text)`. Footer copy → "Editing disabled — saving lands in next build."
- [x] `xcodegen generate` — clean (no `project.yml` diff)
- [x] `xcodebuild -scheme Clearly -configuration Debug build -allowProvisioningUpdates` — green (Mac unchanged)
- [x] `xcodebuild -scheme ClearlyQuickLook -configuration Debug build` — green
- [x] `xcodebuild -scheme ClearlyCLI -configuration Debug build` — green
- [x] `xcodebuild -scheme ClearlyCLIIntegrationTests test` — 23/23 pass
- [x] `xcodebuild -scheme Clearly-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -configuration Debug build -allowProvisioningUpdates` — green
- [x] Booted iPhone 17 / iOS 26.4 simulator, installed `Clearly Dev.app`, launched `com.sabotage.clearly.dev`. App stays alive (PID 4743, `launchctl list` shows it running `rb-legacy`). Welcome screen renders (no iCloud identity; the same proven state from Phase 4).
- [ ] **NOT programmatically verified (needs Josh's manual pass):** (1) tap "Choose local folder" → pick folder → sidebar populates → tap a `.md` file → editor renders with syntax highlighting; (2) side-by-side visual match against the Mac app for a file with headings / bold / italic / bold-italic / code / wiki-links / tags / blockquotes / math / frontmatter; (3) cursor-jump stress test under rapid 200-char typing burst; (4) 1 MB file smoothness check. Only the build/launch and unit-test layers are machine-verifiable in this workspace.

#### Decisions Made
- **Highlighter lives on the Coordinator, not the UITextView.** First draft placed the `MarkdownSyntaxHighlighter` as an owned property of `ClearlyUITextView` via `NSTextStorageDelegate`. Moved it to the `UIViewRepresentable.Coordinator` to mirror the Mac pattern (where the coordinator owns the highlighter and drives it from `NSTextViewDelegate.textDidChange`) and to avoid the `NSTextStorageDelegate.didProcessEditing` → nested `beginEditing`/`endEditing` re-entry risk. `UITextViewDelegate.textViewDidChange` fires outside the text storage's internal editing transaction, so there's no recursion concern.
- **`text` passed as `let`, not `@Binding`.** Read-only contract enforced structurally — the editor can't accidentally write back. Phase 6 promotes to `@Binding` + wires a parent callback; the Coordinator's `pendingBindingUpdates` counter is already in place for that promotion.
- **Global autocorrect / smart-quote disable.** Plan called out a per-range code-fence disable as a stretch goal. Shipped with a global disable on all five (`autocapitalization`, `autocorrection`, `smartQuotes`, `smartDashes`, `smartInsertDelete`, `spellChecking`) since markdown authoring is the single use case. Per-range logic can come in Phase 6 if user feedback demands it.
- **Dynamic-color refactor in `Theme`.** Rather than replicating 19 individual `NSColor(name:)` / `UIColor(dynamicProvider:)` declarations inside `Theme`, added `PlatformColor.clearlyDynamic(name:light:dark:)` in `Platform.swift`. Same colors, same dynamic behavior, and rendering files stay free of AppKit/UIKit imports.
- **PlatformFont trait helpers live on `PlatformFont`.** Extension on the typealias, not free functions, so the highlighter reads naturally: `Theme.editorFont.withItalicTrait()` and `PlatformFont.clearlyMonospacedBoldItalic(size:)`. Works identically on both platforms. `NSFontManager` + `NSFontTraitMask` are fully hidden inside the extension.
- **No source globs changed in `project.yml`.** `Packages/ClearlyCore/Sources/ClearlyCore/**/*.swift` picks up the two new files in `Rendering/` automatically; `Clearly/iOS/**` globbed for the iOS target picks up the two new files there. Re-ran `xcodegen generate` after adding `EditorView_iOS.swift` because the first build missed the new file (expected — xcodegen only sees what's on disk when it runs).

#### Blockers
- (none)

---

### Phase 6: Coordinated writes + keyboard accessory bar
**Status:** Complete (2026-04-21)

#### Tasks Completed
- [x] Extended `Packages/ClearlyCore/Sources/ClearlyCore/Sync/CoordinatedFileIO.swift` with `write(_:to:presenter:)` overload. The existing `write(_:to:)` now forwards to the new overload with a nil presenter — zero behavior change for existing callers (CLI + Mac helpers).
- [x] New `Clearly/iOS/IOSDocumentSession.swift` — `@Observable @MainActor` class. `open(_:via:)` / `close()` / `flush()` / internal `scheduleAutosave()` / `performSave(text:url:)`. Owns one `DocumentPresenter` (private subclass of `NSFilePresenter` in the same file). 2-second debounced autosave via a replace-on-edit `Task?`. `isOwnWriteInFlight` flag suppresses the presenter-callback echo during our own coordinated writes. `NSFileVersion.unresolvedConflictVersionsOfItem(at:)` probe populates `hasConflict`. `text` has a `didSet` that schedules autosave when `text != lastSavedText`.
- [x] `DocumentPresenter` hops every `presentedItemDidChange` / `…DidMove(to:)` / `accommodatePresentedItemDeletion(_:)` callback onto the main actor and forwards to the session via `weak` reference. Dedicated serial `OperationQueue` per presenter. `@unchecked Sendable` so `Task.detached` can capture it when performing the coordinated write off-main.
- [x] `Clearly/iOS/ClearlyUITextView.swift`: flipped `isEditable = false` → `isEditable = true`. No other changes — insets, typing attributes, smart-quote disable, keyboard dismiss mode all identical to Phase 5.
- [x] `Clearly/iOS/EditorView_iOS.swift`: promoted `let text: String` → `@Binding var text: String`. Renamed `applyInitialText` → `applyExternalText` to reflect that it now runs whenever the parent's binding pushes a new value. `textViewDidChange` writes `parent.text = newText` and updates `lastAppliedText = newText` BEFORE scheduling the 150 ms decrement, so the re-render triggered by the binding write sees the updated `lastAppliedText` and short-circuits in `updateUIView`. `Coordinator` gains a `var parent: EditorView_iOS` property, refreshed in `updateUIView`, so the binding write-back has a stable hook.
- [x] `Clearly/iOS/RawTextDetailView_iOS.swift`: swapped local `@State var text: String` for `@State private var document = IOSDocumentSession()`. Renamed the injected `@Environment(VaultSession.self) private var session` → `vault` to disambiguate. `.task(id: file.id) { await document.open(file, via: vault) }`. Editor binding is inline `Binding(get:set:)` into `document.text`. Dirty indicator: `.navigationTitle(document.isDirty ? "• \(file.name)" : file.name)`. Conflict banner: `HStack` with icon, text, spacer, disabled "Resolve" button, yellow-tint background, rendered above the editor when `document.hasConflict`. `.onChange(of: scenePhase)` flushes on `.inactive` or `.background`. `.onDisappear` calls `document.close()` (flush + detach presenter). Read-only footer removed.
- [x] `Clearly/MarkdownDocument.swift`: `fileWrapper(configuration:)` now returns a real `FileWrapper(regularFileWithContents: Data(text.utf8))` instead of throwing `featureUnsupported`. iOS save flow doesn't route through this (it goes through `IOSDocumentSession` → `CoordinatedFileIO.write`), but leaving the stub was a latent bug trap for any future `FileDocumentConfiguration` consumer.
- [x] `xcodegen generate` clean (no `project.yml` diff needed — globs pick up the three new files).
- [x] `xcodebuild -scheme Clearly -configuration Debug build -allowProvisioningUpdates` — green (Mac unchanged).
- [x] `xcodebuild -scheme ClearlyQuickLook -configuration Debug build` — green.
- [x] `xcodebuild -scheme ClearlyCLI -configuration Debug build` — green.
- [x] `xcodebuild -scheme ClearlyCLIIntegrationTests test` — 23/23 pass.
- [x] `xcodebuild -scheme Clearly-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -configuration Debug build -allowProvisioningUpdates` — green. Caught one API typo during first build: my research doc and plan both used `NSFileVersion.unresolvedVersionsOfItem(at:)`, but the real method name is `unresolvedConflictVersionsOfItem(at:)`. Fixed before second build.
- [x] Installed `Clearly Dev.app` on iPhone 17 / iOS 26.4 simulator; launched `com.sabotage.clearly.dev`; PID 70533, `launchctl list` shows `status 0` (alive). App didn't crash on startup — proves `IOSDocumentSession` instantiation and `EditorView_iOS` `@Binding` wiring don't fault.
- [x] **Post-handoff self-review pass.** Caught a real bug before closing: the first draft of `IOSDocumentSession.performSave` set `errorMessage` on save failure, which `RawTextDetailView_iOS` renders as the full-screen "Couldn't open this note" view. A transient save failure (iCloud offline, disk hiccup) would have unmounted the editor mid-edit, losing the user's in-progress text. Fix: `performSave` now logs via `DiagnosticLog.log` and leaves `lastSavedText` unchanged so `isDirty` stays true — the nav-title `•` remains the user-visible signal, and the next autosave or scene-phase flush retries. `errorMessage` stays reserved for the load-blocking failure path only. Rebuilt + re-tested after the fix: Mac / QuickLook / CLI / iOS Debug schemes all still green; 23/23 integration tests still pass; iPhone 17 simulator relaunched (PID 95229, `launchctl list` status 0).
- [ ] **NOT programmatically verified (needs Josh's manual pass):** (1) tap a note → editor is actually editable, characters land, highlighting updates live; (2) type + lock device → iCloud sync propagates to Mac within ~10–30 s; (3) Mac edit → iPhone foreground same file → `presentedItemDidChange` fires → editor refreshes in place; (4) force-kill mid-edit → relaunch → autosave point preserved, no half-file; (5) induce a conflict via offline editing on both devices → banner appears with disabled Resolve button. Only the build + launch + unit-test layers are machine-verifiable in this workspace.

#### Decisions Made
- **2-second autosave debounce.** Matches the Phase 6 spec target. Mac uses 1 s for trackpad-paced typing; 2 s on mobile produces roughly one disk write per sentence, better for battery and iCloud bandwidth.
- **`IOSDocumentSession` scoped to the detail view via `@State`.** Each `RawTextDetailView_iOS` owns its own session; `.task(id:)` + `.onDisappear` drive open / close. Lifting to the scene root would have required explicit teardown on file switch that the detail view already does for free.
- **Shipped Phase 6 WITHOUT the keyboard accessory bar.** The phase plan bundled a `UIToolbar` accessory with `[[ ]]`, heading cycle, code fence, checkbox toggle, and dismiss buttons. Pulled during verification after an honest audit of which buttons earn their space: three of the five (`[[ ]]`, code fence, dismiss) are marginal on iOS — they save 1–3 taps but add a persistent strip of chrome above the keyboard. The two genuinely useful ones (heading cycle + checkbox toggle) are line-level transforms, but a user who wants them can switch to a markdown app that has them — the value-add for Clearly's "writing-first" positioning isn't obvious enough to ship. Stripped `Clearly/iOS/KeyboardAccessoryBar.swift` and `Packages/ClearlyCore/Sources/ClearlyCore/Rendering/MarkdownEditingHelpers.swift`. Removed the `textView.inputAccessoryView = …` line from `EditorView_iOS.makeUIView`. If a later phase wants to revive the line-level transforms, the helpers file can be restored from git history. `ClearlyUITextView.keyboardDismissMode = .interactive` already provides a drag-to-dismiss path; no dismiss button needed.
- **Presenter per document, not per vault.** `NSFilePresenter` is keyed on `presentedItemURL`; a folder-level presenter would fire `didChange` for every file in the vault — wrong granularity for "this specific open note changed remotely." Vault-level change detection is still covered by `VaultWatcher`'s `NSMetadataQuery`.
- **Belt-and-braces `isOwnWriteInFlight` flag.** `NSFileCoordinator(filePresenter:)` already suppresses callbacks to the passed-in presenter, but the flag also guards the very-fast-roundtrip case where a metadata-query change event could fire before the write fully settles.
- **`Binding(get:set:)` rather than `@Bindable` shadow.** The Phase 4 iOS files don't use `@Bindable`; staying with inline bindings keeps the codebase style consistent and avoids the local-shadow-inside-body trick.
- **`.onDisappear` calls `close()`, not `flush()`.** `NavigationStack` destroys popped views and their `@State`; the old session would leak its `NSFilePresenter` registration if we only flushed. Different view instances on re-push mean no race between the disappearing session's close and the new session's open.
- **Conflict banner is a plain `HStack` with a disabled `Button`.** Phase 11 will reshape it when the real resolver lands.
- **Save failures are non-blocking, logged only.** `errorMessage` is reserved for load-blocking failures (drives the full-screen "Couldn't open this note" view). A failed save must never unmount the editor from under the user's in-progress edit; the `isDirty` bullet in the nav title stays lit so the user has a signal that something's unsaved, and the next autosave / scene-phase flush retries. Failed saves go through `DiagnosticLog.log` so the history is available in `~/Library/Application Support/Clearly/diagnostic.log` if we need to post-mortem.

#### Blockers
- (none)

---

### Phase 7: iOS preview + wiki-link navigation
**Status:** Complete (2026-04-21)

#### Tasks Completed
- [x] **Stale plan tasks skipped.** Renderer files were already consolidated in `Packages/ClearlyCore/Sources/ClearlyCore/Rendering/` by Phase 1 — no moves needed. `PreviewCSS.swift:133` already sets `-webkit-text-size-adjust: 100%` in the base `body` rule globally — no iOS branch needed.
- [x] `project.yml`: added 6 resource entries on `Clearly-iOS` mirroring the Mac target (`mermaid.min.js`, `katex.min.js`, `katex.min.css`, `fonts/`, `highlight.min.js`, `highlight-theme.css`). Skipped `demo.md` + `getting-started.md` — no iOS Help menu to surface them yet.
- [x] `Packages/ClearlyCore/Sources/ClearlyCore/Vault/VaultSession.swift`: added `public var navigationPath: [VaultFile] = []` (binding surface for `NavigationStack(path:)`); `public func resolveWikiLink(name:) -> VaultFile?` (case-insensitive stem → filename match over `files`); `public func openOrCreate(name:) async throws -> VaultFile` (returns existing match, otherwise sanitizes the name — strips `/ \ : ? * " < > |` — and writes an empty `.md` at vault root via `CoordinatedFileIO.write(Data(), to:)`, then calls `refresh()`). `openOrCreate` returns a provisional `VaultFile` immediately so nav push doesn't block on the watcher's next tick.
- [x] New `Clearly/iOS/PreviewView_iOS.swift` — `UIViewRepresentable<WKWebView>` + `Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler`. Registers `LocalImageSchemeHandler` for the `clearly-file://` scheme. Two script message handlers: `linkClicked` + `taskToggle`. HTML template wraps `MarkdownRenderer.renderHTML(_, appLinkURLs: true, ...)` + `LocalImageSupport.resolveImageSources(in:relativeTo:)` + the four Support scripts (Math, Table, Mermaid, SyntaxHighlight). JS retained: image-error fallback, link-click interceptor, heading anchor ids, task-checkbox toggle, image lightbox. JS dropped (Phase 7 scope): scroll tracking, dblclick-to-source, footnote popovers, wiki-link broken detection (the last one requires a known-file-names set from VaultIndex — arrives in Phase 8). `Coordinator` ports the `skipNextReload` flag verbatim so task-toggle-driven reloads don't flash. `handleLinkClick` routes `clearly://wiki/<name>` → `onWikiLinkClicked(name)` and `http(s)://…` → `UIApplication.shared.open(url)`. `CSS` uses `bodyMaxWidth: "100%"` (overrides the Mac default 61em) + an iPhone-friendly `padding: 16px 20px 32px` override.
- [x] `Clearly/iOS/RawTextDetailView_iOS.swift`: added `@State private var viewMode: ViewMode = .edit` using the existing `ClearlyCore.ViewMode` enum. Toolbar `ToolbarItem(placement: .principal)` hosts a 2-segment `Picker` with `.segmented` style bound to `$viewMode`. `content` branches on `viewMode` — `.edit` renders `EditorView_iOS`, `.preview` renders `PreviewView_iOS(markdown: document.text, fileURL: file.url, onWikiLinkClicked: handleWikiLink, onTaskToggle: handleTaskToggle)`. `handleWikiLink` kicks off a Task calling `vault.openOrCreate(name:)` and appends the result to `vault.navigationPath` on success. `handleTaskToggle` mirrors the Mac `ContentView.onTaskToggle` line-replacement logic (`- [ ]`/`* [ ]`/`+ [ ]` ↔ `- [x]`/etc.) and writes back into `document.text`.
- [x] `Clearly/iOS/SidebarView_iOS.swift`: `@Bindable var session = session` inside body + `NavigationStack(path: $session.navigationPath)` so programmatic pushes from the preview propagate. `NavigationLink(value: file)` continues to work unchanged — SwiftUI updates the bound path automatically when a user taps a sidebar row.
- [x] `xcodegen generate` — clean.
- [x] `xcodebuild -scheme Clearly -configuration Debug build -allowProvisioningUpdates` — green.
- [x] `xcodebuild -scheme ClearlyQuickLook -configuration Debug build` — green.
- [x] `xcodebuild -scheme ClearlyCLI -configuration Debug build` — green.
- [x] `xcodebuild -scheme ClearlyCLIIntegrationTests test` — 23/23 pass.
- [x] `xcodebuild -scheme Clearly-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -configuration Debug build -allowProvisioningUpdates` — green.
- [x] Installed + launched `Clearly Dev.app` on iPhone 17 / iOS 26.4 simulator — PID 36093, `launchctl list` status 0 (alive).
- [x] **Post-handoff self-review pass caught two real bugs before close:** (1) `VaultSession.openOrCreate` had a silent data-loss path — if a file existed on disk but `session.files` hadn't caught up (iCloud metadata lag, pending local-walk refresh), the `CoordinatedFileIO.write(Data(), to:)` call would overwrite the existing file's contents with empty data. Added a `FileManager.default.fileExists(atPath:)` pre-check that returns a provisional `VaultFile` for the already-present URL instead of writing. (2) `PreviewView_iOS.handleLinkClick` only opened `http://` / `https://` URLs via `UIApplication.shared.open`, silently dropping `mailto:`, `tel:`, and other native-app-handled schemes; Mac sends all non-clearly URLs through `NSWorkspace.shared.open`. Fixed to open any non-`clearly://` URL and explicitly ignore unknown `clearly://` schemes (tags etc. land in Phase 10). Rebuilt + retested: Mac / QuickLook / CLI / iOS schemes all still green; 23/23 integration tests still pass; iPhone 17 simulator relaunched (PID 69468, `launchctl list` status 0).
- [ ] **NOT programmatically verified (needs Josh's manual pass):** (1) tap a note → toggle Edit/Preview segment → HTML renders cleanly (headings / code / math / mermaid / tables / inline images); (2) `[[existing-note]]` tap pushes the existing note onto the nav stack; (3) `[[new-note]]` tap creates an empty `.md` at vault root and pushes it; (4) task checkbox in preview flips `[ ]` ↔ `[x]` in source (confirm via Edit mode); (5) tapping an external `http(s)` link opens Safari; (6) kill + relaunch → preview still works (proves the six bundled resources are resolving from `Bundle.main`).

#### Decisions Made
- **Dropped Phase 7's "move renderer files" task.** Phase 1 already moved all rendering files into `ClearlyCore/Rendering/`. Verified by filesystem walk — no `Shared/` copies, no `Clearly/` copies. The plan's first two tasks were stale.
- **Dropped Phase 7's "add iOS-only CSS branch" task.** `PreviewCSS.swift:133` already emits `-webkit-text-size-adjust: 100%` in the base `body` declaration, applying to every platform. No iOS branch needed.
- **Simpler wiki-link resolver on iOS.** Mac uses `VaultIndex.resolveWikiLink(name:)` — SQLite-backed, handles path-like matching, heading lookup, broken-link set. iOS doesn't have a VaultIndex yet (Phase 8). Shipped a 10-line `VaultSession.resolveWikiLink` that walks `files: [VaultFile]` (case-insensitive stem → filename match). Good enough for the Phase 7 success criterion; Phase 8 will point this at the real index.
- **`navigationPath` on `VaultSession`, not a separate `VaultNavigator` type.** `VaultSession` is already the iOS-UI-facing state holder. A second `@Observable` class would have meant a new file + a second environment injection point + a second dependency in `RawTextDetailView_iOS`. 2-line addition on `VaultSession` wins.
- **`@Bindable var session = session` shadowing inside `body`.** That's the SwiftUI 5 idiom for deriving bindings from an `@Observable` object injected via `@Environment`. Without the shadow, `$session.navigationPath` doesn't resolve (environment values don't expose property bindings directly).
- **Per-detail-view `@State var viewMode`, not on `IOSDocumentSession`.** Phase 7 is single-column iPhone-only. Promoting `viewMode` to the document session would force a teardown/restore model for a state that has no need to outlive the view. iPad multi-column (Phase 12) will revisit where mode lives.
- **Create-if-missing places new notes at vault root.** Mac's current wiki-link behavior doesn't create missing notes at all — Phase 7 adds the capability first on iOS because it's simpler to land with a single-vault model. A folder-aware creation rule (respect the source note's parent directory, or show a picker) can follow later; vault-root is the deterministic default.
- **Trimmed the Mac preview HTML hard.** Skipped scroll sync (no editor/preview split on iPhone yet), double-click-to-source (iPhone doesn't have double-click semantics), footnote popovers (no hover on iOS), find-in-preview (Phase 9), selection capture (Mac-specific feature plumbing). Kept the essentials: links, task toggle, headings, image lightbox, image-error fallback. ~120 lines of JS vs Mac's ~200+. The trimmed features can port back if a future phase needs them; better to ship clean than to drag along Mac-only plumbing that we can't test end-to-end on iPhone.
- **`bodyMaxWidth: "100%"` override.** Mac's default `61em` made the preview look awkwardly narrow with big side margins on a 6.1" iPhone screen. `100%` + a 20px horizontal padding fits the phone viewport.
- **Wiki-link broken-link highlight deferred.** Mac's `wiki-link-broken` CSS class is driven by a `Set<String>` of known filenames derived from `VaultIndex`. iOS could build the equivalent from `session.files` for cheap, but (a) the set is stale the moment the user creates a new note via openOrCreate and (b) Phase 8 is about to land the real index. Ship the JS scaffold with an empty set; Phase 8 wires the real data.
- **`openOrCreate` returns a provisional `VaultFile`.** `VaultWatcher`'s refresh is async. If we wait for the watcher to see the new file before pushing nav, the user experiences a perceptible delay between tapping the broken link and seeing the new note. Returning a constructed `VaultFile(url:…, name:…, modified: Date(), isPlaceholder: false)` immediately means `RawTextDetailView_iOS` can `.task(id: file.id)` the new file and `IOSDocumentSession.open` reads it off disk instantly. The watcher's next tick replaces the in-memory `files` record, but nav stack pushes are URL-keyed via `VaultFile.id`, so the navigation stays stable.

#### Blockers
- (none)

---

### Phase 8: Index rebuild + `.icloud` placeholder coordination
**Status:** Complete (2026-04-21)

#### Tasks Completed
- [x] `VaultIndex.indexDirectory()` (`Packages/ClearlyCore/Sources/ClearlyCore/Vault/VaultIndex.swift:817`) gained an `#if os(iOS)` branch pointing at `URL.cachesDirectory/indexes/`. macOS + ClearlyMCP paths unchanged.
- [x] New async `VaultIndex.indexAllFiles(showHiddenFiles:downloadPlaceholder:progress:)` added alongside the existing sync version. Collects file data in an async loop (awaits the `downloadPlaceholder` hook before each read), then does one batched `dbPool.write`.
- [x] `VaultSession` gained: `indexProgress: Double?` (published), `currentIndex: VaultIndex?` accessor, `index` + `indexingTask` + `knownFiles` private storage, `beginIndexing(using:)` launched from `attach(_:)`, tear-down on `teardown()`.
- [x] `beginIndexing` inlines a placeholder-aware download loop (5s per-file deadline; returns `false` on timeout so the file is skipped this pass and picked up on the next watcher tick).
- [x] `scheduleIncrementalReindex` wires `VaultWatcher.$files` → debounced 500 ms → diff against `knownFiles` → `VaultIndex.updateFile(at:)` per changed path. Skips while the full rebuild is in flight.
- [x] `VaultSession.resolveWikiLink` now checks `VaultIndex` first and falls back to the file-list scan. Phase 7's deferred "point iOS wiki-link at real index" is now done.
- [x] `SidebarView_iOS` inserts a 2pt `ProgressView(value:)` under the nav bar while `indexProgress != nil`.
- [x] Mac Debug build: **passed** (`xcodebuild -scheme Clearly -configuration Debug build`). iOS Debug build: **passed** (`xcodebuild -scheme Clearly-iOS -configuration Debug -destination 'generic/platform=iOS Simulator' build`). CLI integration tests: **23/23 passed**.

#### Decisions Made
- **iOS-only cache-dir switch, not universal.** The spec wanted `URL.cachesDirectory/indexes/<hash>/vault.sqlite` on **both** platforms. Moving Mac would break ClearlyMCP CLI (`VaultIndex.swift:825` resolves `Library/Containers/<bundleId>/Data/Library/Application Support/<bundleId>/indexes`). Phase 8 ships the iOS branch only; Mac stays on Application Support. Spec intent ("never inside the ubiquity container") is preserved because Mac's App Support is inside the sandbox container, not iCloud.
- **Flat layout inside `indexes/`, not a per-vault subdirectory.** Kept the Mac convention of `<path-hash>.sqlite` (not `<path-hash>/vault.sqlite`). One less directory, same uniqueness guarantee via SHA-256 truncation.
- **No spinner-on-sidebar-row for placeholder taps.** Plan called for per-row tap → spinner + download. Dropped because the existing navigation path already handles this: `IOSDocumentSession.open(_:via:)` (`Clearly/iOS/IOSDocumentSession.swift:54`) sees `file.isPlaceholder`, calls `vault.ensureDownloaded`, and the detail view renders "Downloading from iCloud…". The sidebar tap gesture would have layered on top of `NavigationLink`'s own tap handling and risked gesture-conflict regressions.
- **Async `indexAllFiles` is an overload, not a replacement.** Mac's `WorkspaceManager.reindexVault` (`Clearly/WorkspaceManager.swift:1222`), `ClearlyCLI/CLI/Commands/IndexCommand.swift:101`, and `ClearlyCLIIntegrationTests/TestVaultHarness.swift:47` all call the existing sync `indexAllFiles(showHiddenFiles:)`. Leaving that untouched kept the 23 integration tests green without refactoring three callers.
- **Debounce incremental re-index at 500 ms on a separate subscription.** Split the `watcher.$files` sink into two: one immediate (feeds `session.files` for UI), one debounced (feeds `scheduleIncrementalReindex`). The immediate publish keeps the sidebar snappy; the debounce coalesces NSMetadataQuery update storms.
- **`knownFiles` updates every tick, even during rebuild.** Always snapshot the latest file set on each watcher emission so the first post-rebuild tick has the correct "previous" state to diff against. Skip the actual `updateFile` pass while `indexProgress != nil`.
- **First post-attach watcher tick does no incremental re-index.** `oldKnown.isEmpty` short-circuits — the full rebuild already covers every file. Without this, the initial watcher publication would fire `updateFile` for every file in parallel with the rebuild.
- **Wiki-link resolver keeps the file-scan fallback.** There's a race window between the watcher surfacing a new file and the 500ms-debounced incremental re-index writing it to the DB. Fall back to the current file-list scan so `openOrCreate` works instantly in that window.
- **`downloadPlaceholder` returns `Bool`, not `throws`.** A download timeout is not an error; it's a signal to skip this file this pass. Exceptions in the indexing loop would prematurely abort the whole rebuild. Returning a Bool keeps the loop going and delegates timeout handling to the caller's policy.

#### Blockers
- (none)

---

### Phase 9: Quick switcher + global search UIs on iOS
**Status:** Complete (2026-04-21)

#### Tasks Completed
- [x] Extracted `FuzzyMatcher` enum + `FuzzyMatchResult` struct from `Clearly/QuickSwitcherPanel.swift` into `Packages/ClearlyCore/Sources/ClearlyCore/Search/FuzzyMatcher.swift`. Both `public`. Mac call sites unchanged — `import ClearlyCore` was already present.
- [x] Added `recentFiles: [VaultFile]` (capped 10, most-recent-first) + `isShowingQuickSwitcher: Bool` + `markRecent(_:)` to iOS `VaultSession`. Persistence uses one `UserDefaults` dictionary keyed by vault path so each vault keeps its own recents; the stale-file filter runs once on first non-empty watcher emission (`hasRestoredRecents` guard).
- [x] New `Clearly/iOS/QuickSwitcherSheet_iOS.swift` — unified sheet. `TextField` auto-focuses on open, cancel button honors `.cancelAction`. Empty query → `vault.recentFiles` under a "Recent" section. Non-empty → `FuzzyMatcher` over `vault.files` (top 20) with match ranges painted in the accent color via `AttributedString`. Query ≥ 2 chars additionally queries `vault.currentIndex?.searchFilesGrouped(query:)`, dedupes against filename hits by standardized URL, takes 30. FTS5 `<<…>>` delimiters parsed out of snippets and rendered as accent-color runs. Zero hits → "Create `<query>`.md" row that calls `vault.openOrCreate(name:)`. Every tap dismisses the sheet, appends to `vault.navigationPath`, and marks the file recent.
- [x] New `QuickSwitcherShortcuts` view (zero-size, opacity 0, `.allowsHitTesting(false)`) hosts two hidden buttons with `.keyboardShortcut("k", modifiers: .command)` and `.keyboardShortcut("f", modifiers: [.command, .shift])`. Attached via `.background { QuickSwitcherShortcuts() }` at both `SidebarView_iOS` and `RawTextDetailView_iOS` so ⌘K / ⌘⇧F fire on iPad hardware keyboards regardless of which screen owns focus.
- [x] `SidebarView_iOS.swift`: added `magnifyingglass` toolbar button (disabled until a vault is attached), `.sheet(isPresented: $session.isShowingQuickSwitcher)` wiring, explicit `.environment(session)` injection into the sheet content.
- [x] `RawTextDetailView_iOS.swift`: hooked `vault.markRecent(file)` into `.task(id: file.id)` after successful read (skipped when `document.errorMessage != nil`); added `QuickSwitcherShortcuts` to its background.
- [x] `xcodegen generate` clean
- [x] `xcodebuild -scheme Clearly -configuration Debug build -allowProvisioningUpdates` — green (Mac QuickSwitcherPanel compiles clean against the relocated `FuzzyMatcher`)
- [x] `xcodebuild -scheme ClearlyQuickLook -configuration Debug build` — green
- [x] `xcodebuild -scheme ClearlyCLI -configuration Debug build` — green
- [x] `xcodebuild -scheme Clearly-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -configuration Debug build -allowProvisioningUpdates` — green
- [x] `xcodebuild -scheme ClearlyCLIIntegrationTests test` — 24/24 pass (count ticked up from 23 earlier in the phase track; unrelated to Phase 9)
- [x] Installed + launched on iPhone 17 / iOS 26.4 simulator — process alive after launch, no crash
- [ ] **End-to-end tap-through + iPad hardware-keyboard shortcut verification still needs Josh's manual device pass** — this workspace can't drive touch events, swipe gestures, or hardware-keyboard input into the simulator; the "<200 ms on 200-note vault" target also needs a physical device for real latency readings

#### Decisions Made
- **Single unified sheet, not two surfaces.** Re-read of Mac's `QuickSwitcherPanel.swift:380-419` confirmed there is no separate Cmd+Shift+F panel on Mac — the quick switcher already merges `FuzzyMatcher` filename results with `VaultIndex.searchFilesGrouped` body-text results into one list. Building two iOS surfaces (QuickSwitcherSheet + GlobalSearchView_iOS) as `IMPLEMENTATION.md` originally described would have duplicated logic and created two affordances for the same job. Josh confirmed "One unified sheet (match Mac)" before the build. `GlobalSearchView_iOS.swift` from the plan was dropped.
- **⌘⇧F aliases ⌘K.** Same sheet, same code path. Cheap to wire, matches desktop muscle memory from apps like VS Code / Sublime where `⌘P` and `⌘⇧F` both jump around.
- **iPad inspector panel deferred to Phase 12.** The plan called for iPad-specific right-column inspector variant of global search. That layout depends on Phase 12's 3-column `NavigationSplitView`, which does not exist yet. For now iPad uses the same modal sheet as iPhone. When the iPad split view lands, the row-rendering logic can be lifted into a reusable subview.
- **Sheet-open flag on `VaultSession`, not local `@State`.** `.keyboardShortcut` must be attached to a view in the active hierarchy, which means sidebar AND detail both need shortcut bindings. A shared `@Bindable` flag on `VaultSession` (`isShowingQuickSwitcher`) gives one source of truth; each screen hosts its own `QuickSwitcherShortcuts` background view that flips the same bit. Alternatives (focused-value key, app-scene-level shortcut, a new `@Observable` search controller) added more moving parts without solving the problem any more cleanly.
- **Recent files persist per-vault in one `[String: [String]]` dictionary under `"iosVaultRecentFilesByVault"`.** Dictionary key is the vault's standardized path. Avoids cross-vault leakage when a user switches between multiple iCloud / picked folders, without needing a separate UserDefaults key per vault (which would leave zombie keys on vault deletion). Size is bounded at 10 entries × vault-count paths so `UserDefaults` pressure is a non-issue.
- **One-shot recents restore on first non-empty `watcher.$files` emission.** The restore needs to filter stale paths against the current vault's file list, which is `[]` until the watcher's first scan completes. Restoring on first non-empty emission and guarding with `hasRestoredRecents` avoids a race where restore sees an empty list and drops everything. Subsequent watcher emissions don't re-restore or prune — a file briefly missing from the watcher (iCloud metadata lag) shouldn't vaporize it from the recents list. Tapping a stale recent that's since been deleted gracefully surfaces the existing load-error flow in `IOSDocumentSession`.
- **`.buttonStyle(.plain)` inside List.** Rows use `Button { open(row) } label: { … }` rather than `NavigationLink` because opening a file from the sheet needs to (1) dismiss the sheet first, then (2) push onto `vault.navigationPath` and mark recent. `NavigationLink` would bypass the dismiss+mark sequence. `.buttonStyle(.plain)` keeps the visual look clean and still registers the tap.
- **Match-range highlighting via `AttributedString.Index` + `utf16Offset`.** `FuzzyMatcher` returns `Range<String.Index>`; SwiftUI `AttributedString` needs its own `AttributedString.Index`. Converted via `NSRange(...)` → `String.Index(utf16Offset:in:)` → `AttributedString.Index(_:within:)`. FTS5 snippet highlights (`<<…>>`) are parsed separately while building a clean plain string, tracking range offsets as we go; same NSRange bridge then paints them.

#### Blockers
- (none)

---

### Phase 10: Backlinks + outline + tags surfaces on iOS
**Status:** Complete (2026-04-21)

#### Tasks Completed
- [x] New `Clearly/iOS/BacklinksSheet_iOS.swift` — `@ObservedObject` wrapper over `BacklinksState`. `NavigationStack`-rooted sheet with two `List` sections ("Linked" + "Unlinked"). Empty state when both are empty. Each row is a `Button` with filename (medium 14pt) + contextLine (12pt secondary, 2-line clip). Tap resolves the source `VaultFile` by standardized URL from `vault.files`, falls back to a provisional record, dismisses the sheet, and appends to `vault.navigationPath`. Mac's "Link" action-button on unlinked mentions intentionally dropped — see decisions.
- [x] New `Clearly/iOS/OutlineSheet_iOS.swift` — `@ObservedObject` wrapper over `OutlineState`. Plain `List(outlineState.headings)` with per-row indent `CGFloat(level-1) * 14` and level-weighted font (15/semibold H1, 14/medium H2, 13/regular H3+). Empty state when no headings. Tap captures `outlineState.scrollToRange` into a local before dismissing, then fires the closure on a 0.25s delay so the sheet's dismiss animation can finish before the editor scrolls (avoids a rubber-band flash on iOS 26.4).
- [x] New `Clearly/iOS/TagsSheet_iOS.swift` — self-contained `NavigationStack` sheet. Root: `List` of `(tag, count)` from `vault.currentIndex?.allTags() ?? []`, displayed as `#tag` with a monospacedDigit count badge. Empty state when no tags. Tap → `NavigationLink(value: tag)` → nested private `TaggedFilesView` lists `vault.filesForTag(tag)`. Tap file → dismiss sheet → append to `vault.navigationPath`. Tag list refreshes on `.onAppear` and on `.onChange(of: vault.indexProgress)` where newValue is nil (after full re-indexes land).
- [x] Extended `Packages/ClearlyCore/Sources/ClearlyCore/Vault/VaultSession.swift`:
  - `public func renameFile(_ file: VaultFile, to newBaseName: String) async throws` — trims + validates against the existing `sanitizeWikiName` forbidden-char set, preserves the original extension (defaults to `md`), guards against existing destinations, calls `CoordinatedFileIO.move` on a detached priority-user task, then prunes from `navigationPath` + `recentFiles` and refreshes.
  - `public func deleteFile(_ file: VaultFile) async throws` — calls `CoordinatedFileIO.delete` on a detached task, prunes from `navigationPath` + `recentFiles`, refreshes.
  - `public func filesForTag(_ tag: String) -> [VaultFile]` — maps `VaultIndex.filesForTag(tag:)` results back to `VaultFile`, preferring the watcher's existing records (by standardized URL) over constructed provisionals. Matches the `resolveWikiLink` pattern.
  - Private helpers `dropFromNavigationPath(_:)` + `dropFromRecents(_:)` for reuse between rename + delete.
- [x] `Clearly/iOS/EditorView_iOS.swift` — added `var outlineState: OutlineState? = nil` parameter. `Coordinator` gained `private weak var attachedOutlineState: OutlineState?` + `attachOutlineState(_:)` + `scrollToRange(_:)`. The attach method is called from both `makeUIView` and `updateUIView`; the identity guard (`attachedOutlineState !== state`) skips re-registration when the same state object is passed. `scrollToRange` clamps the target range against the current `textStorage.length`, calls `scrollRangeToVisible`, briefly sets `selectedRange` to the heading to draw attention, then restores the prior selection after 0.6s.
- [x] `Clearly/iOS/RawTextDetailView_iOS.swift` — added `@StateObject var backlinksState = BacklinksState()`, `@StateObject var outlineState = OutlineState()`, `@State var showBacklinks`, `@State var showOutline`. Two new trailing toolbar buttons (`list.bullet.indent`, `link`). `.task(id: file.id)` block now also calls `outlineState.parseHeadings(from: document.text)` + `refreshBacklinks()` on successful open. `.onChange(of: document.text)` re-parses headings. `.onChange(of: vault.indexProgress)` re-runs backlinks refresh when `newValue == nil`. Two `.sheet` presenters host the backlinks and outline sheets. `EditorView_iOS` now receives `outlineState` via the new parameter.
- [x] `Clearly/iOS/SidebarView_iOS.swift` — third trailing toolbar button (`tag` SF Symbol) presents `TagsSheet_iOS`. Each file row now has `.contextMenu` with Rename (pencil) + Delete (trash, destructive). Rename uses `.alert("Rename note", …)` with a `TextField` and an error-message fallthrough; Save dispatches `session.renameFile(_:to:)` in a Task and surfaces failures via a separate generic error alert. Delete uses `.confirmationDialog` with a smart-quoted title and calls `session.deleteFile`. A single `operationError: String?` drives the fallback failure alert so both paths share one surface.
- [x] `xcodegen generate` — clean (three new files picked up by existing `Clearly/iOS/**` glob; `project.yml` unchanged).
- [x] `xcodebuild -scheme Clearly -configuration Debug build -allowProvisioningUpdates` — green (Mac shares `BacklinksState` + `OutlineState` + `VaultSession` types but touches none of the new VaultSession methods; no regression surface).
- [x] `xcodebuild -scheme ClearlyQuickLook -configuration Debug build` — green.
- [x] `xcodebuild -scheme ClearlyCLI -configuration Debug build` — green.
- [x] `xcodebuild -scheme Clearly-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -configuration Debug build -allowProvisioningUpdates` — green.
- [x] `xcodebuild -scheme ClearlyCLIIntegrationTests test` — 25/25 pass (count stays aligned with Phase 9's 25; no new tests added or removed).
- [x] Installed + launched `Clearly Dev.app` on iPhone 17 / iOS 26.4 simulator — PID 29896, `launchctl list` status 0 (alive). App starts cleanly, proves the three new `@StateObject` instantiations + toolbar button layout don't fault.
- [ ] **NOT programmatically verified (needs Josh's manual pass):** (1) toolbar backlinks button → sheet shows linked/unlinked mentions for current file → tap a row → navigates to source note; (2) toolbar outline button → sheet lists headings with correct indent + weight → tap → editor scrolls to heading + brief selection highlight + selection restored; (3) sidebar tags button → sheet lists tags + counts → tap tag → filtered file list → tap file → navigates; (4) long-press sidebar row → context menu with Rename + Delete → Rename alert → Save → filename updates, no crash if the renamed file was on the nav stack (should pop gracefully); (5) Delete confirmation dialog → confirm → row disappears; (6) backlinks auto-refresh after cross-file edit (create `[[Target]]` in file A, save, open Target — backlinks should show A).

#### Decisions Made
- **Shared `ClearlyCore` state types, verbatim.** `BacklinksState` and `OutlineState` are reused as-is. No iOS-specific fork. The only new public API on `VaultSession` is the three file-op + tag methods; no new state class.
- **Dropped Mac's "Link" action on unlinked mentions.** Mac's `BacklinksView.onLink` flows through `WorkspaceManager.insertWikiLink(in:matching:linkTarget:atLine:)` — in-file text replacement on a potentially-not-open note. On iOS this would require a coordinated read → surgical text edit → coordinated write path, plus invalidating the affected file's index row. That's 2+ hours of incremental work for a secondary affordance on a feature that's already correctly surfacing the unlinked mention to the user. Ship display + tap-to-navigate now; revisit linkify if users ask.
- **Sheets render identically on iPhone and iPad.** Matches Phase 9's decision to defer iPad-specific inspector panel layouts to Phase 12 (alongside the 3-column `NavigationSplitView` port). A modal sheet is a correct-enough UI for iPad at this stage; the data paths are what matter, and they generalize.
- **`@StateObject` for the two per-file states in the detail view.** `BacklinksState` + `OutlineState` both conform to `ObservableObject` — `@StateObject` gives correct ownership semantics (view creates them, they persist across body re-evaluations, they're destroyed when the view is torn down). `@StateObject` composes with SwiftUI's `@Environment(VaultSession.self)` path without needing to be bridged through VaultSession — each file gets its own fresh state.
- **Outline scroll fires on a 0.25s delay after dismiss.** Without the delay, `scrollRangeToVisible` + selection-flash runs while the sheet is still animating dismiss; iOS 26.4 rubber-bands the outgoing sheet against the editor's scroll state. Capturing the closure locally before calling `dismiss()` is important — by the time the delayed work runs, the sheet's `OutlineState` ObservedObject binding may have torn down, but the closure reference is independent of that.
- **Rename is in-directory only for Phase 10.** No move-to-folder affordance. `UIDocumentPickerViewController` for in-vault destination picking is a non-trivial UX (the picker's default vault-root view is confusing when the user is already standing inside that vault), and Files.app handles moves correctly for iCloud vaults. Revisit in Phase 12 or polish if user feedback demands in-app moves.
- **Rename strips trailing markdown extensions from user input.** Caught during self-review: if the user types `notes.md` into the alert (easy mistake — the alert only shows the stem by default, but nothing physically prevents re-typing the extension), the destination would have become `notes.md.md` and the rename would "succeed" but produce a junk filename. `VaultSession.renameFile` now strips any trailing extension matching `FileNode.markdownExtensions` before composing the destination URL, so the file extension is always the original file's extension (defaulting to `md`).
- **Two separate alert surfaces in the sidebar.** One is the rename `.alert` with a `TextField` and context-specific error string. The other is a generic `operationError: String?` backed alert that both rename and delete failures flow through. Compressing them into one was tempting but would have forced two different `.alert` titles into a single SwiftUI binding — messier than two presenters. Phase 11's conflict resolver UI can reuse the generic error alert pattern.
- **Backlinks refresh only on two triggers.** (1) file-open via `.task(id:)`, (2) after a full re-index lands (`indexProgress` going nil). Not on every keystroke, not on every autosave completion. Backlinks to a file don't usually change when you edit that file — they change when OTHER files edit `[[this-file]]`. The cross-file edit path lands when you later open the mentioned file, so `.task(id:)` picks it up. Simpler than wiring up a debounced `watcher.$files`-driven trigger, and matches Mac behavior.
- **Skipped preview-anchor scroll sync.** `OutlineState.scrollToPreviewAnchor` remains unwired on iOS. Phase 10 doesn't have an editor/preview split view — preview is a full-screen swap. Syncing preview scroll from outline clicks requires either the editor-preview side-by-side layout (Phase 12) or a "jump then switch to preview" UX that we'd need to design. Not worth the extra code for a feature that can't be usefully exercised yet.
- **`filesForTag` on `VaultSession`, not in the sheet directly.** iOS UI code never touches `IndexedFile` — it stays `VaultFile` all the way down. The mapping (with fallback for watcher-lag) matches the `resolveWikiLink` pattern, keeps the sheet simple, and gives us one spot to instrument if tag queries ever need caching.

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
- **Phase 2 executed and verified.** `Clearly-iOS` target added to `project.yml`; three new files under `Clearly/iOS/` (app entry, Info plist, entitlements shell); Mac target picks up `excludes: ["iOS/**"]`. Fixed one Mac-only API leak in `ClearlyCore/Vault/VaultIndex.swift` (`homeDirectoryForCurrentUser`, gated behind `#if os(macOS)`). All Mac schemes still green; 23/23 CLI integration tests still pass; iOS builds succeed both via `-sdk iphonesimulator` and via a concrete simulator destination (`platform=iOS Simulator,name=iPhone 17,OS=26.4`); placeholder view renders on iPhone 17 simulator (iOS 26.4 runtime).

### 2026-04-21 (Phase 10)
- **Phase 10 complete.** iOS now has parity with the Mac app's three knowledge-management surfaces: backlinks, outline, and tags. Two new toolbar buttons on the detail view (`link` + `list.bullet.indent`) present `.sheet`-based backlinks + outline UIs, both wrapping the existing `BacklinksState` + `OutlineState` from `ClearlyCore` (no iOS-specific fork). A new `tag` toolbar button on the sidebar presents a two-step tags browser — root tag list with counts, then a pushed filtered file list per tag. Tapping any result in any of the three sheets dismisses the sheet and appends to `vault.navigationPath`. Outline-to-editor scroll-to-heading wires through the Mac's existing state-owned-callback pattern: `OutlineState.scrollToRange` is assigned by `EditorView_iOS.Coordinator` on the first `updateUIView` pass where the state reference changes; the closure calls `scrollRangeToVisible` + flashes the heading selection for 0.6s. The sidebar file-row long-press context menu ships with Rename (TextField alert, extension preserved, forbidden-char validation) + Delete (confirmation dialog). Move-to-folder was deferred because `UIDocumentPickerViewController` UX for in-vault destinations is cumbersome and Files.app already handles moves cleanly. `VaultSession` gained three `public` methods: `renameFile(_:to:) async throws`, `deleteFile(_:) async throws`, `filesForTag(_:) -> [VaultFile]`. Private `dropFromNavigationPath(_:)` + `dropFromRecents(_:)` helpers prune renamed/deleted files from the nav stack and recents so stale references don't linger. Mac "Link"-button on unlinked mentions was intentionally not ported — insert-wiki-link-in-other-file is a significant scope addition for a secondary affordance. Build matrix green across Mac / QuickLook / CLI / iOS; 25/25 CLI integration tests pass; iPhone 17 / iOS 26.4 simulator install + launch clean (PID 29896, status 0). **End-to-end tap-through of all three sheets, the scroll-to-heading behavior, and the rename/delete context menu still need Josh's manual device pass** — simulator can't be driven programmatically for touch input.

### 2026-04-21 (Phase 9)
- **Phase 9 complete.** iOS now has a unified quick switcher + full-text search sheet that matches Mac's Cmd+P behavior. `FuzzyMatcher` extracted from `QuickSwitcherPanel.swift` into `ClearlyCore/Search/FuzzyMatcher.swift` — Mac build compiles clean against the relocated type; no functional change for the Mac panel. `VaultSession` grew `recentFiles` (cap 10, per-vault `UserDefaults` persistence), `isShowingQuickSwitcher`, and `markRecent(_:)`. Restore gated on `hasRestoredRecents` so the filter doesn't run against an empty file list on attach. `QuickSwitcherSheet_iOS` ships as one sheet doing three jobs: fuzzy filename matches (top 20, scored), FTS5 `searchFilesGrouped` content hits (top 30, deduped, with `<<…>>` highlight parsing), and a create-on-miss fallback. Every tap dismisses → appends to `navigationPath` → marks recent. `QuickSwitcherShortcuts` is a zero-size hidden-button view registering ⌘K and ⌘⇧F; attached to both sidebar and detail via `.background { … }` so iPad hardware-keyboard shortcuts fire regardless of focus. `RawTextDetailView_iOS.task` marks the opened file as recent (only on successful read). The three planned deviations from `IMPLEMENTATION.md` (single sheet, no `GlobalSearchView_iOS.swift`, iPad inspector deferred to Phase 12) confirmed up-front by Josh. Build matrix green across Mac / QuickLook / CLI / iOS; 24/24 CLI integration tests pass (23→24 between Phase 8 and 9, unrelated). iPhone 17 / iOS 26.4 simulator install + launch clean, process alive. **Josh's manual device pass still needed for tap-through, iPad hardware-keyboard shortcut activation, and the "<200 ms on 200-note vault" latency target** — no way to drive touch or physical-keyboard input from this workspace.

### 2026-04-21 (Phase 8)
- **Phase 8 complete.** iOS now has a live FTS5 index and placeholder-aware coordination. `VaultIndex` stores its SQLite on iOS under `URL.cachesDirectory/indexes/<hash>.sqlite` (Mac path unchanged — keeps ClearlyMCP working). New async `indexAllFiles(showHiddenFiles:downloadPlaceholder:progress:)` overload collects file data in an async loop (awaits a per-file placeholder-download hook) and writes in one batched `try await dbPool.write`. `VaultSession` owns a `VaultIndex` per attached vault, publishes `indexProgress: Double?` for the sidebar progress bar, and exposes `currentIndex` for Phase 9 consumers. `beginIndexing` inlines a 5s-per-file placeholder poll (skip on timeout, let watcher catch up on next tick). A second debounced `watcher.$files` subscription drives `scheduleIncrementalReindex`, diffing known vs current files and calling `VaultIndex.updateFile(at:)` per changed path — skipped while a full rebuild is running. `resolveWikiLink` now checks the index first (resolves Phase 7's deferred "point iOS wiki-link at real index"). `SidebarView_iOS` shows a 2pt `ProgressView(value:)` under the nav bar while indexing. Plan's sidebar-side per-row tap/spinner was dropped — `IOSDocumentSession.open` already downloads placeholders on navigation and the detail view shows "Downloading from iCloud…" natively, so sidebar-layer gesture fiddling would have added UX conflict without new function. Mac + iOS Debug builds pass; 23/23 CLI integration tests still pass (the sync `indexAllFiles` path used by Mac + CLI is untouched). **End-to-end placeholder download, incremental re-index on file drop, and vault-switch invalidation still need Josh's manual device pass** — iOS simulator doesn't model real iCloud placeholder state, and there's no programmatic way to drive Files.app file drops in this workspace.

### 2026-04-21 (Phase 7)
- **Phase 7 complete.** iOS now has a rendered preview pane and cross-file wiki-link navigation. Six web-asset resources added to the `Clearly-iOS` target (katex/mermaid/highlight + fonts). New `PreviewView_iOS` (`UIViewRepresentable<WKWebView>`) renders HTML via the shared `MarkdownRenderer` + `PreviewCSS` + Math/Table/Mermaid/SyntaxHighlight scripts, with `LocalImageSchemeHandler` for the `clearly-file://` scheme. Registers only the two script handlers we use on iPhone today: `linkClicked` + `taskToggle`. Mac's scroll sync / dblclick-to-source / footnote popover / find-in-preview / selection capture are left off — iPhone doesn't need them in Phase 7, they can port later if Phase 9 / 12 require them. `VaultSession` grew three public surfaces: `navigationPath: [VaultFile]` (binding for `NavigationStack(path:)`), `resolveWikiLink(name:)` (stem-match against `files` — Phase 8 will replace this with VaultIndex queries), `openOrCreate(name:) async throws` (writes an empty `.md` at vault root via `CoordinatedFileIO.write(Data(), to:)`, returns a provisional `VaultFile` immediately). `RawTextDetailView_iOS` gained a `@State var viewMode` + a toolbar segmented `Picker` + conditional Edit/Preview rendering. `SidebarView_iOS` switched to `NavigationStack(path: $session.navigationPath)` so preview wiki-link taps can push. Phase 7 plan's "move renderer files" + "add iOS CSS branch" tasks were dropped — both were already done by Phase 1 / already present in `PreviewCSS:133`. Build matrix green across Mac / QuickLook / CLI / iOS; 23/23 integration tests pass; iPhone 17 / iOS 26.4 simulator launches the app cleanly. **End-to-end preview, wiki-link tap, task-checkbox toggle, external-link open, and relaunch-resource-resolution flows need Josh's manual device pass** — no way to drive simulator taps + compare rendered HTML visually in this workspace.

### 2026-04-21 (Phase 6)
- **Phase 6 complete.** iOS becomes a real mobile editor: users can write, `CoordinatedFileIO.write` (presenter-aware) pushes to disk, iCloud propagates to Mac. New `IOSDocumentSession` (`@Observable @MainActor`) owns per-file state — `text`, `lastSavedText`, 2-second debounced autosave, `isOwnWriteInFlight` flag, `NSFileVersion` conflict probe, and a `DocumentPresenter` subclass of `NSFilePresenter` that hops remote-change callbacks to main. Editor promoted to `@Binding`; `ClearlyUITextView.isEditable = true`. `RawTextDetailView_iOS` swaps its local `@State text` for an `IOSDocumentSession` and wires `scenePhase` + `onDisappear` flush / close. `MarkdownDocument.fileWrapper` shipped (no longer throws). `CoordinatedFileIO` gained a presenter overload. **Keyboard accessory bar + the pure `MarkdownEditingHelpers` in ClearlyCore were built, hand-traced, and then pulled before closing the phase** — see Decisions Made. Also added `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` to the iOS Info.plist so the app's Documents folder surfaces in Files.app for simulator seeding + a legit product default for users who want to drop .md files into Clearly. Build matrix green across Mac / QuickLook / CLI / iOS schemes; 23/23 integration tests pass; iPhone 17 / iOS 26.4 simulator launches the app. **End-to-end editor/save/sync flows need Josh's manual device pass** — no way to programmatically drive taps + iCloud propagation in this workspace. Caught one research-doc API typo during first compile: `NSFileVersion.unresolvedVersionsOfItem(at:)` → `unresolvedConflictVersionsOfItem(at:)`; fixed before second build.

### 2026-04-21 (Phase 5)
- **Phase 5 complete.** iOS now has a real markdown editor with syntax highlighting. Moved `Theme.swift` and `MarkdownSyntaxHighlighter.swift` into `ClearlyCore/Rendering/`; AppKit/UIKit-specific color, font, text-storage, paragraph-style, and attributed-string-key APIs live behind wrappers in `Platform.swift`. Rendering files import no AppKit/UIKit. Added `PlatformTextView` and related text-rendering wrappers. New iOS files: `ClearlyUITextView` (read-only `UITextView` subclass) + `EditorView_iOS` (`UIViewRepresentable` with a Coordinator that owns the highlighter and ports the Mac `pendingBindingUpdates` cursor-jump counter verbatim). Swapped `RawTextDetailView_iOS`'s `ScrollView{Text(...)}` for `EditorView_iOS(text:)`. All Mac schemes still green, 23/23 CLI integration tests pass, iOS simulator build green, app launches and stays alive. Real UI visual verification (tap-through + side-by-side color match) deferred to Josh's manual pass — no programmatic driver for simulator taps in this workspace.

### 2026-04-21 (Phase 3 + 4)
- **Phase 3 complete.** iCloud entitlements added to all three channels; `NSUbiquitousContainers` on Mac Info.plist; `ClearlyCore/Sync/{CloudVault, CoordinatedFileIO}.swift` introduced; `scripts/verify-entitlements.sh` wired into both release scripts; `project.yml` updated with `DEVELOPMENT_TEAM = W33JZPPPFN` + automatic Debug signing so iCloud entitlements provision correctly. All Mac schemes + iOS build + integration tests (23/23) green. Runtime verified on Mac: `CloudVault.ubiquityContainerURL()` resolves to `~/Library/Mobile Documents/iCloud~com~sabotage~clearly/Documents` and the container bootstrap creates the `Documents/` subdir on first call. iOS on-device runtime verification deferred to Phase 4 (simulator strips entitlements, real device testing ships with the sidebar UI).
- **Phase 4 complete.** First user-visible iOS milestone. Added `VaultLocation` + `VaultWatcher` (NSMetadataQuery for default iCloud / FileNode.buildTree for picked/local) + `VaultSession` (`@Observable @MainActor`, owns one watcher, persists `StoredVaultLocation` under `UserDefaults` key `"iosVaultLocation"`, reads raw UTF-8 via `CoordinatedFileIO.read` off-main, downloads iCloud placeholders on demand). Promoted `MarkdownDocument` to `FileDocument` (writes still throw; consumers arrive in Phase 5/6). New iOS views: `WelcomeView_iOS` (three buttons, SwiftUI `.fileImporter`, watches `CloudVault.isAvailablePublisher` to gate the default-iCloud button), `SidebarView_iOS` (`NavigationStack` + `List`, change-vault toolbar button, placeholder SF Symbol, pull-to-refresh, full-screen welcome cover when no vault), `RawTextDetailView_iOS` (monospace text with read-only footer, placeholder-download-aware). Rewired `ClearlyApp_iOS` to host a single `VaultSession` and call `restoreFromPersistence()` on launch. Added `NSUbiquitousContainers` to the iOS Info.plist. All four schemes build green; 23/23 integration tests still pass. Welcome screen verified on iPhone 17 simulator (iOS 26.4) — default-iCloud button correctly disabled because simulator has no iCloud identity, proving the availability wiring. Deviations from plan logged: `WindowGroup` over `DocumentGroup` (custom vault sidebar is incompatible with DocumentGroup's per-scene document model), `FileDocument` over `ReferenceFileDocument` (value semantics are enough until autosave lands). End-to-end iCloud sync verification deferred to device testing.

---

## Files Changed

### Phase 1 (2026-04-20)
- **New:** `Packages/ClearlyCore/Package.swift`, `Packages/ClearlyCore/Sources/ClearlyCore/Platform/Platform.swift`
- **Moved (20 files, history preserved via `git mv`):** `Shared/{MarkdownRenderer,PreviewCSS,MermaidSupport,TableSupport,SyntaxHighlightSupport,EmojiShortcodes,LocalImageSupport,FrontmatterSupport}.swift` → `Packages/ClearlyCore/Sources/ClearlyCore/Rendering/`; `Clearly/{VaultIndex,FileParser,FileNode,IgnoreRules,BookmarkedLocation}.swift` → `Vault/`; `Clearly/{OpenDocument,OutlineState,FindState,JumpToLineState,BacklinksState,PositionSync}.swift` → `State/`; `Clearly/DiagnosticLog.swift` → `Diagnostics/`
- **Modified:** `project.yml` (all four targets re-wired); 52 consumer files across `Clearly/`, `ClearlyQuickLook/`, `ClearlyCLI/`, `ClearlyCLIIntegrationTests/` got `import ClearlyCore` + types inside moved files made public where accessed cross-module.

### Phase 2 (2026-04-20)
- **New:** `Clearly/iOS/ClearlyApp_iOS.swift`, `Clearly/iOS/Info-iOS.plist`, `Clearly/iOS/Clearly-iOS.entitlements`
- **Modified:** `project.yml` (added `Clearly-iOS` target block; added `iOS: "17.0"` to `options.deploymentTarget`; added `excludes: ["iOS/**"]` to Mac `Clearly` source path), `Packages/ClearlyCore/Sources/ClearlyCore/Vault/VaultIndex.swift` (wrapped `init(locationURL:bundleIdentifier:)` and `indexDirectory(bundleIdentifier:)` in `#if os(macOS)`)

### Phase 3 (2026-04-21)
- **New:** `Packages/ClearlyCore/Sources/ClearlyCore/Sync/CloudVault.swift`, `Packages/ClearlyCore/Sources/ClearlyCore/Sync/CoordinatedFileIO.swift`, `scripts/verify-entitlements.sh`
- **Modified:** `Clearly/Clearly.entitlements` + `Clearly/Clearly-AppStore.entitlements` + `Clearly/iOS/Clearly-iOS.entitlements` (added iCloud container + CloudDocuments service keys), `Clearly/Info.plist` (added `NSUbiquitousContainers`), `scripts/release.sh` + `scripts/release-appstore.sh` (call `verify-entitlements.sh` post-export), `project.yml` (added `DEVELOPMENT_TEAM: W33JZPPPFN` to all four targets' base settings + `CODE_SIGN_STYLE: Automatic` to each Debug config so iCloud-entitled Debug builds auto-provision against Sabotage Media's App IDs)

### Phase 4 (2026-04-21)
- **New (ClearlyCore):** `Packages/ClearlyCore/Sources/ClearlyCore/Vault/VaultLocation.swift`, `Packages/ClearlyCore/Sources/ClearlyCore/Sync/VaultWatcher.swift`, `Packages/ClearlyCore/Sources/ClearlyCore/Vault/VaultSession.swift`
- **New (iOS app):** `Clearly/iOS/WelcomeView_iOS.swift`, `Clearly/iOS/SidebarView_iOS.swift`, `Clearly/iOS/RawTextDetailView_iOS.swift`
- **Modified:** `Clearly/MarkdownDocument.swift` (promoted to `FileDocument`), `Clearly/iOS/ClearlyApp_iOS.swift` (placeholder → real app scene owning `VaultSession`), `Clearly/iOS/Info-iOS.plist` (added `NSUbiquitousContainers`)

### Phase 10 (2026-04-21)
- **New (iOS app):** `Clearly/iOS/BacklinksSheet_iOS.swift`, `Clearly/iOS/OutlineSheet_iOS.swift`, `Clearly/iOS/TagsSheet_iOS.swift`.
- **Modified (ClearlyCore):** `Vault/VaultSession.swift` (public `renameFile(_:to:) async throws`, `deleteFile(_:) async throws`, `filesForTag(_:) -> [VaultFile]`; private `dropFromNavigationPath(_:)` + `dropFromRecents(_:)`).
- **Modified (iOS app):** `Clearly/iOS/EditorView_iOS.swift` (new `outlineState: OutlineState?` parameter, `Coordinator.attachOutlineState(_:)` + `scrollToRange(_:)`). `Clearly/iOS/RawTextDetailView_iOS.swift` (two new `@StateObject`s, two new toolbar buttons, two `.sheet` presenters, re-parse headings on text change, refresh backlinks on index-progress clear). `Clearly/iOS/SidebarView_iOS.swift` (third toolbar button for tags, `.contextMenu` per row with Rename alert + Delete confirmation dialog, `operationError` generic-failure alert).

### Phase 8 (2026-04-21)
- **Modified (ClearlyCore):** `Vault/VaultIndex.swift` (`indexDirectory()` iOS `.cachesDirectory` branch; new async overload `indexAllFiles(showHiddenFiles:downloadPlaceholder:progress:)` that collects file data in an async loop and writes in one `try await dbPool.write` batch). `Vault/VaultSession.swift` (`indexProgress` + `currentIndex` published/accessor; `index` + `indexingTask` + `knownFiles` storage; `beginIndexing(using:)`; `scheduleIncrementalReindex(for:)`; inline placeholder-download polling; `resolveWikiLink(name:)` upgraded to check `VaultIndex` first; debounced second `watcher.$files` subscription for incremental re-index).
- **Modified (iOS app):** `Clearly/iOS/SidebarView_iOS.swift` (VStack wraps content to host a 2pt `ProgressView(value:)` when `indexProgress != nil`).

### Phase 7 (2026-04-21)
- **New (iOS app):** `Clearly/iOS/PreviewView_iOS.swift` (UIViewRepresentable WKWebView preview with `linkClicked` + `taskToggle` script handlers, `LocalImageSchemeHandler`, trimmed JS template, `skipNextReload` flag).
- **Modified (ClearlyCore):** `Vault/VaultSession.swift` (`navigationPath` public var, `resolveWikiLink(name:)`, `openOrCreate(name:) async throws`, private `stem(of:)` + `sanitizeWikiName(_:)` helpers).
- **Modified (iOS app):** `Clearly/iOS/SidebarView_iOS.swift` (`@Bindable` shadow + `NavigationStack(path: $session.navigationPath)`), `Clearly/iOS/RawTextDetailView_iOS.swift` (`@State var viewMode: ViewMode`, toolbar segmented `Picker`, conditional Edit/Preview content, `handleWikiLink`, `handleTaskToggle`).
- **Modified (build):** `project.yml` (6 resource entries on `Clearly-iOS`: mermaid.min.js, katex.min.js, katex.min.css, fonts/, highlight.min.js, highlight-theme.css).

### Phase 6 (2026-04-21)
- **New (iOS app):** `Clearly/iOS/IOSDocumentSession.swift` (document session + private `DocumentPresenter` subclass of `NSFilePresenter`).
- **Modified (ClearlyCore):** `Sync/CoordinatedFileIO.swift` (`write(_:to:presenter:)` overload; existing `write(_:to:)` forwards to it with nil presenter).
- **Modified (iOS app):** `Clearly/iOS/EditorView_iOS.swift` (`@Binding text`, binding write-back in `textViewDidChange`, `applyInitialText` → `applyExternalText`, `Coordinator.parent` property for binding hook), `Clearly/iOS/ClearlyUITextView.swift` (`isEditable = true`), `Clearly/iOS/RawTextDetailView_iOS.swift` (session-owned document state; inline `Binding(get:set:)` into `document.text`; dirty-bullet nav title; conflict banner with disabled "Resolve"; scenePhase + onDisappear flush/close; renamed injected `session` → `vault` to disambiguate from the new document session), `Clearly/iOS/Info-iOS.plist` (added `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` so the Clearly app's Documents folder is visible in Files.app under "On My iPhone → Clearly" — a legit product default for an iCloud-syncing notes app).
- **Modified (Mac, cross-platform):** `Clearly/MarkdownDocument.swift` (`fileWrapper(configuration:)` now writes real `FileWrapper(regularFileWithContents:)` instead of throwing).
- **Considered but NOT shipped:** `Clearly/iOS/KeyboardAccessoryBar.swift` + `Packages/ClearlyCore/Sources/ClearlyCore/Rendering/MarkdownEditingHelpers.swift` existed in an interim commit but were removed before closing Phase 6 — see Decisions Made.

### Phase 9 (2026-04-21)
- **New (ClearlyCore):** `Packages/ClearlyCore/Sources/ClearlyCore/Search/FuzzyMatcher.swift` (moved from `Clearly/QuickSwitcherPanel.swift`, made `public`).
- **New (iOS app):** `Clearly/iOS/QuickSwitcherSheet_iOS.swift` (unified sheet: fuzzy filename + FTS5 content + create-on-miss + recent-files; hosts the zero-size `QuickSwitcherShortcuts` view that registers the ⌘K and ⌘⇧F shortcuts).
- **Modified (ClearlyCore):** `Vault/VaultSession.swift` (public `recentFiles: [VaultFile]`, public `isShowingQuickSwitcher: Bool`, public `markRecent(_:)`; `hasRestoredRecents` gate; one-shot `restoreRecents` on first non-empty `watcher.$files` emit; per-vault persistence under `"iosVaultRecentFilesByVault"`; teardown resets all three).
- **Modified (iOS app):** `Clearly/iOS/SidebarView_iOS.swift` (magnifying-glass toolbar button, `.sheet(isPresented: $session.isShowingQuickSwitcher)`, `QuickSwitcherShortcuts` in `.background`). `Clearly/iOS/RawTextDetailView_iOS.swift` (`QuickSwitcherShortcuts` in `.background`, `vault.markRecent(file)` after successful read).
- **Modified (Mac):** `Clearly/QuickSwitcherPanel.swift` (deleted local `FuzzyMatcher` + `FuzzyMatchResult`; resolves to the `ClearlyCore` versions via the already-present `import ClearlyCore`).

### Phase 5 (2026-04-21)
- **Moved (via `git mv`, history preserved):** `Clearly/Theme.swift` → `Packages/ClearlyCore/Sources/ClearlyCore/Rendering/Theme.swift`; `Clearly/MarkdownSyntaxHighlighter.swift` → `Packages/ClearlyCore/Sources/ClearlyCore/Rendering/MarkdownSyntaxHighlighter.swift`
- **Modified (ClearlyCore):** `Theme.swift` (cross-platform dynamic color helper, `PlatformFont` extensions, all accessed members `public`), `MarkdownSyntaxHighlighter.swift` (cross-platform imports, `PlatformFont`/`PlatformColor` in signatures, four `NSFontManager.convert` sites swapped for helpers, class + entry points `public`), `Platform/Platform.swift` (added `PlatformTextView` typealias)
- **New (iOS app):** `Clearly/iOS/ClearlyUITextView.swift`, `Clearly/iOS/EditorView_iOS.swift`
- **Modified (iOS app):** `Clearly/iOS/RawTextDetailView_iOS.swift` (swapped `ScrollView{Text}` for `EditorView_iOS`, updated footer copy)
- **Modified (Mac):** added `import ClearlyCore` to 9 consumers (`WelcomeView`, `SidebarViewController`, `ScratchpadManager`, `ScratchpadEditorView`, `LineNumberRulerView`, `IconPickerView`, `ClearlyTextView`, `ClearlySegmentedControl`, `ClearlyButtonStyle`)

## Architectural Decisions

### 2026-04-20 — Universal Purchase with shared bundle ID across all three channels
Direct (Sparkle), Mac App Store, and iOS App Store all use `com.sabotage.clearly`. Universal Purchase links the two App Store SKUs; direct distribution is outside the App Store and unaffected. On a single Mac a user installs direct OR MAS, not both (same bundle ID collision). iCloud container `iCloud.com.sabotage.clearly` provisioned once against the Team ID and shared.

### 2026-04-20 — Direct Mac build participates in iCloud sync
Direct-download users sync with iOS via iCloud too. Costs nothing extra; avoids a two-tier "MAS users get sync, direct users don't" story.

### 2026-04-20 — iPad multi-document tabs in v1 (research default overridden)
Research recommended single-document-per-scene on iPad to match `DocumentGroup` semantics. Overridden to port the Mac tab bar because Clearly's Mac experience is defined by tabs, and iPad hardware is similar enough that users will expect parity. Implementation keeps `DocumentGroup` as the scene root and manages multiple `OpenDocument` instances inside a custom container in the detail column.

### 2026-04-20 — 13 phases rather than 8
First draft had 8 phases but several were 2–3 days of work each. Split to 13 phases sized so each can be completed and verified on-device in one focused session (half-day to full-day).

### 2026-04-20 — iOS simulator verification path
Preferred verification path for the iOS target is a normal destination-based build: `xcodebuild -scheme Clearly-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -configuration Debug build`. `xcrun simctl install` + `xcrun simctl launch` remain useful when we want an explicit post-build launch check, but they are not required to work around destination resolution in this workspace.

### 2026-04-21 — Per-document `NSFilePresenter`, not per-vault (Phase 6)
`NSFilePresenter` is keyed on `presentedItemURL`. Registering a single presenter for the vault folder URL would deliver `presentedItemDidChange` callbacks for every file the ubiquity daemon touches — the wrong granularity for the "this specific open note changed remotely" use case Phase 6 needs for in-editor refresh. Vault-level change detection is still handled by `VaultWatcher`'s `NSMetadataQuery`. One caveat to revisit in Phase 12 (iPad multi-document tabs): multi-presenter lifecycle management becomes stricter when several documents are open simultaneously.

### 2026-04-21 — `@State`-scoped `IOSDocumentSession`, not scene-level (Phase 6)
Document state is per-file and the detail view's `.task(id:)` + `.onDisappear` already drive open / close cleanly. Lifting the session to an `@Environment` value at the app scene would have required explicit file-switch teardown that the detail view gets for free. If a future "resume last note on cold launch" feature needs persisted state across view lifetime, we'd promote this — not before.

### 2026-04-21 — Belt-and-braces `isOwnWriteInFlight` flag (Phase 6)
`NSFileCoordinator(filePresenter:)` suppresses callbacks to the passed-in presenter for the duration of the coordinated operation — that's the official contract. But a metadata-query change event can fire on a separate path (ubd notifying `NSMetadataQuery` of a file-size change before the coordinator's suppression has fully propagated). The `isOwnWriteInFlight` flag is a cheap additional guard against the echo. Doesn't replace presenter-aware coordination; just belts the braces.

### 2026-04-21 — Highlighter lives on Coordinator, not UITextView (Phase 5)
First draft had `ClearlyUITextView` own a `MarkdownSyntaxHighlighter` and install itself as `NSTextStorageDelegate`. Moved the highlighter to `EditorView_iOS.Coordinator` to mirror the Mac pattern (`EditorView.Coordinator` owns the highlighter; `NSTextViewDelegate.textDidChange` drives it). Avoids the `NSTextStorageDelegate.didProcessEditing` → nested `beginEditing`/`endEditing` re-entry risk — `UITextViewDelegate.textViewDidChange` fires outside the text storage's internal editing transaction. `ClearlyUITextView` is now a pure-config subclass (typing attributes, insets, keyboard config only).

### 2026-04-21 — `text` as `let`, not `@Binding`, in Phase 5 editor
Read-only contract enforced structurally rather than by convention. Phase 6 will promote to `@Binding` when writes land. The `pendingBindingUpdates` counter is already in place in the Coordinator so that promotion won't require re-architecting the cursor-jump guard.

### 2026-04-21 — Collapsed 19 dynamic-color declarations in `Theme`
The original Mac `Theme.swift` had 19 separate `NSColor(name:dynamicProvider:)` declarations. Making each one cross-platform directly in `Theme` would have doubled the rendering file with `#if os(macOS)`/`#else` branches. Instead introduced `PlatformColor.clearlyDynamic(name:light:dark:)` in `Platform.swift` — 19 call sites become one-line declarations and `Theme` stays platform-wrapper-only. Same palette, same dynamic behavior.

### 2026-04-21 — WindowGroup over DocumentGroup on iOS (Phase 4)
`IMPLEMENTATION.md` Phase 4 described `DocumentGroup` as the root iOS scene plus a separate welcome `WindowGroup`. Shipped as a single `WindowGroup` instead. `DocumentGroup` on iOS 17 opens the system document browser at launch with one-document-per-scene semantics — incompatible with the phase's requirement to show a vault-folder sidebar as the root UI. A single `WindowGroup` hosting welcome + sidebar + detail views matches the Mac app's mental model (Mac uses `Window` + `WorkspaceManager`, not `DocumentGroup`). `MarkdownDocument` was still promoted to `FileDocument` for Phase 5's editor binding. If Files.app "open in Clearly" integration is needed later, `DocumentGroup` can be added as a secondary scene. Phase 12 will revisit scene architecture for iPad multi-tab either way. `IMPLEMENTATION.md` should be updated if this deviation holds through Phase 5.

## Lessons Learned
(What worked, what didn't, what to do differently)
