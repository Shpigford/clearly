# Live Editor PR Plan

## Objective

Prepare the live preview editor branch for an upstream PR to Josh Pigford.

This document is the working checklist for that effort. The goal is not just to make the feature work locally. The goal is to make the branch:

- technically sound
- reviewable
- minimal in scope
- safe for user documents
- clean in terms of tracked files
- aligned with the repo's existing architecture and conventions

## Product Positioning

The feature should be presented as:

- an experimental live preview editor
- Obsidian-style markdown-first editing
- CodeMirror 6 hosted inside `WKWebView`
- classic editor preserved
- markdown remains the persisted source of truth
- default app behavior unchanged unless the user opts in

The feature should **not** be presented as:

- a replacement for the classic editor
- a rich-text editor that happens to export markdown
- a permanent architecture decision that removes the native editor path

## Technical Direction

### Chosen approach

- SwiftUI + AppKit app shell remains the host
- file state remains owned by `WorkspaceManager`
- live editor is implemented as a web editor in `WKWebView`
- CodeMirror 6 is the editing substrate
- markdown files remain the canonical saved format
- preview/export/Quick Look remain on the existing rendering pipeline

### Why this approach is appropriate

- `NSTextView` is a good source editor, but the wrong substrate for Obsidian-style live decorations, inline widgets, and selection-aware hiding/revealing of markdown syntax
- CodeMirror 6 provides the right primitives for inline marks, widgets, replacement decorations, and selection-aware rendering
- `WKWebView` keeps the live editor isolated from the rest of the app while allowing the native app to continue owning files, commands, menus, export, and settings
- preserving the classic engine keeps rollout risk acceptable

### Architecture bar before PR

- no document corruption on save
- no document corruption on document switch
- no stale overwrite after external file changes
- no hidden local-only runtime dependency required for normal app builds
- live editor remains optional/experimental
- generated web assets are committed if the repo expects that model

## Current Branch Status

### Completed

- [x] Live editor uses CodeMirror 6 in `WKWebView`
- [x] Classic engine still exists
- [x] Editor engine abstraction exists
- [x] Web editor source is isolated in `ClearlyLiveEditorWeb/`
- [x] Built web assets are bundled under `Shared/Resources/live-editor/`
- [x] `npm run typecheck` passes
- [x] `npm run build` passes
- [x] `xcodebuild -project Clearly.xcodeproj -scheme Clearly -configuration Debug -derivedDataPath ./build CODE_SIGNING_ALLOWED=NO build` passes
- [x] Local-only paths now ignored in `.gitignore`
- [x] `ClearlyLiveEditorWeb/node_modules/` removed from the worktree
- [x] Critical save/switch/external-change guard logic has been substantially hardened

### In progress

- [ ] Final file audit: keep / drop / decide for every changed file
- [ ] Architecture cleanup review for repo-style fit
- [ ] Manual QA against the dangerous document-integrity paths
- [ ] Performance validation on larger notes
- [ ] PR narrative and commit shaping

### Not started

- [ ] Draft PR write-up
- [ ] Final staged commit set
- [ ] Optional refactor to reduce bridge/session coupling if needed

## File Audit

This section is the source of truth for what should and should not be part of the PR.

### Keep

- [x] `.gitignore`
- [x] `Clearly/ClearlyApp.swift`
- [x] `Clearly/ContentView.swift`
- [x] `Clearly/EditorEngine.swift`
- [x] `Clearly/LiveEditorView.swift`
- [x] `Clearly/SettingsView.swift`
- [x] `Clearly/WorkspaceManager.swift`
- [x] `ClearlyLiveEditorWeb/build.mjs`
- [x] `ClearlyLiveEditorWeb/package.json`
- [x] `ClearlyLiveEditorWeb/package-lock.json`
- [x] `ClearlyLiveEditorWeb/src/index.ts`
- [x] `ClearlyLiveEditorWeb/tsconfig.json`
- [x] `Shared/Resources/live-editor/index.html`
- [x] `Shared/Resources/live-editor/live-editor.js`
- [x] `project.yml`

### Decide

