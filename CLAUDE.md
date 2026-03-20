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
- Dependencies: `cmark-gfm` (GFM markdown → HTML), `Sparkle` (auto-updates) via Swift Package Manager

## Architecture

**Two targets** defined in `project.yml`:

1. **Clearly** (main app) — document-based SwiftUI app
2. **ClearlyQuickLook** (app extension) — QLPreviewProvider for Finder previews

**Shared code** lives in `Shared/` and is compiled into both targets:
- `MarkdownRenderer.swift` — wraps `cmark_gfm_markdown_to_html()` for GFM rendering (tables, strikethrough, task lists, autolinks)
- `PreviewCSS.swift` — CSS string used by both the in-app preview and the QuickLook extension

**App code** in `Clearly/`:
- `ClearlyApp.swift` — App entry point. `DocumentGroup` with `MarkdownDocument`, menu commands for switching view modes (⌘1 Editor, ⌘2 Preview)
- `MarkdownDocument.swift` — `FileDocument` conformance for reading/writing markdown files
- `ContentView.swift` — Hosts the mode picker toolbar and switches between `EditorView` and `PreviewView`. Defines `ViewMode` enum and `FocusedValueKey` for menu commands
- `EditorView.swift` — `NSViewRepresentable` wrapping `NSTextView` with undo, find panel, and live syntax highlighting via `NSTextStorageDelegate`
- `MarkdownSyntaxHighlighter.swift` — Regex-based syntax highlighter applied to `NSTextStorage`. Handles headings, bold, italic, code blocks, links, blockquotes, lists, etc. Code blocks are matched first to prevent inner highlighting
- `PreviewView.swift` — `NSViewRepresentable` wrapping `WKWebView` that renders the full HTML preview
- `Theme.swift` — Centralized colors (dynamic light/dark via `NSColor(name:)`) and font/spacing constants

**Key pattern**: The editor uses AppKit (`NSTextView`) bridged to SwiftUI via `NSViewRepresentable`, not SwiftUI's `TextEditor`. This is intentional — it provides undo support, find panel, and `NSTextStorageDelegate`-based syntax highlighting.

## Sparkle & Sandboxing

The app is sandboxed and uses Sparkle 2.x for auto-updates. This combination has a critical gotcha:

- **Xcode strips `temporary-exception` entitlements during `xcodebuild archive` + export.** The mach-lookup entitlements in `Clearly.entitlements` (needed for Sparkle's XPC installer service) will be present in local builds but silently removed from archived/exported builds. The release script (`scripts/release.sh`) works around this by re-signing the exported app with the resolved entitlements and verifying they're present before creating the DMG.
- If you ever change entitlements, verify them on the **exported** app (`codesign -d --entitlements :- build/export/Clearly.app`), not just the local build.
- `SUEnableInstallerLauncherService` in Info.plist must stay `YES` — without it, Sparkle can't launch the installer in a sandboxed app.
- Do NOT copy Sparkle's XPC services to `Contents/XPCServices/` — that's the old Sparkle 1.x approach. Sparkle 2.x bundles them inside the framework.

## Conventions

- All colors go through `Theme` with dynamic light/dark resolution — don't hardcode colors
- Preview CSS in `PreviewCSS.swift` must stay in sync with `Theme` colors for visual consistency between editor and preview modes
- Changes to `project.yml` require running `xcodegen generate` to update the Xcode project
