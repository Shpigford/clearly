# Markdown Rendering Architecture

This document describes how Clearly transforms markdown text into rendered output across its three rendering contexts: the live preview editor, the classic preview pane, and QuickLook/PDF export.

---

## Rendering Contexts

| Context | Entry point | Output |
|---------|------------|--------|
| Classic editor | `EditorView.swift` + `MarkdownSyntaxHighlighter.swift` | Syntax-colored `NSTextView` |
| Classic preview | `PreviewView.swift` | Full HTML in `WKWebView` |
| Live preview editor | `LiveEditorView.swift` + `ClearlyLiveEditorWeb/` | CodeMirror in `WKWebView` with inline widgets |
| QuickLook | `ClearlyQuickLook/PreviewProvider.swift` | Full HTML in `QLPreviewReply` |
| PDF / Print | `PDFExporter.swift` | Full HTML printed via `WKWebView` |

---

## 1. Markdown → HTML Pipeline (Classic Preview / QuickLook / PDF)

All three static rendering contexts share `Shared/MarkdownRenderer.swift`, which wraps `cmark_gfm_markdown_to_html()` from the `cmark-gfm` library and applies a sequential post-processing pipeline.

### 1.1 cmark-gfm

`cmark_gfm` produces GitHub-Flavored Markdown HTML. Enabled extensions: `table`, `strikethrough`, `autolink`, `tagfilter`, `tasklist`.

### 1.2 Post-processing pipeline

Each step runs in order on the raw HTML string. Steps that touch inline syntax must use `protectCodeRegions()` / `restoreProtectedSegments()` to avoid transforming content inside `<pre>` / `<code>` tags.

| Order | Step | Source |
|-------|------|--------|
| 1 | Protect code regions | `MarkdownRenderer.swift` |
| 2 | Math spans (`$...$` → KaTeX `<span>`) | `MathSupport.swift` |
| 3 | Highlight marks (`==text==` → `<mark>`) | `MarkdownRenderer.swift` |
| 4 | Superscript / subscript (`^x^`, `~x~`) | `MarkdownRenderer.swift` |
| 5 | Emoji shortcodes (`:smile:`) | `MarkdownRenderer.swift` |
| 6 | Callouts / admonitions (`[!TYPE]` blockquotes) | `MarkdownRenderer.swift` |
| 7 | TOC generation (`[[toc]]`) | `MarkdownRenderer.swift` |
| 8 | Table captions | `TableSupport.swift` |
| 9 | Code filename headers | `MarkdownRenderer.swift` |
| 10 | Restore code regions | `MarkdownRenderer.swift` |

### 1.3 JS feature injection

After the HTML pipeline, each rendering context injects optional `<script>` blocks for client-side features. Each support file exposes a static method that returns an HTML string (a `<script>` tag) or empty string if the feature is not needed for the current content:

- `MathSupport.renderScript(html:)` — KaTeX math rendering
- `MermaidSupport.renderScript(html:)` — diagram rendering
- `SyntaxHighlightSupport.renderScript()` — code block syntax highlighting via highlight.js
- `TableSupport.renderScript(html:)` — sortable table headers

### 1.4 CSS

`PreviewCSS.swift` holds the full stylesheet as a Swift string. It covers four contexts:

1. **Base (light)** — default styles
2. **`@media (prefers-color-scheme: dark)`** — dark mode overrides
3. **`@media print`** — hides interactive elements, adjusts layout for printing
4. **`forExport` override string** — injected for PDF/clipboard exports to force light theme and hide UI chrome

**Source order rule**: Base (light) styles must appear BEFORE `@media (prefers-color-scheme: dark)` overrides for the same elements. A base rule defined after a dark-mode `@media` block wins by source order, breaking dark mode. Add each dark-mode override immediately after its base definition.

---

## 2. Classic Editor Syntax Highlighting

`Shared/MarkdownSyntaxHighlighter.swift` applies `NSTextStorage`-based live highlighting to the `NSTextView` in `EditorView`. It uses `NSTextStorageDelegate.textStorage(_:didProcessEditing:range:changeInLength:)` to re-highlight affected ranges after each edit.

Highlighting is regex-based. Order matters because code blocks are matched first to prevent inner syntax from being styled:

1. Fenced code blocks (``` ``` ```)
2. Inline code (`` ` ``)
3. Headings (`#` … `######`)
4. Bold / italic / bold-italic
5. Links and images
6. Blockquotes
7. List markers
8. Horizontal rules

