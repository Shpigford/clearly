# Sidebar / List-View Polish — Product Brief

**Goal:** Bring the folder list-view pane in line with the rest of the app's UI conventions. Two clear bugs and one nice-to-have.

---

## 1. Replace blue section icon with native-style icon

**Problem.** The blue filled icon next to the section header (e.g. "Projects · 252 Notes", "cookbook-creator · 2 Notes") doesn't match the visual language of the rest of the app — every other icon is monochrome, outlined, SF Symbols-weight.

**Fix.** Swap the blue icon for an SF Symbol in the same monochrome / secondary-colour style used by the toolbar icons (Live Preview, Aa, attach, search, share, etc.). Treat the section-header chrome as informational, not a primary action.

**Done when.** A user scanning the sidebar can't pick out a single icon as visually heavier than the others.

---

## 2. Clicking a note must not change the list-view's scope

**Problem.** Clicking a note that lives inside a subfolder causes the middle list-view to filter down to *just that subfolder's notes* — e.g. clicking a note inside `Projects/cookbook-creator` switches the list from "Projects · 252 Notes" to "cookbook-creator · 2 Notes". The user did not navigate; they opened a note. Losing 250 of their list items as a side-effect is unexpected.

**Fix.** The list-view's scope should be driven *only* by what the user selects in the folder sidebar. Selecting a note opens that note in the editor and updates selection — it must leave the list-view's contents and header unchanged.

**Done when.** Opening any note from the list never changes which notes the list shows.

---

## 3. Bonus — drag the list-view pane closed (match folder-pane behaviour)

**Goal.** The folder pane already collapses when dragged left past a snap threshold. The list-view pane should do the same — drag its right edge leftward, snap closed below a threshold. Symmetry with the folder pane makes the gesture self-discoverable.

**Constraint.** Only ship if SwiftUI / `NSSplitView` gives us this mostly out of the box (collapsible-pane API, threshold-based snap). If it would need a meaningful chunk of custom drag/gesture code, drop it for this round and revisit.

**Done when.** Dragging the list-view divider left past a threshold collapses the pane with the same feel as the folder pane; dragging back out re-opens it.

---

**Out of scope.** No changes to note opening, editor behaviour, search, or sort order. Visual / interaction polish only.
