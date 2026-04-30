# list-view-polish Implementation Plan

## Overview

Three polish items on the Mac 3-pane layout, sequenced into two phases:

- **Phase 1 — Bugs (Issues 1 + 2).** Restyle the recursion toggle so it stops looking like a primary action, and stop the middle list-view from changing scope when the user opens a note.
- **Phase 2 — Bonus (Issue 3).** Time-boxed drag-to-collapse spike on the middle pane. Ship if it lands cleanly; drop entirely if it doesn't.

Decisions locked in (from /build research + follow-up questions):

- **Issue 1 styling:** Always `.foregroundStyle(.secondary)` — no colour difference between active and inactive. The glyph swap (`rectangle.stack.fill` ↔ `rectangle`) is the *only* state cue.
- **Issue 2 fix direction:** Move "set parent folder" responsibility into the sidebar's own selection path; remove the global `onChange(of: selectedFileURL)` observer in `MacRootView`.
- **Issue 3:** Drag gesture only. **No menu / keyboard fallback.** If the drag spike doesn't land cleanly inside ~2 hours, drop the bonus and document why.

## Prerequisites

- Worktree on `claude/blissful-saha-9e5e60` (current).
- Xcode 26+ with macOS 26 SDK.
- `xcodegen generate && xcodebuild -derivedDataPath ./.build/DerivedData -scheme "Clearly Dev" -configuration Debug build` succeeds from the worktree root before any phase begins.

## Phase Summary

| # | Phase | Size | User-visible result |
|---|---|---|---|
| 1 | Restyle toggle + decouple scope | ~3 hr | Header icon goes quiet (matches everything else); clicking notes no longer collapses the list. |
| 2 | Drag-to-collapse spike | ≤2 hr | *(If lands)* Drag the middle pane's right divider left to snap it closed. *(If not)* Nothing — bonus deferred. |

---

## Phase 1: Restyle toggle + decouple scope from note clicks

### Objective

Bundle the two confirmed bugs into one phase. After this phase ships, the middle list-view header is visually consistent with the rest of the app, and clicking a note from the list never changes the list's scope.

### Rationale

These are the two items the user actually noticed. Issue 1 is a one-line change; Issue 2 is a careful refactor. They share the same surface (`MacRootView` + the middle pane) so reviewing them together is natural. If priorities shift later, both are independently revertable inside the phase.

### Tasks

#### 1.1 — Restyle the recursion toggle (Issue 1)

- [ ] In `recursionToggle(folder:)` at [Clearly/Native/MacNoteListView.swift:86-101](../../Clearly/Native/MacNoteListView.swift), change line 95 from `.foregroundStyle(isRecursive ? Color.accentColor : Color.secondary)` to `.foregroundStyle(.secondary)`.
- [ ] Keep the existing glyph swap (`rectangle.stack.fill` when recursive, `rectangle` when not). That swap now carries 100% of the state signal.
- [ ] Add `.accessibilityLabel(…)` to the button reflecting the current state — mirror the strings from `.help(…)` on lines 98-100. This is the only state cue available to VoiceOver since colour no longer differs.
- [ ] Build + screenshot in **light** and **dark** mode. Confirm the toggle reads "calm but legible" next to the sort icon (`arrow.up.arrow.down`, line 119, also `.secondary`).

#### 1.2 — Decouple list-view scope from note clicks (Issue 2)

- [ ] Read [Clearly/Native/MacFolderSidebar.swift:43-110, 420-441, 729-737](../../Clearly/Native/MacFolderSidebar.swift) before changing anything. There's non-trivial bookkeeping around the selection-restoration path on view rebuilds (lines 420-441) and a documented cmd-click vs. plain-click branch (lines 729-737). Both must keep working.
- [ ] Add a parameter to `MacFolderSidebar`: `var onUserSelectFile: ((URL) -> Void)? = nil`. Fire it **only** on a user-initiated selection (an actual click), not during programmatic selection-restoration.
  - Implementation hint: gate the callback behind a comparison against `previousSelection` plus a "was this triggered by the rebuild guard?" flag, OR wrap the `List(selection:)` binding so the setter knows about user-initiated changes.