- [ ] `docs/expansion/IMPLEMENTATION.md`
- [ ] `docs/markdown-rendering-architecture.md`

### Likely drop from upstream PR

- [ ] `CLAUDE.md`

### Must never be included

- [x] `.agents/`
- [x] `.codex/`
- [x] `AGENTS.md`
- [x] `script/`
- [x] `ClearlyLiveEditorWeb/node_modules/`
- [x] local build artifacts and caches

## Repo-Style Review Checklist

### Conventions

- [ ] Colors still flow through existing app theme conventions where relevant
- [ ] New code comments are minimal and only explain non-obvious behavior
- [ ] Experimental behavior is clearly labeled as experimental
- [ ] Project structure remains coherent and unsurprising
- [ ] App Store / Sparkle build assumptions are unaffected

### Boundary quality

- [ ] Native app owns file lifecycle, menus, and settings
- [ ] JS editor owns immediate editing/rendering behavior only
- [ ] Bridge surface is narrow and explicit
- [ ] No accidental coupling from low-level app state into arbitrary web editor internals
- [ ] If `WorkspaceManager` depends on live-editor session state, that dependency is intentional and reviewable

### Feature behavior

- [ ] Live editor does not regress classic editor behavior
- [ ] Live editor does not force preview mode concepts back into the new model
- [ ] Unsupported markdown falls back to editable source rather than hidden broken state

## Correctness Gate

The PR should not be opened until these are manually verified.

### Document integrity

- [ ] Type in a file, save, quit, reopen: content preserved
- [ ] Type in file A, switch immediately to file B: A and B both remain correct
- [ ] Delete all content, save, reopen: file stays empty and does not resurrect stale content
- [ ] External file modification while editor is open: app reloads without stale overwrite
- [ ] Discard/reload flows do not restore stale live-editor content

### Navigation and opening

- [ ] Opening files from sidebar works consistently
- [ ] Opening existing documents does not blank them
- [ ] Markdown links open correctly
- [ ] Wiki links and tag actions still route correctly

### Input behavior

- [ ] Plain typing remains stable
- [ ] Inline formatting updates correctly
- [ ] Paste works when editor has focus
- [ ] Paste does not leak into editor when another control owns focus
- [ ] Undo/redo behaves correctly

### Search / commands

- [ ] Find integration works in live editor
- [ ] Menu formatting commands target the correct editor engine
- [ ] Outline navigation still works

## Performance Gate

- [ ] Small note: no visible lag while typing
- [ ] Medium note: decorations remain responsive
- [ ] Large note: no unacceptable typing lag
- [ ] Large paste: app remains usable
- [ ] Scrolling through notes with code fences/tables/math/Mermaid is acceptable
- [ ] Decoration rebuild behavior is not obviously wasteful on non-document transactions

## Documentation Needed Before PR

- [ ] This plan remains current
- [ ] One concise architecture note exists for the live editor
- [ ] PR description includes:
  - problem statement
  - chosen approach
  - why CodeMirror over native/AppKit for this feature
  - rollout strategy
  - known limitations
  - manual QA summary

## PR Strategy

### Recommended PR shape

Open as a draft PR first.

Suggested framing:

- add experimental live preview editor
- preserve classic engine
- markdown remains source of truth
- keep feature opt-in

### Suggested commit grouping

1. bridge + editor engine plumbing
2. CodeMirror web editor package + bundled assets
3. data-integrity hardening for save/switch/external-file sync
4. docs / repo hygiene

### Review posture

The branch should be reviewable even if the feature is not accepted immediately.

That means:

- no local junk
- no unexplained file additions
- no mixed-in unrelated docs/config edits
- no vague “works for me” claims
- no hiding of known risks

## Immediate Next Steps

- [ ] Decide whether `CLAUDE.md` belongs in the PR at all
- [ ] Decide whether `docs/expansion/IMPLEMENTATION.md` and `docs/markdown-rendering-architecture.md` belong in this PR
- [ ] Run the full manual document-integrity matrix
- [ ] Run performance checks on representative notes
- [ ] Review `WorkspaceManager` ↔ live editor bridge coupling for cleanliness
- [ ] Prepare the draft PR summary
