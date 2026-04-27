# Changelog

## [Unreleased]

## [2.6.1] - 2026-04-27
- Settings and preferences now carry over correctly when upgrading from v2.5.0

## [2.6.0] - 2026-04-27
- LLM Wiki vaults — turn any folder into an AI-curated knowledge base with AGENTS.md, index.md, and log.md
- Capture (⌃⌘I): paste a URL or text and the agent files it as new notes
- Chat (⌃⌘A): ask questions about your vault with semantic retrieval and cited sources; "File as Note" for keepers
- Review: runs once a day to propose tidy-ups; "Review ready" badge above the log sidebar
- Diff-review sheet on every agent-proposed change — accept or reject per file before anything lands
- Log timeline sidebar (⌃⌘T) shows every accepted operation with timestamp, kind, and changed files
- Powered by your local Claude Code or Codex CLI subscription — no API key, no extra billing
- Settings → Wiki tab to pick a runner and see install status
- File → New LLM Wiki seeds a fresh vault; right-click any vault for Convert to LLM Wiki…
- Sidebar marks wiki vaults with a book icon and WIKI badge
- Clickable [[wiki-links]] in chat answers
- New `semantic_search` MCP tool for embedding-based retrieval from any agent
- Marketing site links now show a preview image when shared

## [2.5.0] - 2026-04-24
- Paste and drop images directly into the editor
- Drag and drop files and folders in the sidebar to reorganize
- Adjust sidebar text size in Settings
- New setting to hide the menu bar icon
- CLI install no longer needs sudo or Terminal — installs to ~/.local/bin
- Recoverable CLI install flow with clearer diagnostics
- Public changelog page with in-app links
- Fixed pasted text disappearing in the editor until you scrolled
- Fixed ⌘+H removing the Dock icon instead of hiding windows
- Fixed third-party cloud folders being labeled as iCloud in Sync settings
- Fixed Settings not coming to the front when opened from the menu bar icon
- Fixed inline LaTeX rendering on dollar-sign currency amounts

## [2.4.0] - 2026-04-23
- Native macOS shell: two-column NavigationSplitView with folder tree + detail pane
- Sidebar inherits your System Settings accent color (like Finder)
- New Recents and Tags sections in the sidebar
- Customize each folder's icon and color; nested files inherit the look
- ⌘-click a sidebar row to open the note in a new tab
- New Copy menu in the toolbar: copy path, filename, markdown, HTML, RTF, or plain text
- Sample Document now opens an editable copy of the demo instead of a blank file
- File → Open Recent lists recently opened documents
- Window title shows the active document name, with a dot when unsaved
- Sync Settings labels vault locations by capability (iCloud, Desktop & Documents, local-only)
- Minimum macOS raised to Sequoia 15 so Clearly picks up Liquid Glass on macOS 26 automatically

## [2.3.0] - 2026-04-20
- `clearly` command-line tool shipped — install from Settings → Command Line for terminal and MCP-client access to your vault
- MCP server grows from 3 to 9 tools: `read_note`, `list_notes`, `get_headings`, `get_frontmatter` (reads) plus `create_note`, `update_note` (writes)
- Structured JSON on every tool, input/output schemas published via MCP, stable error identifiers
- Agent-friendly `--help` with examples on every CLI subcommand
- XCTest integration suite drives every MCP tool end-to-end on every PR
- `ClearlyMCP` target renamed to `ClearlyCLI` internally (same bundled binary, new subcommand tree)
- New Command Line tab in Settings replaces the MCP Config tab

## [2.2.0] - 2026-04-16
- Hide frontmatter in preview mode with a new toggle in Settings
- Empty folders now appear in the sidebar file tree
- Drag the window from the top of preview mode
- Sidebar width persists correctly on macOS 15
- MCP server config now points to the correct binary
- Opening a scratchpad no longer brings the main workspace window forward
- Sparkle update checks disabled in debug builds

## [2.1.0] - 2026-04-15
- Pin favorite documents to the top of the sidebar for quick access
- Set a preferred content width for comfortable reading on wide displays
- Welcome view with a Getting Started guide greets new users on first launch
- Middle-click a tab to close it
- Toggle the Go to Line and Find bars open/closed with their keyboard shortcuts
- Selected text stays highlighted when switching between editor and preview
- Sidebar remembers its width between app restarts
- Editor stays responsive on large markdown files
- Sidebar and vault index skip heavy directories and respect .gitignore
- Window controls stay accessible when the sidebar and tab bar are hidden
- Location bookmarks validate directory access on restore

## [2.0.0] - 2026-04-14
- Open multiple documents in tabs (Cmd+T, Cmd+W, Cmd+Shift+[/] to switch)
- Link between notes with [[wiki-link]] syntax and auto-complete as you type
- Find any note instantly with Quick Switcher (Cmd+P) and full-text content search
- See which notes link to the current one in the Backlinks panel, with one-click Link for unlinked mentions
- Browse your #tags from the sidebar, with highlighting in both editor and preview
- Expose your vault to AI agents through the bundled MCP server
- Line numbers in the editor with jump-to-line
- Pick a preview font: San Francisco, New York, or SF Mono
- Redesigned marketing site and overhauled demo document
- Large vaults no longer freeze the app while loading
- Fullscreen windows now have correct sidebar and content spacing
- Export PDF and Print work again after the multi-file redesign
- Typing is smooth again on long documents
- Preview cursor no longer leaks into editor mode
- Polished code blocks: copy button, rounded corners, proper gutter width
- Frontmatter tags register correctly alongside inline #tags