- [ ] In [Clearly/Native/MacRootView.swift:50-65](../../Clearly/Native/MacRootView.swift), pass an `onUserSelectFile` closure to `MacFolderSidebar`. The closure replicates the deleted observer's intent: standardise the URL, run the `vaultIndexAndRelativePath(for:)` guard, then call `workspace.setSelectedFolder(url.deletingLastPathComponent())`.
- [ ] Delete the entire `onChange(of: selectedFileURL)` block at [Clearly/Native/MacRootView.swift:73-86](../../Clearly/Native/MacRootView.swift). The behaviour now lives where intent is unambiguous.
- [ ] Audit other selection paths that currently set `selectedFileURL`: wiki rows, recents rows, pinned rows (all inside `MacFolderSidebar` — they benefit from the new callback automatically), file-open via menu / ⌘O, drag-and-drop import. The latter two must NOT trigger the parent-folder change — they're not "navigations" — so they correctly stay outside the sidebar's callback.
- [ ] Smoke-test cmd-click (referenced in lines 729-737) — selecting via cmd-click should continue to do whatever it currently does, unchanged.

### Success Criteria

#### Issue 1
- The recursion toggle's icon, in either state, reads as `.secondary` and looks at home next to the sort icon and the surrounding header.
- Toggling on/off remains visually distinguishable via the glyph fill/outline swap.
- VoiceOver reads the appropriate state from the new `.accessibilityLabel`.

#### Issue 2
- Click a note in the **middle list-view** → the editor opens the note, the list-view header is unchanged, `selectedFolderURL` is unchanged.
- Click a deeply-nested file in the **sidebar** → the editor opens the note, the middle list scope moves to the file's parent so siblings appear.
- Recents / Pinned / Wiki row clicks still open files normally.
- Cmd-click in the sidebar behaves exactly as it does today.
- Selecting a file via ⌘O does not move the list scope.

#### Both
- Verified by running the actual Mac app and capturing screenshots:
  - Light + dark mode for the recursion toggle in active and inactive states (4 screenshots).
  - "Before" screenshot (list shows "Projects · 252 Notes") + "after click on subfolder note" screenshot (header still says "Projects · 252 Notes") — proves Issue 2.

### Files Likely Affected

- `Clearly/Native/MacNoteListView.swift` — Issue 1
- `Clearly/Native/MacFolderSidebar.swift` — Issue 2 (add callback)
- `Clearly/Native/MacRootView.swift` — Issue 2 (delete observer, pass callback)

### Notes / Risks

- **Calling the callback at the right moment is the central risk for Issue 2.** Naive `onChange(of: selectedFileURL)` inside the sidebar would fire during rebuild-restoration (lines 428-441) and re-introduce the bug we just removed. Either:
  1. Wrap the `List(selection: $selectedFileURL)` binding in a custom `Binding` whose `set:` also calls the callback — the rebuild path bypasses this since it assigns `selectedFileURL` directly, not via the binding.
  2. Add a `@State private var userInitiatedSelection: Bool = true` flag, set it `false` around the rebuild assignment, gate the callback on it.
- If `.secondary` proves *too* subtle in dark mode (the glyph fill alone may be hard to read against a low-contrast background), revisit — but only after capturing the screenshots and looking, not pre-emptively.

---

## Phase 2: Drag-to-collapse spike (≤2hr cap, drop if blocked)

### Objective

Let the user drag the middle list-view's right divider leftward past a snap threshold to collapse the pane. Re-opening: drag rightward from the collapsed edge. **No menu, no keyboard shortcut** — drag is the entire interaction surface.

Hard cap: **2 hours**. If at any point the implementation requires meaningful custom split-view chrome, abandon and document.

### Rationale

The brief was explicit: "only if this is not some crazy amount of custom dev". The user reaffirmed that — drag-only, no menu fallback. So this phase is opportunistic. We try, and either it works or we drop it.

### Tasks

