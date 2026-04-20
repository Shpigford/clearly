# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Clearly is a native macOS markdown editor built with SwiftUI. It's a document-based app (`DocumentGroup`) that opens/saves `.md` files, with two modes: a syntax-highlighted editor and a WKWebView-based preview. It also ships a QuickLook extension for previewing markdown files in Finder.

## Build & Run

The Xcode project is generated from `project.yml` using [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
xcodegen generate        # Regenerate .xcodeproj from project.yml
xcodebuild -scheme Clearly -configuration Debug build   # Build from CLI
```

Open in Xcode: `open Clearly.xcodeproj` (gitignored, so regenerate with xcodegen first).

- Deployment target: macOS 14.0
- Swift 5.9, Xcode 16+
- Dependencies: `cmark-gfm` (GFM markdown → HTML), `Sparkle` (auto-updates, direct distribution only), `GRDB` (SQLite + FTS5), `MCP` (Model Context Protocol SDK) via Swift Package Manager

## Architecture

**Three targets** defined in `project.yml`, all depending on the local `ClearlyCore` Swift package:

1. **Clearly** (main app) — document-based SwiftUI app
2. **ClearlyQuickLook** (app extension) — QLPreviewProvider for Finder previews
3. **ClearlyCLI** (command-line tool) — MCP server exposing vault index to AI agents. Uses `VaultIndex.init(locationURL:bundleIdentifier:)` from `ClearlyCore` to open the same SQLite index the sandboxed app creates. Exposes tools: `search_notes` (FTS5 ranked search), `get_backlinks` (linked + unlinked mentions), `get_tags` (tag aggregation), plus read/write note tools. Read-only index access via WAL mode.

**`ClearlyCore`** — local Swift package at `Packages/ClearlyCore/`. Holds every platform-agnostic file. Platforms: `macOS 14` + `iOS 17`. Organized into `Rendering/` (`MarkdownRenderer`, `PreviewCSS`, `MermaidSupport`, `MathSupport` inside MermaidSupport.swift, `TableSupport`, `SyntaxHighlightSupport`, `EmojiShortcodes`, `LocalImageSupport`, `FrontmatterSupport`), `Vault/` (`VaultIndex`, `FileParser`, `FileNode`, `IgnoreRules`, `BookmarkedLocation`), `State/` (`OpenDocument`, `OutlineState`, `FindState`, `JumpToLineState`, `BacklinksState`, `PositionSync`), `Diagnostics/` (`DiagnosticLog`), and `Platform/Platform.swift` (typealiases `PlatformFont`/`PlatformColor`/`PlatformImage`/`PlatformPasteboard`).

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

### Privileged ops from the sandboxed app

Clearly is sandboxed, so any operation that needs root (`/usr/local/bin/` writes, privileged installs) can't route through `NSAppleScript … with administrator privileges` — that path is silently blocked and surfaces as a misleading **"The administrator user name or password was incorrect"** error with no SecurityAgent dialog ever appearing. Don't use it.

The working pattern (see `Clearly/CLIInstaller.swift`) is `tell application "Terminal" to do script "sudo …"`. Terminal's own inline sudo prompt handles authentication. Required pieces:

- `com.apple.security.temporary-exception.apple-events` with `com.apple.Terminal` as the only target in `Clearly.entitlements`.
- `NSAppleEventsUsageDescription` in `Info.plist` with a user-visible reason. **Without it, TCC silently auto-denies — the consent prompt never appears.** This was the single most time-consuming debug step during Phase 5 of `local-mcp-cli`.
- For ad-hoc-signed Debug builds iterating on AppleEvents, TCC can cache stale denials across rebuilds. Reset with `tccutil reset AppleEvents com.sabotage.clearly.dev`.

**Cross-channel warning:** the apple-events exception lives in `Clearly.entitlements` (direct/Sparkle) but **not** in `Clearly-AppStore.entitlements`, which strips temporary-exceptions to pass MAS review. That means the CLI install flow (and anything else that drives Terminal) won't work in the App Store build as-is. Either mirror the entitlement into the MAS file (review-risk) or gate the Install UI behind `#if canImport(Sparkle)` and ship a copy-paste fallback for MAS.

## Conventions

- All colors go through `Theme` with dynamic light/dark resolution — don't hardcode colors
- Preview CSS in `PreviewCSS.swift` must stay in sync with `Theme` colors for visual consistency between editor and preview modes
- CSS changes in `PreviewCSS.swift` must cover four contexts: base (light), `@media (prefers-color-scheme: dark)`, `@media print`, and the `forExport` override string. Interactive elements (copy buttons, sort indicators) should be hidden in print/export
- **CSS source order in `PreviewCSS.swift`**: Base (light) styles for new elements must be defined BEFORE any `@media (prefers-color-scheme: dark)` overrides for those elements. If a base style comes after a dark-mode `@media` block, the base style wins by source order and dark mode breaks. Place the dark-mode override immediately after the base definition (in its own `@media` block if needed), not in the consolidated dark-mode block near the top of the file.
- Changes to `project.yml` require running `xcodegen generate` to update the Xcode project

### Adding sidebar sections

When adding a new sidebar section that can appear/disappear dynamically (like PINNED or TAGS), add a `hadXBefore` boolean tracker in the Coordinator. Check it in `reloadIfNeeded()` — if the section just appeared (`!hadXBefore && !data.isEmpty`), call `outlineView.expandItem(item(for: .newSection))`. Without this, new sections appear collapsed and the user can't see their contents. Also expand explicitly in any `@objc` action handler that triggers the section to appear, since `reloadAndExpand()` only auto-expands all sections on very first launch (no autosave state).

### Adding preview features

Follow the `MathSupport`/`MermaidSupport`/`TableSupport`/`SyntaxHighlightSupport` pattern: create a `*Support.swift` enum in `Shared/` with a static method that returns a `<script>` block (or empty string if the feature isn't needed for the current content). Integrate it into `PreviewView.swift`, `PreviewProvider.swift`, and `PDFExporter.swift` HTML templates. This ensures the feature works in preview, QuickLook, and PDF export.

**Preview-to-editor communication**: Interactive preview features that modify source text or switch modes use `WKScriptMessageHandler` callbacks. Register the handler in `makeNSView`, add a callback closure on `PreviewView`, and wire it in `ContentView`. When the preview modifies source text (e.g., task checkbox toggle), set `coordinator.skipNextReload = true` before updating the binding — this prevents a full `loadHTMLString` flash since the DOM is already updated.

### Demo document

`Shared/Resources/demo.md` is bundled with the app and accessible via **Help → Sample Document**. Keep it updated when adding new markdown features so it serves as both a user showcase and a test fixture.