Colors come from `Theme.swift` dynamic `NSColor` pairs (light/dark). No colors are hard-coded.

---

## 3. Live Preview Editor

The live preview editor is a hybrid: raw markdown source is edited inside a CodeMirror 6 instance rendered in a `WKWebView`. CodeMirror's decoration system overlays rendered widgets on completed blocks while the cursor is elsewhere, giving an "edit in place" feel.

Its visual styling should track the classic preview pane as closely as possible: the same typography, heading scale, spacing, link treatments, code surfaces, and block presentation should be used unless live editing behavior requires a deliberate deviation.

### 3.1 Architecture

```
Swift (LiveEditorView.swift)          JS (ClearlyLiveEditorWeb/src/index.ts)
──────────────────────────            ──────────────────────────────────────
LiveEditorWebView (WKWebView)
  └── Coordinator
        ├── evaluateJavaScript ──→    window.clearlyLiveEditor.<method>(json)
        └── WKScriptMessageHandler ←── window.webkit.messageHandlers
                                              .liveEditor.postMessage(...)
```

**Swift → JS** (via `evaluateJavaScript`):

| Method | Purpose |
|--------|---------|
| `mount(markdown, appearance, fontSize, filePath, epoch)` | Initial editor setup |
| `setDocument(markdown, epoch)` | Replace document on file switch |
| `setTheme(appearance, fontSize, filePath)` | Update theme/font |
| `applyCommand(command)` | Formatting actions (bold, italic, heading…) |
| `setFindQuery(query)` | Drive the in-editor find bar |
| `scrollToLine(line)` | Navigate outline / backlinks clicks |
| `scrollToOffset(offset)` | Navigate outline ranges |
| `focus()` | Restore CodeMirror focus |
| `getDocument()` | Synchronous content read (returns Promise) |
| `insertText(text)` | Paste routing (bypasses WebKit clipboard restriction) |

**JS → Swift** (via `postMessage`):

| Type | Payload | Purpose |
|------|---------|---------|
| `ready` | — | Web app loaded; Swift calls `mount` |
| `docChanged` | `{markdown, epoch}` | Text changed; Swift updates binding |
| `findStatus` | `{matchCount, currentIndex}` | Find bar state |
| `openLink` | `{kind, target/href/tag}` | Link / wiki-link / tag clicked |
| `log` | `{message}` | Debug forwarded to `DiagnosticLog` |

### 3.2 Document epoch

`WorkspaceManager.documentEpoch` is a monotonically increasing integer incremented on every document switch. It is passed with `mount`/`setDocument` and echoed back in every `docChanged` message. Swift rejects `docChanged` messages whose epoch doesn't match the current epoch, preventing stale editor content from overwriting the active file after a rapid switch.

### 3.3 Flush protocol

Before any save or document snapshot, `WorkspaceManager.snapshotActiveDocument()` calls `flushActiveEditorBuffer()`, which posts the `.flushEditorBuffer` notification synchronously. The coordinator handles it in two stages:

1. **Synchronous path**: if `hasReceivedDocChanged` is true, immediately deliver `lastSyncedText` via `onFlushContent`. This is the confirmed last known state from the previous `docChanged` message.
2. **Async path**: fire `getDocument()` via `evaluateJavaScript` to capture any keystrokes that haven't yet posted a `docChanged` message. The completion is guarded by both `LiveEditorSession.currentDocumentID` and `documentEpoch` — stale completions are rejected.

`LiveEditorSession.currentDocumentID` and `documentEpoch` are updated together synchronously in `WorkspaceManager.activateDocument` and `restoreActiveDocument` via `LiveEditorSession.update(documentID:epoch:)`. That combined update happens before SwiftUI's `updateNSView` has a chance to run, so any in-flight async completions from the previous document are rejected.

`hasReceivedDocChanged` is reset in the coordinator's `syncFromSwiftIfNeeded` whenever `documentID` changes (detected via `lastKnownDocumentID`). This ensures the synchronous flush path skips delivering stale content for the brief window between document activation and the first `docChanged` from the new document.

### 3.4 NSViewRepresentable binding anti-pattern

SwiftUI can call `updateNSView` at any time (layout passes, unrelated state changes), not just when the `text` binding changes. When the user types:

1. CodeMirror fires a `docChanged` JS message
2. Coordinator sets `parent.text = markdown` (async, via `DispatchQueue.main.async`)
3. SwiftUI may call `updateNSView` before that async block runs — seeing a stale binding and trying to overwrite the editor

