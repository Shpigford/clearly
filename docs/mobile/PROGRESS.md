# Mobile Progress

## Status: Phase 2 - Complete

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
- **Phase 2 executed and verified.** `Clearly-iOS` target added to `project.yml`; three new files under `Clearly/iOS/` (app entry, Info plist, entitlements shell); Mac target picks up `excludes: ["iOS/**"]`. Fixed one Mac-only API leak in `ClearlyCore/Vault/VaultIndex.swift` (`homeDirectoryForCurrentUser`, gated behind `#if os(macOS)`). All Mac schemes still green; 23/23 CLI integration tests still pass; iOS builds succeed both via `-sdk iphonesimulator` and via a concrete simulator destination (`platform=iOS Simulator,name=iPhone 17,OS=26.4`); placeholder view renders on iPhone 17 simulator (iOS 26.4 runtime).

---

## Files Changed

### Phase 1 (2026-04-20)
- **New:** `Packages/ClearlyCore/Package.swift`, `Packages/ClearlyCore/Sources/ClearlyCore/Platform/Platform.swift`
- **Moved (20 files, history preserved via `git mv`):** `Shared/{MarkdownRenderer,PreviewCSS,MermaidSupport,TableSupport,SyntaxHighlightSupport,EmojiShortcodes,LocalImageSupport,FrontmatterSupport}.swift` → `Packages/ClearlyCore/Sources/ClearlyCore/Rendering/`; `Clearly/{VaultIndex,FileParser,FileNode,IgnoreRules,BookmarkedLocation}.swift` → `Vault/`; `Clearly/{OpenDocument,OutlineState,FindState,JumpToLineState,BacklinksState,PositionSync}.swift` → `State/`; `Clearly/DiagnosticLog.swift` → `Diagnostics/`
- **Modified:** `project.yml` (all four targets re-wired); 52 consumer files across `Clearly/`, `ClearlyQuickLook/`, `ClearlyCLI/`, `ClearlyCLIIntegrationTests/` got `import ClearlyCore` + types inside moved files made public where accessed cross-module.

### Phase 2 (2026-04-20)
- **New:** `Clearly/iOS/ClearlyApp_iOS.swift`, `Clearly/iOS/Info-iOS.plist`, `Clearly/iOS/Clearly-iOS.entitlements`
- **Modified:** `project.yml` (added `Clearly-iOS` target block; added `iOS: "17.0"` to `options.deploymentTarget`; added `excludes: ["iOS/**"]` to Mac `Clearly` source path), `Packages/ClearlyCore/Sources/ClearlyCore/Vault/VaultIndex.swift` (wrapped `init(locationURL:bundleIdentifier:)` and `indexDirectory(bundleIdentifier:)` in `#if os(macOS)`)

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

## Lessons Learned
(What worked, what didn't, what to do differently)
