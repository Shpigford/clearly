# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commit message rule (hard requirement)

Mac and iOS release independently (see "Versioning" below). The `/release` skill builds per-platform changelogs by filtering commits on a scope prefix, so every commit MUST start with one:

- `[mac]` — Mac-only changes. Paths: `Clearly/` excluding `Clearly/iOS/`, `ClearlyQuickLook/`, `ClearlyCLI/`, `scripts/release.sh`, `scripts/release-appstore.sh`, `website/`.
- `[ios]` — iOS-only changes. Paths: `Clearly/iOS/`, `scripts/release-ios.sh`.
- `[shared]` — affects both platforms. Paths: `Packages/ClearlyCore/`, `Shared/Resources/`, cross-cutting `project.yml` edits. Appears in both changelogs.
- `[chore]` — dev tooling, docs, CI, meta. Excluded from both user-facing changelogs. Paths: `CLAUDE.md`, `.github/`, `docs/`, `.claude/`, test harnesses, non-release scripts.

Conventional-commit markers (`feat:`, `fix:`) may follow the scope — `[ios] feat: add conflict resolver`. Not required; the release skill has a fallback for ambiguous cases.

When a change touches paths from more than one scope, pick the most-specific user-visible scope. A bug fix that required a `ClearlyCore` tweak is still `[ios]` or `[mac]` if only that platform's users see the result. Use `[shared]` only when both platforms actually benefit. A missing or wrong scope means the commit lands in the wrong release notes or none at all — the release skill halts if it sees any un-scoped commit in the range.

## Versioning

Mac and iOS ship on independent cadences with independent version numbers and tags:

- **Mac** (`Clearly` app, `ClearlyQuickLook`, `ClearlyCLI`): tags `v<VERSION>` (e.g. `v2.3.0`). Changelog: `CHANGELOG.md`. QuickLook and CLI versions move in lockstep with the Mac app.
- **iOS** (`Clearly-iOS`): tags `ios-v<VERSION>` (e.g. `ios-v1.0.0`). Changelog: `CHANGELOG-iOS.md`.

Version numbers on the two platforms are unrelated — don't try to keep them in sync.

## What This Is

Clearly is a native macOS markdown editor built with SwiftUI. It's a document-based app (`DocumentGroup`) that opens/saves `.md` files, with two modes: a syntax-highlighted editor and a WKWebView-based preview. It also ships a QuickLook extension for previewing markdown files in Finder.

## Build & Run

