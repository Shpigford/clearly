# list-view-polish Progress

## Status: Phase 1 - Complete

## Quick Reference

- Research: [docs/list-view-polish/RESEARCH.md](RESEARCH.md)
- Implementation: [docs/list-view-polish/IMPLEMENTATION.md](IMPLEMENTATION.md)
- Source brief: [docs/list-view/POLISH-BRIEF.md](../list-view/POLISH-BRIEF.md)
- Target branch: `claude/blissful-saha-9e5e60` (eventual PR to upstream/main)
- Worktree: `.claude/worktrees/sad-wescoff-b21eb9` (path-misnamed; tracks blissful-saha)

---

## Phase Progress

### Phase 1: Restyle toggle + decouple scope from note clicks
**Status:** Complete

#### Tasks Completed

##### 1.1 — Restyle the recursion toggle (Issue 1)
- [x] Change line 95 in `MacNoteListView.swift` to `.foregroundStyle(.secondary)` (dropped the `accentColor` branch).
- [x] Add `.accessibilityLabel(…)` matching the active/inactive `.help(…)` strings.
- [x] Build (`xcodebuild ... -derivedDataPath ./.build/DerivedData CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO`) — `BUILD SUCCEEDED`.
- [x] Screenshot in light mode — toggle reads as `.secondary` gray, indistinguishable in weight from the neighbouring sort icon. Filled-vs-outlined glyph swap clearly visible (`rectangle.stack.fill` for recursive; `rectangle` for not).
- [x] Screenshot in dark mode — same. Soft gray icon, glyph fill cue still readable against the dark surface.
- [x] Legibility confirmed next to `arrow.up.arrow.down` sort icon — both render at identical weight.

##### 1.2 — Decouple list-view scope from note clicks (Issue 2)
- [x] Read `MacFolderSidebar.swift:43-110, 420-441, 725-776` and `MacRootView.swift:1-158`.
- [x] **Architecture changed during implementation** (see Decisions Made): instead of adding a callback parameter to `MacFolderSidebar`, leveraged the pre-existing `SidebarClickModifierWatcher` probe (already attached to both panes) by introducing a `ClickSource` enum and recording the click origin. Smaller diff, no signature change to `MacFolderSidebar`.
- [x] Added `private enum ClickSource { case none, sidebar, list }` and `@State private var lastClickSource: ClickSource = .none` in `MacRootView`.
- [x] Sidebar probe sets `lastClickSource = .sidebar`; list probe sets `lastClickSource = .list`.
- [x] In the existing `onChange(of: selectedFileURL)` observer, gated the parent-folder logic behind `cameFromSidebar = lastClickSource == .sidebar && timestamp within 0.25s`.
- [x] Reset `lastClickSource = .none` along with the existing modifier/time resets so stale state can't leak into the next event.
- [x] Smoke-tested all three intended behaviours — see Verification.

#### Decisions Made

- **Used the existing click-source probe instead of adding a callback to `MacFolderSidebar`.** Reason: `SidebarClickModifierWatcher` is already attached to both panes and was already feeding `lastSidebarClickModifiers`/`lastSidebarClickTime` for the cmd-click branch. Adding a `ClickSource` enum to the same flow gave us "where did this click come from" with minimal new code, no new parameter on `MacFolderSidebar`, and no concerns about firing a callback during programmatic re-selection (the probe only fires on real `.leftMouseDown` events). The IMPLEMENTATION.md's "callback + rebuild-guard" plan would have been correct but was strictly more code for the same outcome.
- **Kept the original cmd-click logic untouched.** Both panes still feed the same modifier/time state for cmd-click → "open in new tab" behaviour. The new `ClickSource` only gates the parent-folder logic, not the cmd-click logic.

#### Blockers

- (none)

#### Verification