- [ ] **Spike step 1 (~15 min):** Check what `NavigationSplitView` already does on its inter-column dividers. Drag the existing middle/detail divider in the running app. If it already snap-collapses past the column's `min` width and exposes that via `columnVisibility` or any binding, the work is just reading + binding to that state.
- [ ] **Spike step 2 (~30 min):** If step 1 doesn't yield a freebie, try overlaying an invisible drag handle on the right edge of the middle column:
  ```swift
  .overlay(alignment: .trailing) {
      Color.clear
          .frame(width: 8)
          .contentShape(Rectangle())
          .gesture(
              DragGesture()
                  .onChanged { /* track translation */ }
                  .onEnded { value in
                      if value.translation.width < -50 {
                          withAnimation(Theme.Motion.smooth) { isListVisible = false }
                      }
                  }
          )
  }
  ```
- [ ] **Spike step 3:** Add the visibility state itself — a `@State private var isListVisible: Bool = true` in `MacRootView` (no need to persist or expose via `@FocusedValue` since there's no menu / no shortcut).
- [ ] **Spike step 4:** Re-opening the pane needs to also be drag-only. Options:
  - A thin invisible peek strip along the left edge of the editor that responds to a rightward drag past +50pt → re-show the list.
  - Or accept that the pane only re-opens when the user changes folder selection, and document that.
- [ ] **Spike step 5:** Verify the snap feels like the existing folder-sidebar snap (which is a SwiftUI freebie). If our drag implementation is jarring — cursor jumps, divider visual artefacts, animation feels wrong — that's the signal to abandon.
- [ ] **Decision gate at the 2hr mark:** If everything above is working, polish and ship. If not, revert all changes, write a "Spike findings" entry into PROGRESS.md describing what was tried and what blocked, and stop.

### Success Criteria

**If shipped:**
- Drag the middle list-view's right divider leftward past ~50pt → pane animates closed.
- Drag the editor's left edge rightward past ~50pt → pane animates open. (Or whatever re-open mechanism the spike landed on.)
- Snap feel matches the folder-pane behaviour closely enough that a user would describe both as "the same gesture".
- No regressions to folder-sidebar snap or to either of Phase 1's fixes.
- Verified by recording the gesture (screenshot before / mid-drag / after) in light or dark mode.

**If dropped:**
- All Phase 2 changes reverted from the working tree.
- PROGRESS.md "Spike findings" section explains what was attempted and why it didn't land cleanly. Specifically: was it `NavigationSplitView` chrome rejecting overlays, was it the divider hit-testing, was the snap animation impossible without an `NSSplitView` wrapper, etc.

### Files Likely Affected

*(Only if shipped — empty if dropped.)*

- `Clearly/Native/MacRootView.swift` — visibility state, conditional column rendering, drag overlay.

### Notes / Risks

- **The biggest risk is silent abandonment.** Spikes are easy to over-extend. The 2-hour cap is real. Set a timer and respect it.
- `NavigationSplitView`'s API for hiding the *content* column (vs. the sidebar) is asymmetric — there is no `NavigationSplitViewVisibility` value that hides only the middle. So conditional rendering is the most likely path; if SwiftUI complains about column-tree changes mid-flight, the next-cheapest workaround is animating the column's frame width to 0.
- The 3-pane → 2-pane fallback already in `MacRootView` (the file branches between two `NavigationSplitView` configurations at lines 44 vs 50 — depending on whether the user is in 3-pane mode or not) must keep working. Don't compose with it unless verified.

---

## Post-Implementation

- [ ] Take "before / after" screenshots in light + dark and attach to the eventual PR.
- [ ] Update `docs/list-view/POLISH-BRIEF.md` with a "Resolution" note linking the PR and listing which items shipped.
- [ ] Commits on `claude/blissful-saha-9e5e60` with `[mac]` scope (per CLAUDE.md). Phase 1 = one commit (or two — toggle and scope-fix as separate commits if cleaner). Phase 2 = one commit if shipped, none if dropped.

## Notes

- Phase 1 is the load-bearing one — the two items the user actually flagged as broken. Phase 2 is bonus.
- If anything in Phase 1's Issue 2 starts requiring sidebar refactors beyond "add a callback parameter and wire it", stop and re-plan — the bug fix isn't worth a sweeping rewrite of `MacFolderSidebar`'s 1000+ lines.
- Phase 2's drag spike is the one place with genuine uncertainty. Honour the time-box.
