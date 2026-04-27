import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands";
import { markdown } from "@codemirror/lang-markdown";
import { EditorState, RangeSetBuilder, Compartment, StateEffect, StateField, type Extension } from "@codemirror/state";
import {
  search,
  searchKeymap,
  SearchQuery,
  setSearchQuery,
  findNext,
  findPrevious
} from "@codemirror/search";
import {
  Decoration,
  drawSelection,
  EditorView,
  keymap,
  type DecorationSet,
  WidgetType
} from "@codemirror/view";
import MarkdownIt from "markdown-it";

declare global {
  interface Window {
    clearlyLiveEditor: {
      mount: (payload: MountPayload) => void;
      setDocument: (payload: { markdown: string }) => void;
      setTheme: (payload: ThemePayload) => void;
      setFindQuery: (payload: { query: string }) => void;
      applyCommand: (payload: { command: string }) => void;
      scrollToLine: (payload: { line: number }) => void;
      scrollToOffset: (payload: { offset: number }) => void;
      insertText: (payload: { text: string }) => void;
      focus: () => void;
      getDocument: () => string;
    };
    webkit?: {
      messageHandlers?: {
        liveEditor?: {
          postMessage: (message: Record<string, unknown>) => void;
        };
      };
    };
    katex?: {
      renderToString?: (source: string, options?: Record<string, unknown>) => string;
    };
    mermaid?: {
      initialize?: (options: Record<string, unknown>) => void;
      render?: (id: string, source: string) => Promise<{ svg: string }>;
    };
    hljs?: {
      highlight?: (source: string, options: { language: string }) => { value: string };
      highlightAuto?: (source: string) => { value: string };
      getLanguage?: (name: string) => boolean;
    };
  }
}

type MountPayload = {
  markdown: string;
  appearance: "light" | "dark";
  fontSize: number;
  filePath: string;
  epoch: number;
};

type ThemePayload = {
  appearance: "light" | "dark";
  fontSize: number;
  filePath: string;
};

type ActiveRange = { from: number; to: number };

const root = document.getElementById("editor");
const themeCompartment = new Compartment();
const livePreviewCompartment = new Compartment();
const markdownIt = new MarkdownIt({ html: true, linkify: true, breaks: false });

let editor: EditorView | null = null;
let currentFilePath = "";
let currentQuery = "";
let currentAppearance: "light" | "dark" = "light";
let currentFontSize = 16;
let isApplyingHostUpdate = false;
let mermaidInitialized = false;
// Logical clock incremented by the Swift host on every document switch.
// Echoed back in every docChanged so Swift can reject stale messages from
// the previous document that arrive after the switch has already happened.
let currentEpoch = 0;
// True while any table cell has focus. Prevents rangeHasSelection from
// collapsing the table widget back to raw markdown during in-place editing.
let tableFocusActive = false;

const hiddenDecoration = Decoration.replace({});
const setOutlineFlashEffect = StateEffect.define<number>();
const clearOutlineFlashEffect = StateEffect.define<void>();

const outlineFlashField = StateField.define<DecorationSet>({
  create() {
    return Decoration.none;
  },
  update(value, transaction) {
    let next = value.map(transaction.changes);

    for (const effect of transaction.effects) {
      if (effect.is(clearOutlineFlashEffect)) {
        next = Decoration.none;
      } else if (effect.is(setOutlineFlashEffect)) {
        const clamped = Math.max(0, Math.min(effect.value, transaction.state.doc.length));
        const line = transaction.state.doc.lineAt(clamped);
        next = Decoration.set([
          Decoration.line({ class: "cm-live-outline-flash" }).range(line.from)
        ]);
      }
    }

    return next;
  },
  provide(field) {
    return EditorView.decorations.from(field);
  }
});

function postMessage(message: Record<string, unknown>) {
  window.webkit?.messageHandlers?.liveEditor?.postMessage(message);
}

function log(message: string) {
  postMessage({ type: "log", message });
}

window.addEventListener("error", (event) => {
  log(`window error: ${event.message}`);
});

window.addEventListener("unhandledrejection", (event) => {
  log(`unhandled rejection: ${String(event.reason)}`);
});

function escapeHTML(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll("\"", "&quot;");
}

function revealAt(view: EditorView, position: number) {
  const anchor = Math.max(0, Math.min(position, view.state.doc.length));
  view.dispatch({
    selection: { anchor },
    scrollIntoView: true
  });
  view.focus();
}

function blockWrapper(view: EditorView, from: number, className: string) {
  const wrapper = document.createElement("div");
  wrapper.className = `cm-live-block ${className}`;
  wrapper.tabIndex = 0;
  wrapper.addEventListener("mousedown", (event) => {
    if ((event.target as HTMLElement).closest("a")) {
      return;
    }
    event.preventDefault();
    revealAt(view, from);
  });
  return wrapper;
}

class LivePrefixWidget extends WidgetType {
  constructor(
    private readonly from: number,
    private readonly label: string,
    private readonly className: string
  ) {
    super();
  }

  eq(other: LivePrefixWidget) {
    return this.label === other.label && this.className === other.className;
  }

  toDOM(view: EditorView) {
    const span = document.createElement("span");
    span.className = `cm-live-prefix ${this.className}`;
    span.textContent = this.label;
    span.addEventListener("mousedown", (event) => {
      event.preventDefault();
      revealAt(view, this.from);
    });
    return span;
  }

  ignoreEvent() {
    return false;
  }
}

class TaskCheckboxWidget extends WidgetType {
  constructor(
    private readonly from: number,
    private readonly to: number,
    private readonly bullet: string,
    private readonly checked: boolean
  ) {
    super();
  }

  eq(other: TaskCheckboxWidget) {
    return this.bullet === other.bullet && this.checked === other.checked;
  }

  toDOM(view: EditorView) {
    const input = document.createElement("input");
    input.type = "checkbox";
    input.checked = this.checked;
    input.className = "cm-live-task-checkbox";
    input.addEventListener("mousedown", (event) => {
      event.preventDefault();
      const marker = `${this.bullet} [${this.checked ? " " : "x"}] `;
      view.dispatch({
        changes: { from: this.from, to: this.to, insert: marker }
      });
      view.focus();
    });
    return input;
  }

  ignoreEvent() {
    return false;
  }
}

class HTMLBlockWidget extends WidgetType {
  constructor(
    private readonly from: number,
    private readonly html: string,
    private readonly className: string
  ) {
    super();
  }

  eq(other: HTMLBlockWidget) {
    return this.html === other.html && this.className === other.className;
  }

  toDOM(view: EditorView) {
    const wrapper = blockWrapper(view, this.from, this.className);
    wrapper.innerHTML = this.html;
    return wrapper;
  }