The Xcode project is generated from `project.yml` using [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
xcodegen generate        # Regenerate .xcodeproj from project.yml
xcodebuild -scheme Clearly -configuration Debug build   # Build from CLI
```

Open in Xcode: `open Clearly.xcodeproj` (gitignored, so regenerate with xcodegen first).

**Worktree-local DerivedData (Conductor / parallel workspaces).** When working in a Conductor worktree, always pass `-derivedDataPath ./.build/DerivedData` to `xcodebuild`. Without it, `xcodebuild` writes to the shared `~/Library/Developer/Xcode/DerivedData` and silently picks up products from a different worktree or the main repo, and `open` then launches a stale or wrong-source app. The `/verify` skill enforces this; do the same for any direct `xcodebuild` invocation. The launched bundle path under `.build/DerivedData/Build/Products/Debug/Clearly Dev.app` should always match the worktree you're editing — verify with `lsappinfo info -only bundlepath "Clearly Dev"` if in doubt.

- Deployment target: macOS 15.0 (raised from 14.0 to enable SwiftUI API parity with iPad shell and ship with macOS 26 SDK); iOS 17.0
- Swift 5.9 app / Swift 5 language mode for ClearlyCore (tools 6.0 so we can declare `.macOS(.v15)`). Xcode 26+ required to compile against the macOS 26 SDK so Liquid Glass lights up automatically on stock SwiftUI chrome.
- Dependencies: `cmark-gfm` (GFM markdown → HTML), `Sparkle` (auto-updates, direct distribution only), `GRDB` (SQLite + FTS5), `MCP` (Model Context Protocol SDK) via Swift Package Manager

## Architecture

**Three targets** defined in `project.yml`, all depending on the local `ClearlyCore` Swift package:

1. **Clearly** (main app) — document-based SwiftUI app
2. **ClearlyQuickLook** (app extension) — QLPreviewProvider for Finder previews
3. **ClearlyCLI** (command-line tool) — MCP server exposing vault index to AI agents. Uses `VaultIndex.init(locationURL:bundleIdentifier:)` from `ClearlyCore` to open the same SQLite index the sandboxed app creates. Exposes tools: `search_notes` (FTS5 ranked search), `get_backlinks` (linked + unlinked mentions), `get_tags` (tag aggregation), plus read/write note tools. Read-only index access via WAL mode.

**`ClearlyCore`** — local Swift package at `Packages/ClearlyCore/`. Holds every platform-agnostic file. Platforms: `macOS 15` + `iOS 17`. Package.swift uses swift-tools-version 6.0 so it can declare `.v15`, but pins target language mode to `.v5` (via `swiftSettings: [.swiftLanguageMode(.v5)]`) to keep Swift 5 semantics — Swift 6 strict concurrency would flag existing shared state in `State/PositionSync.swift` and others. Organized into `Rendering/` (`MarkdownRenderer`, `PreviewCSS`, `MermaidSupport`, `MathSupport` inside MermaidSupport.swift, `TableSupport`, `SyntaxHighlightSupport`, `EmojiShortcodes`, `LocalImageSupport`, `FrontmatterSupport`), `Vault/` (`VaultIndex`, `FileParser`, `FileNode`, `IgnoreRules`, `BookmarkedLocation`), `State/` (`OpenDocument`, `OutlineState`, `FindState`, `JumpToLineState`, `BacklinksState`, `PositionSync`), `Diagnostics/` (`DiagnosticLog`), and `Platform/Platform.swift` (typealiases `PlatformFont`/`PlatformColor`/`PlatformImage`/`PlatformPasteboard`).

**Rules for `ClearlyCore`:**
- Any type or member used across the package boundary must be `public`. Consuming files need `import ClearlyCore`.
- No `import AppKit` inside the package — use the `Platform.swift` typealiases. AppKit-only code (editor, preview AppKit-representables, theme colors, syntax highlighter) stays in `Clearly/`. UIKit equivalents land in `Clearly/iOS/` when the iOS target arrives.
- Pipeline contract for `MarkdownRenderer`: wraps `cmark_gfm_markdown_to_html()` for GFM rendering. Post-processing pipeline (in order): math (`$...$` → KaTeX spans), highlight marks (`==text==` → `<mark>`), superscript/subscript, emoji shortcodes, callouts/admonitions (`[!TYPE]` blockquotes), TOC generation, table captions, code filename headers. All post-processing that touches inline syntax must use `protectCodeRegions()`/`restoreProtectedSegments()` to avoid transforming content inside `<pre>`/`<code>` tags.
- Preview JS/CSS helpers (`MathSupport`, `MermaidSupport`, `TableSupport`, `SyntaxHighlightSupport`) each expose a static `scriptHTML(for:)` that returns an empty string when the feature isn't needed for the current content.

**Shared web assets** (katex, mermaid, highlight, fonts, `demo.md`, `getting-started.md`) live at `Shared/Resources/` and are loaded via `Bundle.main.url(forResource:)` inside `MermaidSupport.swift` and `SyntaxHighlightSupport.swift`. `project.yml` bundles them into Clearly + ClearlyQuickLook via explicit resource buildPhase entries. Do NOT move these under the package's `resources:` unless you also migrate every `Bundle.main` lookup to `Bundle.module`.

**App code** in `Clearly/`:
- `ClearlyApp.swift` — App entry point. `DocumentGroup` with `MarkdownDocument`, menu commands for switching view modes (⌘1 Editor, ⌘2 Preview)
- `MarkdownDocument.swift` — `FileDocument` conformance for reading/writing markdown files
- `ContentView.swift` — Hosts the mode picker toolbar and switches between `EditorView` and `PreviewView`. Defines `ViewMode` enum and `FocusedValueKey` for menu commands
- `EditorView.swift` — `NSViewRepresentable` wrapping `NSTextView` with undo, find panel, and live syntax highlighting via `NSTextStorageDelegate`
- `MarkdownSyntaxHighlighter.swift` — Regex-based syntax highlighter applied to `NSTextStorage`. Handles headings, bold, italic, code blocks, links, blockquotes, lists, etc. Code blocks are matched first to prevent inner highlighting
- `PreviewView.swift` — `NSViewRepresentable` wrapping `WKWebView` that renders the full HTML preview
- `Theme.swift` — Centralized colors (dynamic light/dark via `NSColor(name:)`) and font/spacing constants

**Key pattern**: The editor uses AppKit (`NSTextView`) bridged to SwiftUI via `NSViewRepresentable`, not SwiftUI's `TextEditor`. This is intentional — it provides undo support, find panel, and `NSTextStorageDelegate`-based syntax highlighting.

**Threading rule for `FileNode.buildTree()`**: This method does recursive filesystem I/O and must never run on the main thread. Use `WorkspaceManager.loadTree(for:at:reindex:)` which dispatches to a background queue, guards against stale completions via a generation counter, and assigns the result on main. The same applies to any new code that calls `FileManager.contentsOfDirectory` over potentially large directory trees.

**Avoid `.inspector()` for panels that must look correct in fullscreen.** SwiftUI's `.inspector()` introduces an internal safe area gap at the top of the panel in fullscreen mode. The background and borders don't extend to the window edge, and there's no reliable way to fix it from the outside — painting ancestor NSViews, `.toolbarBackgroundVisibility(.hidden)`, ZStack backgrounds with `.ignoresSafeArea()`, and adding border subviews to AppKit containers were all tried and failed or caused dark mode / alignment regressions. The outline panel was converted from `.inspector()` to a plain `HStack` sibling with a manual 1px separator for this reason.

**`NSApp.delegate` is NOT `ClearlyAppDelegate`**: SwiftUI's `@NSApplicationDelegateAdaptor` wraps the real delegate in a `SwiftUI.AppDelegate` proxy. `NSApp.delegate as? ClearlyAppDelegate` always returns nil. Use `ClearlyAppDelegate.shared` (a static weak reference set in `applicationDidFinishLaunching`) to reach the delegate from outside the delegate class itself. Lifecycle callbacks (`applicationDidBecomeActive`, etc.) work fine because SwiftUI forwards them — the cast only fails when you go through `NSApp.delegate` directly.

**Don't add subviews to `_NSHostingView` with Auto Layout constraints.** SwiftUI's hosting view manages subview layout internally and will override your frames/constraints, causing the subview to fill the entire hosting view. The same applies to `NSSplitView`, which treats added subviews as panes. If you need an AppKit overlay on top of SwiftUI content, subclass the underlying AppKit view instead (e.g., `DraggableWKWebView` in `PreviewView.swift` overrides `mouseDown` to enable window dragging in the top region).

**NSViewRepresentable binding gotcha**: SwiftUI can call `updateNSView` at any time — layout passes, state changes, etc. — not just in response to binding changes. When the user types, the text view's content changes immediately but the `@Binding` update is async. If `updateNSView` fires in between, it sees a mismatch and overwrites the text view with the stale binding value, causing the cursor to jump. A simple `isUpdating` boolean set inside the async block does NOT protect against this because SwiftUI defers the actual `updateNSView` call past the flag's lifetime. The fix is `pendingBindingUpdates` — a counter incremented synchronously in `textDidChange` and decremented in the async block. `updateNSView` skips text replacement while this counter is > 0. This pattern applies to any `NSViewRepresentable` that pushes changes from the AppKit side back to SwiftUI bindings asynchronously.

**`@Published` emits in `willSet` — the property hasn't been written yet at sink-fire time.** A `.sink` on `state.$prop` runs *before* the assignment completes on the same thread. Reading `state.prop` synchronously inside the sink returns the OLD value, so any code that re-derives behavior from current state (e.g., `performFind()` reading `findState.caseSensitive`) sees stale options. Two safe patterns: (1) capture the new value from the closure parameter and pass it through, like the existing `state.$query.sink { newQuery in self.performFind(query: newQuery) }` in `EditorView.Coordinator`; or (2) `DispatchQueue.main.async` inside the sink so the property is written by the time the work runs. The CombineLatest subscription on the find option toggles uses pattern (2).

**SwiftUI `.keyboardShortcut(letter, modifiers: [.command, .option])` does not dispatch on this macOS** even though the menu item displays the shortcut. `.command` alone and `[.command, .shift]` work fine; the option modifier on a letter silently fails. For ⌥⌘-letter shortcuts, follow the `injectHideToolbarIfNeeded` pattern in `ClearlyAppDelegate.applicationWillUpdate`: build an `NSMenuItem` with `keyEquivalent: "x"` + `keyEquivalentModifierMask = [.command, .option]`, target an `@objc` selector or post a notification, and let `MacRootView` observe. Don't use `.keyboardShortcut(... [.command, .option])` from a SwiftUI `Button` and assume it dispatches.

## Dual Distribution: Sparkle + App Store

The app ships through two channels from the same codebase:

1. **Direct (Sparkle)** — `scripts/release.sh` → DMG + notarize + GitHub Release + Sparkle appcast
2. **App Store** — `scripts/release-appstore.sh` → archive without Sparkle + upload to App Store Connect

**Conditional compilation**: All Sparkle code is wrapped in `#if canImport(Sparkle)`. The App Store build uses a modified `project.yml` (generated at build time by the release script) that removes the Sparkle package, so `canImport(Sparkle)` is `false` and all update-related code compiles out.

**Two entitlements files**:
- `Clearly.entitlements` — for direct distribution. Includes `temporary-exception` entries for Sparkle's mach-lookup XPC services and home-relative-path read access for local images.
- `Clearly-AppStore.entitlements` — for App Store. No temporary exceptions (App Store hard-rejects them). Local images outside the document's directory won't render in preview.

### Sparkle + Sandboxing Gotchas

- **Xcode strips `temporary-exception` entitlements during `xcodebuild archive` + export.** The release script (`scripts/release.sh`) works around this by re-signing the exported app with the resolved entitlements and verifying they're present before creating the DMG.
- If you ever change entitlements, verify them on the **exported** app (`codesign -d --entitlements :- build/export/Clearly.app`), not just the local build.
- `SUEnableInstallerLauncherService` in Info.plist must stay `YES` — without it, Sparkle can't launch the installer in a sandboxed app.
- Do NOT copy Sparkle's XPC services to `Contents/XPCServices/` — that's the old Sparkle 1.x approach. Sparkle 2.x bundles them inside the framework.

### Adding Sparkle references

When adding new Sparkle-dependent code, always wrap it in `#if canImport(Sparkle)`. The App Store build must compile cleanly without the Sparkle module.

### CLI install: user-local, no privileged ops

Clearly is sandboxed. Historically, the CLI installer drove Terminal via AppleScript to run `sudo ln -sf … /usr/local/bin/clearly`. That path was fragile (required two separate AppleEvents entitlements on hardened runtime, broke silently on macOS 26 — see issue #241) and is no longer used.

The current installer (`Clearly/CLIInstaller.swift`) writes a symlink directly at `~/.local/bin/clearly` using `FileManager.createSymbolicLink`, requiring no sudo, no Terminal, no Apple Events. Required pieces:

- `com.apple.security.temporary-exception.files.home-relative-path.read-write = ["/.local/bin/"]` in `Clearly.entitlements`. Narrow-scope (only `~/.local/bin/`), mirroring the read-only variant already used for local-image previews.
- **No** `NSAppleEventsUsageDescription`, **no** `temporary-exception.apple-events`. Do not reintroduce either unless a new feature actually sends Apple Events.
- Legacy `/usr/local/bin/clearly` installs from Clearly ≤ 2.4.x are detected via `CLIInstaller.symlinkState()` and left alone. Removing a legacy symlink still requires sudo; the UI surfaces a copy-paste `sudo rm` command instead of attempting it.

**Cross-channel status:** the home-relative-path read-write exception is only in `Clearly.entitlements` (Sparkle). `Clearly-AppStore.entitlements` intentionally omits it — MAS review strips temporary-exceptions. MAS users get the `CLIInstaller.shellCommand` copy-paste fallback (no sudo either — still writes to `~/.local/bin`). Don't add the temporary-exception to the MAS entitlements file without weighing review risk.

**Never reintroduce** `NSAppleScript … with administrator privileges` (silently blocked in sandbox, surfaces as a misleading "The administrator user name or password was incorrect" error) or `tell Terminal to do script sudo …` (the exact path #241 broke).

### iCloud (and any profile-requiring entitlement) breaks ad-hoc Debug signing

Adding an entitlement that needs a provisioning profile — iCloud, Push, Keychain Sharing, App Groups — immediately breaks Debug builds that were previously signing ad-hoc with `-`. The failure looks like `"Clearly" requires a provisioning profile. Enable development signing and select a provisioning profile in the Signing & Capabilities editor.` The fix is in `project.yml`, not the entitlements file:

- Add `DEVELOPMENT_TEAM: W33JZPPPFN` to `settings.base` on every affected target.
- Add `CODE_SIGN_STYLE: Automatic` to each target's Debug config.
- Run `xcodebuild … -allowProvisioningUpdates` — this is the CLI equivalent of Xcode's "Automatically manage signing" UI: it registers missing App IDs, associates capabilities/containers, and downloads profiles without opening Xcode.

Verify entitlements survived on the signed app with `codesign -d --entitlements :- "<path>/Clearly Dev.app"`. The `com.apple.developer.team-identifier` key should read `W33JZPPPFN`.

### Verifying iCloud container provisioning

Finder's iCloud Drive sidebar is **not** authoritative. It does not reliably surface `NSUbiquitousContainers`-declared folders from Debug builds (`com.sabotage.clearly.dev`) or apps living under `DerivedData`. You can spend an hour trying to make it show the folder when iCloud is already fully wired.

Use these instead:

- **System Settings → [Your Name] → iCloud → Drive → Apps syncing to iCloud Drive** — authoritative app registration list.
- `brctl status iCloud.com.sabotage.clearly` — `bird`'s view of sync state. `caught-up` + `ever-full-sync` = working.
- `ls ~/Library/Mobile\ Documents/` — container directory exists once `FileManager.url(forUbiquityContainerIdentifier:)` has been called. Modern `iCloud.*` containers land at `iCloud~com~sabotage~clearly` *without* a team-ID prefix; that is correct, not a bug. Legacy-format containers (identifier without the `iCloud.` prefix, e.g. `com.dayoneapp.dayone`) get the `TEAMID~` prefix — both shapes coexist in `Mobile Documents/`.

### iOS scene architecture — `WindowGroup`, not `DocumentGroup`

`Clearly/iOS/ClearlyApp_iOS.swift` roots the app in a `WindowGroup` hosting `SidebarView_iOS`, mirroring how the Mac app uses `Window` + `WorkspaceManager` instead of `DocumentGroup`. Don't "fix" this back to `DocumentGroup` — its one-document-per-scene model is incompatible with the custom vault-folder sidebar (first screen needs to show a list of a user-picked folder's `.md` files, not the system document browser). `MarkdownDocument` is still a `FileDocument` so Phase 5's editor can bind to it, but no scene instantiates `DocumentGroup`. If Files.app "open in Clearly" integration is needed later, add `DocumentGroup` as a *second* scene alongside `WindowGroup`, don't swap it in.

### `ClearlyUITextView` must stay on TextKit 1, not TextKit 2

`Clearly/iOS/ClearlyUITextView.swift` calls `super.init(frame:textContainer:)` with a manually-constructed `NSTextStorage` → `NSLayoutManager` → `NSTextContainer` chain. Passing a non-nil `textContainer` is what forces TextKit 1 on iOS 16+; the default `UITextView(frame:)` defaults to TextKit 2, where `textView.textStorage` is effectively dead. Every path that reaches into `textStorage` — `MarkdownSyntaxHighlighter.highlightAll` / `highlightAround`, typing attributes, `NSTextStorageDelegate`, future save path in Phase 6 — depends on TextKit 1. Don't "simplify" the init to `super.init(frame:)` or use `UITextView(usingTextLayoutManager: true)`; highlighting will silently stop working with no crash.

### iOS find-style highlights need an explicit background-color wipe before each paint

TextKit 1 on iOS has no `removeTemporaryAttribute` API like macOS, so transient highlights (find matches, etc.) must live on `textStorage` via `addAttribute(.backgroundColor, ...)`. Re-running the syntax highlighter to "reset" backgrounds is NOT enough — `MarkdownSyntaxHighlighter.highlightAll` only *adds* attributes, it never removes them. So old find backgrounds from previous keystrokes persist into the next paint as orphaned yellow fragments. Always do `storage.removeAttribute(.backgroundColor, range: fullRange)` first, *then* re-run the highlighter (which repaints `==highlight==` markdown backgrounds), *then* paint your new find ranges. `EditorView_iOS.Coordinator.resetBackgroundsThenRehighlight` is the canonical helper.

### Save failures on iOS must not unmount the editor

`IOSDocumentSession.errorMessage` drives the full-screen "Couldn't open this note" view in `RawTextDetailView_iOS` — it is reserved for load-blocking failures only. **Never set it on a save failure.** A transient save error (iCloud offline, disk hiccup) must keep the editor mounted so the user's in-progress text survives. `performSave` routes failures through `DiagnosticLog.log` and leaves `lastSavedText` unchanged, which keeps `isDirty` true — the nav-title `•` is the user-visible signal that something's unsaved, and the next autosave / scene-phase flush retries. The same discipline applies to any future save path (Phase 11 conflict resolver, Phase 12 multi-document tab writes).

### `NSFileCoordinator.addFilePresenter(_:)` does not retain its presenter

Every `addFilePresenter(_:)` call MUST be paired with `removeFilePresenter(_:)` before the presenter's owning object deallocates, or the presenter zombies in the global registry and `presentedItemDidChange` callbacks fire into a nil weak target (silent, but the remote-refresh path is dead). `IOSDocumentSession.close()` handles the pairing; `RawTextDetailView_iOS.onDisappear` calls `close()` specifically so `NavigationStack`'s teardown doesn't leak a registration. Any future presenter owners — Phase 11's conflict resolver, Phase 12's iPad multi-document tabs — follow the same add/remove discipline. Presenter is keyed on `presentedItemURL`, so keep one per open document, not one per vault (folder-level presenters fire `didChange` for every file in the vault, which is the wrong granularity).

### `NSFileVersion` conflict API is `unresolvedConflictVersionsOfItem(at:)`

Note the "Conflict" in the middle. Apple's older sample code and docs show `unresolvedVersionsOfItem(at:)` — that method does not exist. `ConflictResolver` and every call site in `IOSDocumentSession` / `WorkspaceManager` use the correct spelling. Don't type from memory or paste from `docs/mobile/RESEARCH.md` / older `IMPLEMENTATION.md` revisions — both still contain the wrong name in narrative text, and every mistyped use eats a compile cycle.

### Never wrap `evictUbiquitousItem(at:)` in `NSFileCoordinator.coordinate`

Known iCloud deadlock (research risk #3). `FileManager.default.evictUbiquitousItem(at:)` must be called directly — iCloud serializes it internally. `CoordinatedFileIO` deliberately exposes no eviction helper to prevent accidental wrapping. Every other vault-file operation (read, write, move, delete) must still route through `CoordinatedFileIO` so coordination discipline isn't diluted.

### Mac conflict detection does NOT require `NSFilePresenter`

`NSFileVersion.unresolvedConflictVersionsOfItem(at:)` is populated by iCloud's `bird` daemon regardless of whether your process registered a presenter. `WorkspaceManager.refreshConflictOutcomeForActiveDocument()` on Mac passes `presenter: nil` to `ConflictResolver.resolveIfNeeded(at:presenter:)` and still detects conflicts correctly — `FileWatcher`'s dispatch-source change events are enough to decide when to re-run the resolver. iOS keeps a per-document presenter because it also wants in-place remote-change refresh callbacks, which are a separate need from version queries. Don't migrate the Mac to presenters "to enable conflicts" — conflicts already work.

## iOS development

The iOS app is a second target (`Clearly-iOS` in `project.yml`) that shares most business logic with Mac through the `ClearlyCore` Swift package at `Packages/ClearlyCore/`.

**Package layout:** Everything platform-agnostic (markdown rendering, vault indexing, FTS5, syntax helpers) lives in `ClearlyCore`. UI code stays in the per-platform folders: `Clearly/*.swift` is AppKit/Mac-only, `Clearly/iOS/*.swift` is UIKit/iOS-only. Cross-platform SwiftUI code inside `ClearlyCore` must use the typealiases from `Platform.swift` (`PlatformFont`, `PlatformColor`, `PlatformImage`, `PlatformPasteboard`) — never `import AppKit`/`import UIKit` directly inside the package.

**Entitlements:** iOS uses its own file at `Clearly/iOS/Clearly-iOS.entitlements` with only `com.apple.developer.icloud-container-identifiers` + `com.apple.developer.icloud-services = CloudDocuments`. No temporary-exceptions (App Store hard-rejects them), no mach-lookup (no Sparkle on iOS), no App Sandbox entitlement (iOS apps are sandboxed by default without that key).

**Bundle ids:** Release = `com.sabotage.clearly` (shared with Mac — Universal Purchase-ready, though Universal Purchase pairing is a later-phase manual step in ASC). Debug = `com.sabotage.clearly.dev` so Debug and Release installs coexist on the same device.

**TestFlight release:** `scripts/release-ios.sh <version>` archives, exports, and uploads to App Store Connect. Builds land in TestFlight, not on the public App Store. Complete the encryption export-compliance question and add testers through the ASC UI after upload.

## Conventions

- All colors go through `Theme` with dynamic light/dark resolution — don't hardcode colors
- Preview CSS in `PreviewCSS.swift` must stay in sync with `Theme` colors for visual consistency between editor and preview modes
- CSS changes in `PreviewCSS.swift` must cover four contexts: base (light), `@media (prefers-color-scheme: dark)`, `@media print`, and the `forExport` override string. Interactive elements (copy buttons, sort indicators) should be hidden in print/export
- **CSS source order in `PreviewCSS.swift`**: Base (light) styles for new elements must be defined BEFORE any `@media (prefers-color-scheme: dark)` overrides for those elements. If a base style comes after a dark-mode `@media` block, the base style wins by source order and dark mode breaks. Place the dark-mode override immediately after the base definition (in its own `@media` block if needed), not in the consolidated dark-mode block near the top of the file.
- Changes to `project.yml` require running `xcodegen generate` to update the Xcode project. **Adding or removing source files also requires `xcodegen generate`**, even in glob-based paths like `Clearly/iOS` or `Packages/ClearlyCore/Sources/ClearlyCore/**` — xcodegen snapshots the file list at generation time and writes it into the `.xcodeproj`. A new file added after the last `xcodegen generate` will not be in the project until you re-run it, and the compiler will fail with `cannot find 'X' in scope` even though the file exists on disk.

### Adding sidebar sections

When adding a new sidebar section that can appear/disappear dynamically (like PINNED or TAGS), add a `hadXBefore` boolean tracker in the Coordinator. Check it in `reloadIfNeeded()` — if the section just appeared (`!hadXBefore && !data.isEmpty`), call `outlineView.expandItem(item(for: .newSection))`. Without this, new sections appear collapsed and the user can't see their contents. Also expand explicitly in any `@objc` action handler that triggers the section to appear, since `reloadAndExpand()` only auto-expands all sections on very first launch (no autosave state).

### Adding preview features

Follow the `MathSupport`/`MermaidSupport`/`TableSupport`/`SyntaxHighlightSupport` pattern: create a `*Support.swift` enum in `Shared/` with a static method that returns a `<script>` block (or empty string if the feature isn't needed for the current content). Integrate it into `PreviewView.swift`, `PreviewProvider.swift`, and `PDFExporter.swift` HTML templates. This ensures the feature works in preview, QuickLook, and PDF export.

**Preview-to-editor communication**: Interactive preview features that modify source text or switch modes use `WKScriptMessageHandler` callbacks. Register the handler in `makeNSView`, add a callback closure on `PreviewView`, and wire it in `ContentView`. When the preview modifies source text (e.g., task checkbox toggle), set `coordinator.skipNextReload = true` before updating the binding — this prevents a full `loadHTMLString` flash since the DOM is already updated.

### Demo document

`Shared/Resources/demo.md` is bundled with the app and accessible via **Help → Sample Document**. Keep it updated when adding new markdown features so it serves as both a user showcase and a test fixture.
