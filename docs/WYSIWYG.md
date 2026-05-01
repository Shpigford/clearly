# WYSIWYG Editor — Tiptap Migration Plan

This is the single source of truth for adding a WYSIWYG-style markdown
editor mode to Clearly using **Tiptap** (built on ProseMirror) inside a
WKWebView. It captures the full backstory: what was tried in a previous
worktree, why those approaches failed, the empirical research that
informed the decision, the migration plan itself, the specific lessons
that must NOT be re-learned, and a complete schema/architecture map.

**Read this end-to-end before writing any code.** The previous worktree
spent many hours on dead-end paths because the failure modes weren't
understood up front. This document exists so you don't repeat that.

> **Authoring context:** Written 2026-04-30 in worktree `sarajevo-v6`,
> branch `wysiwyg-editor`. That worktree is being abandoned. None of the
> code on the `wysiwyg-editor` branch carries forward — only the three
> commits in `docs/` survive (this plan is one of them; the other two
> are the earlier research drafts and may be deleted once this plan is
> on `main`).
>
> **Branching point:** the new worktree branches from `main` at
> commit `6179ab7e` (or whatever `main` is at execution time). Clearly
> has two editor modes today on `main`: **Edit** (NSTextView with
> regex syntax highlighting) and **Preview** (WKWebView rendering
> cmark-gfm output). This plan adds a third: **WYSIWYG** (Tiptap in
> WKWebView), gated behind an experimental settings flag.

---

## 0. TL;DR

1. **Don't rebuild the CodeMirror 6 WYSIWYG.** The previous worktree
   did. It hits a wall: any block widget (rendered table, code block,
   callout, frontmatter card) causes CM6's heightmap to drift from the
   actual rendered DOM after webfont/wrap reflow, which makes click
   hit-testing land on the wrong line. There is no fix at the CM6
   layer. Inline-only WYSIWYG (hide `**` markers, render headings, etc.)
   works but the visual ceiling is "syntax-highlighted markdown," not
   Notion.

2. **Use Tiptap (not vanilla ProseMirror, not Lexical).**
   `prosemirror-markdown` is archived (April 2026); the actively
   maintained markdown integration is `@tiptap/markdown` (GA March
   2026). Lexical has unbounded memory growth in long sessions. Tiptap
   is on top of ProseMirror so the escape hatch is real.

3. **Performance clears the bar.** Empirical benchmark on Apple
   Silicon, headless Chrome, Tiptap 3.22 + StarterKit + `@tiptap/markdown`,
   synthetic markdown of realistic shape:
   - 100k words: 35 ms p95 keystroke (target ≤ 50 ms) — PASS
   - 200k words: 38 ms p95 — PASS
   - 500k words: 218 ms p95 — FAIL (out of realistic note size)
   - Mount @100k: 92 ms; @200k: 105 ms
   - Scroll: refresh-rate bound (120 fps) at all sizes

4. **License is clean.** All Tiptap packages we'd ship are MIT.
   Dependency tree: 110 MIT, 13 Apache-2.0 (Puppeteer dev-only), 8 ISC,
   5 BSD-2, 3 BSD-3 (highlight.js etc.), 1 0BSD. **Zero GPL/AGPL/LGPL.**
   Distribution-safe for an MIT codebase shipping via GitHub + Sparkle
   + Mac App Store.

5. **Two open performance questions that gate the migration.** The
   benchmark used StarterKit + Markdown only; real Clearly will add
   ~6 custom extensions. And headless Chrome ≠ WKWebView. Both must
   re-benchmark before you commit fully — they're explicit Phase 0
   and Phase 4 gates in the plan below.

---

## 1. Context

### 1.1 What Clearly is

Clearly is a native macOS markdown editor / Obsidian-style local
knowledge base. App is MIT-licensed, distributed via GitHub releases
(Sparkle direct distribution) and the Mac App Store. Two channels share
one codebase via conditional compilation (`#if canImport(Sparkle)`).

User profile: knowledge workers, writers, researchers. Notes routinely
exceed 50k words; power users have 100k+ word notes (research
compendiums, long-running journals). Performance at this scale is a
non-negotiable product requirement — not a stretch goal.

### 1.2 Existing editor architecture (on `main`)

Three targets in `project.yml`, all sharing the local `ClearlyCore`
Swift package:

1. **`Clearly`** — main app. Document-based SwiftUI app using
   `WindowGroup` (Mac) / `WindowGroup` (iOS). Two editor modes today:
   - **Edit (⌘1)**: `NSTextView` (`Clearly/EditorView.swift` on Mac,
     iOS port at `Clearly/iOS/ClearlyUITextView.swift` using TextKit 1)
     with regex-driven syntax highlighting via `NSTextStorageDelegate`.
     Battle-tested, fast, undo/find-panel correct.
   - **Preview (⌘2)**: `WKWebView` rendering full HTML built by
     `MarkdownRenderer` (uses `cmark-gfm` + KaTeX + Mermaid + highlight.js).
     Read-only.
2. **`ClearlyQuickLook`** — QuickLook extension for Finder previews.
   Reuses `MarkdownRenderer`.
3. **`ClearlyCLI`** — CLI / MCP server.

`Clearly/Native/MacDetailColumn.swift` hosts the toolbar mode picker
and the `ZStack` that mounts whichever mode is active.

`Packages/ClearlyCore/Sources/ClearlyCore/State/OpenDocument.swift`
defines `ViewMode` (currently `.edit | .preview`).

### 1.3 What "WYSIWYG mode" means here

A **third** editor mode (⌘3 when toggle is on) where users see roughly
what Preview shows — bold rendered as bold, lists rendered as bullets,
links rendered as styled links — but the editor is live and editable.
Markdown remains the on-disk source of truth. The WYSIWYG view parses
markdown on open and serializes back on save. Notion is the visual
reference point; Obsidian's Live Preview is the closest existing
implementation in the markdown space.

This is gated behind an experimental settings toggle (off by default).
Toggle off → 2-segment picker (Edit / Preview), no menu items, no UI
trace. Toggle on → 3-segment picker, ⌘1/⌘2/⌘3 = Edit / WYSIWYG /
Preview, new documents default to WYSIWYG.

---

## 2. What was tried in the abandoned worktree

The `wysiwyg-editor` branch in the previous worktree built a CM6-based
WYSIWYG editor through 7 phases over many sessions. It shipped
working, but a click-correctness bug surfaced that proved structural,
not incidental. **Read this section. The trap is real and easy to fall
back into.**

### 2.1 The original CM6 buildout (phases 0–7)

The previous worktree built (in `ClearlyWYSIWYGWeb/`, a TS package
bundled by esbuild and consumed by a `WKWebView` via the JS↔Swift
bridge in `Clearly/WYSIWYGView.swift` / `WYSIWYGSession.swift`):

- **Phase 0**: rename from "Live Preview" → "WYSIWYG" branding.
- **Phase 1**: 3-segment toolbar picker, `ViewMode.wysiwyg`, ⌘1/⌘2/⌘3
  menu commands, default mode for new docs.
- **Phase 2**: viewport-bounded decoration foundation (the perf win).
- **Phase 3**: permanent inline marker hiding + IME composition guard.
- **Phase 4**: link-edit popover.
- **Phase 5**: callout block widgets (synchronous + foldable
  `<details>`), mermaid (Code/Preview/Split toggle, later simplified
  to preview-only with click→popover edit), math popover, image
  popover with width round-trip, inline-editable code block (with
  syntax-highlighting on blur), inline images.
- **Phase 6**: integrated demo doc coverage — wiki links, tags,
  callouts, foldable callouts (`> [!TIP]-`), inline math `$..$`,
  block math `$$..$$`, mermaid, footnote refs (`[^1]`), emoji
  shortcodes, sup/sub, highlight, etc.
- **Phase 7**: slash menu (`/heading`, `/code`, `/table`, etc.).

The product worked. The user could click into the WYSIWYG, see
rendered tables and diagrams and callouts, edit a math expression
via a popover, type `**bold**` and have the markers auto-hide.

### 2.2 The bug that ended the road

**Repro**: open a document with a multi-line wrapped paragraph (in
the demo doc, the line `Add #tags inline to categorize your notes…`
which wraps to 3 visual rows). Click somewhere in the third visual
row. **Caret lands on the next paragraph, not the line you clicked.**