  ignoreEvent() {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Interactive table widget
// ---------------------------------------------------------------------------

function buildTableMarkdown(rows: string[][]): string {
  if (rows.length === 0) return "";
  const colCount = Math.max(...rows.map((r) => r.length), 1);
  const normalized = rows.map((r) => {
    const padded = [...r];
    while (padded.length < colCount) padded.push("");
    return padded;
  });
  const colWidths = Array.from({ length: colCount }, (_, i) =>
    Math.max(3, ...normalized.map((r) => (r[i] ?? "").length))
  );
  const formatRow = (cells: string[]) =>
    "| " + cells.map((c, i) => c.padEnd(colWidths[i] ?? 3)).join(" | ") + " |";
  const sep = "| " + colWidths.map((w) => "-".repeat(w)).join(" | ") + " |";
  return [formatRow(normalized[0] ?? []), sep, ...normalized.slice(1).map(formatRow)].join("\n");
}

function selectAllContent(el: HTMLElement) {
  const range = document.createRange();
  const sel = window.getSelection();
  range.selectNodeContents(el);
  sel?.removeAllRanges();
  sel?.addRange(range);
}

class TableBlockWidget extends WidgetType {
  constructor(
    private readonly from: number,
    private readonly tableLines: string[]
  ) {
    super();
  }

  eq(other: TableBlockWidget) {
    return (
      this.tableLines.length === other.tableLines.length &&
      this.tableLines.every((line, i) => line === other.tableLines[i])
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  private parseRows(): string[][] {
    return this.tableLines
      .filter((_, i) => i !== 1) // skip separator row
      .map((line) => line.replace(/^\||\|$/g, "").split("|").map((c) => c.trim()));
  }

  /** Read the current table boundaries and row data from the live document. */
  private currentTableData(view: EditorView): { from: number; to: number; rows: string[][] } {
    const state = view.state;
    let lastLine = state.doc.lineAt(this.from);
    while (lastLine.number < state.doc.lines) {
      const next = state.doc.line(lastLine.number + 1);
      if (!next.text.trim().startsWith("|")) break;
      lastLine = next;
    }
    const to = lastLine.to;
    const lines = state.sliceDoc(this.from, to).split("\n");
    const rows = lines
      .filter((_, i) => i !== 1)
      .map((line) => line.replace(/^\||\|$/g, "").split("|").map((c) => c.trim()));
    return { from: this.from, to, rows };
  }

  // ---------------------------------------------------------------------------
  // Cell interactions
  // ---------------------------------------------------------------------------

  private dataCells(wrapper: HTMLElement): HTMLElement[] {
    return Array.from(
      wrapper.querySelectorAll<HTMLElement>("th:not([data-control]), td:not([data-control])")
    );
  }

  private onCellInput(view: EditorView, wrapper: HTMLElement) {
    const { from, to } = this.currentTableData(view);
    const rows: string[][] = [];
    wrapper.querySelectorAll<HTMLElement>("tr").forEach((tr) => {
      const cells = Array.from(
        tr.querySelectorAll<HTMLElement>("th:not([data-control]), td:not([data-control])")
      ).map((c) => c.textContent ?? "");
      if (cells.length > 0) rows.push(cells);
    });
    if (rows.length > 0) {
      view.dispatch({ changes: { from, to, insert: buildTableMarkdown(rows) } });
    }
  }

  private onCellKeydown(
    e: KeyboardEvent,
    view: EditorView,
    wrapper: HTMLElement,
    cell: HTMLElement
  ) {
    if (e.key === "Tab") {
      e.preventDefault();
      e.stopPropagation();
      const all = this.dataCells(wrapper);
      const idx = all.indexOf(cell);
      const next = all[idx + (e.shiftKey ? -1 : 1)];
      if (next) { next.focus(); selectAllContent(next); }
    } else if (e.key === "Enter") {
      e.preventDefault();
      e.stopPropagation();
      const all = this.dataCells(wrapper);
      const idx = all.indexOf(cell);
      const colCount = cell.closest("tr")
        ?.querySelectorAll("th:not([data-control]), td:not([data-control])").length ?? 1;
      const next = all[idx + colCount];
      if (next) { next.focus(); selectAllContent(next); }
    } else if (e.key === "Escape") {
      e.preventDefault();
      tableFocusActive = false;
      cell.blur();
      // Move CM cursor into the table range → rangeHasSelection becomes true →
      // the widget is skipped → raw markdown is revealed (intentional collapse).
      revealAt(view, this.from);
    }
  }

  private makeCellListeners(view: EditorView, wrapper: HTMLElement, cell: HTMLElement) {
    cell.addEventListener("focus", () => { tableFocusActive = true; });
    cell.addEventListener("blur", () => {
      requestAnimationFrame(() => {
        if (document.activeElement?.closest(".cm-live-table-block")) return;
        tableFocusActive = false;
        const anchor = view.state.selection.main.anchor;
        view.dispatch({ selection: { anchor } });
      });
    });
    cell.addEventListener("input", () => this.onCellInput(view, wrapper), { passive: true });
    cell.addEventListener("keydown", (e) => this.onCellKeydown(e, view, wrapper, cell));
    cell.addEventListener("paste", (e) => {
      e.preventDefault();
      const plain = e.clipboardData?.getData("text/plain") ?? "";
      const sel = window.getSelection();
      if (!sel?.rangeCount) return;
      sel.deleteFromDocument();
      sel.getRangeAt(0).insertNode(document.createTextNode(plain));
      sel.collapseToEnd();
      cell.dispatchEvent(new Event("input", { bubbles: true }));
    });
  }

  // ---------------------------------------------------------------------------
  // Row / column management — contextual (position-specific)
  // ---------------------------------------------------------------------------

  /**
   * Release any focused table cell so updateDOM will perform a full re-render
   * after the structural change (add row / add column) is dispatched.
   */
  private releaseTableFocus() {
    const active = document.activeElement;
    if (active instanceof HTMLElement && active.closest(".cm-live-table-block")) {
      tableFocusActive = false;
      active.blur();
    }
  }

  /**
   * Insert an empty row after body row at `afterBodyRowIdx` (0-based in tbody).
   * rows[0] is the header, rows[1] is the first body row, so the insert position
   * in the full rows array is afterBodyRowIdx + 2.
   */
  private addRowAt(view: EditorView, afterBodyRowIdx: number) {
    this.releaseTableFocus();
    const { from, to, rows } = this.currentTableData(view);
    const colCount = rows[0]?.length ?? 1;
    rows.splice(afterBodyRowIdx + 2, 0, Array<string>(colCount).fill(""));
    view.dispatch({ changes: { from, to, insert: buildTableMarkdown(rows) } });
  }

  /**
   * Insert an empty column after the data column at `afterColIdx` (0-based).
   */
  private addColumnAt(view: EditorView, afterColIdx: number) {
    this.releaseTableFocus();
    const { from, to, rows } = this.currentTableData(view);
    rows.forEach((row) => row.splice(afterColIdx + 1, 0, ""));
    view.dispatch({ changes: { from, to, insert: buildTableMarkdown(rows) } });
  }

  // ---------------------------------------------------------------------------
  // DOM rendering
  // ---------------------------------------------------------------------------

  private renderInto(view: EditorView, wrapper: HTMLElement) {
    while (wrapper.firstChild) wrapper.removeChild(wrapper.firstChild);

    const rows = this.parseRows();
    const scrollShell = document.createElement("div");
    scrollShell.className = "table-wrapper";
    const table = document.createElement("table");

    // ---- Header row ----
    const thead = table.createTHead();
    const headerTr = thead.insertRow();
    (rows[0] ?? []).forEach((text, colIdx) => {
      const th = document.createElement("th");
      th.contentEditable = "true";
      th.spellcheck = false;
      th.textContent = text;
      this.makeCellListeners(view, wrapper, th);

      // Column + button: sits at the right border of this header cell.
      // Clicking it inserts a column after this column's index.
      const colBtn = document.createElement("button");
      colBtn.className = "cm-live-table-col-add";
      colBtn.textContent = "+";
      colBtn.title = "Add column after";
      colBtn.addEventListener("mousedown", (e) => {
        e.preventDefault();
        this.addColumnAt(view, colIdx);
      });
      th.appendChild(colBtn);

      headerTr.appendChild(th);
    });
    // Empty control cell aligns with the row-add column in tbody
    const headerCtrl = document.createElement("th");
    headerCtrl.setAttribute("data-control", "true");
    headerCtrl.className = "cm-live-table-row-add-cell";
    headerTr.appendChild(headerCtrl);

    // ---- Body rows ----
    const tbody = table.createTBody();
    rows.slice(1).forEach((cells, bodyRowIdx) => {
      const tr = tbody.insertRow();
      cells.forEach((text) => {
        const td = document.createElement("td");
        td.contentEditable = "true";
        td.spellcheck = false;
        td.textContent = text;
        this.makeCellListeners(view, wrapper, td);
        tr.appendChild(td);
      });

      // Row + button: sits in a narrow last column.
      // Clicking it inserts a row after this body row.
      const rowCtrl = document.createElement("td");
      rowCtrl.setAttribute("data-control", "true");
      rowCtrl.className = "cm-live-table-row-add-cell";
      const rowBtn = document.createElement("button");
      rowBtn.className = "cm-live-table-row-add-btn";
      rowBtn.textContent = "+";
      rowBtn.title = "Add row after";
      rowBtn.addEventListener("mousedown", (e) => {
        e.preventDefault();
        this.addRowAt(view, bodyRowIdx);
      });
      rowCtrl.appendChild(rowBtn);
      tr.appendChild(rowCtrl);
    });

    scrollShell.appendChild(table);
    wrapper.appendChild(scrollShell);

    // Click on wrapper background moves CM cursor to the table position
    wrapper.addEventListener("mousedown", (e) => {
      if ((e.target as HTMLElement).closest("td, th")) return;
      e.preventDefault();
      revealAt(view, this.from);
    });
  }

  toDOM(view: EditorView) {
    const wrapper = document.createElement("div");
    wrapper.className = "cm-live-block cm-live-table-block table-shell";
    this.renderInto(view, wrapper);
    return wrapper;
  }

  updateDOM(dom: HTMLElement, view: EditorView): boolean {
    if (!isApplyingHostUpdate && dom.contains(document.activeElement)) {
      return true;
    }
    this.renderInto(view, dom);
    return true;
  }

  ignoreEvent() {
    return true;
  }
}

class MermaidBlockWidget extends WidgetType {
  constructor(private readonly from: number, private readonly source: string) {
    super();
  }

  eq(other: MermaidBlockWidget) {
    return this.source === other.source;
  }

  toDOM(view: EditorView) {
    const wrapper = blockWrapper(view, this.from, "cm-live-mermaid-block");
    const container = document.createElement("div");
    container.className = "mermaid cm-live-mermaid-diagram";
    wrapper.appendChild(container);

    if (!mermaidInitialized) {
      window.mermaid?.initialize?.({
        startOnLoad: false,
        securityLevel: "loose",
        theme: currentAppearance === "dark" ? "dark" : "default"
      });
      mermaidInitialized = true;
    }

    if (window.mermaid?.render) {
      const id = `clearly-mermaid-${Math.random().toString(36).slice(2)}`;
      window.mermaid.render(id, this.source)
        .then(({ svg }) => {
          container.innerHTML = svg;
        })
        .catch(() => {
          container.innerHTML = `<pre>${escapeHTML(this.source)}</pre>`;
        });
    } else {
      container.innerHTML = `<pre>${escapeHTML(this.source)}</pre>`;
    }

    return wrapper;
  }

  ignoreEvent() {
    return false;
  }
}

class MathBlockWidget extends WidgetType {
  constructor(private readonly from: number, private readonly source: string) {
    super();
  }

  eq(other: MathBlockWidget) {
    return this.source === other.source;
  }

  toDOM(view: EditorView) {
    const wrapper = blockWrapper(view, this.from, "cm-live-math-block");
    wrapper.classList.add("math-block");
    if (window.katex?.renderToString) {
      wrapper.innerHTML = window.katex.renderToString(this.source, {
        displayMode: true,
        throwOnError: false
      });
    } else {
      wrapper.innerHTML = `<pre>${escapeHTML(this.source)}</pre>`;
    }
    return wrapper;
  }

  ignoreEvent() {
    return false;
  }
}

function widgetDecoration(widget: WidgetType, block = false) {
  return Decoration.replace({ widget, block });
}

function markDecoration(className: string, attributes?: Record<string, string>) {
  return Decoration.mark({
    class: className,
    attributes
  });
}

function lineDecoration(className: string) {
  return Decoration.line({ class: className });
}

function lineHasSelection(state: EditorState, from: number, to: number) {
  return state.selection.ranges.some((range) => {
    if (range.empty) {
      return range.from >= from && range.from <= to;
    }
    return range.from <= to && range.to >= from;
  });
}

function rangeHasSelection(state: EditorState, from: number, to: number) {
  return state.selection.ranges.some((range) => {
    if (range.empty) {
      return range.from >= from && range.from <= to;
    }
    return range.from <= to && range.to >= from;
  });
}

function resolvedImageURL(source: string) {
  if (/^(https?:|data:|clearly-file:)/i.test(source)) {
    return source;
  }

  if (source.startsWith("/")) {
    return `clearly-file://localhost${encodeURI(source)}`;
  }

  if (!currentFilePath) {
    return source;
  }

  const baseDirectory = currentFilePath.slice(0, currentFilePath.lastIndexOf("/") + 1);
  const resolved = new URL(source, `file://${baseDirectory}`).pathname;
  return `clearly-file://localhost${encodeURI(resolved)}`;
}

function renderHTMLSnippet(markdownSource: string) {
  const html = markdownIt.render(markdownSource);
  const template = document.createElement("template");
  template.innerHTML = html;
  template.content.querySelectorAll("img").forEach((image) => {
    const source = image.getAttribute("src");
    if (source) {
      image.setAttribute("src", resolvedImageURL(source));
    }
  });
  return template.innerHTML;
}

function renderFrontmatterHTML(source: string) {
  const lines = source.split(/\r?\n/).slice(1, -1);
  const rows = lines
    .map((line) => {
      const separator = line.indexOf(":");
      if (separator === -1) {
        return "";
      }
      const key = escapeHTML(line.slice(0, separator).trim());
      const value = escapeHTML(line.slice(separator + 1).trim());
      return `<div class="frontmatter-row"><dt>${key}</dt><dd>${value}</dd></div>`;
    })
    .filter(Boolean)
    .join("");

  if (!rows) {
    return `<pre>${escapeHTML(source)}</pre>`;
  }

  return `<div class="frontmatter"><dl>${rows}</dl></div>`;
}

function renderCodeBlockHTML(info: string, source: string) {
  const language = info.split(/\s+/)[0] ?? "";
  const highlighter = window.hljs;
  const highlighted = language && highlighter?.getLanguage?.(language)
    ? highlighter.highlight?.(source, { language }).value
    : highlighter?.highlightAuto?.(source).value;
  const codeHTML = highlighted ?? escapeHTML(source);
  const labelHTML = language ? `<div class="cm-live-code-label">${escapeHTML(language)}</div>` : "";
  return `<div class="code-block-wrapper">${labelHTML}<pre><code>${codeHTML}</code></pre></div>`;
}

function renderImageHTML(alt: string, source: string) {
  const resolved = resolvedImageURL(source);
  const label = alt ? `<figcaption>${escapeHTML(alt)}</figcaption>` : "";
  return `<figure class="cm-live-image-figure"><img src="${resolved}" alt="${escapeHTML(alt)}">${label}</figure>`;
}

function sliceBetweenLines(state: EditorState, startLineNumber: number, endLineNumber: number) {
  if (endLineNumber < startLineNumber) {
    return "";
  }
  return state.sliceDoc(state.doc.line(startLineNumber).from, state.doc.line(endLineNumber).to);
}

function updateFindStatus(state: EditorState) {
  if (!currentQuery) {
    postMessage({ type: "findStatus", matchCount: 0, currentIndex: 0 });
    return;
  }

  const text = state.doc.toString();
  const query = currentQuery.toLowerCase();
  const lower = text.toLowerCase();
  const positions: number[] = [];
  let start = 0;

  while (start < lower.length) {
    const found = lower.indexOf(query, start);
    if (found === -1) {
      break;
    }
    positions.push(found);
    start = found + Math.max(1, query.length);
  }

  if (!positions.length) {
    postMessage({ type: "findStatus", matchCount: 0, currentIndex: 0 });
    return;
  }

  const anchor = state.selection.main.from;
  let currentIndex = positions.findIndex((position) => position === anchor);
  if (currentIndex === -1) {
    currentIndex = positions.findIndex((position) => position >= anchor);
  }
  if (currentIndex === -1) {
    currentIndex = positions.length - 1;
  }

  postMessage({
    type: "findStatus",
    matchCount: positions.length,
    currentIndex: currentIndex + 1
  });
}

function replaceSelection(
  view: EditorView,
  builder: (selected: string) => { insert: string; selectionFrom: number; selectionTo: number }
) {
  const range = view.state.selection.main;
  const selected = view.state.sliceDoc(range.from, range.to);
  const result = builder(selected);
  view.dispatch({
    changes: { from: range.from, to: range.to, insert: result.insert },
    selection: {
      anchor: range.from + result.selectionFrom,
      head: range.from + result.selectionTo
    }
  });
  view.focus();
}

function selectedLineRange(view: EditorView) {
  const selection = view.state.selection.main;
  const start = view.state.doc.lineAt(selection.from);
  const end = view.state.doc.lineAt(selection.to);
  return { from: start.from, to: end.to };
}

function wrapSelection(view: EditorView, prefix: string, suffix: string, placeholder: string) {
  replaceSelection(view, (selected) => {
    if (!selected) {
      return {
        insert: `${prefix}${placeholder}${suffix}`,
        selectionFrom: prefix.length,
        selectionTo: prefix.length + placeholder.length
      };
    }
    return {
      insert: `${prefix}${selected}${suffix}`,
      selectionFrom: prefix.length,
      selectionTo: prefix.length + selected.length
    };
  });
}

function toggleLinePrefix(view: EditorView, prefix: string, placeholder: string) {
  const selection = view.state.selection.main;
  const selected = view.state.sliceDoc(selection.from, selection.to);
  if (!selected) {
    view.dispatch({
      changes: {
        from: selection.from,
        to: selection.to,
        insert: `${prefix}${placeholder}`
      },
      selection: {
        anchor: selection.from + prefix.length,
        head: selection.from + prefix.length + placeholder.length
      }
    });
    view.focus();
    return;
  }

  const range = selectedLineRange(view);
  const lines = view.state.sliceDoc(range.from, range.to).split("\n");
  const result = lines.map((line) => (line ? `${prefix}${line}` : line)).join("\n");
  view.dispatch({
    changes: { from: range.from, to: range.to, insert: result }
  });
  view.focus();
}

function toggleNumberedList(view: EditorView) {
  const selection = view.state.selection.main;
  const selected = view.state.sliceDoc(selection.from, selection.to);
  if (!selected) {
    const text = "1. list item";
    view.dispatch({
      changes: { from: selection.from, to: selection.to, insert: text },
      selection: { anchor: selection.from + 3, head: selection.from + text.length }
    });
    view.focus();
    return;
  }

  const range = selectedLineRange(view);
  const lines = view.state.sliceDoc(range.from, range.to).split("\n");
  let number = 1;
  const result = lines.map((line) => {
    if (!line) {
      return line;
    }
    const next = `${number}. ${line}`;
    number += 1;
    return next;
  }).join("\n");
  view.dispatch({
    changes: { from: range.from, to: range.to, insert: result }
  });
  view.focus();
}

function cycleHeading(view: EditorView) {
  const selection = view.state.selection.main;
  const line = view.state.doc.lineAt(selection.from);
  const current = line.text;
  const hashes = current.match(/^#+/)?.[0] ?? "";
  const trimmed = current.replace(/^#+\s*/, "");

  let nextLine = trimmed;
  if (!hashes.length) {
    nextLine = `# ${trimmed}`;
  } else if (hashes.length < 6) {
    nextLine = `${"#".repeat(hashes.length + 1)} ${trimmed}`;
  }

  view.dispatch({
    changes: { from: line.from, to: line.to, insert: nextLine }
  });
  view.focus();
}

function insertSnippet(view: EditorView, snippet: string, selectedRangeFrom?: number, selectedRangeTo?: number) {
  const selection = view.state.selection.main;
  view.dispatch({
    changes: { from: selection.from, to: selection.to, insert: snippet },
    selection: selectedRangeFrom != null && selectedRangeTo != null
      ? {
          anchor: selection.from + selectedRangeFrom,
          head: selection.from + selectedRangeTo
        }
      : undefined
  });
  view.focus();
}

function requestAddAnnotation(view: EditorView) {
  const selection = view.state.selection.main;
  const fromRect = view.coordsAtPos(selection.from);
  const toRect = view.coordsAtPos(selection.to);
  const selectionRect = fromRect && toRect
    ? {
        x: Math.min(fromRect.left, toRect.left),
        y: Math.min(fromRect.top, toRect.top),
        width: Math.max(1, Math.abs(toRect.right - fromRect.left)),
        height: Math.max(fromRect.bottom, toRect.bottom) - Math.min(fromRect.top, toRect.top)
      }
    : null;
  postMessage({
    type: "addAnnotationRequested",
    markdown: view.state.doc.toString(),
    from: selection.from,
    to: selection.to,
    selectionRect
  });
}

function applyFormattingCommand(command: string) {
  if (!editor) {
    return;
  }

  switch (command) {
    case "bold":
      wrapSelection(editor, "**", "**", "bold text");
      break;
    case "italic":
      wrapSelection(editor, "*", "*", "italic text");
      break;
    case "strikethrough":
      wrapSelection(editor, "~~", "~~", "strikethrough text");
      break;
    case "heading":
      cycleHeading(editor);
      break;
    case "link":
      replaceSelection(editor, (selected) => {
        if (!selected) {
          return {
            insert: "[link text](url)",
            selectionFrom: "[link text](".length,
            selectionTo: "[link text](url".length
          };
        }
        const insert = `[${selected}](url)`;
        const start = `[${selected}](`.length;
        return {
          insert,
          selectionFrom: start,
          selectionTo: start + "url".length
        };
      });
      break;
    case "image":
      replaceSelection(editor, (selected) => {
        if (!selected) {
          return {
            insert: "![alt text](url)",
            selectionFrom: "![alt text](".length,
            selectionTo: "![alt text](url".length
          };
        }
        const insert = `![${selected}](url)`;
        const start = `![${selected}](`.length;
        return {
          insert,
          selectionFrom: start,
          selectionTo: start + "url".length
        };
      });
      break;
    case "bulletList":
      toggleLinePrefix(editor, "- ", "list item");
      break;
    case "numberedList":
      toggleNumberedList(editor);
      break;
    case "todoList":
      toggleLinePrefix(editor, "- [ ] ", "task");
      break;
    case "blockquote":
      toggleLinePrefix(editor, "> ", "quote");
      break;
    case "horizontalRule":
      insertSnippet(editor, "\n\n---\n\n");
      break;
    case "table":
      insertSnippet(editor, "| Column 1 | Column 2 | Column 3 |\n| --- | --- | --- |\n| Cell | Cell | Cell |");
      break;
    case "inlineCode":
      wrapSelection(editor, "`", "`", "code");
      break;
    case "codeBlock": {
      const selected = editor.state.sliceDoc(editor.state.selection.main.from, editor.state.selection.main.to);
      if (!selected) {
        insertSnippet(editor, "```\ncode\n```", 4, 8);
      } else {
        insertSnippet(editor, `\`\`\`\n${selected}\n\`\`\``);
      }
      break;
    }
    case "inlineMath":
      wrapSelection(editor, "$", "$", "math");
      break;
    case "mathBlock": {
      const selected = editor.state.sliceDoc(editor.state.selection.main.from, editor.state.selection.main.to);
      if (!selected) {
        insertSnippet(editor, "$$\nmath\n$$", 3, 7);
      } else {
        insertSnippet(editor, `$$\n${selected}\n$$`);
      }
      break;
    }
    case "pageBreak":
      insertSnippet(editor, "\n\n<div class=\"page-break\"></div>\n\n");
      break;
    case "addAnnotation": {
      requestAddAnnotation(editor);
      break;
    }
    case "findNext":
      findNext(editor);
      updateFindStatus(editor.state);
      break;
    case "findPrevious":
      findPrevious(editor);
      updateFindStatus(editor.state);
      break;
    default:
      log(`Unknown command: ${command}`);
  }
}

function isTableSeparator(text: string) {
  return /^\s*\|?(?:\s*:?-+:?\s*\|)+\s*:?-+:?\s*\|?\s*$/.test(text);
}

function isQuoteLine(text: string) {
  return /^(\s*)>\s?/.test(text);
}

function buildDecorations(state: EditorState): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();

  // Collect all inline decoration adds for a line before flushing to the shared
  // builder. Each pattern scans the line independently, so matches from different
  // patterns can appear out of position order within the line. Sort before flushing.
  const applyInlineDecorations = (text: string, offset: number, usedRanges: ActiveRange[]) => {
    const overlaps = (from: number, to: number) => usedRanges.some((range) => range.from < to && range.to > from);
    const reserve = (from: number, to: number) => usedRanges.push({ from, to });

    type PendingAdd = { from: number; to: number; deco: Decoration };
    const pending: PendingAdd[] = [];

    const decorateWrapped = (
      regex: RegExp,
      className: string,
      attributeBuilder?: (match: RegExpExecArray) => Record<string, string>
    ) => {
      regex.lastIndex = 0;
      let match: RegExpExecArray | null;
      while ((match = regex.exec(text)) !== null) {
        const fullMatch = match[0];
        const content = match[1] ?? "";
        const start = offset + match.index;
        const contentStart = start + fullMatch.indexOf(content);
        const contentEnd = contentStart + content.length;
        const end = start + fullMatch.length;
        if (!content.length || overlaps(start, end)) {
          continue;
        }
        // If the cursor is within the span, show raw markers so the user can edit
        if (rangeHasSelection(state, start, end)) {
          continue;
        }
        pending.push({ from: start, to: contentStart, deco: hiddenDecoration });
        pending.push({ from: contentStart, to: contentEnd, deco: markDecoration(className, attributeBuilder?.(match)) });
        pending.push({ from: contentEnd, to: end, deco: hiddenDecoration });
        reserve(start, end);
      }
    };

    decorateWrapped(/(?<!!)\[([^\]]+)\]\(([^)]+)\)/g, "cm-live-link", (match) => ({
      "data-live-link-kind": "markdown",
      "data-live-href": match[2] ?? ""
    }));
    decorateWrapped(/\{==(.+?)==\}\{>>\s*(.+?)\s*<<\}\[\^(cn-[A-Za-z0-9.-]+)\]/g, "cm-live-annotation", (match) => ({
      "data-live-annotation-id": match[3] ?? "",
      "data-live-annotation-comment": match[2] ?? ""
    }));
    decorateWrapped(/\{==(.+?)==\}\[\^(cn-[A-Za-z0-9.-]+)\]/g, "cm-live-annotation", (match) => ({
      "data-live-annotation-id": match[2] ?? ""
    }));
    decorateWrapped(/\[\[([^\]#]+(?:#[^\]]+)?)\]\]/g, "cm-live-wiki-link", (match) => {
      const raw = match[1] ?? "";
      const [target, heading] = raw.split("#");
      return {
        "data-live-link-kind": "wiki",
        "data-live-target": target,
        "data-live-heading": heading ?? ""
      };
    });
    decorateWrapped(/`([^`]+)`/g, "cm-live-inline-code");
    decorateWrapped(/(?:\*\*|__)(.+?)(?:\*\*|__)/g, "cm-live-strong");
    decorateWrapped(/~~(.+?)~~/g, "cm-live-strikethrough");
    decorateWrapped(/(?<!\*)\*([^*]+)\*(?!\*)/g, "cm-live-emphasis");
    decorateWrapped(/(?<!_)_([^_]+)_(?!_)/g, "cm-live-emphasis");

    const tagRegex = /(^|\s)(#[\p{L}\p{N}_/-]+)/gu;
    let tagMatch: RegExpExecArray | null;
    while ((tagMatch = tagRegex.exec(text)) !== null) {
      const prefix = tagMatch[1] ?? "";
      const tag = tagMatch[2] ?? "";
      const start = offset + tagMatch.index + prefix.length;
      const end = start + tag.length;
      if (overlaps(start, end)) {
        continue;
      }
      pending.push({ from: start, to: end, deco: markDecoration("cm-live-tag", {
        "data-live-link-kind": "tag",
        "data-live-tag": tag.slice(1)
      }) });
      reserve(start, end);
    }

    pending.sort((a, b) => a.from - b.from || a.to - b.to);
    for (const { from, to, deco } of pending) {
      builder.add(from, to, deco);
    }
  };

  // Single pass: process each line in document order. Block checks run first;
  // `continue` skips past the block, guaranteeing that all builder.add() calls
  // are in strictly non-decreasing `from` order — a RangeSetBuilder invariant.
  let lineNumber = 1;
  while (lineNumber <= state.doc.lines) {
    const line = state.doc.line(lineNumber);
    const trimmed = line.text.trim();

    // --- Frontmatter block (line 1 only) ---
    if (lineNumber === 1 && trimmed === "---") {
      let closeLine = lineNumber + 1;
      while (closeLine <= state.doc.lines && state.doc.line(closeLine).text.trim() !== "---") {
        closeLine += 1;
      }
      if (closeLine <= state.doc.lines) {
        const endLine = state.doc.line(closeLine);
        const from = line.from;
        const to = endLine.to;
        if (!rangeHasSelection(state, from, to)) {
          const source = state.sliceDoc(from, to);
          builder.add(from, to, widgetDecoration(new HTMLBlockWidget(from, renderFrontmatterHTML(source), "cm-live-frontmatter-block"), true));
        }
        lineNumber = closeLine + 1;
        continue;
      }
    }

    // --- Fenced code block ---
    const fenceMatch = /^(?<fence>`{3,}|~{3,})(?<info>.*)$/.exec(line.text);
    if (fenceMatch?.groups) {
      const fence = fenceMatch.groups.fence;
      const info = fenceMatch.groups.info.trim();
      let closeLine = lineNumber + 1;
      while (closeLine <= state.doc.lines) {
        const candidate = state.doc.line(closeLine).text.trim();
        if (candidate.startsWith(fence[0]) && candidate.length >= fence.length) {
          break;
        }
        closeLine += 1;
      }
      if (closeLine <= state.doc.lines) {
        const endLine = state.doc.line(closeLine);
        const from = line.from;
        const to = endLine.to;
        if (!rangeHasSelection(state, from, to)) {
          const source = sliceBetweenLines(state, lineNumber + 1, closeLine - 1);
          if (info === "mermaid") {
            builder.add(from, to, widgetDecoration(new MermaidBlockWidget(from, source), true));
          } else {
            builder.add(from, to, widgetDecoration(new HTMLBlockWidget(from, renderCodeBlockHTML(info, source), "cm-live-code-block"), true));
          }
        }
        lineNumber = closeLine + 1;
        continue;
      }
    }

    // --- Math block ($$) ---
    if (trimmed === "$$") {
      let closeLine = lineNumber + 1;
      while (closeLine <= state.doc.lines && state.doc.line(closeLine).text.trim() !== "$$") {
        closeLine += 1;
      }
      if (closeLine <= state.doc.lines) {
        const endLine = state.doc.line(closeLine);
        const from = line.from;
        const to = endLine.to;
        if (!rangeHasSelection(state, from, to)) {
          const source = sliceBetweenLines(state, lineNumber + 1, closeLine - 1);
          builder.add(from, to, widgetDecoration(new MathBlockWidget(from, source), true));
        }
        lineNumber = closeLine + 1;
        continue;
      }
    }

    // --- Table block ---
    if (lineNumber + 1 <= state.doc.lines && line.text.trim().startsWith("|") && isTableSeparator(state.doc.line(lineNumber + 1).text)) {
      let endLineNumber = lineNumber + 1;
      while (endLineNumber + 1 <= state.doc.lines && state.doc.line(endLineNumber + 1).text.trim().startsWith("|")) {
        endLineNumber += 1;
      }
      const endLine = state.doc.line(endLineNumber);
      const from = line.from;
      const to = endLine.to;
      // Collapse to raw markdown when the CM cursor is inside the table range
      // (Cmd+A, arrow navigation, or Escape from a cell) — but NOT while a cell
      // is being edited (tableFocusActive guards against that).
      if (!tableFocusActive && rangeHasSelection(state, from, to)) {
        lineNumber = endLineNumber + 1;
        continue;
      }
      const tableLines = state.sliceDoc(from, to).split("\n");
      builder.add(from, to, widgetDecoration(new TableBlockWidget(from, tableLines), true));
      lineNumber = endLineNumber + 1;
      continue;
    }

    // --- Standalone image line ---
    const imageOnlyMatch = /^!\[([^\]]*)\]\(([^)]+)\)\s*$/.exec(trimmed);
    if (imageOnlyMatch) {
      if (!lineHasSelection(state, line.from, line.to)) {
        builder.add(line.from, line.to, widgetDecoration(new HTMLBlockWidget(line.from, renderImageHTML(imageOnlyMatch[1], imageOnlyMatch[2]), "cm-live-image-block"), true));
      }
      lineNumber += 1;
      continue;
    }

    // --- Horizontal rule ---
    if (/^([-*_])(?:\s*\1){2,}$/.test(trimmed)) {
      if (!lineHasSelection(state, line.from, line.to)) {
        builder.add(line.from, line.to, widgetDecoration(new HTMLBlockWidget(line.from, "<hr>", "cm-live-rule-block"), true));
      }
      lineNumber += 1;
      continue;
    }

    // --- Page break ---
    if (trimmed === "<div class=\"page-break\"></div>") {
      if (!lineHasSelection(state, line.from, line.to)) {
        builder.add(line.from, line.to, widgetDecoration(new HTMLBlockWidget(line.from, "<div class=\"cm-live-page-break-mark\">Page Break</div>", "cm-live-page-break-block"), true));
      }
      lineNumber += 1;
      continue;
    }

    // --- Inline decorations for this non-block line ---
    const text = line.text;
    if (!text) {
      lineNumber += 1;
      continue;
    }

    const usedRanges: ActiveRange[] = [];

    const headingMatch = /^(#{1,6})\s+/.exec(text);
    if (headingMatch) {
      const level = headingMatch[1].length;
      const markerLength = headingMatch[0].length;
      const markerEnd = line.from + markerLength;
      builder.add(line.from, line.from, lineDecoration(`cm-live-heading-line cm-live-heading-line-${level}`));
      // Hide the `# ` prefix only when cursor is not within it
      if (!rangeHasSelection(state, line.from, markerEnd)) {
        builder.add(line.from, markerEnd, hiddenDecoration);
      }
      usedRanges.push({ from: line.from, to: markerEnd });
    }

    const taskRe = /^(\s*)([-*+]) \[( |x|X)\] /;
    const taskMatch = taskRe.exec(text);
    if (taskMatch) {
      const indent = taskMatch[1]?.length ?? 0;
      const bullet = taskMatch[2] ?? "-";
      const checked = (taskMatch[3] ?? " ").toLowerCase() === "x";
      const markerFrom = line.from + indent;
      const markerTo = markerFrom + taskMatch[0].length - indent;
      // lineDecoration must come before markerFrom to maintain RangeSetBuilder ordering
      builder.add(line.from, line.from, lineDecoration("cm-live-task-line"));
      if (!rangeHasSelection(state, markerFrom, markerTo)) {
        builder.add(markerFrom, markerTo, widgetDecoration(new TaskCheckboxWidget(markerFrom, markerTo, bullet, checked)));
      }
      usedRanges.push({ from: markerFrom, to: markerTo });
    } else {
      const quoteRe = /^(\s*)>\s?/;
      const quoteMatch = quoteRe.exec(text);
      if (quoteMatch) {
        const indent = quoteMatch[1]?.length ?? 0;
        const markerFrom = line.from + indent;
        const markerTo = markerFrom + quoteMatch[0].length - indent;
        const prevIsQuote = lineNumber > 1 && isQuoteLine(state.doc.line(lineNumber - 1).text);
        const nextIsQuote = lineNumber < state.doc.lines && isQuoteLine(state.doc.line(lineNumber + 1).text);
        const quoteLineClass = prevIsQuote
          ? nextIsQuote
            ? "cm-live-quote-line cm-live-quote-middle"
            : "cm-live-quote-line cm-live-quote-bottom"
          : nextIsQuote
            ? "cm-live-quote-line cm-live-quote-top"
            : "cm-live-quote-line cm-live-quote-single";
        builder.add(line.from, line.from, lineDecoration(quoteLineClass));
        if (!rangeHasSelection(state, markerFrom, markerTo)) {
          builder.add(markerFrom, markerTo, hiddenDecoration);
        }
        usedRanges.push({ from: markerFrom, to: markerTo });
      } else {
        const bulletRe = /^(\s*)([-*+])\s+/;
        const bulletMatch = bulletRe.exec(text);
        if (bulletMatch) {
          const indent = bulletMatch[1]?.length ?? 0;
          const markerFrom = line.from + indent;
          const markerTo = markerFrom + bulletMatch[0].length - indent;
          if (!rangeHasSelection(state, markerFrom, markerTo)) {
            builder.add(markerFrom, markerTo, widgetDecoration(new LivePrefixWidget(markerFrom, "•", "cm-live-list-prefix")));
          }
          usedRanges.push({ from: markerFrom, to: markerTo });
        } else {
          const numberedRe = /^(\s*)(\d+)\.\s+/;
          const numberedMatch = numberedRe.exec(text);
          if (numberedMatch) {
            const indent = numberedMatch[1]?.length ?? 0;
            const markerFrom = line.from + indent;
            const markerTo = markerFrom + numberedMatch[0].length - indent;
            if (!rangeHasSelection(state, markerFrom, markerTo)) {
              builder.add(markerFrom, markerTo, widgetDecoration(new LivePrefixWidget(markerFrom, `${numberedMatch[2]}.`, "cm-live-list-prefix cm-live-ordered-prefix")));
            }
            usedRanges.push({ from: markerFrom, to: markerTo });
          }
        }
      }
    }

    applyInlineDecorations(text, line.from, usedRanges);

    lineNumber += 1;
  }

  return builder.finish();
}

function buildDecorationsSafely(state: EditorState, fallback: DecorationSet = Decoration.none): DecorationSet {
  try {
    return buildDecorations(state);
  } catch (error) {
    log(`buildDecorations error: ${String(error)}`);
    return fallback;
  }
}

const livePreviewDecorations = StateField.define<DecorationSet>({
  create(state) {
    return buildDecorationsSafely(state);
  },
  update(value, transaction) {
    if (transaction.docChanged || transaction.selection) {
      return buildDecorationsSafely(transaction.state, value);
    }
    return value;
  },
  provide: (field) => EditorView.decorations.from(field)
});

function livePreviewTheme(appearance: "light" | "dark", fontSize: number): Extension {
  const isDark = appearance === "dark";
  const background = isDark ? "#323236" : "#FFFFFF";
  const text = isDark ? "#F5F5F7" : "#1D1D1F";
  const muted = isDark ? "#AEAEB2" : "#86868B";
  const subtleText = isDark ? "#E5E5EA" : "#48484A";
  const link = isDark ? "#0A84FF" : "#0071E3";
  const wiki = isDark ? "#5ABF80" : "#34855A";
  const wikiBorder = isDark ? "rgba(90, 191, 128, 0.3)" : "rgba(52, 133, 90, 0.3)";
  const tag = isDark ? "#7AB0D9" : "#3A6EA5";
  const tagBackground = isDark ? "rgba(122, 176, 217, 0.12)" : "rgba(58, 110, 165, 0.08)";
  const inlineCodeBackground = isDark ? "rgba(255, 255, 255, 0.06)" : "rgba(0, 0, 0, 0.04)";
  const preBackground = isDark ? "rgba(255, 255, 255, 0.05)" : "#F5F5F7";
  const codeLabelBackground = isDark ? "rgba(255, 255, 255, 0.07)" : "#EDEDF0";
  const quoteBackground = isDark ? "rgba(255, 255, 255, 0.04)" : "rgba(0, 0, 0, 0.03)";
  const tableBorder = isDark ? "rgba(255, 255, 255, 0.15)" : "rgba(0, 0, 0, 0.12)";
  const tableRowBorder = isDark ? "rgba(255, 255, 255, 0.08)" : "rgba(0, 0, 0, 0.06)";
  const tableHover = isDark ? "rgba(255, 255, 255, 0.03)" : "rgba(0, 0, 0, 0.02)";
  const buttonBackground = isDark ? "rgba(255, 255, 255, 0.07)" : "rgba(0, 0, 0, 0.05)";
  const buttonHover = isDark ? "rgba(255, 255, 255, 0.1)" : "rgba(0, 0, 0, 0.08)";
  const buttonActive = isDark ? "rgba(255, 255, 255, 0.14)" : "rgba(0, 0, 0, 0.12)";
  const selection = isDark ? "rgba(10, 132, 255, 0.28)" : "rgba(0, 113, 227, 0.18)";

  return EditorView.theme({
    "&": {
      height: "100%",
      backgroundColor: background,
      color: text,
      fontSize: `${fontSize}px`,
      overflow: "hidden"
    },
    ".cm-scroller": {
      overflow: "auto",
      fontFamily: 'system-ui, -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", "Helvetica Neue", sans-serif'
    },
    ".cm-content": {
      width: "100%",
      maxWidth: "61em",
      margin: "0 auto",
      boxSizing: "border-box",
      padding: "16px clamp(20px, 6vw, 64px) 48px",
      minHeight: "100%",
      lineHeight: "1.75",
      caretColor: text,
      WebkitFontSmoothing: "antialiased",
      overflowWrap: "anywhere"
    },
    ".cm-focused": {
      outline: "none"
    },
    ".cm-line": {
      padding: "0",
      color: text,
      maxWidth: "100%",
      overflowWrap: "anywhere",
      wordBreak: "break-word"
    },
    ".cm-selectionBackground, ::selection": {
      backgroundColor: selection
    },
    ".cm-cursor, .cm-dropCursor": {
      borderLeftColor: text
    },
    ".cm-activeLine": {
      backgroundColor: "transparent"
    },
    ".cm-line.cm-live-heading-line": {
      color: text,
      fontFamily: 'system-ui, -apple-system, BlinkMacSystemFont, "SF Pro Display", "Helvetica Neue", sans-serif',
      fontWeight: "650",
      lineHeight: "1.25",
      letterSpacing: "-0.015em"
    },
    ".cm-line.cm-live-heading-line-1": {
      fontSize: "2.25em",
      fontWeight: "700",
      lineHeight: "1.15",
      letterSpacing: "-0.025em",
      paddingTop: "0.08em",
      paddingBottom: "0.1em"
    },
    ".cm-line.cm-live-heading-line-2": {
      fontSize: "1.625em",
      lineHeight: "1.18",
      paddingTop: "0.06em",
      paddingBottom: "0.08em"
    },
    ".cm-line.cm-live-heading-line-3": {
      fontSize: "1.3125em",
      fontWeight: "600",
      lineHeight: "1.22",
      paddingTop: "0.05em",
      paddingBottom: "0.06em"
    },
    ".cm-line.cm-live-heading-line-4": {
      fontSize: "1.125em",
      fontWeight: "600"
    },
    ".cm-line.cm-live-heading-line-5": {
      fontSize: "1em",
      fontWeight: "600"
    },
    ".cm-line.cm-live-heading-line-6": {
      fontSize: "0.9375em",
      fontWeight: "600",
      textTransform: "uppercase",
      letterSpacing: "0.05em",
      color: isDark ? "rgba(245, 245, 247, 0.55)" : "rgba(29, 29, 31, 0.55)"
    },
    ".cm-line.cm-live-outline-flash": {
      backgroundColor: isDark ? "rgba(90, 191, 128, 0.18)" : "rgba(52, 133, 90, 0.12)",
      boxShadow: isDark
        ? "0 0 0 1px rgba(90, 191, 128, 0.45) inset"
        : "0 0 0 1px rgba(52, 133, 90, 0.35) inset",
      borderRadius: "8px"
    },
    ".cm-live-strong": {
      fontWeight: "700"
    },
    ".cm-live-emphasis": {
      fontStyle: "italic"
    },
    ".cm-live-strikethrough": {
      textDecoration: "line-through",
      opacity: "0.6"
    },
    ".cm-live-inline-code": {
      fontFamily: '"SF Mono", SFMono-Regular, Menlo, monospace',
      fontSize: "0.875em",
      backgroundColor: inlineCodeBackground,
      borderRadius: "5px",
      padding: "0.125em 0.375em",
      color: text
    },
    ".cm-live-link": {
      color: link,
      textDecoration: "none"
    },
    ".cm-live-wiki-link": {
      color: wiki,
      textDecoration: "none",
      borderBottom: `1px solid ${wikiBorder}`
    },
    ".cm-live-tag": {
      color: tag,
      backgroundColor: tagBackground,
      borderRadius: "3px",
      padding: "1px 5px",
      fontSize: "0.9em"
    },
    ".cm-live-annotation": {
      backgroundColor: isDark ? "rgba(255, 214, 0, 0.2)" : "rgba(255, 212, 0, 0.24)",
      borderBottom: `1px solid ${isDark ? "rgba(255, 214, 0, 0.45)" : "rgba(191, 142, 0, 0.45)"}`,
      borderRadius: "3px",
      padding: "0.05em 0.15em"
    },
    ".cm-live-prefix": {
      display: "inline-flex",
      alignItems: "center",
      justifyContent: "center",
      minWidth: "1.4rem",
      marginRight: "0.15rem",
      color: muted
    },
    ".cm-line.cm-live-quote-line": {
      backgroundColor: quoteBackground,
      color: subtleText,
      boxSizing: "border-box",
      paddingLeft: "1.25em",
      paddingRight: "1.25em"
    },
    ".cm-line.cm-live-quote-single": {
      borderRadius: "8px",
      paddingTop: "0.75em",
      paddingBottom: "0.75em"
    },
    ".cm-line.cm-live-quote-top": {
      borderTopLeftRadius: "8px",
      borderTopRightRadius: "8px",
      paddingTop: "0.75em"
    },
    ".cm-line.cm-live-quote-middle": {
      borderRadius: "0"
    },
    ".cm-line.cm-live-quote-bottom": {
      borderBottomLeftRadius: "8px",
      borderBottomRightRadius: "8px",
      paddingBottom: "0.75em"
    },
    ".cm-live-task-checkbox": {
      transform: "translateY(1px)",
      marginRight: "0.45rem"
    },
    ".cm-live-block": {
      display: "block",
      boxSizing: "border-box",
      paddingBottom: "1.25em"
    },
    ".cm-live-block:last-child": {
      paddingBottom: "0"
    },
    ".cm-live-block pre": {
      position: "relative",
      backgroundColor: preBackground,
      borderRadius: "10px",
      padding: "1.125em 1.25em",
      margin: "0",
      overflowX: "auto",
      whiteSpace: "pre"
    },
    ".cm-live-code-label": {
      fontFamily: '"SF Mono", SFMono-Regular, Menlo, monospace',
      padding: "0.5em 1.25em",
      background: codeLabelBackground,
      borderRadius: "10px 10px 0 0",
      fontSize: "0.8em",
      color: muted
    },
    ".code-block-wrapper": {
      position: "relative"
    },
    ".code-block-wrapper > pre": {
      marginBottom: "0"
    },
    ".cm-live-code-label + pre": {
      borderTopLeftRadius: "0",
      borderTopRightRadius: "0"
    },
    ".cm-live-code-block code, .cm-live-code-block pre code": {
      fontFamily: '"SF Mono", SFMono-Regular, Menlo, monospace',
      background: "none",
      color: text,
      padding: "0",
      fontSize: "0.875em"
    },
    ".frontmatter": {
      padding: "1em 1.25em",
      backgroundColor: quoteBackground,
      borderRadius: "10px",
      fontSize: "0.85em"
    },
    ".frontmatter dl": {
      margin: "0"
    },
    ".frontmatter .frontmatter-row": {
      display: "flex",
      gap: "0.5em",
      padding: "0.15em 0"
    },
    ".frontmatter dt": {
      fontWeight: "600",
      color: muted,
      minWidth: "6em"
    },
    ".frontmatter dd": {
      margin: "0",
      color: text,
      whiteSpace: "pre-wrap"
    },
    ".cm-live-image-figure": {
      margin: "0",
      display: "grid",
      gap: "0.7rem"
    },
    ".cm-live-image-figure img": {
      maxWidth: "100%",
      borderRadius: "12px",
      display: "block"
    },
    ".cm-live-image-figure figcaption": {
      color: muted,
      fontSize: "0.9em"
    },
    ".cm-live-rule-block hr": {
      border: "0",
      borderTop: `0.5px solid ${isDark ? "rgba(255, 255, 255, 0.1)" : "rgba(0, 0, 0, 0.1)"}`,
      margin: "0"
    },
    ".cm-live-page-break-mark": {
      fontSize: "0.8em",
      color: muted,
      textTransform: "uppercase",
      letterSpacing: "0.08em"
    },
    ".cm-live-math-block, .cm-live-mermaid-block": {
      textAlign: "center",
      overflowX: "auto"
    },
    ".table-wrapper": {
      overflowX: "auto"
    },
    ".cm-live-table-block table": {
      width: "100%",
      borderCollapse: "collapse",
      fontVariantNumeric: "tabular-nums"
    },
    ".cm-live-table-block th, .cm-live-table-block td": {
      padding: "0.625em 0.875em",
      minWidth: "80px",
      verticalAlign: "top",
      cursor: "text",
      maxWidth: "20em",
      overflowWrap: "break-word"
    },
    ".cm-live-table-block th": {
      fontWeight: "600",
      backgroundColor: "transparent",
      borderBottom: `1px solid ${tableBorder}`,
      position: "relative",
      overflow: "visible",
      whiteSpace: "nowrap"
    },
    ".cm-live-table-block td": {
      borderBottom: `1px solid ${tableRowBorder}`
    },
    ".cm-live-table-block th:focus, .cm-live-table-block td:focus": {
      outline: `2px solid ${link}`,
      outlineOffset: "-2px"
    },
    // Column + button: floats at the right edge of each header cell
    ".cm-live-table-col-add": {
      position: "absolute",
      right: "-11px",
      top: "50%",
      transform: "translateY(-50%)",
      zIndex: "2",
      width: "20px",
      height: "20px",
      borderRadius: "50%",
      border: "none",
      backgroundColor: buttonBackground,
      color: muted,
      fontSize: "14px",
      lineHeight: "1",
      padding: "0",
      cursor: "pointer",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      opacity: "0",
      transition: "opacity 0.15s",
      fontFamily: "inherit"
    },
    ".cm-live-table-block th:hover .cm-live-table-col-add": {
      opacity: "1"
    },
    ".cm-live-table-block tr:hover td": {
      backgroundColor: tableHover
    },
    // Row + control: a narrow column on the right side of the table
    ".cm-live-table-row-add-cell": {
      width: "26px",
      minWidth: "0",
      border: "none",
      backgroundColor: "transparent",
      padding: "0 0 0 4px",
      verticalAlign: "middle",
      textAlign: "center"
    },
    ".cm-live-table-row-add-btn": {
      width: "20px",
      height: "20px",
      borderRadius: "50%",
      border: "none",
      backgroundColor: buttonBackground,
      color: muted,
      fontSize: "14px",
      lineHeight: "1",
      padding: "0",
      cursor: "pointer",
      display: "inline-flex",
      alignItems: "center",
      justifyContent: "center",
      opacity: "0",
      transition: "opacity 0.15s",
      fontFamily: "inherit"
    },
    ".cm-live-table-block tr:hover .cm-live-table-row-add-btn": {
      opacity: "1"
    },
    ".cm-live-table-col-add:hover, .cm-live-table-row-add-btn:hover": {
      backgroundColor: buttonHover
    },
    ".cm-live-table-col-add:active, .cm-live-table-row-add-btn:active": {
      backgroundColor: buttonActive
    }
  }, { dark: isDark });
}

function openLinkFromTarget(target: HTMLElement) {
  const kind = target.dataset.liveLinkKind;
  if (!kind) {
    return;
  }

  if (kind === "wiki") {
    postMessage({
      type: "openLink",
      kind: "wiki",
      target: target.dataset.liveTarget ?? "",
      heading: target.dataset.liveHeading ?? ""
    });
    return;
  }

  if (kind === "tag") {
    postMessage({
      type: "openLink",
      kind: "tag",
      tag: target.dataset.liveTag ?? ""
    });
    return;
  }

  postMessage({
    type: "openLink",
    kind: "markdown",
    href: target.dataset.liveHref ?? ""
  });
}

function createEditor(payload: MountPayload) {
  currentFilePath = payload.filePath;
  currentAppearance = payload.appearance;
  currentFontSize = payload.fontSize;
  currentEpoch = payload.epoch;

  const extensions: Extension[] = [
    drawSelection(),
    history(),
    markdown(),
    search(),
    outlineFlashField,
    EditorView.lineWrapping,
    EditorView.contentAttributes.of({
      spellcheck: "true",
      autocorrect: "off",
      autocapitalize: "off",
      autocomplete: "off"
    }),
    keymap.of([
      ...defaultKeymap,
      ...historyKeymap,
      ...searchKeymap,
      indentWithTab
    ]),
    themeCompartment.of(livePreviewTheme(payload.appearance, payload.fontSize)),
    livePreviewCompartment.of(livePreviewDecorations),
    EditorView.domEventHandlers({
      mousedown(event) {
        const target = (event.target as HTMLElement | null)?.closest<HTMLElement>("[data-live-link-kind]");
        if (!target || !event.metaKey) {
          return false;
        }
        event.preventDefault();
        openLinkFromTarget(target);
        return true;
      }
    }),
    EditorView.updateListener.of((update) => {
      if (update.docChanged && !isApplyingHostUpdate) {
        postMessage({
          type: "docChanged",
          markdown: update.state.doc.toString(),
          epoch: currentEpoch
        });
      }
      if (update.docChanged || update.selectionSet) {
        updateFindStatus(update.state);
      }
    })
  ];

  const state = EditorState.create({
    doc: payload.markdown,
    extensions
  });

  if (!root) {
    throw new Error("Live editor root element not found");
  }

  editor = new EditorView({
    state,
    parent: root
  });

  setFindQuery(currentQuery);
  updateFindStatus(editor.state);
}

function setDocument(markdownSource: string, epoch = 0) {
  if (!editor) {
    return;
  }
  // Always update epoch first — even if content is unchanged — so that
  // any docChanged messages produced after this call carry the new epoch.
  currentEpoch = epoch;
  tableFocusActive = false;
  if (editor.state.doc.toString() === markdownSource) {
    return;
  }
  // Reset cursor to top. This is intentional: setDocument is only called by
  // the Swift host for document switches or external file changes — not for
  // incremental edits (those go through CodeMirror's own input handling).
  isApplyingHostUpdate = true;
  try {
    editor.dispatch({
      changes: { from: 0, to: editor.state.doc.length, insert: markdownSource },
      selection: { anchor: 0 }
    });
  } finally {
    isApplyingHostUpdate = false;
  }
  updateFindStatus(editor.state);
}

function setTheme(payload: ThemePayload) {
  currentAppearance = payload.appearance;
  currentFontSize = payload.fontSize;
  currentFilePath = payload.filePath;
  mermaidInitialized = false;
  if (!editor) {
    return;
  }
  editor.dispatch({
    effects: themeCompartment.reconfigure(livePreviewTheme(payload.appearance, payload.fontSize))
  });
}

function setFindQuery(query: string) {
  currentQuery = query;
  if (!editor) {
    return;
  }
  editor.dispatch({
    effects: setSearchQuery.of(new SearchQuery({
      search: query,
      caseSensitive: false,
      regexp: false,
      literal: true
    }))
  });
  updateFindStatus(editor.state);
}

function centerAndFlashLineAt(position: number) {
  if (!editor) {
    return;
  }

  const clamped = Math.max(0, Math.min(position, editor.state.doc.length));
  const line = editor.state.doc.lineAt(clamped);

  editor.dispatch({
    effects: clearOutlineFlashEffect.of()
  });

  requestAnimationFrame(() => {
    if (!editor) {
      return;
    }

    editor.dispatch({
      effects: [
        EditorView.scrollIntoView(line.from, { y: "center" }),
        setOutlineFlashEffect.of(line.from)
      ]
    });

    window.setTimeout(() => {
      editor?.dispatch({
        effects: clearOutlineFlashEffect.of()
      });
    }, 900);
  });
}

function scrollToLine(line: number) {
  if (!editor || line <= 0) {
    return;
  }
  const targetLine = editor.state.doc.line(Math.min(line, editor.state.doc.lines));
  centerAndFlashLineAt(targetLine.from);
}

function scrollToOffset(offset: number) {
  if (!editor) {
    return;
  }
  centerAndFlashLineAt(offset);
}

window.clearlyLiveEditor = {
  mount(payload: MountPayload) {
    if (!editor) {
      createEditor(payload);
    } else {
      setTheme(payload);
      setDocument(payload.markdown, payload.epoch);
    }
  },

  setDocument(payload: { markdown: string; epoch?: number }) {
    setDocument(payload.markdown, payload.epoch ?? 0);
  },

  setTheme(payload: ThemePayload) {
    setTheme(payload);
  },

  setFindQuery(payload: { query: string }) {
    setFindQuery(payload.query);
  },

  applyCommand(payload: { command: string }) {
    applyFormattingCommand(payload.command);
  },

  scrollToLine(payload: { line: number }) {
    scrollToLine(payload.line);
  },

  scrollToOffset(payload: { offset: number }) {
    scrollToOffset(payload.offset);
  },

  insertText(payload: { text: string }) {
    if (!editor) { return; }
    const text = payload.text.replace(/\r\n?/g, "\n");
    const { from, to } = editor.state.selection.main;
    try {
      editor.dispatch({
        changes: { from, to, insert: text },
        selection: { anchor: from + text.length }
      });
    } catch (e) {
      log(`insertText dispatch error: ${String(e)}`);
    }
    editor.focus();
  },

  focus() {
    editor?.focus();
  },

  getDocument() {
    return editor?.state.doc.toString() ?? "";
  }
};

postMessage({ type: "ready" });