## [1.16.0] - 2026-04-12
- Redesigned UI with refined sidebar, toolbar, and file explorer styling

## [1.15.0] - 2026-04-11
- Tables get captions, sortable columns, sticky headers, and a copy-as-TSV button
- Code blocks get syntax highlighting for 27+ languages, line numbers, diff highlighting, and filename headers
- Highlight text with ==marks==, write super^script^ and sub~script~, and use :emoji: shortcodes
- 15 types of callouts and admonitions, with foldable support
- Auto-generated table of contents with [TOC]
- Click any preview element to jump to its source, toggle task checkboxes inline, and view images in a lightbox
- Heading anchor links and footnote popovers
- Sample Document available under the Help menu
- Now licensed under FSL-1.1-MIT (converts to MIT after two years)

## [1.14.0] - 2026-04-10
- Clear your recent files list with one click from the sidebar
- Show or hide hidden files in the file explorer
- Copy files and folders from the toolbar or sidebar right-click menu

## [1.13.1] - 2026-04-09
- Fresh app icon and menubar icon

## [1.13.0] - 2026-04-08
- Create new untitled documents without saving them first
- Bold and bold-italic text now renders visually in the editor instead of just showing markers
- Pick custom icons for folders in the sidebar
- Compact file explorer rows and refined sidebar layout for easier scanning

## [1.12.0] - 2026-04-08
- File explorer sidebar shows favorite locations and recent files for quick navigation

## [1.11.0] - 2026-04-07
- Editor and preview now toggle in place at the same scroll position, replacing side-by-side mode
- Copy code blocks in preview with a one-click button
- Cursor stays put when typing quickly in the editor
- Save scratchpad notes to a file with Cmd+S
- Cmd+Q no longer quits the app when only scratchpads are open

## [1.10.1] - 2026-04-03
- New documents open in front instead of behind existing windows
- Outline panel no longer overlaps the preview in side-by-side mode

## [1.10.0] - 2026-04-02
- Document outline panel lets you jump to any heading with a click
- Native spell checking with persistent preferences for each document
- PDF export handles page breaks correctly instead of slicing content mid-line
- Cmd+Q closes all windows instead of force-quitting, so unsaved work isn't lost
- Editor no longer jumps when typing near the bottom of the window

## [1.9.0] - 2026-03-30
- Scratchpad: a menubar app with a global hotkey for capturing quick notes without opening a full document
- Inline Find bar replaces the broken system Find panel for searching within documents
- Window size and position are remembered per document
- Pasting rich text no longer mangles your markdown
- Opening multiple documents no longer hangs when scroll sync is active

## [1.8.0] - 2026-03-29
- Preview content uses the full window width for easier reading
- Documents automatically refresh when modified by another app

## [1.7.4] - 2026-03-27
- Opening multiple documents no longer freezes the editor when scroll sync is active
- Faster syntax highlighting for documents with frontmatter

## [1.7.3] - 2026-03-26
- Opening multiple documents at once no longer causes the app to hang
- Appearance setting correctly applies your chosen light or dark mode

## [1.7.2] - 2026-03-26
- Diagnostic logs now survive force-quit and include previous session entries
- Faster document opening with fewer redundant highlighting passes

## [1.7.1] - 2026-03-25
- Fixed a hang that could occur when opening multiple documents at once
- Export diagnostic logs from the Help menu for easier troubleshooting

## [1.7.0] - 2026-03-24
- Fixed a Gatekeeper warning when opening markdown files by double-clicking
- Now available on the App Store in addition to direct download

## [1.6.1] - 2026-03-23
- Markdown files are no longer greyed out in the Open panel on some systems

## [1.6.0] - 2026-03-23
- Frontmatter blocks (title, date, tags) are formatted in the editor and rendered cleanly in preview
- Markdown file links are clickable in preview mode — click to open linked documents
- Math expressions now use bundled KaTeX for faster, offline rendering
- The Open Recent menu shows full file paths so you can tell apart files with the same name
- Text and cursor are vertically centered within editor lines for better readability
- New styled DMG installer with drag-to-Applications support

## [1.5.0] - 2026-03-21
- Paste images directly into the editor — they're saved alongside your document and render in preview
- Fixed markdown files not opening correctly from some apps due to a non-standard file type declaration

## [1.4.0] - 2026-03-20
- Right-click to bold, italic, or format selected text
- Math expressions render in preview using LaTeX syntax
- QuickLook previews in Finder's column view use a smaller, better-fitting font

## [1.3.0] - 2026-03-20
- Export your documents as PDF or send them to a printer
- Mermaid diagrams now render in preview mode
- Markdown files open correctly from Finder and other apps

## [1.2.1] - 2026-03-19
- Fixed auto-update failing with "error launching the installer"

## [1.2.0] - 2026-03-19
- Your preferred view mode (editor, preview, or side-by-side) is now remembered across sessions
- Editor and preview scroll together so you always see what you're editing
- Dark mode app icon no longer shows white corners
- Adjust font size with Cmd+ and Cmd- keyboard shortcuts
- Automatic update support via Sparkle

## [1.1.2] - 2026-03-18
- Fixed an issue that prevented auto-updates from installing correctly

## [1.1.1] - 2026-03-18
- Fixed an issue that prevented auto-updates from installing correctly

## [1.1.0] - 2026-03-18
- New side-by-side view mode lets you edit and preview simultaneously
- Code blocks in dark mode preview are now readable
- Broken or relative images show a placeholder instead of nothing

## [1.0.0] - 2026-03-18
- Initial release