Initial assumption: a few CSS metrics on inline elements were pushing
line widths just enough to cause off-by-one on click hit-testing.
**Wrong.**

### 2.3 Failed fixes that you must not re-attempt

1. **CSS micro-tweaks on inline elements.** Sup/sub vertical-align,
   inline math wrapping, inline code padding, tag chip border, wiki
   link border, callout pill padding. Each one *appeared* to fix the
   bug because it nudged line widths enough that the user's specific
   click happened to land on text instead of empty trailing space.
   None addressed the root cause. Cycled here for hours before
   diagnosing. **Don't do CSS-only fixes on click-position bugs.**
2. **Bumping `@codemirror/view` version.** 6.41.0 added a fix for
   `posAtCoords` on mixed-font-size lines; 6.41.1 added a fix for
   "clicking after the end of a wrapped line." Neither resolved the
   bug because the bug isn't in CM6's `posAtCoords` per se — it's in
   the heightmap-vs-DOM disagreement that `posAtCoords` consults.
3. **Custom mousedown override** that intercepted the click, ran
   DOM hit-testing via `elementFromPoint`, and dispatched a corrective
   selection if CM disagreed with the DOM. The override fired too
   eagerly (any time CM's resolved position was outside the
   DOM-detected line, including legitimate clicks past text on a wrap
   row), which jumped the caret to the line end on every click in the
   trailing whitespace. Worse than the original bug.

### 2.4 Diagnostic that finally exposed the root cause

Added to the editor's mousedown handler:

```ts
const cmPos = view.posAtCoords({ x, y });
const cmLine = view.state.doc.lineAt(cmPos);
const cmCoords = view.coordsAtPos(cmPos);
const block = view.lineBlockAt(cmPos);
const contentTop = view.contentDOM.getBoundingClientRect().top;
const docY = y - contentTop;
const blockAtY = view.lineBlockAtHeight(docY);

const elAtPoint = document.elementFromPoint(x, y);
const lineAtPoint = elAtPoint?.closest(".cm-line");
const lineRect = lineAtPoint?.getBoundingClientRect();

log(
  `MDOWN click=(${x},${y}) docY=${docY}\n` +
  `  posAtCoords→ pos=${cmPos} line=${cmLine.number} rowCoords=${cmCoords.top}-${cmCoords.bottom}\n` +
  `  lineBlockAt(pos)→ top=${block.top} bot=${block.bottom} height=${block.height}\n` +
  `  lineBlockAtHeight(docY)→ line=${blockAtY.from} top=${blockAtY.top} bot=${blockAtY.bottom}\n` +
  `  DOM at click→ lineRect=${lineRect.top}-${lineRect.bottom}`
);
```

This lets you compare CM's heightmap (`block.top`/`block.bottom` from
`lineBlockAt`) against the actual rendered DOM (`lineRect` from
`getBoundingClientRect()`). When clicks misbehave, the heightmap is
30+ pixels off from the DOM. **Keep this diagnostic in your back
pocket** — if click position weirdness ever appears in the new Tiptap
implementation (much less likely but possible), this is the technique
to localize it.

### 2.5 Root cause

CodeMirror 6 maintains a **heightmap**: an internal model of how tall
each line and block decoration is. `posAtCoords` uses heightmap-based
math to map (x, y) coordinates to a document position. The browser's
real DOM has its own measurement.

When the heightmap diverges from the actual DOM, `posAtCoords` returns
the wrong position. Drift sources, in observed order of severity:

1. **Async block widgets** — mermaid SVG (Promise-based render),
   KaTeX math (synchronous-but-with-intrinsic-line-metrics), images
   (load completion). CM measures the widget at `toDOM` time; the
   widget grows after; CM is not notified.
2. **`<details>`/`<summary>` toggles** — open/close changes height.
3. **Inline element vertical metrics** — padding, vertical-align,
   non-default font-size on a `Decoration.mark`. The
   "mixed-font-size" case CM6 6.41.0 partially fixed but not fully.
4. **Webfonts loading after first paint** — text reflows, line
   heights settle to slightly different values than what CM measured.
5. **Content-dependent wrapping in widgets** — a callout body whose
   wrap-row count depends on container width. Even synchronous
   fixed-structure widgets are vulnerable: content wrap settles after
   `toDOM` returns.

### 2.6 Plan A polish — the CM6 ceiling

After Option A (strip all block widgets), clicks worked. Visual
quality was "syntax-highlighted raw markdown." Pass 1 polish added a
tuned `HighlightStyle` and per-line decorations (`Decoration.line`
classes) for fenced code, frontmatter, math fences, table rows, and
callout lines — heightmap-safe because they only add a class to the
line element, no widgets.

User reaction after Pass 1: *"better but still relatively unpolished."*

Pass 2 attempted to selectively bring back four "synchronous,
fixed-structure" block widgets that were hypothesized to be drift-safe
(HR, page break, frontmatter `<dl>`, non-foldable callout). **Drift
returned immediately.** Reverted within the hour.

**Conclusion stronger than the original research suggested:** in CM6,
*every* block widget is a heightmap drift risk, not just the async or
toggle ones. Webfont reflow + content-dependent wrap is enough to
make any widget's settled height differ from its toDOM-time
measurement. The block-widget class is structurally ruled out for our
use case. Plan A's ceiling is exactly Pass 1: HighlightStyle +
per-line decorations. There is no further polish to push within CM6.

That ceiling isn't enough for "Notion-style WYSIWYG." Hence Tiptap.

---

## 3. ProseMirror / Tiptap evaluation

### 3.1 Library landscape (April 2026)

