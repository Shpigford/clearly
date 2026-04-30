# list-view-polish Research

## Overview

Three polish items on the Mac 3-pane layout's middle "Notes list" column (`MacNoteListView`):

1. The blue filled icon in the list-view header is visually heavier than every other icon in the app.
2. Clicking a note that lives inside a subfolder unexpectedly reduces the list-view's scope to just that subfolder.
3. *(Bonus)* Allow the list-view pane to be dragged closed with a snap, the same way the folder sidebar collapses today.

Source brief: [docs/list-view/POLISH-BRIEF.md](../list-view/POLISH-BRIEF.md).

## Problem Statement

The 3-pane Notes-style layout was added recently (commit `0326f23 [mac] Add Notes-style 3-pane layout with folder-driven note list`). The middle column works, but three rough edges undermine it:

- **Visual inconsistency.** The header's recursion-toggle icon uses `Color.accentColor` for its "active" state — every other icon in the app is `.secondary` or unstyled (system tint at default weight), so the active toggle looks like a primary CTA when it's really a quiet state indicator.
- **Surprising scope change on note click.** Selecting a note in the list silently changes the folder scope, even when the user had no intent to navigate. They lose the broader list of notes they were just browsing.
- **No snap-collapse on the middle pane.** The folder sidebar snap-collapses on drag (free SwiftUI behaviour). The middle column does not. Asymmetry hurts discoverability.

## User Stories / Use Cases

- *I drag through a long flat list of all my project notes, click one to read, and the list stays put so I can keep scanning.*
- *I scan the toolbar / list-view header at a glance and don't see any element that screams louder than the others.*
- *I'm working with a small note in the middle column and want more editor width — I drag the list pane left and it collapses, just like the folder pane does.*

## Technical Research

### Issue 1 — Blue icon is the recursion toggle

The icon lives in [Clearly/Native/MacNoteListView.swift:86-101](../../Clearly/Native/MacNoteListView.swift). It's a `Button` that toggles `WorkspaceManager.isFolderRecursive(folder)` between two states:

- `rectangle.stack.fill` + `Color.accentColor` → "Showing notes from subfolders" (recursive)
- `rectangle` + `Color.secondary` → "Showing this folder only" (non-recursive)

The icon-style audit confirmed the rest of the Mac app's icons are either:
- Toolbar icons (`MacDetailColumn.swift`) — unstyled, default tint, monochrome
- Sidebar row icons (`MacFolderSidebar.swift:564, 679`) — `.foregroundStyle(.secondary)` by default, `.tint` only when the row is *selected*

Neither pattern uses `Color.accentColor` for a stateful icon at rest. The recursion toggle is the lone offender. `Theme.swift` exposes `accentColor` and `accentColorSwiftUI` but defines no dedicated "active state" icon token — the convention is to lean on system semantic styles (`.secondary`, `.tint`, `.primary`).

**The toggle itself is useful** (the tooltip even explains it), so removing it is the wrong call. The fix is restyling the active state to match the rest of the app.

#### Approach options for the active state

| Option | Pros | Cons |
|---|---|---|
| **A. `.primary` for active, `.secondary` for inactive; keep `fill` vs outline glyph swap** | Minimal change. Glyph-fill carries the state; colour difference is subtle but readable. Matches the convention for stateful icons used in `RecentRowLabel`. | If `.primary` is also default toolbar tint, "active" may not pop enough. |
| **B. Always `.secondary`; rely solely on the glyph swap (filled vs outlined) for state** | Calmest visually. Closest match to other icons. | "Filled vs outline" alone may be too subtle for a button users need to find. |
| **C. Keep `.accentColor` but reduce visual weight (smaller `imageScale`, lower opacity, or a soft background pill)** | Preserves the "this state is non-default" cue. | Still introduces a colour the rest of the header lacks. |
| **D. Small filled background "pill" behind the icon when active (icon stays `.secondary` or `.primary`)** | Native Mac toolbar pattern. Clear "this is on" signal without colour pollution. | Adds 5-10 lines for the pill view. |

**Recommended: Option A** for the simplest path; **Option D** if the team wants the toggle to read as "on/off" more loudly while still being calm.

### Issue 2 — List-view scope changes on note click (root-caused)

Bug source: [Clearly/Native/MacRootView.swift:73-86](../../Clearly/Native/MacRootView.swift). The `onChange(of: selectedFileURL)` handler unconditionally moves the active folder to the clicked note's parent:

