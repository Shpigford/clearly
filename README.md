<p align="center">
  <img src="website/icon.png" width="128" height="128" alt="Clearly icon" />
</p>

<h1 align="center">Clearly Markdown</h1>

<p align="center">A clean, native markdown editor for macOS.</p>

<p align="center">
  <a href="https://github.com/Shpigford/clearly/releases/latest/download/Clearly.dmg">Download</a> &middot;
  <a href="https://clearly.md">Website</a> &middot;
  <a href="https://x.com/Shpigford">@Shpigford</a>
</p>

<p align="center">
  <img src="website/screenshot.jpg" width="720" alt="Clearly screenshot" />
</p>

Write with syntax highlighting, preview instantly, and get back to what matters. No Electron, no subscriptions, no bloat.

## Features

- **Syntax highlighting** — headings, bold, italic, links, code blocks, and more
- **Instant preview** — rendered GitHub Flavored Markdown with Cmd+2
- **Format shortcuts** — Cmd+B, Cmd+I, Cmd+K for bold, italic, and links
- **QuickLook** — preview .md files right in Finder
- **Light & Dark** — follows system appearance or set manually

## Requirements

- macOS 14 (Sonoma) or later

## Development

```bash
brew install xcodegen
xcodegen generate
xcodebuild -scheme Clearly -configuration Debug build
```

## Architecture

- **SwiftUI** + **AppKit** — NSTextView bridged via NSViewRepresentable for undo, find panel, and syntax highlighting
- **Sparkle** — auto-updates via GitHub Releases
- **cmark-gfm** — GitHub Flavored Markdown rendering (tables, task lists, strikethrough, autolinks)
- **Sandboxed** — runs in App Sandbox with user-selected file access

## License

MIT — see [LICENSE](LICENSE).