| Library | Status | What you get | What's missing |
|---|---|---|---|
| `prosemirror-*` (vanilla PM) | Active core, but `prosemirror-markdown` **archived April 2026** | Battle-tested PM primitives | No actively maintained markdown integration |
| **Tiptap** | Active, well-funded (YC), v3 GA March 2026 | ~50 first-party extensions, clean Extension/Node/Mark API, **`@tiptap/markdown`** with bidirectional support | Documented perf footguns when used in React (n/a for us — we're vanilla TS in WKWebView) |
| Lexical (Meta) | Active, no 1.0 as of 2026 | Fast cold-start, Meta backing | **Memory growth** in long sessions (3.9 GB heap crash in 1-hour stress test); no pure-decoration model; markdown round-trip not first-class |

### 3.2 Why `prosemirror-markdown` is dead

Archived April 2026, moved off the ProseMirror GitHub org to a
personal mirror. Long-standing wontfix bugs that matter for our use
case:

- **#3** — backslash escapes get duplicated on round-trip (open since 2017)
- **#32** — autolinks `<https://x>` serialize as `[https://x](https://x)`
- **#57** — tight-list metadata detected on parse, ignored on render;
  tight↔loose flips on every save
- **#80** — hard breaks always append literal `\\\n` even when not needed
- **#82** — nested emphasis (`**foo *bar **baz** bim* bop**`) mis-parsed
  vs. CommonMark spec example 431

Vanilla `prosemirror-markdown` + custom serializers is no longer a
real option. If you want PM, you want Tiptap.

### 3.3 Why Lexical is ruled out

1. **Memory growth.** Emergence Engineering ran a 1-hour stress test
   (scripted typing, history on) on Lexical and PM with identical
   configs. Lexical crashed at ~8.2k nodes / ~3.9 GB heap. PM stayed
   at 6–18 MB and reached ~11.5k nodes. For a long-session editor in
   WKWebView, "memory grows over time" is the wrong tradeoff.
2. **No 1.0 as of 2026.** The markdown transformer architecture
   round-trips through Lexical's own node tree; fidelity for long-tail
   GFM features is up to us to extend.
3. **No pure-decoration model.** Find highlights, spell-check
   underlines, AI-suggestion overlays would all have to be drawn as
   positioned divs that re-layout on scroll. PM and CM6 both have
   first-class decoration APIs; Lexical doesn't.

### 3.4 Performance — empirical benchmarks

The pessimistic ProseMirror perf research (citing Marijn Haverbeke's
forum statements about "no viewporting" and 50–100 ms keypress jank
at 50k chars on 2020 Intel MacBooks) does **not** apply to our target
hardware/setup. Ran an actual benchmark.

**Test setup:**
- Headless Chrome via puppeteer-core
- Apple Silicon (M-class)
- Tiptap 3.22.5 + `@tiptap/markdown` 3.22.5 + StarterKit
- Synthetic markdown docs of realistic shape: frontmatter + headings
  every ~30 lines + fenced code every ~80 lines + tables every ~150
  lines + paragraphs with inline links/bold/inline-code. Mirrors the
  CM6 perf-harness shape, so the comparison is apples-to-apples.
- 50 keystrokes per measurement, inserted at start/middle/end of doc.

**Results (p95 keystroke latency):**

| Doc size | Mount | p95 @end | p95 @middle | p95 @start | Verdict |
|---|---|---|---|---|---|
| 50k words | 89 ms | 17.8 ms | 17.3 ms | 17.4 ms | PASS |
| 100k words | 92 ms | 35.2 ms | 33.7 ms | 33.7 ms | PASS |
| **200k words** | **105 ms** | **35.8 ms** | **35.1 ms** | **38.1 ms** | **PASS** |
| 500k words | 416 ms | 176.8 ms | 218.9 ms | 171.5 ms | FAIL |

Target: 50 ms p95 keystroke (CM6 baseline, proven achievable at 95k
words via viewport-bounded decorations).

Tiptap clears the bar at 100k AND 200k words. Mount times stay under
100 ms up to 200k words. Scroll is refresh-rate bound (120 fps) at
every size. Falls apart at 500k+ — a 2.5 MB single note, well outside
realistic knowledge-base territory.

**Note: large step from "StarterKit only" to "StarterKit + Markdown."**
Without `@tiptap/markdown` loaded: 1.6 ms p95 at 100k words. With it
loaded: 35 ms p95. The markdown extension is doing real work per
transaction (~22× per-keystroke cost). Investigate during Phase 4
whether we can defer markdown serialize to save-time only.

**Caveats that gate the migration (must re-benchmark):**

1. **Custom-extension overhead.** The benchmark used StarterKit +
   Markdown only. Real Clearly will add ~6 custom extensions (wiki
   links, tags, callouts, math, mermaid, [TOC]) plus tables, task
   lists, mentions. Each adds per-keystroke transaction cost. The
   200k-word 35 ms p95 leaves only ~12 ms of headroom before busting
   the 50 ms target. **Re-benchmark after Phase 4 with the full
   stack.**
2. **WKWebView ≠ headless Chrome.** WebKit's `contenteditable`
   performance is not identical to Chromium's. **Re-benchmark inside
   the actual host before Phase 6 ships.**

The reproducible benchmark harness lives at
`.context/tiptap-perf/` in the abandoned worktree. The new worktree
should rebuild it from scratch using the script at the bottom of
this document (Section 9.1).

### 3.5 License audit

All Tiptap packages we'd ship are MIT. Verified by reading the
`LICENSE.md` file in each `node_modules/@tiptap/*/` directory after
installation.

| Package | Version | License |
|---|---|---|
| `@tiptap/core` | 3.22.5 | MIT |
| `@tiptap/pm` | 3.22.x | MIT |
| `@tiptap/starter-kit` | 3.22.x | MIT |
| `@tiptap/markdown` | 3.22.5 | MIT |
| `@tiptap/extension-table` | 3.22.x | MIT |
| `@tiptap/extension-task-list` | 3.22.x | MIT |
| `@tiptap/extension-task-item` | 3.22.x | MIT |
| `@tiptap/extension-link` | 3.22.x | MIT |
| `@tiptap/extension-image` | 3.22.x | MIT |
| `@tiptap/extension-code-block-lowlight` | 3.22.x | MIT |
| `@tiptap/extension-typography` | 3.22.x | MIT |
| `@tiptap/extension-mention` | 3.22.x | MIT |

**Full dependency tree** (counted post-install with `find node_modules -name package.json`):

| License | Count | Examples |
|---|---|---|
| MIT | 110 | All Tiptap, ProseMirror, esbuild, etc. |
| Apache-2.0 | 13 | Puppeteer/Chrome dev-only (NOT in shipped bundle) |
| ISC | 8 | cliui, get-caller-file, lru-cache, semver |
| BSD-2-Clause | 5 | escodegen, esprima, estraverse |
| BSD-3-Clause | 3 | highlight.js, source-map, devtools-protocol |
| 0BSD | 1 | tslib |

**No GPL / AGPL / LGPL anywhere in the tree.** Distribution-safe for
Clearly's MIT codebase shipping via GitHub + Sparkle + Mac App Store.

**Distribution obligations:**
- Standard MIT: include the copyright notice in the binary's
  "Acknowledgements" or `THIRD_PARTY_LICENSES` file.
- Add a license-aggregation step to the release script
  (`scripts/release.sh`) — generate `THIRD_PARTY_LICENSES.txt` from
  `node_modules` automatically. Tools: `license-checker`, `npm-license`.
- Mac App Store: no clauses in any of these licenses block App Store
  distribution.

### 3.6 WKWebView-specific concerns

- **WebKit IME bugs hit ProseMirror disproportionately.** Active
  upstream PM issues #934, #935, #971, #1190 — Japanese / pinyin /
  Korean composition edge cases. Most have workaround commits in PM
  core but resurface at the edges. **Mandatory IME regression test
  pass** before shipping (Section 5.7).
- **First-responder integration.** WKWebView's first-responder
  behavior differs from `NSTextView`. Native menu items (⌘B, find
  panel, undo) won't reach the JS editor unless we forward them via
  `WKScriptMessageHandler`. The existing Preview→editor bridge
  pattern transfers — same shape.
- **Spellcheck/autocorrect.** WKWebView gives you native squiggles
  for free. Don't reimplement in JS.
- **Selection / scroll on huge docs.** Pre-budget viewport-only
  decorations for find/replace before our note size grows past 200k
  words. ProseMirror plugins exist for this.

---

## 4. Decision

**Proceed with the Tiptap migration.** Empirical perf clears the bar.
License is clean. Tiptap is the actively-maintained successor to the
archived `prosemirror-markdown`. Lexical is ruled out for memory.
Vanilla PM is ruled out for archival.

### 4.1 Open gates (must pass before final cutover)

| Gate | When | Pass criterion |
|---|---|---|
| **Gate 0**: WKWebView baseline perf | Phase 0 | Tiptap + StarterKit only, 100k-word doc, in WKWebView. p95 keystroke ≤ 50 ms. |
| **Gate 1**: Round-trip fidelity | Phase 1 | Every existing demo doc parses + serializes byte-identically when nothing has been edited. |
| **Gate 2**: Full extension stack perf | Phase 4 | Tiptap + all 14 features, 100k-word doc, in WKWebView. p95 keystroke ≤ 50 ms. |
| **Gate 3**: IME / paste / soak | Phase 5 | Manual JP/CN/KR pass; paste from Notion/Word/Obsidian; 1-hour idle session with no leaks. |

If any gate fails, halt the migration and reassess. The previous
worktree's CM6 implementation can stay on `main` behind the same flag
as a fallback (dual-mode shipping is OK during evaluation).

### 4.2 Naming and conventions for the new worktree

Naming was ambiguous in the abandoned worktree (Live Preview →
WYSIWYG → some symbols still `LiveEditor*`). **Pick once, stick
with it.**

- **User-facing mode name**: "WYSIWYG (experimental)"
- **Settings flag**: `EditorEngine.wysiwygExperimental` (Bool)
- **`ViewMode` enum**: `.edit | .wysiwyg | .preview`
- **Keyboard shortcuts**: ⌘1 = Edit, ⌘2 = WYSIWYG (when toggle on,
  else Preview), ⌘3 = Preview (when toggle on)
- **JS bundle directory**: `ClearlyWYSIWYGWeb/`
- **JS bundle output**: `Shared/Resources/wysiwyg/wysiwyg.js`
- **Bundle entry**: `ClearlyWYSIWYGWeb/src/index.ts`
- **Swift host classes**: `WYSIWYGView.swift` (NSViewRepresentable
  hosting a WKWebView), `WYSIWYGSession.swift` (state holder)
- **JS API global**: `window.clearlyWYSIWYG` (cleaner than
  `clearlyLiveEditor` from the abandoned naming)
- **WKScriptMessageHandler name**: `wysiwyg`
- **Swift→JS commands enum**: `WYSIWYGCommand`
- **NotificationCenter name**: `Notification.Name.wysiwygCommand`

Branch name: `wysiwyg-tiptap`. Do not reuse `wysiwyg-editor`.

---

## 5. Migration plan

Six phases. Each ships independently mergeable to `main` (behind
the experimental flag, default off — invisible to production users).

### Phase 0 — Preflight and WKWebView baseline (1–2 days)

**Goal**: prove Tiptap can run in WKWebView at our scale before we
build anything else.

Tasks:

1. Create branch `wysiwyg-tiptap` off `main`.
2. Scaffold `ClearlyWYSIWYGWeb/` with `package.json`, `tsconfig.json`,
   esbuild build script (`build.mjs`). Mirror the existing
   `ClearlyEditorWeb/` (or whatever exists on main; if nothing exists,
   reference the abandoned `ClearlyWYSIWYGWeb/` structure for shape).
3. Install: `@tiptap/core` `@tiptap/pm` `@tiptap/starter-kit`
   `@tiptap/markdown`. Pin exact versions.
4. Build a minimal `index.ts` that mounts a Tiptap editor on
   `#editor` with StarterKit + Markdown.
5. Build the perf harness (Section 9.1 below) and run it in headless
   Chrome. Confirm the numbers from Section 3.4 reproduce on the
   developer's machine.
6. **Gate 0 — WKWebView baseline.** Build a throwaway test harness:
   a `WKWebView` host in a SwiftUI `.app` target (or a plain
   `xcrun simctl`-launched WKWebView shim) that loads
   `Shared/Resources/wysiwyg/wysiwyg.js`. Inject the synthetic 100k-
   and 200k-word docs (you already have them from Step 5). Run a JS
   timing script that simulates `editor.chain().setTextSelection(pos)
   .insertContent("x").run()` 50 times in a loop. Log p95.
   - **PASS**: p95 ≤ 50 ms at 100k words inside WKWebView.
   - **FAIL**: open a discussion before continuing.

Phase 0 commit: `[chore] Tiptap perf harness + WKWebView baseline`.

### Phase 1 — Schema, parser, serializer, round-trip test (1 week)

**Goal**: a Tiptap editor that opens any Clearly markdown file and
serializes it back byte-identically when nothing has been edited.

Tasks:

1. **Schema**: define Tiptap nodes for the 14 features in Section 6.
   Wire the existing extensions; build custom Nodes/Marks for the 6
   that need them.
2. **Parser hookups**: `@tiptap/markdown` uses `marked.js` under the
   hood. For each custom feature, register a marked tokenizer. See
   Section 6 for which markdown-it / marked plugins map to which
   feature; some need handwritten tokenizers.
3. **Serializer hookups**: per-extension `renderMarkdown` callbacks.
4. **Round-trip preservation**:
   - On parse, attribute every PM node with the byte range it parsed
     from (`node.attrs.sourceFrom`, `node.attrs.sourceTo`).
   - On serialize, walk the doc; if a node's source range is
     untouched (no transactions intersected it), emit the original
     bytes verbatim from `editor.storage.markdown.originalSource`
     (you'll need to keep the original source on the editor instance).
     Only edited subtrees go through `marked` re-rendering.
   - Why this matters: prosemirror-markdown / @tiptap/markdown
     normalize on save by default (`-` bullets become `*`, `~~~`
     fences become ` ``` `, autolinks rewrite, etc.). For Clearly,
     where markdown is the on-disk source synced via iCloud and
     potentially version-controlled, save-doesn't-churn is a hard
     requirement.
5. **Round-trip test harness**: `npm run test:round-trip`. For every
   file in `Shared/Resources/*.md` plus `demo.md`, parse → serialize
   → compare bytes. Must be byte-identical. Fails the build if any
   file diverges.

Phase 1 commit: `[chore] Tiptap schema + round-trip-preserving serializer`.

**Gate 1 PASS criterion**: round-trip test green for the entire
existing markdown corpus.

### Phase 2 — Swift host bridge (3–4 days)

**Goal**: the editor mounts inside the actual WYSIWYGView, talks to
Swift, paste/find/keyboard plumbing works.

Tasks:

1. **`Clearly/WYSIWYGView.swift`** — `NSViewRepresentable` wrapping
   a `WKWebView`. Loads `Shared/Resources/wysiwyg/index.html` (which
   loads `wysiwyg.js`). Mirrors the existing `Clearly/PreviewView.swift`
   pattern. Sets `webView.isInspectable = true` in Debug.
2. **`Clearly/WYSIWYGSession.swift`** — state holder. Same shape as
   the existing Preview-side session. Exposes `setDocument`,
   `getDocument`, `applyCommand`, `setFindQuery`, `scrollToLine`,
   `focus`, etc.
3. **JS↔Swift bridge contract** (`window.clearlyWYSIWYG` global):
   - `mount(payload)` — initial doc + theme
   - `setDocument({ markdown, epoch })` — external update from Swift
   - `setTheme({ appearance, fontSize, filePath })`
   - `setFindQuery({ query, replacement, options })`
   - `applyCommand({ command })` — bold/italic/⌘K link/etc.
   - `scrollToLine({ line })` / `scrollToOffset({ offset })`
   - `insertText({ text })` (for paste-from-Swift)
   - `getDocument(): string` (for save)
   - `focus()`
4. **Outgoing messages** via `WKScriptMessageHandler` (handler name
   `"wysiwyg"`):
   - `{ type: "ready" }`
   - `{ type: "docChanged", markdown, epoch }`
   - `{ type: "openLink", kind, target, heading? }`
   - `{ type: "log", line }` (diagnostic logging → `DiagnosticLog`)
5. **Find/replace**: route through Tiptap's existing
   `prosemirror-search` plugin or a custom plugin that mimics CM6's
   search behavior. Native ⌘F panel forwards via the existing
   `FindState` mechanism — same shape as the Edit mode plumbing.
6. **Native menu commands** (⌘B, ⌘I, ⌘K, etc.): forward via
   `applyCommand` to Tiptap commands.

Phase 2 commit: `[mac] WYSIWYG view + Tiptap host bridge`.

### Phase 3 — ViewMode + experimental flag plumbing (1–2 days)

**Goal**: the toggle works; users can opt in.

Tasks:

1. **`Packages/ClearlyCore/.../OpenDocument.swift`**: add
   `case wysiwyg` to `ViewMode`. Update any switch statements (none
   should break — `OpenDocument`'s ViewMode is consumed by code that
   should treat `wysiwyg` like `edit` for navigation purposes; treat
   like `preview` for read-only intents).
2. **`Clearly/EditorEngine.swift`** (or wherever the existing
   experimental flags live): add `wysiwygExperimental` Bool default
   false.
3. **`Clearly/Native/MacDetailColumn.swift`**:
   - Toolbar picker: 3-segment when toggle on, 2-segment otherwise.
   - `ZStack`: always mount EditorView for `.edit`; mount
     WYSIWYGView for `.wysiwyg` only when toggle on; always mount
     PreviewView for `.preview`.
   - Format/Checklist/Insert toolbar buttons enabled in both
     `.edit` and `.wysiwyg`, disabled in `.preview`.
   - Add a guard: if user turns toggle off while a doc is in
     `.wysiwyg` mode, coerce to `.edit`.
4. **`Clearly/ClearlyApp.swift`**:
   - View menu: dynamically rebuild Editor / WYSIWYG / Preview items
     based on toggle state. ⌘1 = Edit (always), ⌘2 = WYSIWYG (toggle
     on) or Preview (toggle off), ⌘3 = Preview (toggle on).
   - Use the same `applicationWillUpdate` injection pattern the
     existing toolbar-hide menu items use (NSMenuItem +
     keyEquivalent + selector). **Do not** use SwiftUI
     `.keyboardShortcut(letter, modifiers: [.command, .option])` —
     that doesn't dispatch reliably on this macOS (see CLAUDE.md).
5. **`Clearly/WorkspaceManager.swift`**: `defaultViewModeForNewDocument`
   computed property: `.wysiwyg` when toggle on, `.edit` when off.
   All 4 new-document creation sites use this.
6. **iOS**: Phase 3 is Mac-only. iOS WYSIWYG host is deferred
   (probably Phase 8+ in a future plan). iOS picker stays 2-segment.
   Compiles cleanly with the new ViewMode case because all iOS
   sites use `==` checks (no exhaustive switch).

Phase 3 commit: `[mac] WYSIWYG mode plumbing — toolbar picker, menu, default mode`.

### Phase 4 — Feature parity (1.5–2 weeks)

**Goal**: all 14 features in Section 6 render correctly, edit
correctly, round-trip cleanly. After this phase, the WYSIWYG mode is
a complete editor for our markdown dialect.

Approach: build feature by feature, in priority order. After each,
re-run the round-trip test (Phase 1 harness) and the perf harness.

Order of attack (informed by visual impact and risk):

1. CommonMark + GFM core (StarterKit covers most; verify each)
2. Tables (`@tiptap/extension-table`)
3. Task lists (`@tiptap/extension-task-list` + task-item)
4. Links (`@tiptap/extension-link`) + the link-edit popover from
   Phase 2 of the abandoned worktree
5. Frontmatter (custom — strip before parse, re-prepend on serialize)
6. Wiki links `[[…]]` (custom mark + custom marked tokenizer)
7. Tags `#tag` (custom mark + custom marked tokenizer)
8. Highlight `==…==` (custom mark + `markdown-it-mark` ported to marked)
9. Footnote refs / defs (custom mark + node + `markdown-it-footnote`-equivalent)
10. Inline math `$..$` (custom NodeView with KaTeX, **important**:
    measure widget after KaTeX renders and call `editor.view.updateState`
    if needed — Tiptap has primitives for this that CM6 didn't)
11. Block math `$$..$$` (custom block NodeView)
12. Mermaid (custom block NodeView with async render — same caution
    as math, Tiptap's NodeView lifecycle is more forgiving than CM6's)
13. Callouts `> [!TIP]` foldable + non-foldable (custom block node)
14. Inline images + HTML `<img>` (custom node with width attribute
    preservation)
15. Emoji shortcodes (`markdown-it-emoji`-equivalent)
16. Sup/sub (custom marks)
17. `[TOC]` (inline atom node, render TOC live)
18. Slash menu (`/heading`, `/code`, `/table`, etc.) — Tiptap has
    `@tiptap/suggestion` for this
19. Backslash escapes (verify CommonMark default; guard for
    duplicate-on-toggle issue from prosemirror-markdown #3)

For each feature, fold tests into the round-trip suite. Don't ship
the next feature until the previous one round-trips for every
existing markdown file.

**Gate 2 — Full extension stack perf.** After all 14 features are
in, re-run the perf harness with the full extension list loaded
inside WKWebView. Pass criterion: p95 keystroke ≤ 50 ms at 100k
words. If failing: profile the worst extension (likely a custom
NodeView doing heavy work on every transaction) and either optimize
or defer-to-save-time.

Phase 4 commits: one per feature, `[mac] WYSIWYG: <feature>`.

### Phase 5 — IME, paste, polish (1 week)

**Goal**: ship-quality editor.

Tasks:

1. **IME regression pass**:
   - Japanese (Kotoeri / Hiragana) — type ~500 chars, verify no
     composition orphan / mark loss.
   - Chinese (Pinyin) — same.
   - Korean (Hangul) — same.
   - Specifically test: typing `**bold**` in mid-composition; typing
     a wiki link `[[Japanese page name]]` with an active IME.
2. **Paste-from-Word, paste-from-Notion, paste-from-Obsidian.**
   Tiptap's clipboard handling generally does the right thing via
   `editor.commands.insertContent`. Verify; add custom paste rules
   only if needed.
3. **WKWebView soak**: leave the editor open for 1 hour with a 100k-
   word doc. Memory should plateau, not grow. (PM/Tiptap is generally
   well-behaved here, unlike Lexical, but verify.)
4. **`Gate 3` re-benchmark inside WKWebView**: same bench as Phase 0
   but with the now-full extension stack.

Phase 5 commit: `[mac] WYSIWYG: IME + paste + WKWebView soak passes`.

### Phase 6 — Cutover decision (a few days)

**Goal**: decide whether to graduate WYSIWYG out of experimental.

Tasks:

1. Dogfood for 1 week: turn the experimental flag on for the
   developer's primary work. Use it as the default for all new docs.
2. If it holds: keep experimental flag on by default in next release,
   add release-note language, set up an opt-out path.
3. If it doesn't hold: keep behind flag, document specific
   showstoppers, plan Phase 7 fixes.
4. **Do not** delete the existing Edit / Preview modes. They stay
   as the proven workhorses. WYSIWYG is the third option, not a
   replacement.

Phase 6 commit: `[mac] WYSIWYG: graduate from experimental` OR
`[mac] WYSIWYG: extend experimental period — known issues TBD`.

---

## 6. Schema map: 14 features

For each markdown feature, the parse / serialize / Tiptap-node strategy:

| # | Feature | Parser | Tiptap | Serializer | Notes |
|---|---|---|---|---|---|
| 1a | Headings (ATX `#`/`##`/etc.) | StarterKit Heading | `Heading` | StarterKit | ATX only. Setext (`===`/`---`) not in scope. |
| 1b | Bold `**…**` | StarterKit Bold | `Bold` | StarterKit | |
| 1c | Italic `*…*` `_…_` | StarterKit Italic | `Italic` | StarterKit | |
| 1d | Strikethrough `~~…~~` | StarterKit Strike | `Strike` | StarterKit | |
| 1e | Inline code `` `…` `` | StarterKit Code | `Code` | StarterKit | |
| 1f | Bullet list `-`/`*`/`+` | StarterKit BulletList | `BulletList`+`ListItem` | **Custom serializer** | **Round-trip preserve** — keep original marker char. |
| 1g | Ordered list `1.` | StarterKit OrderedList | `OrderedList`+`ListItem` | StarterKit | |
| 1h | Blockquote `>` | StarterKit Blockquote | `Blockquote` | StarterKit | |
| 1i | Fenced code ` ``` ` | StarterKit CodeBlock + lowlight | `CodeBlock` | **Custom serializer** | **Round-trip preserve** — keep original fence char (` ``` ` vs `~~~`) and info string. |
| 1j | HR `---` | StarterKit HorizontalRule | `HorizontalRule` | **Custom** | **Round-trip preserve** — keep original char (`-`/`*`/`_`). |
| 1k | Plain link `[text](url)` | `@tiptap/extension-link` | `Link` mark | extension | |
| 1l | Autolink `<https://x>` | extension-link autolink mode | `Link` mark + attr `autolink: true` | **Custom** | **Round-trip preserve** — emit `<url>` not `[url](url)`. |
| 2 | YAML frontmatter | **Custom**: strip before parse, re-prepend on serialize. | Stored on `editor.storage.frontmatter` | Custom | Render as a non-editable header card; user clicks → reveals raw YAML in a small mode panel. |
| 3 | Wiki links `[[Page\|alias#heading]]` | **Custom** marked tokenizer | Custom inline atom node `WikiLink` with attrs `target`, `alias`, `heading` | Custom | Click → existing `openLink` Swift bridge (kind: `"wiki"`). |
| 4 | Tags `#tag`, `#nested/tag`, unicode | **Custom** marked rule | Custom mark `Tag` with attr `name` | Custom | Click → `openLink` (kind: `"tag"`). Visual: chip-style background. |
| 5 | Highlight `==text==` | `markdown-it-mark` ported to marked | Custom mark `Highlight` | Custom | Yellow highlight background. |
| 6 | Footnotes `[^id]` + `[^id]: text` | `markdown-it-footnote` ported to marked | Inline mark for refs + block node for defs | Custom | Refs render as superscript chip. |
| 7a | Inline math `$x=mc^2$` | `markdown-it-katex`-equivalent | Custom inline atom node `InlineMath` with KaTeX renderer | Custom | **In Tiptap, NodeView re-measure works** — call `view.updateState({...})` if KaTeX render shifts metrics. Click → small popover (mirror Phase 4 of abandoned worktree). |
| 7b | Block math `$$..$$` | Same | Custom block node `BlockMath` | Custom | Click → popover. |
| 8 | Mermaid (fenced `mermaid`) | StarterKit fence + custom node detector | Custom block NodeView with async `mermaid.render()` | Custom | Same async caution: re-measure after render. Click → popover. |
| 9 | Callouts `> [!TIP]` / foldable `[!TIP]-` | **Custom** block tokenizer | Custom block node `Callout` with attrs `type`, `foldable`, `summary` | Custom | Foldable uses native `<details>`. Pill + colored left border. |
| 10 | Image-only line `![alt](url)` + HTML `<img>` | StarterKit Image + custom HTML attr preservation | `Image` node with attrs `alt`, `src`, `width` | Custom | Width attribute round-trips: emit `![alt](url)` if no width, else `<img …>` HTML. |
| 11 | Inline images (image inside paragraph) | Same | Same node, just inline | Same | Cap visual at 1.5× line-height. |
| 12 | Emoji shortcodes `:rocket:` → 🚀 | `markdown-it-emoji`-equivalent | Custom inline atom or simple text replacement | Custom | Mirror table from `Packages/ClearlyCore/.../EmojiShortcodes.swift`. |
| 13 | Sup/sub `^x^`, `~x~` | Custom marked rules | Custom marks `Superscript`, `Subscript` | Custom | Use `font-variant-position: super/sub` (CSS-spec correct, doesn't grow line box). |
| 14 | `[TOC]` placeholder | Custom marked rule | Custom inline atom node `TOC` | Custom | Render TOC live based on current doc headings. Serialize back to literal `[TOC]`. |

---

## 7. Round-trip fidelity — the source-range preservation strategy

The single most important architectural decision in this migration.
Don't skip.

### 7.1 The problem

`@tiptap/markdown` normalizes on serialize:

- Bullet lists always emit `*` (your source `-` becomes `*`)
- Fenced code always emits ` ``` ` (your `~~~` becomes ` ``` `)
- Hard breaks always append `\\\n`
- Soft breaks (single newlines in source) → spaces (line wrapping lost)
- Headings normalized to ATX (we don't have Setext, fine)
- Backslash escapes can duplicate
- Autolinks rewritten to `[text](url)` form

For Clearly this is unacceptable: markdown is the on-disk format,
synced via iCloud, potentially version-controlled. Saves that rewrite
"unedited" content churn external state.

### 7.2 The fix

Layered on top of `@tiptap/markdown`'s default serializer:

1. **On parse**: every PM node gets `attrs.sourceFrom` and
   `attrs.sourceTo` recording the byte range of the original markdown
   it was parsed from. The parser plugin emits these via marked's
   `raw` token field (every marked token carries the original source
   text plus offset).
2. **On editor mount**: store the original markdown text in
   `editor.storage.markdown.originalSource: string`.
3. **On dispatch**: track which document ranges have been mutated.
   Tiptap's `state.doc` has stable node IDs; on each transaction, mark
   touched node IDs. (Use `transaction.steps` to identify the
   touched ranges; map back to node IDs via `state.doc.descendants`.)
4. **On serialize**: walk the doc. For each node:
   - If the node's `sourceFrom`/`sourceTo` range is in the
     "untouched" set, emit `originalSource.slice(sourceFrom, sourceTo)`
     verbatim.
   - Otherwise, run the registered `renderMarkdown` for that node.
5. **Edge case — paragraph-internal edit**: if the user edits one
   word in a paragraph, the entire paragraph node is marked
   "touched" and goes through the renderer. That's correct: the
   paragraph genuinely changed. We're preserving fidelity at the
   *block* level, not character level.
6. **Edge case — block deleted**: if a block was deleted, no
   serialize call happens for it. Deletion is byte-correct by
   default.
7. **Edge case — block inserted**: a new block has no
   `sourceFrom`/`sourceTo`. Goes through the renderer. That's the
   correct behavior — a brand-new block has no original bytes to
   preserve.

### 7.3 Round-trip test harness (Phase 1 deliverable)

Lives at `ClearlyWYSIWYGWeb/test/round-trip.test.ts`. Runs in Node
(no browser, just `parse` + `serialize` of `@tiptap/markdown` with
the editor instance reified in jsdom or via direct API calls).

```ts
import { readFileSync } from "node:fs";
import { glob } from "fast-glob";
import { Editor } from "@tiptap/core";
import StarterKit from "@tiptap/starter-kit";
import { Markdown } from "@tiptap/markdown";
// ... all custom extensions

const files = await glob(["Shared/Resources/**/*.md", "demo.md"]);
let pass = true;
for (const f of files) {
  const src = readFileSync(f, "utf8");
  const editor = new Editor({
    extensions: [StarterKit, Markdown, /* ... */],
    content: src,
    enableContentCheck: true,
  });
  const out = editor.storage.markdown.serialize(editor.state.doc.toJSON());
  if (out !== src) {
    console.error(`Diverged: ${f}`);
    diff(src, out); // print the actual diff
    pass = false;
  }
  editor.destroy();
}
process.exit(pass ? 0 : 1);
```

Run on every commit via git pre-commit hook. If a feature can't
round-trip, fix the serializer or revert the feature.

---

## 8. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Performance fails Gate 2 (full extensions overflow 50 ms p95) | Medium | High — would force feature scope cuts | Profile the offending extension; defer markdown re-serialize to save-time only; consider lazy-loading mermaid/KaTeX renderers; budget aggressively per extension (≤ 3 ms p95 cost each at 100k words) |
| WKWebView regression vs Chrome (Gate 0 fails) | Low-medium | High — entire migration paused | If found: investigate cause (WebKit `contenteditable` on macOS 15+ has been stable; macOS 26 less tested). Worst case: ship behind doc-size warning. |
| Round-trip diverges on uncommon markdown construct | Medium | Medium — saves churn external state | Round-trip test on every commit. When a divergence is found in production, ship a hotfix to the serializer — never silently normalize. |
| WebKit IME regression hits production | Medium | Medium | Phase 5 manual IME pass mandatory before each release. Add regression test fixtures for JP/CN/KR. |
| Tiptap version bump breaks custom serializers | Medium (every release) | Low | Pin Tiptap version. Run round-trip suite on every bump. Treat Tiptap as a load-bearing dep — bump deliberately, not automatically. |
| Custom extension drifts heightmap-style click bugs reappear | Low (Tiptap's NodeView lifecycle is healthier than CM6's) | High | If found: use the diagnostic technique from Section 2.4. PM has `view.updateState` for forced remeasure after async content arrives — call it. |
| User pastes content that breaks the schema | Low | Medium | Tiptap's clipboard handler defaults to safe HTML conversion. Add custom paste rules for known sources (Notion, Word) only if needed. |
| App Store review challenges Tiptap's MIT terms | Very low | Low | All code is MIT, no temp-exception entitlements needed. Standard NOTICE file in Acknowledgements. |

---

## 9. Reproducible artifacts

### 9.1 Tiptap perf harness

Build this in Phase 0. Self-contained in `ClearlyWYSIWYGWeb/perf/`.

**`package.json`** (additions to the main `ClearlyWYSIWYGWeb/package.json`
or a separate sub-package):

```json
{
  "scripts": {
    "perf": "node perf/bench.mjs"
  },
  "devDependencies": {
    "puppeteer-core": "^24.0.0"
  }
}
```

**`perf/bench.mjs`** — the script that ran the benchmarks in Section
3.4. Full source:

```js
import { performance } from "node:perf_hooks";
import puppeteer from "puppeteer-core";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { execSync } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const KEYSTROKE_COUNT = 50;
const SIZES = [50_000, 100_000, 200_000, 500_000];

function generateMarkdown(targetWords) {
  const out = [];
  let wordCount = 0;
  out.push("---", "title: Synthetic perf doc", "tags: bench, perf", "---", "");
  const sample = "The quick brown fox jumps over the lazy dog. ".repeat(2);
  const linkLine = "Here is [a link](https://example.com) and **bold** text with `inline code`. ";
  const codeFence = ["```ts", "function example() {", "  return 42;", "}", "```"];
  const tableBlock = ["| Col A | Col B | Col C |", "|---|---|---|", "| 1 | 2 | 3 |", "| 4 | 5 | 6 |"];
  let line = 5;
  while (wordCount < targetWords) {
    if (line % 150 === 0 && line > 5) {
      tableBlock.forEach((t) => { out.push(t); wordCount += t.split(/\s+/).length; });
      line += tableBlock.length;
      out.push(""); line += 1;
      continue;
    }
    if (line % 80 === 0 && line > 5) {
      codeFence.forEach((c) => { out.push(c); wordCount += c.split(/\s+/).length; });
      line += codeFence.length;
      out.push(""); line += 1;
      continue;
    }
    if (line % 30 === 0) {
      out.push(`# Heading ${Math.floor(line / 30)}`);
      wordCount += 3; line += 1;
      continue;
    }
    const useLink = line % 4 === 0;
    const text = useLink ? linkLine + sample : sample;
    out.push(text);
    wordCount += text.split(/\s+/).length;
    line += 1;
  }
  return { md: out.join("\n"), lines: out.length, wordCount };
}

console.log("Building bundle...");
execSync("npx esbuild src/main.ts --bundle --outfile=dist/bundle.js --format=iife --target=es2020", { cwd: __dirname, stdio: "pipe" });

const chromePath = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const browser = await puppeteer.launch({ executablePath: chromePath, headless: "new", args: ["--no-sandbox"] });

function summarize(t) {
  const s = [...t].sort((a, b) => a - b);
  const sum = s.reduce((a, b) => a + b, 0);
  return {
    mean: sum / s.length, p50: s[Math.floor(s.length * 0.5)],
    p95: s[Math.floor(s.length * 0.95)], p99: s[Math.floor(s.length * 0.99)],
    max: s[s.length - 1],
  };
}
const fmt = (n) => `${n.toFixed(1).padStart(7)}ms`;
const results = [];

for (const targetWords of SIZES) {
  const { md, lines, wordCount } = generateMarkdown(targetWords);
  console.log(`\n=== ${wordCount.toLocaleString()} words / ${lines.toLocaleString()} lines ===`);
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 900 });
  await page.goto("file://" + resolve(__dirname, "index.html"), { waitUntil: "load" });
  await page.evaluate((c) => { window.__initialContent = c; window.__initialContentIsMarkdown = true; }, md);
  const t0 = performance.now();
  await page.evaluate(() => window.__mountEditor());
  const mountWall = performance.now() - t0;
  const mountInternal = await page.evaluate(() => window.__mountTimeMs);
  console.log(`  Mount: ${fmt(mountInternal)} (wall ${fmt(mountWall)})`);
  for (const position of ["end", "middle", "start"]) {
    const timings = await page.evaluate((c, p) => window.__runKeystrokes(c, p), KEYSTROKE_COUNT, position);
    const s = summarize(timings);
    console.log(`  Keystroke @${position}: p95 ${fmt(s.p95)}`);
    results.push({ words: wordCount, position, ...s });
  }
  await page.close();
}
await browser.close();

console.log("\n=== Verdict matrix ===");
for (const r of results) {
  const status = r.p95 < 50 ? "PASS" : r.p95 < 100 ? "MARGINAL" : "FAIL";
  console.log(`${r.words.toLocaleString().padStart(8)} ${r.position.padEnd(8)} p95 ${fmt(r.p95)} ${status}`);
}
```

**`perf/index.html`**:

```html
<!doctype html>
<html><head><meta charset="utf-8"><title>perf</title>
<style>body{font:16px/1.6 system-ui;margin:0;background:#fff;color:#1d1d1f}#editor{max-width:720px;margin:0 auto;padding:24px}.ProseMirror{outline:none;min-height:100vh}.ProseMirror p{margin:0 0 1em}</style>
</head><body><div id="editor"></div><script src="../dist/bundle.js"></script></body></html>
```

**`perf/src/main.ts`** (the harness entry — different from the
production `src/index.ts`):

```ts
import { Editor } from "@tiptap/core";
import StarterKit from "@tiptap/starter-kit";
import { Markdown } from "@tiptap/markdown";
declare global {
  interface Window {
    __editor: Editor | null;
    __mountTimeMs: number | null;
    __initialContent: string;
    __initialContentIsMarkdown: boolean;
    __mountEditor: () => void;
    __runKeystrokes: (count: number, position: "start" | "middle" | "end") => Promise<number[]>;
  }
}
window.__mountEditor = () => {
  const root = document.getElementById("editor")!;
  const t0 = performance.now();
  const exts: any[] = [StarterKit];
  if (window.__initialContentIsMarkdown) exts.push(Markdown.configure({}));
  window.__editor = new Editor({ element: root, extensions: exts, content: window.__initialContent });
  void root.getBoundingClientRect();
  window.__mountTimeMs = performance.now() - t0;
};
window.__runKeystrokes = async (count, position) => {
  const editor = window.__editor!;
  const timings: number[] = [];
  const docSize = editor.state.doc.content.size;
  let basePos = position === "start" ? 1 : position === "middle" ? Math.floor(docSize / 2) : docSize - 1;
  for (let i = 0; i < count; i++) {
    const pos = basePos + (position === "end" ? i : 0);
    const t0 = performance.now();
    editor.chain().setTextSelection(pos).insertContent("x").run();
    void editor.view.dom.getBoundingClientRect();
    timings.push(performance.now() - t0);
    await new Promise((r) => setTimeout(r, 0));
  }
  return timings;
};
```

Run: `npm run perf` from `ClearlyWYSIWYGWeb/`. Expected output
matches Section 3.4 numbers within run-to-run variance.

### 9.2 License verification command

After `npm install` in `ClearlyWYSIWYGWeb/`:

```bash
find node_modules -name "package.json" -maxdepth 3 \
  -not -path "*/node_modules/*/node_modules/*" 2>/dev/null \
| xargs -I {} node -e 'const p=require("{}");console.log((p.license||"unknown")+"|"+p.name)' \
| sort -u | awk -F'|' '{counts[$1]++} END {for (k in counts) printf "%-30s %5d\n", k, counts[k]}' \
| sort
```

Expected output (counts may vary slightly by version):

```
0BSD                               1
Apache-2.0                        13
BSD-2-Clause                       5
BSD-3-Clause                       3
ISC                                8
MIT                              110
```

If GPL/AGPL/LGPL appear in the output, **stop and investigate** —
something's wrong (wrong package added, transitive dep changed
license).

---

## 10. Swift integration map (for the new worktree)

This section assumes `main` does not yet have a WYSIWYG mode.

### 10.1 Files to add

| File | Purpose | Mirrors |
|---|---|---|
| `Clearly/WYSIWYGView.swift` | `NSViewRepresentable` hosting the `WKWebView` | Pattern of existing `Clearly/PreviewView.swift` |
| `Clearly/WYSIWYGSession.swift` | State holder + JS bridge | Pattern of `Clearly/PreviewSession.swift` (or whatever exists on main) |
| `ClearlyWYSIWYGWeb/package.json` | npm package | New |
| `ClearlyWYSIWYGWeb/tsconfig.json` | TS config | New |
| `ClearlyWYSIWYGWeb/build.mjs` | esbuild script | Mirror existing JS build scripts on main |
| `ClearlyWYSIWYGWeb/src/index.ts` | Entry; mounts Tiptap, exposes `window.clearlyWYSIWYG.*` API | New |
| `ClearlyWYSIWYGWeb/src/extensions/*.ts` | Custom Tiptap extensions per Section 6 | New |
| `Shared/Resources/wysiwyg/index.html` | Page loaded by WKWebView | Mirror existing preview HTML |
| `Shared/Resources/wysiwyg/wysiwyg.js` | Built bundle (generated, gitignored) | New |

### 10.2 Files to modify

| File | Change |
|---|---|
| `Packages/ClearlyCore/Sources/ClearlyCore/State/OpenDocument.swift` | Add `case wysiwyg` to `ViewMode` |
| `Clearly/EditorEngine.swift` | Add `wysiwygExperimental: Bool` setting, default false |
| `Clearly/Native/MacDetailColumn.swift` | Toolbar 3-segment picker when toggle on; ZStack mounts WYSIWYGView for `.wysiwyg` |
| `Clearly/ClearlyApp.swift` | View menu items; ⌘1/⌘2/⌘3 commands; default mode for new docs via `WorkspaceManager` |
| `Clearly/WorkspaceManager.swift` | `defaultViewModeForNewDocument` computed property |
| `project.yml` | Bundle `Shared/Resources/wysiwyg/` into the `Clearly` target. Run `xcodegen generate` after. |
| `.gitignore` | Add `ClearlyWYSIWYGWeb/dist/`, `ClearlyWYSIWYGWeb/node_modules/`, `Shared/Resources/wysiwyg/wysiwyg.js` (or wherever the built artifact lands) |

### 10.3 JS API contract (frozen this version forward)

Swift → JS (called via `webView.evaluateJavaScript`):

```ts
window.clearlyWYSIWYG = {
  mount: (payload: { filePath: string; appearance: "light" | "dark"; fontSize: number; epoch: number; }) => void;
  setDocument: (payload: { markdown: string; epoch: number; }) => void;
  setTheme: (payload: { appearance: "light" | "dark"; fontSize: number; filePath: string; }) => void;
  setFindQuery: (payload: { query: string; replacement: string; caseSensitive: boolean; wholeWord: boolean; regex: boolean; }) => void;
  applyCommand: (payload: { command: string }) => void;  // "bold" | "italic" | "link" | "horizontalRule" | "pageBreak" | …
  scrollToLine: (payload: { line: number }) => void;
  scrollToOffset: (payload: { offset: number }) => void;
  insertText: (payload: { text: string }) => void;
  focus: () => void;
  getDocument: () => string;
};
```

JS → Swift (via `WKScriptMessageHandler` named `wysiwyg`):

```ts
{ type: "ready" }
{ type: "docChanged", markdown: string, epoch: number }
{ type: "openLink", kind: "wiki" | "tag" | "url", target: string, heading?: string, alias?: string }
{ type: "log", line: string }
{ type: "findStatusChanged", currentMatch: number, totalMatches: number }
```

Same shape as the existing Preview→Editor bridge — patterns transfer.

### 10.4 Build pipeline

`ClearlyWYSIWYGWeb/build.mjs` runs esbuild to produce
`Shared/Resources/wysiwyg/wysiwyg.js`. Hooked into the Xcode build via
a Run Script Build Phase that runs `npm run build` in
`ClearlyWYSIWYGWeb/` if any source under `src/` is newer than the
output bundle. Same pattern Clearly uses for any other JS-in-WKWebView
asset. Mirror exactly.

---

## 11. Things NOT to do (lessons from sarajevo-v6)

1. **Do not rebuild the CM6 WYSIWYG.** Section 2 covers why
   exhaustively. If you ever feel tempted, re-read.
2. **Do not chase click-position bugs with CSS micro-tweaks.** If
   click position drifts in Tiptap (much less likely than in CM6),
   use the diagnostic technique in Section 2.4. The fix is
   architectural, not stylistic.
3. **Do not build block widgets that resize after `toDOM`.** CM6's
   issue. ProseMirror is more forgiving (it has `view.updateState`
   for forced remeasure), but the principle holds: any widget whose
   final-paint height differs from its mount-time height is a click-
   correctness risk. Call `view.updateState` after async render.
4. **Do not skip the round-trip test.** Without it, every Tiptap
   version bump silently regresses save fidelity.
5. **Do not normalize markdown on save.** Bullet style, fence char,
   autolinks, hard breaks — preserve the user's source. The
   source-range strategy in Section 7 is non-optional.
6. **Do not enable Tiptap Cloud / collab features.** They're paid
   tiers. Stick to the MIT-licensed core + extensions audited in
   Section 3.5.
7. **Do not delete the existing Edit / Preview modes.** They're the
   proven workhorses. WYSIWYG is the experimental third option.
8. **Do not rename the JS API or message-handler name once shipped.**
   The Swift side has the contract baked in. Pick names per Section
   4.2 and stick with them.
9. **Do not use SwiftUI `.keyboardShortcut(letter, modifiers:
   [.command, .option])` for ⌥⌘-letter shortcuts.** It doesn't
   dispatch on this macOS. Use the `applicationWillUpdate` NSMenuItem
   injection pattern (see CLAUDE.md).
10. **Do not commit `node_modules/` or built bundles.** They're
    gitignored for a reason. The build hook in Xcode regenerates
    them on every build.

---

## 12. Decision log (chronological, for posterity)

| Date | Decision | Rationale |
|---|---|---|
| 2026-04 (early) | Adopt CM6 for WYSIWYG | Markdown source of truth, viewport rendering, Obsidian precedent |
| 2026-04 (mid) | Build through phases 0–7 | Standard editor maturity arc |
| 2026-04 | Click drift bug diagnosed | CM6 heightmap drift from async/wrap/font reflow on block widgets |
| 2026-04 | Try Option A (inline-only) | Hypothesis: stripping block widgets eliminates drift |
| 2026-04 | Confirmed: Option A fixes clicks, loses rich rendering | Demo doc visual review |
| 2026-04 | Plan A pass 1 (HighlightStyle + per-line decorations) shipped | "Better but unpolished" — clicks correct |
| 2026-04 | Plan A pass 2 (4 synchronous block widgets) reverted | Drift returned. ALL block widgets in CM6 are unsafe, not just async/toggle ones. |
| 2026-04 | Plan A ceiling reached | Block-widget class structurally ruled out in CM6 |
| 2026-04 | Initial pessimistic ProseMirror research | Cited Marijn's "no viewporting"; older PM, Intel Macs, React-PM dev mode |
| 2026-04 | License audit + empirical Tiptap perf benchmark | All MIT; perf clears 50 ms target at 200k words on Apple Silicon |
| 2026-04 | **Recommendation: migrate to Tiptap.** | Empirical perf clears the bar; license clean; Plan A's CM6 ceiling not enough. |
| 2026-04 | This consolidated migration plan | Single source of truth for new worktree |

---

## 13. References

### ProseMirror / Tiptap
- [Tiptap bidirectional markdown launch (March 2026)](https://tiptap.dev/blog/release-notes/introducing-bidirectional-markdown-support-in-tiptap)
- [Tiptap markdown extension API](https://tiptap.dev/docs/editor/markdown/api/extension)
- [Tiptap performance guide](https://tiptap.dev/docs/guides/performance)
- [Tiptap pricing](https://tiptap.dev/pricing)
- [Tiptap MIT-relicense (HN, 2025)](https://news.ycombinator.com/item?id=44202103)
- [`prosemirror-markdown` (archived April 2026)](https://github.com/ProseMirror/prosemirror-markdown)
- [PM forum: "no viewporting" thread](https://discuss.prosemirror.net/t/improving-performance-loading-on-scroll/4972)
- [PM forum: 200k-word doc perf thread](https://discuss.prosemirror.net/t/need-help-to-improve-editor-performance/8860)
- [PM doc model (whole-tree, persistent)](https://prosemirror.net/docs/guide/#doc)

### Lexical
- [Emergence Engineering: Lexical vs ProseMirror stress test](https://emergence-engineering.com/blog/lexical-prosemirror-comparison)
- [Lexical markdown package docs](https://lexical.dev/docs/packages/lexical-markdown)

### Comparison / production apps
- [Liveblocks: 2025 editor framework comparison](https://liveblocks.io/blog/which-rich-text-editor-framework-should-you-choose-in-2025)
- [Outline `rich-markdown-editor` (archived Jan 2022)](https://github.com/outline/rich-markdown-editor)
- [Atlassian editor-core / atlaskit](https://atlaskit.atlassian.com/packages/editor/editor-core)

### Markdown plugins / PM nodes
- [`@benrbray/prosemirror-math`](https://github.com/benrbray/prosemirror-math)
- [`markdown-it-obsidian-callouts`](https://github.com/ebullient/markdown-it-obsidian-callouts)
- [`markdown-it-wikilinks-plus`](https://github.com/rgruner/markdown-it-wikilinks-plus)

### CodeMirror 6 (background — only relevant for understanding why we left)
- [`@codemirror/view` 6.41.0 changelog](https://github.com/codemirror/view/blob/main/CHANGELOG.md)
- [Marijn on widget heights](https://discuss.codemirror.net/t/cursor-changing-heights-over-widget-created-spans/9148)
- [`font-variant-position` MDN](https://developer.mozilla.org/en-US/docs/Web/CSS/font-variant-position)

---

*This document is committed to `main` so the new worktree starts with
full context. Branch off `main`, follow the phased plan, gate at each
checkpoint, and you'll have a shippable Tiptap WYSIWYG editor in
roughly 4 weeks of focused work. Good luck.*
