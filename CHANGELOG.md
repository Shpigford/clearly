# Changelog

## [Unreleased]

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