- **Channels:** Built and ran the actual `Clearly Dev.app` (not signed for distribution — used `CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO`). Captured five screenshots at `mcp__computer-use__screenshot` resolution.
- **Issue 1 (icon style) — light mode:** With recursion ON, header showed "Projects · 255 Notes" plus a `.secondary` gray filled-stack glyph at identical weight to the adjacent sort icon. With recursion OFF, glyph swapped to outlined `rectangle` at the same `.secondary` weight. No colour difference between active/inactive.
- **Issue 1 (icon style) — dark mode:** Same monochrome rendering at `.secondary`, soft gray against the dark surface. Glyph fill still clearly readable.
- **Issue 2 (list click does not change scope):** Pre-test, list showed "Projects · 255 Notes". Clicked `property24` (a note that lives inside one of the Projects subfolders) in the middle list. Editor opened the note correctly; **list header remained "Projects · 255 Notes"**. The bug is fixed.
- **Issue 2 (sidebar click still navigates):** Clicked "One file" (a leaf in the sidebar's `Desktop` location). Editor opened the note; **list header changed to "Desktop · 1 Note"** as expected. Sidebar navigation still works.
- **Behavioural regressions checked:** None observed during the smoke test. Cmd-click logic was preserved (not directly tested in the smoke since both panes feed the same modifier state — but the `lastSidebarClickModifiers` reset path is unchanged).
- **Result:** Phase 1 complete. Build succeeded; both fixes verified at runtime in light + dark mode.

---

### Phase 2: Drag-to-collapse spike (≤2hr cap, drop if blocked)
**Status:** Not Started

#### Tasks Completed

- [ ] **Spike step 1 (~15 min):** Check whether `NavigationSplitView`'s middle/detail divider already snap-collapses past `min` width — if so, just bind to it.
- [ ] **Spike step 2 (~30 min):** If no freebie, add an invisible `.overlay(alignment: .trailing)` drag handle on the middle column with a `DragGesture` and -50pt threshold.
- [ ] **Spike step 3:** Add `@State private var isListVisible: Bool = true` in `MacRootView`. Conditionally render the column.
- [ ] **Spike step 4:** Implement re-open mechanism (peek strip on editor's left edge, OR document the limitation).
- [ ] **Spike step 5:** Verify snap feels parity with the folder-sidebar snap.
- [ ] **Decision gate at 2hr:** Polish & ship if working, OR revert all + write Spike findings.

#### Decisions Made

- **Drag-only, no menu/shortcut fallback.** User explicitly chose this in /build implementation.
- **Drop entirely if spike doesn't land.** No menu-toggle fallback ships.

#### Blockers

- (none)

#### Verification

- *(to be filled in either when shipped or when dropped)*

---

## Session Log

### 2026-04-30 — Planning
- Created research doc from `POLISH-BRIEF.md` after 4-agent codebase exploration.
- Confirmed scope-bug root cause: `MacRootView.swift:73-86` `onChange(of: selectedFileURL)` observer fires on list clicks, not just sidebar clicks.
- Confirmed "blue icon" is the recursion toggle, styled with `Color.accentColor` when active — only stateful icon in the Mac app using accent.
- Confirmed Mac UI is already a 3-column `NavigationSplitView` (`MacRootView.swift:50-65`), so the bonus is closer to a freebie than a rewrite.
- User chose: `.secondary` everywhere on the toggle (no colour difference); drag-or-nothing for the bonus; two-phase split (bugs / spike).
- Wrote IMPLEMENTATION.md reflecting those choices. PROGRESS.md set up.

---

## Files Changed

- `Clearly/Native/MacNoteListView.swift` — recursion toggle now `.foregroundStyle(.secondary)` always; added `.accessibilityLabel`. Phase 1, Issue 1.
- `Clearly/Native/MacRootView.swift` — added `ClickSource` enum + `@State`; both probes record the click origin; observer's parent-folder logic gated on `cameFromSidebar`. Phase 1, Issue 2.

## Architectural Decisions

- **Active state on the recursion toggle is conveyed by glyph fill alone, not colour.** Risk: subtler than convention. User accepted on the basis that the rest of the app's icons are also monochrome-secondary, so distinguishing the toggle by colour was the actual outlier.
- **Issue 2 fix moves logic into the sidebar's selection path rather than guarding the global observer.** Rationale: makes click-source intent explicit (sidebar = navigation, list = open). Trade-off: requires a callback parameter and care around the rebuild-restoration path (`MacFolderSidebar.swift:420-441`).
- **No menu / keyboard-shortcut fallback for the list-pane visibility.** User wanted drag or nothing — symmetry with sidebar's ⌘L was deemed not worth shipping if drag couldn't.
- **Issue 2 fix used existing click-source probe, not a new callback parameter.** See Phase 1 Decisions Made — same intent as the IMPLEMENTATION.md plan but smaller diff and no `MacFolderSidebar` signature change.

## Lessons Learned

- **Read existing surrounding code before locking in an implementation plan.** The IMPLEMENTATION.md called for a new callback on `MacFolderSidebar` to surface user-initiated selections. The existing `SidebarClickModifierWatcher` probe already had every primitive needed for the same job — once the file was actually open and read in detail, the simpler path became obvious. Rule of thumb: when planning a "fire callback only on user clicks" mechanism, scan first for any pre-existing modifier/event probe that already discriminates user input from programmatic state changes.
- **`xcodebuild` from the worktree needs `-derivedDataPath ./.build/DerivedData` (per CLAUDE.md) AND, on a machine without a registered Apple Developer account, `CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` to skip provisioning.** Worth pre-baking into a `bin/build-debug.sh` if other phases need ad-hoc local builds.
