<p align="center">
  <img src="website/icon.png" width="128" height="128" alt="Clearly icon" />
</p>

<h1 align="center">Clearly</h1>

<p align="center">Markdown editor and knowledge base for Mac.</p>

<p align="center">
  <a href="https://apps.apple.com/app/clearly-markdown/id6760669470">Mac App Store</a> &middot;
  <a href="https://github.com/Shpigford/clearly/releases/latest/download/Clearly.dmg">Direct Download</a> &middot;
  <a href="https://clearly.md">Website</a> &middot;
  <a href="https://x.com/Shpigford">@Shpigford</a>
</p>

<p align="center">
  <img src="website/screenshots/screenshot-1.jpg" width="720" alt="Clearly — editor with sidebar and document outline" />
</p>

Write with syntax highlighting, link your thoughts with wiki-links, search everything, preview beautifully. Native macOS, no Electron, no subscriptions.

## Features

### Writing

- **Syntax highlighting** — headings, bold, italic, links, code blocks, tables, highlighted as you type
- **Format shortcuts** — ⌘B bold, ⌘I italic, ⌘K links
- **Extended markdown** — ==highlights==, ^superscript^, ~subscript~, :emoji: shortcodes, `[TOC]` generation
- **Scratchpad** — menubar scratch pad with a global hotkey

### Knowledge

- **Wiki-links** — link documents with `[[wiki-links]]`, type `[[` to autocomplete
- **Backlinks** — linked and unlinked mentions with one-click linking
- **Tags** — organize with #tags, browse in the sidebar
- **Global search** — full-text search across every document, ranked by relevance
- **Document outline** — navigable heading outline, click to jump
- **File explorer** — browse folders, bookmark locations, create and rename files

### Preview

- **GFM rendering** — tables, task lists, footnotes, strikethrough
- **KaTeX math** — inline and block equations
- **Mermaid diagrams** — flowcharts, sequence diagrams from code blocks
- **Code blocks** — 27+ languages, line numbers, diff highlighting, one-click copy
- **Callouts** — NOTE, TIP, WARNING, and 15+ types, foldable
- **Interactive** — toggle checkboxes, zoom images, hover footnotes, double-click to jump to source

### Integration

- **AI / MCP server** — built-in MCP server exposes your vault to AI agents for search and retrieval
- **QuickLook** — preview .md files in Finder with Space
- **PDF export** — export or print, page breaks handled
- **Copy formats** — markdown, HTML, or rich text

## Screenshots

<p>
  <img src="website/screenshots/screenshot-2-alt.jpg" width="360" alt="" />
  <img src="website/screenshots/screenshot-3.jpg" width="360" alt="" />
</p>
<p>
  <img src="website/screenshots/screenshot-4.jpg" width="360" alt="" />
  <img src="website/screenshots/screenshot-5-alt.jpg" width="360" alt="" />
</p>

## Prerequisites

