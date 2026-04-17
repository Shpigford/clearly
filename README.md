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

- **AI / MCP server** — built-in MCP server and `clearly` CLI expose your vault to AI agents. See [clearly CLI](#clearly-cli) and [ClearlyMCP](#clearlymcp).
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
├── CLIInstaller.swift              # Installs /usr/local/bin/clearly symlink from Settings
├── Theme.swift                     # Centralized colors (light/dark) and font constants
└── Info.plist

ClearlyQuickLook/
├── PreviewProvider.swift           # QLPreviewProvider for Finder previews
└── Info.plist

ClearlyCLI/                         # `clearly` CLI binary + MCP server
├── CLI/                            #   ArgumentParser subcommands + global options
├── Core/                           #   Pure-function tool implementations
└── MCP/                            #   MCP adapter (tool registry + dispatch)

ClearlyCLIIntegrationTests/         # XCTest suite driving MCP server in-process
├── FixtureVault/                   #   Sample .md files exercising every tool
└── *.swift                         #   Per-tool + schema + error + path-guard tests

Shared/
├── MarkdownRenderer.swift          # cmark-gfm → HTML + post-processing pipeline
├── PreviewCSS.swift                # CSS for in-app preview and QuickLook
├── MathSupport.swift               # KaTeX injection
├── MermaidSupport.swift            # Mermaid injection
├── SyntaxHighlightSupport.swift    # Highlight.js injection
├── EmojiShortcodes.swift           # :shortcode: → Unicode lookup
├── FrontmatterSupport.swift        # Shared YAML frontmatter parser
└── Resources/                      # Bundled JS/CSS, demo.md

website/                            # Static site deployed to clearly.md
scripts/                            # Release pipeline + CLI smoke test
project.yml                         # xcodegen config (source of truth)
```

## Architecture

**SwiftUI + AppKit**, document-based app with four targets.

### Targets

1. **Clearly** — main app. `DocumentGroup` with `MarkdownDocument`, editor and preview modes, file explorer, vault indexing.
2. **ClearlyQuickLook** — Finder extension for previewing `.md` files with Space.
3. **ClearlyCLI** — the `clearly` CLI binary and MCP server (same executable, different arg parser). Exposes 9 tools across read and write. See [clearly CLI](#clearly-cli) and [ClearlyMCP](#clearlymcp).
4. **ClearlyCLIIntegrationTests** — XCTest suite driving the MCP server in-process via `InMemoryTransport`. Runs on every PR via `.github/workflows/test.yml`.

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
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | CLI parsing for `clearly` |

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

Automated:

```bash
xcodebuild test -scheme ClearlyCLIIntegrationTests -destination 'platform=macOS'
./scripts/cli-smoke.sh
```

CI runs both on every pull request (`.github/workflows/test.yml`).

Manual:

1. Build and run (⌘R)
2. Open a `.md` file — verify syntax highlighting
3. Switch to preview (⌘2) — verify rendered output
4. Test wiki-links, backlinks, search, tags
5. QuickLook: select a `.md` in Finder, press Space
6. Check both light and dark mode

## clearly CLI

The `clearly` command-line binary is bundled with Clearly.app and operates on the same SQLite index the app maintains — no separate configuration, no data duplication.

### Install

Open Clearly → **Settings → Command Line → Install**. A one-time Terminal prompt for `sudo` creates a symlink at `/usr/local/bin/clearly` pointing to the bundled binary inside `Clearly.app/Contents/Resources/Helpers/ClearlyCLI`. Reinstalling Clearly (Sparkle or App Store) keeps the symlink valid.

Uninstall from the same Settings pane.

### Subcommand reference

```
clearly
├── mcp                 Start the MCP stdio server (this is what MCP clients invoke)
├── search <query>      Full-text search; emits NDJSON hits
├── read <path>         Read a note + metadata (hash, size, mtime, frontmatter, headings, tags)
├── list                List notes as NDJSON (fresh filesystem walk)
├── headings <path>     Heading outline (level, text, line_number)
├── frontmatter <path>  Parsed YAML frontmatter (flat key-value)
├── backlinks <path>    Linked references + unlinked mentions
├── tags [<tag>]        All tags with counts, or files for one tag
├── create <path>       Create a new note from --content or --from-stdin
├── update <path>       Update with --mode replace|append|prepend
├── vaults [list]       List loaded vaults (name, path, file_count, last_indexed_at)
└── index [rebuild]     Rebuild the SQLite index from disk
```

Run `clearly <subcommand> --help` for flags, examples, and output-shape notes.

### Exit codes

| Code | Name | Meaning |
|---|---|---|
| `0` | success | Command completed; output on stdout |
| `1` | general | Generic failure (e.g. no vaults loaded, non-UTF8 file) |
| `2` | usage | Invalid arguments / missing required flags |
| `3` | notFound | Note or vault filter not found |
| `4` | permission | Path resolves outside vault (traversal, `/absolute`, unicode lookalikes) |
| `5` | conflict | Note already exists (on `create`) or ambiguous across vaults |

### Output contract

- **JSON mode** (default): every tool emits a stable structured shape documented per-tool in its `--help`. List-shaped commands (`search`, `list`, `tags`) emit NDJSON — one record per line — for stream-friendly piping. Keys are snake_case.
- **Text mode** (`--format text`): human-readable aligned output, no stability guarantees. Use for terminal eyeballing only; agents and scripts should stick with JSON.
- **Errors** always go to stderr as a structured JSON object with `error` (stable identifier), `message` (human text), and relevant context fields. See the [error identifiers](#error-identifiers) table.

### Pipeline examples

```bash
# Top 20 tag counts, sorted
clearly tags | jq -s 'sort_by(-.count) | .[:20]'

# Grep every note under Projects/ for a term
clearly list --under Projects/ \
  | jq -r '.relative_path' \
  | xargs -I{} sh -c 'clearly read "{}" | jq -r ".content" | grep -l -e "OKR" /dev/stdin && echo "{}"'

# Cache invalidation by content hash
OLD=$(clearly read Notes/plan.md | jq -r '.content_hash')
# ...edit the file...
NEW=$(clearly read Notes/plan.md | jq -r '.content_hash')
[ "$OLD" != "$NEW" ] && echo "rebuild"
```

### Troubleshooting

- **Multi-vault ambiguity** — pass `--in-vault <name>` on per-command calls, or `--vault <path>` on the global command to scope which vault(s) to load.
- **Custom bundle id** — `--bundle-id com.sabotage.clearly.dev` to point at the Debug build's vault store.
- **Dev-build SIGKILL** — the bundled `ClearlyCLI` inside `Clearly Dev.app/Contents/Resources/Helpers/` gets SIGKILL'd by macOS when launched standalone (code-signature invalidation). Use the product binary at `Build/Products/Debug/ClearlyCLI` directly for local testing.

## ClearlyMCP

Same binary, different arg — `clearly mcp` starts a stdio MCP server exposing 9 tools to any [Model Context Protocol](https://modelcontextprotocol.io) client.

### Client config

**Claude Desktop** (`~/Library/Application Support/Claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "clearly": {
      "command": "/usr/local/bin/clearly",
      "args": ["mcp"]
    }
  }
}
```

**Claude Code** (`~/.config/claude-code/mcp.json` or via `claude mcp add`):

```json
{
  "mcpServers": {
    "clearly": {
      "command": "/usr/local/bin/clearly",
      "args": ["mcp"]
    }
  }
}
```

**Cursor** (`~/.cursor/mcp.json`):

```json
{
  "mcpServers": {
    "clearly": {
      "command": "/usr/local/bin/clearly",
      "args": ["mcp"]
    }
  }
}
```

Settings → Command Line → **Copy MCP config** in the Clearly app copies a ready-to-paste snippet (auto-flips to `/usr/local/bin/clearly` once the symlink is installed).

### Tool reference

All tools use snake_case JSON keys on input and output. Every response also includes a `structuredContent` field on success and `isError: true` on failure — both mirror the text content exactly. Error responses include `error` (stable identifier) and `message`.

| Tool | Annotations | Summary |
|---|---|---|
| `search_notes` | read-only, idempotent | Full-text search (BM25). Returns ranked hits with excerpts. |
| `read_note` | read-only, idempotent | Full content + hash, size, mtime, frontmatter, headings, tags. Optional line range. |
| `list_notes` | read-only, idempotent | Fresh filesystem walk. Optional `under` prefix. |
| `get_headings` | read-only, idempotent | Heading outline (level 1–6, text, line_number). |
| `get_frontmatter` | read-only, idempotent | Parsed YAML frontmatter as a flat map. |
| `get_backlinks` | read-only, idempotent | Linked references (via `[[WikiLink]]`) plus unlinked mentions. |
| `get_tags` | read-only, idempotent | All tags with counts, or files per tag. |
| `create_note` | destructive, non-idempotent | New note at a vault-relative path. Conflict on existing. |
| `update_note` | destructive, non-idempotent | `replace` / `append` / `prepend` modes. Prepend is frontmatter-aware. |

Each tool registers its full JSON Schema via MCP `outputSchema`; clients that render schemas (MCP Inspector, the Claude API tool-call viewer) can introspect every field without reading source.

### Example payloads

`search_notes` (NDJSON, one hit per line):

```json
{"excerpts":[{"context_line":"# The Death of SaaS Pricing Pages","line_number":8},{"context_line":"Pricing pages are broken…","line_number":10}],"filename":"The Death of SaaS Pricing Pages","matches_filename":true,"relative_path":"Blog Posts/The Death of SaaS Pricing Pages.md","vault":"Documents","vault_path":"/Users/…/Documents"}
```

`read_note`:

```json
{
  "content": "---\ntitle: Building in Public is a Lie\ndate: 2026-03-15\n---\n\n# Building in Public is a Lie\n…",
  "content_hash": "e9777e4a4e308a77ec7c5814f4d4204c978139249967deb064b4558bf4f2594a",
  "frontmatter": { "date": "2026-03-15", "status": "draft", "tags": "writing, transparency", "title": "Building in Public is a Lie" },
  "headings": [{ "level": 1, "line_number": 8, "text": "Building in Public is a Lie" }],
  "size_bytes": 1703,
  "modified_at": "2026-04-14T15:47:25.274Z",
  "relative_path": "Blog Posts/Building in Public is a Lie.md",
  "vault": "Documents"
}
```

`get_backlinks`:

```json
{
  "linked": [
    { "display_text": "my piece on transparency", "line_number": 23, "relative_path": "Blog Posts/The Death of SaaS Pricing Pages.md", "vault": "Documents" }
  ],
  "unlinked": [],
  "relative_path": "Blog Posts/Building in Public is a Lie.md",
  "vault": "Documents"
}
```

`get_tags` (all tags, NDJSON):

```json
{"count":1,"tag":"ai"}
{"count":33,"tag":"analysis"}
```

### Error identifiers

Every error response — whether emitted by the CLI to stderr or by the MCP server as `structuredContent` with `isError: true` — uses one of these identifiers:

| `error` | Where it fires | Context fields |
|---|---|---|
| `missing_argument` | Required flag/arg not provided | `argument` |
| `invalid_argument` | Bad value (e.g. `--mode` not one of replace/append/prepend) | `argument`, `reason` |
| `invalid_encoding` | File is not valid UTF-8 | `relative_path` |
| `note_not_found` | Target note doesn't exist in any loaded vault | `relative_path` |
| `path_outside_vault` | Path resolves outside the vault (traversal, absolute, unicode lookalike) | `relative_path` |
| `ambiguous_path` | Multiple loaded vaults contain this path | `relative_path`, `matches` |
| `note_exists` | `create_note` against an existing path | `relative_path` |
| `no_vaults` | CLI-only: could not open any vault index | `bundle_id` |
| `no_vault_match` | `--in-vault` filter didn't match any loaded vault | `filter` |
| `unknown_tool` | MCP `tools/call` for an unregistered tool name | `tool` |
| `internal_error` | Uncategorized exception from a tool | `error_type` |

The identifier is the stable contract — agent code should branch on `error`, not on `message` text.

## License

FSL-1.1-MIT — see [LICENSE](LICENSE). Code converts to MIT after two years.