The fix is `pendingBindingUpdates`, a counter incremented synchronously in the message handler and decremented after the async binding update. `syncFromSwiftIfNeeded` skips calling `setDocument` while this counter is > 0.

---

## 4. Live Preview Block Widgets

CodeMirror's decoration API (`StateField<DecorationSet>` + `Decoration.replace` with `block: true`) renders completed markdown blocks as DOM widgets when the cursor is not inside them. The decoration set is rebuilt in `buildDecorations()` on every editor state change.

### 4.1 Which blocks get widgets

| Block | Widget class | Collapses to raw when… |
|-------|-------------|----------------------|
| Fenced code block | `CodeBlockWidget` | Cursor is inside the block |
| Frontmatter (`---` fence) | `FrontmatterBlockWidget` | Cursor is inside the block |
| Math block (`$$...$$`) | `MathBlockWidget` | Cursor is inside the block |
| Mermaid diagram | `MermaidBlockWidget` | Cursor is inside the block |
| Markdown table | `TableBlockWidget` | Cursor is inside the block AND no cell has focus |
| Horizontal rule | rendered inline (CSS) | — |

### 4.2 Card appearance

Only code, frontmatter, math, and mermaid widgets receive the card-like surface background and border (`.cm-live-code-block`, `.cm-live-frontmatter-block`, etc.). The base `.cm-live-block` class provides only margin, not the card chrome, so tables and other non-card blocks don't inherit it.

### 4.3 Table widget

`TableBlockWidget` (in `index.ts`) renders an interactive HTML table with `contentEditable` cells. Key behaviours:

**Cursor / focus guard**: `buildDecorations` skips rendering the table widget (leaves raw markdown) if `rangeHasSelection(state, from, to)` returns true AND `tableFocusActive` is false. `tableFocusActive` is set true on any cell `focus` event and cleared on `blur` (using `requestAnimationFrame` to allow focus to move between cells without flickering).

**Cell navigation**: Tab moves to next cell, Shift+Tab to previous. Enter moves down one row. Escape clears `tableFocusActive`, blurs the cell, then calls `revealAt(view, from)` which moves the CodeMirror cursor into the table range, causing the widget to collapse to raw markdown.

**In-place editing**: Cell `input` events read all cell text content from the DOM, call `buildTableMarkdown()` to regenerate pipe-table syntax, and dispatch a single CodeMirror transaction replacing the table range. This round-trips through JS without a server round-trip.

**Structural mutations** (add row / column): Before any structural change, `releaseTableFocus()` blurs the active cell. This is necessary because `updateDOM` returns `true` to preserve focus when a cell is focused — blurring first forces a full re-render so the new row/column appears.

**`updateDOM` focus preservation**: When the editor state changes while a cell has focus, `updateDOM` short-circuits (returns `true` without rebuilding the DOM) to avoid destroying the in-progress edit. The `isApplyingHostUpdate` flag bypasses this guard during host-driven document replacements (`setDocument`) that require a forced re-render.

**Context add buttons**: Each `<th>` has an absolutely positioned `+` button (`.cm-live-table-col-add`) that appears on hover to add a column after that column. Each body `<tr>` has a trailing control cell with a `+` button (`.cm-live-table-row-add-btn`) that appears on hover to add a row after that row.

---

## 5. Demo Document

`Shared/Resources/demo.md` is bundled with the app and accessible via **Help → Sample Document**. It should be kept updated when adding new markdown features so it acts as both a user-facing showcase and a visual regression fixture.

---

## 6. Adding a New Rendering Feature

Follow the `MathSupport` / `MermaidSupport` / `TableSupport` / `SyntaxHighlightSupport` pattern:

1. Create `Shared/<Feature>Support.swift` with a static method returning a `<script>` HTML string (or `""` if the feature doesn't apply to the current HTML).
2. Integrate into `PreviewView.swift`, `ClearlyQuickLook/PreviewProvider.swift`, and `PDFExporter.swift` HTML templates.
3. If the feature requires live-preview support, add a widget class in `ClearlyLiveEditorWeb/src/index.ts` following the `CodeBlockWidget` pattern: `WidgetType` subclass with `toDOM`, `updateDOM`, `ignoreEvent`, and a `buildDecorations` section that detects the block and instantiates the widget.
4. Update `Shared/Resources/demo.md` with an example of the new feature.
