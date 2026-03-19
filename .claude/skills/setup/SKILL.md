---
name: setup
description: Get a new developer up and running with the Clearly codebase — prerequisites, build, and architecture orientation.
---

Set up the Clearly development environment and orient a new contributor to the codebase.

## Instructions

### Step 1: Check prerequisites

Verify these are installed. If any are missing, tell the user what to install and stop.

1. **macOS 14+** — `sw_vers -productVersion` (must be >= 14.0)
2. **Xcode CLI tools** — `xcode-select -p` (if missing: `xcode-select --install`)
3. **Homebrew** — `which brew` (if missing: direct them to https://brew.sh)
4. **xcodegen** — `which xcodegen` (if missing: `brew install xcodegen`)

### Step 2: Check credentials

If `.env` does not exist in the project root:
- Tell the user to copy `.env.example` to `.env` and fill in their Apple Developer credentials
- This is only needed for release builds, not development

### Step 3: Generate Xcode project

```bash
xcodegen generate
```

This reads `project.yml` (the source of truth for all Xcode project settings) and generates `Clearly.xcodeproj`. Re-run this anytime `project.yml` changes. Never edit the `.xcodeproj` directly.

### Step 4: Build and run

```bash
xcodebuild -scheme Clearly -configuration Debug build
```

Or open in Xcode and hit Cmd+R:

```bash
open Clearly.xcodeproj
```

### Step 5: Orient the developer

Share this architecture overview:

**Two targets** defined in `project.yml`:
1. **Clearly** (main app) — document-based SwiftUI app for editing markdown
2. **ClearlyQuickLook** (app extension) — QLPreviewProvider for Finder previews

**Shared code** in `Shared/`:
- `MarkdownRenderer.swift` — wraps `cmark_gfm_markdown_to_html()` for GFM rendering
- `PreviewCSS.swift` — CSS string used by both the in-app preview and QuickLook extension

**App code** in `Clearly/`:
- `ClearlyApp.swift` — App entry point, `DocumentGroup` with `MarkdownDocument`, menu commands
- `ContentView.swift` — Mode picker toolbar, switches between EditorView and PreviewView
- `EditorView.swift` — `NSViewRepresentable` wrapping `NSTextView` with undo, find panel, and live syntax highlighting
- `MarkdownSyntaxHighlighter.swift` — Regex-based syntax highlighter applied to `NSTextStorage`
- `PreviewView.swift` — `NSViewRepresentable` wrapping `WKWebView` for rendered preview
- `Theme.swift` — Centralized colors (dynamic light/dark) and font/spacing constants

**Key design decisions:**
- The editor uses AppKit `NSTextView` bridged to SwiftUI, not SwiftUI's `TextEditor` — this provides undo, find panel, and `NSTextStorageDelegate`-based highlighting
- All colors go through `Theme` with dynamic light/dark resolution — don't hardcode colors
- Preview CSS in `PreviewCSS.swift` must stay in sync with `Theme` colors
- No test suite — validate changes by building, running, and observing

## Important Rules

- `project.yml` is the source of truth for Xcode settings — never edit `.xcodeproj` directly
- Sparkle and cmark-gfm are the only external dependencies — pulled automatically via SPM
- There is no test suite — always validate changes by building and running the app manually