```swift
.onChange(of: selectedFileURL) { _, newURL in
    guard let url = newURL else { return }
    // Keep the 3-pane middle list in sync with sidebar navigation:
    // selecting a file in the sidebar moves the active folder to
    // its parent so the middle list scrolls to and highlights the
    // file. ...
    let parent = url.deletingLastPathComponent()
    if workspace.selectedFolderURL?.standardizedFileURL != parent.standardizedFileURL,
       workspace.vaultIndexAndRelativePath(for: parent) != nil {
        workspace.setSelectedFolder(parent)
    }
}
```

The comment says *"selecting a file in the sidebar moves the active folder to its parent"* — but `selectedFileURL` is shared between sidebar and list-view. When a user clicks a note in the **middle list** (which is showing recursive results), the same observer fires and snaps the scope to that note's parent, hiding the rest of the list.

#### Approach options

| Option | Pros | Cons |
|---|---|---|
| **A. Move the parent-folder logic out of the observer and into the sidebar's click handler.** When the sidebar selects a file, it both opens the file *and* sets `selectedFolderURL`. The list's row click only opens the file. | Correct separation of concerns. Each click handler does what its surface implies. | Touches both `MacFolderSidebar` and `MacRootView`; needs care so wiki/recents click paths aren't broken. |
| **B. Add a "scope change suppression" flag set by the list, checked by the observer.** | Minimal diff. | State flag pattern is brittle; future click sources (e.g. backlinks pane) need to remember to set it. |
| **C. Guard the observer: only call `setSelectedFolder(parent)` if the new file is *not* already visible in the current list scope.** | One-place fix; no flag plumbing. Naturally captures "the user clicked a note that's already on screen — leave the scope alone." | Requires asking the list whether it currently shows a given URL — needs `WorkspaceManager` or `MacNoteListView` to expose that. |

