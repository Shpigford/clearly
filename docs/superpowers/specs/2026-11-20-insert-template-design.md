# Insert Template — Design

**Date:** 2026-11-20
**Branch:** `feature/template` (from `v2.13.0`)
**Status:** approved

## Intent

Insert a vault template at the start of an already-existing markdown file. The file is created however the user already creates notes. Templates are static markdown, matching the user's Obsidian `Templates/` files, without Dataview or JavaScript.

## Why

The user wants Obsidian-style templates in Clearly: pick a named template from a list and prepend it to the current note. DataviewJS / Dataview queries must not run.

## Goals

- List `.md` files from `<vault>/Templates/` (Obsidian folder name).
- Right-click a file in the Mac sidebar → **Insert Template** submenu.
- Same list on a hotkey for the active document.
- Substitute `{{date}}` (`yyyy-MM-dd`), `{{time}}` (`HH:mm`), `{{title}}` (filename without `.md`).
- Strip `dataview` / `dataviewjs` fenced blocks on insert, including quoted fences inside callouts. Empty `> [!…]` callouts left behind are removed.
- If the target file is open, prepend in the editor buffer (Undo when the source editor is mounted). If it is not open, prepend on disk.
- If `_templates` / settings UI / create-from-template flows were considered, they are out of scope.

## Non-goals

- Creating a new file from a template.
- iOS.
- Executing Dataview, Templater JS, or shell commands.
- Bundling the user's personal templates in the app.
- A settings screen for the templates folder.
- Recursive listing of `Templates/` subfolders.
- Sparkle / update-channel changes.

## Anti-goals

- Running any JavaScript from a template.
- Using `⌥⌘T` (already **Hide Toolbar**).
- Using SwiftUI `.keyboardShortcut` with `[.command, .option]` (does not dispatch; inject via AppKit).

## Constraints

- Mac-only UI; engine in `ClearlyCore` so it can be unit-tested.
- Commits scoped `[shared]` (engine) or `[mac]` (UI).
- `⌥⌘I` for the active-document command (Insert), injected like Hide Toolbar.
- Read/write vault files through `CoordinatedFileIO`.
- Do not set `IOSDocumentSession.errorMessage`-style load failures on a failed insert; log and leave the buffer.

## Approaches

1. **New file from template** (File → New from Template, name sheet). Rejected: user wants to insert into an existing file.
2. **Prepend into the existing file from the sidebar / hotkey.** Chosen.
3. **Execute Dataview/JS like Obsidian.** Rejected: static markdown only.

## How

- `NoteTemplateEngine` in ClearlyCore: list, strip query blocks, expand placeholders, join prefix + existing text.
- `WorkspaceManager.insertTemplate(_:into:)` applies that string to the open buffer or to disk.
- Sidebar `fileContextMenu` gains an `Insert Template` menu.
- AppDelegate injects **Edit → Insert Template** with submenu + `⌥⌘I`.

## Builder calls

- Templates folder name is `Templates`, not `_templates`.
- Only top-level `*.md` in that folder, sorted by localized standard compare.
- Missing or empty folder → menu disabled, no alert.
- File outside any vault, or untitled buffer → menu disabled.
- Join rule: if existing text is empty, result is the expanded template; otherwise expanded template (trimmed of trailing newlines) + `\n\n` + existing text.
- Active document in edit mode: prepend via `NSTextView.insertText` at location 0 so Undo works. Other cases assign the combined string on the document / disk.