- **macOS 14** (Sonoma) or later
- **Xcode 16+** with command-line tools (`xcode-select --install`)
- **Homebrew** ([brew.sh](https://brew.sh))
- **xcodegen** — `brew install xcodegen`

Dependencies (cmark-gfm, Sparkle, GRDB, MCP SDK) are pulled automatically by Xcode via Swift Package Manager.

## Quick Start

```bash
git clone https://github.com/Shpigford/clearly.git
cd clearly
brew install xcodegen    # skip if already installed
xcodegen generate        # generates Clearly.xcodeproj from project.yml
open Clearly.xcodeproj   # opens in Xcode
```

Then hit **⌘R** to build and run.

> The Xcode project is generated from `project.yml`. If you change `project.yml`, re-run `xcodegen generate`. Don't edit the `.xcodeproj` directly.

### CLI build

```bash
xcodebuild -scheme Clearly -configuration Debug build
```

## Project Structure

```
Clearly/
├── ClearlyApp.swift                # @main — DocumentGroup + menu commands (⌘1/⌘2)
├── MarkdownDocument.swift          # FileDocument conformance for .md files
├── ContentView.swift               # Mode picker, Editor ↔ Preview switching
├── EditorView.swift                # NSViewRepresentable wrapping NSTextView
├── MarkdownSyntaxHighlighter.swift # Regex-based highlighting via NSTextStorageDelegate
├── PreviewView.swift               # NSViewRepresentable wrapping WKWebView
├── FileExplorerView.swift          # Sidebar file browser with bookmarks and recents
├── FileParser.swift                # Parses frontmatter, wiki-links, tags from documents
├── VaultIndex.swift                # SQLite + FTS5 index for search, backlinks, tags
├── Theme.swift                     # Centralized colors (light/dark) and font constants
└── Info.plist

ClearlyQuickLook/
├── PreviewProvider.swift           # QLPreviewProvider for Finder previews
└── Info.plist

ClearlyMCP/
├── main.swift                      # MCP server — search_notes, get_backlinks, get_tags
└── (shares VaultIndex, FileParser, FileNode from main app)

Shared/
├── MarkdownRenderer.swift          # cmark-gfm → HTML + post-processing pipeline
├── PreviewCSS.swift                # CSS for in-app preview and QuickLook
├── MathSupport.swift               # KaTeX injection
├── MermaidSupport.swift            # Mermaid injection
├── SyntaxHighlightSupport.swift    # Highlight.js injection
├── EmojiShortcodes.swift           # :shortcode: → Unicode lookup
└── Resources/                      # Bundled JS/CSS, demo.md

website/                            # Static site deployed to clearly.md
scripts/                            # Release pipeline
project.yml                         # xcodegen config (source of truth)
```

## Architecture

**SwiftUI + AppKit**, document-based app with three targets.

### Targets

1. **Clearly** — main app. `DocumentGroup` with `MarkdownDocument`, editor and preview modes, file explorer, vault indexing.
2. **ClearlyQuickLook** — Finder extension for previewing `.md` files with Space.
3. **ClearlyMCP** — command-line MCP server. Exposes `search_notes` (FTS5), `get_backlinks`, and `get_tags` to AI agents. Read-only access to the same SQLite index the main app creates.

### Editor

Wraps AppKit's `NSTextView` via `NSViewRepresentable` — not SwiftUI's `TextEditor`. This provides native undo/redo, the system find panel (⌘F), and `NSTextStorageDelegate`-based syntax highlighting on every keystroke.

### Preview

`PreviewView` wraps `WKWebView` and renders HTML via `MarkdownRenderer` (cmark-gfm). Post-processing pipeline: math → highlight marks → superscript/subscript → emoji → callouts → TOC → tables → code highlighting.

### Knowledge Graph

`VaultIndex` maintains a SQLite database with FTS5 for full-text search. `FileParser` extracts wiki-links, backlinks, and tags from documents. The index is built on a background thread via `WorkspaceManager` to avoid blocking the UI.

### Dependencies

| Package | Purpose |
|---------|---------|
| [cmark-gfm](https://github.com/apple/swift-cmark) | GitHub Flavored Markdown → HTML |
| [Sparkle](https://sparkle-project.org) | Auto-updates (direct distribution only) |
| [GRDB](https://github.com/groue/GRDB.swift) | SQLite + FTS5 for vault indexing |
| [MCP](https://github.com/modelcontextprotocol/swift-sdk) | Model Context Protocol server |

### Key Decisions

- **AppKit bridge** — `NSTextView` over `TextEditor` for undo, find, and `NSTextStorageDelegate` syntax highlighting
- **Dynamic theming** — all colors through `Theme.swift` with `NSColor(name:)` for automatic light/dark
- **Shared code** — `MarkdownRenderer` and `PreviewCSS` compile into both the main app and QuickLook
- **Dual distribution** — Sparkle for direct, App Store without. All Sparkle code wrapped in `#if canImport(Sparkle)`
- **No `.inspector()`** — outline panel uses `HStack` due to fullscreen safe area bugs

## Common Dev Tasks

### Change syntax highlighting

Edit `MarkdownSyntaxHighlighter.swift`. Patterns are applied in order — code blocks first, then everything else.

### Modify preview styling

Edit `Shared/PreviewCSS.swift`. Used by both in-app preview and QuickLook. Keep in sync with `Theme.swift` colors. Base styles must come before `@media (prefers-color-scheme: dark)` overrides.

### Add a preview feature

Follow the `MathSupport`/`MermaidSupport` pattern: create a `*Support.swift` enum in `Shared/` with a static method that returns a `<script>` block. Integrate into `PreviewView.swift`, `PreviewProvider.swift`, and `PDFExporter.swift`.

## Testing

No automated test suite. Validate manually:

1. Build and run (⌘R)
2. Open a `.md` file — verify syntax highlighting
3. Switch to preview (⌘2) — verify rendered output
4. Test wiki-links, backlinks, search, tags
5. QuickLook: select a `.md` in Finder, press Space
6. Check both light and dark mode

## License

FSL-1.1-MIT — see [LICENSE](LICENSE). Code converts to MIT after two years.