**Recommended: Option A** — moves the logic to where intent is unambiguous (the sidebar's selection callback). The observer is removed entirely; sidebar click sets both folder and file, list click only sets file.

### Issue 3 — Drag-to-collapse on the list-view pane

Layout, verified at [Clearly/Native/MacRootView.swift:50-65, 118](../../Clearly/Native/MacRootView.swift): the 3-pane mode uses a 3-column `NavigationSplitView`:

- **Sidebar** — `min: 220, ideal: 260, max: 360`, plus `columnVisibility` binding controlling sidebar/content/detail visibility states.
- **Content (Notes list / `MacNoteListView`)** — `min: 220, ideal: 280, max: 420`.
- **Detail** — editor.

The folder sidebar's snap-to-collapse is a **free** behaviour of `NavigationSplitView` — when the user drags the divider below the column's `min` width, AppKit snaps it closed and updates `columnVisibility`. No custom drag-gesture code in the repo.

For the middle "content" column, the story is murkier:
- The `NavigationSplitViewVisibility` enum has values `.all`, `.doubleColumn` (hides sidebar, shows content+detail), `.detailOnly` (hides both), and `.automatic`. There's no symmetric "hide content only" value.
- Dragging the divider between content and detail in a 3-column split *typically* doesn't snap-close the content column — Apple's API biases toward toggling the *sidebar*, not the middle.

**This means the bonus is likely NOT free.** The escape hatches:

| Option | Cost | Notes |
|---|---|---|
| **A. Add a manual "Hide Notes List" toggle (menu + ⌘-shortcut), animated width collapse.** No drag gesture. | Small (~30 lines). Re-uses outline-pane visibility pattern from `MacDetailColumn`. | Doesn't match the brief's "drag to collapse" feel. |
| **B. Wrap the middle column's right-edge divider in a custom `DragGesture`. Track translation; if dragged past a threshold (-50pt) collapse the pane (animated width to 0).** | Medium (~60-80 lines). | Matches the brief, but reaches into SwiftUI's split-view chrome — fragile across macOS versions. |
| **C. Restructure the content column out of `NavigationSplitView` into the same `HStack` pattern used in `MacDetailColumn` for the outline pane, then implement custom drag-collapse there.** | Large (touches root layout). | Loses the free sidebar snap behaviour for the sidebar, or requires hybrid layout. Not recommended. |

**Recommended:** Try Option B first as a small, time-boxed spike (≤2 hours). If `NavigationSplitView`'s internal divider doesn't expose enough control for a clean implementation, fall back to Option A (a menu toggle, no drag), and ship the polish without the snap. The brief explicitly says "only if this is not some crazy amount of custom dev" — Option B is the upper acceptable bound.

## Required Technologies

- SwiftUI (`NavigationSplitView`, `DragGesture`, `withAnimation`)
- AppKit-adjacent (`NSSplitViewController.toggleSidebar` is already used at `ClearlyApp.swift:674` for the existing sidebar toggle — reference for the menu/keyboard approach in Option 3A)
- SF Symbols (`rectangle`, `rectangle.stack.fill` already in use)
- No new packages.

## Data Requirements

None. All three items are pure UI / state-routing changes. `WorkspaceManager.selectedFolderURL`, `nonRecursiveFolders`, `noteListSortOrder`, and the existing `columnVisibility` cover everything.

## UI/UX Considerations

- **Issue 1's "active" colour decision matters more than it looks.** A too-subtle active state means users won't realise the recursion toggle is on; a too-loud one is the original complaint. Pick A or D and verify by switching modes side-by-side.
- **Issue 2's intended sidebar behaviour must be preserved.** When the user picks a file via the sidebar's outline (e.g. clicks a leaf node deep in `Projects/cookbook-creator/`), the middle list *should* still navigate to that folder — that's how they get the file's siblings on screen. Only middle-list clicks should be scope-preserving.
- **Issue 3's collapsed state needs a way back.** A keyboard shortcut (e.g. ⌥⌘L mirroring ⌘L for sidebar) plus a menu item under View → Show Notes List. CLAUDE.md flags a known pitfall here: SwiftUI `.keyboardShortcut(letter, modifiers: [.command, .option])` does not actually dispatch on this macOS — the `injectHideToolbarIfNeeded` pattern in `ClearlyAppDelegate.applicationWillUpdate` is the workaround. Reference that when wiring the shortcut.

## Integration Points

- [Clearly/Native/MacNoteListView.swift:86-101](../../Clearly/Native/MacNoteListView.swift) — recursion-toggle styling (Issue 1).
- [Clearly/Native/MacRootView.swift:73-86](../../Clearly/Native/MacRootView.swift) — `onChange(of: selectedFileURL)` observer to remove (Issue 2).
- [Clearly/Native/MacFolderSidebar.swift](../../Clearly/Native/MacFolderSidebar.swift) — sidebar selection handler that needs to take over the parent-folder-set responsibility (Issue 2).
- [Clearly/Native/MacRootView.swift:50-65](../../Clearly/Native/MacRootView.swift) — 3-column `NavigationSplitView` where the snap-collapse work lives (Issue 3).
- [Clearly/ClearlyApp.swift](../../Clearly/ClearlyApp.swift) — view-menu wiring + keyboard shortcut for the Notes-list visibility toggle (Issue 3, fallback path).
- `Packages/ClearlyCore/Sources/ClearlyCore/Rendering/Theme.swift` — *no change required* unless we decide to introduce a dedicated "active icon" token.

## Risks and Challenges

- **Issue 2's refactor reach.** Moving the parent-folder logic into the sidebar's click handler means touching every sidebar code path that selects a file (folder rows, recents, pinned, wiki). Risk of regressing one of those flows. Mitigation: enumerate every `setSelected` call site in `MacFolderSidebar` and route them through one helper that does both folder-and-file in one place.
- **Issue 3's drag-gesture brittleness.** SwiftUI's `NavigationSplitView` doesn't expose a public hook for the inter-column divider. Option B's drag-gesture implementation overlays a transparent grab area on the divider region — works today, may break with a macOS SDK update. Time-box the spike; fall back to a menu toggle if the implementation drifts past ~80 lines.
- **Issue 1's accessibility.** The active recursion state must remain readable to screen readers regardless of the visual style chosen. Confirm `accessibilityLabel("Showing notes from subfolders")` is on the button (it isn't yet — the `.help(...)` is for tooltips only).

## Open Questions

1. **Active recursion-toggle style — A (`.primary` colour swap) or D (background pill)?** A is one-line; D is more legible. Need a UI call before implementation. *(See "Approach options" under Issue 1.)*
2. **Issue 3 — accept Option A (menu toggle, no drag) as the deliverable if Option B's drag-spike doesn't land cleanly inside ~2 hours?** If yes, the bonus ships either way; if no, the bonus is "drag-only or nothing".
3. **Should the new "Hide Notes List" command exist regardless of which path Issue 3 takes?** Symmetry argument: the sidebar already has ⌘L plus View menu items. The list pane should too, even if drag works.

## References

- Existing `NavigationSplitView` setup: `Clearly/Native/MacRootView.swift:36-118`
- Existing sidebar toggle / keyboard wiring: `Clearly/ClearlyApp.swift:674`
- Stateful-icon precedent (per-row selection): `Clearly/Native/MacFolderSidebar.swift:679`
- Source brief: `docs/list-view/POLISH-BRIEF.md`
- CLAUDE.md notes referenced: "Avoid `.inspector()` for panels…", "SwiftUI `.keyboardShortcut(letter, modifiers: [.command, .option])` does not dispatch…"
