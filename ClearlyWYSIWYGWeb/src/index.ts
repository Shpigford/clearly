import { Editor } from "@tiptap/core";
import { history } from "@tiptap/pm/history";
import { joinFrontmatter, splitFrontmatter } from "./frontmatter";
import { SourcePreservation } from "./preservation";
import { clearlyExtensions } from "./extensions";
import {
  setFindQuery as findSetQuery,
  navigateMatch as findNavigate,
  replaceCurrent as findReplaceCurrent,
  replaceAll as findReplaceAll,
  resetFind,
} from "./find";
import { setWikiTargets, type WikiTarget } from "./extensions/wiki-completion";
import { setTagTargets, type TagTarget } from "./extensions/tag-completion";

declare global {
  interface Window {
    clearlyWYSIWYG: {
      mount: (payload: { filePath: string; appearance: "light" | "dark"; fontSize: number; epoch: number }) => void;
      setDocument: (payload: { markdown: string; epoch: number }) => void;
      setTheme: (payload: { appearance: "light" | "dark"; fontSize: number; filePath: string }) => void;
      setFindQuery: (payload: { query: string; replacement: string; caseSensitive: boolean; wholeWord: boolean; regex: boolean }) => void;
      setWikiTargets: (payload: { targets: WikiTarget[] }) => void;
      setTagTargets: (payload: { targets: TagTarget[] }) => void;
      applyCommand: (payload: { command: string }) => void;
      scrollToLine: (payload: { line: number }) => void;
      scrollToOffset: (payload: { offset: number }) => void;
      scrollToHeading: (payload: { ordinal: number }) => void;
      insertText: (payload: { text: string }) => void;
      focus: () => void;
      getDocument: () => string;
    };
    webkit?: {
      messageHandlers?: {
        wysiwyg?: { postMessage: (msg: unknown) => void };
      };
    };
  }
}

let editor: Editor | null = null;
let pendingEpoch = 0;
let storedFrontmatter: string | null = null;
let preservation: SourcePreservation | null = null;
/// Counter incremented before any external (host-driven) content change
/// — setContent, preservation.attach's stamping transaction, etc. The
/// editor's onUpdate handler skips posting docChanged while this is > 0,
/// so switching INTO WYSIWYG mode never echoes a re-rendered markdown
/// back to Swift. Decremented in a microtask so all sync transactions
/// from a single host call finish under the same suppression.
let suppressDocChanged = 0;
function withSuppressedUpdates<T>(work: () => T): T {
  suppressDocChanged++;
  try {
    return work();
  } finally {
    // Decrement asynchronously so any update events queued by `work`
    // (PM's view layer can dispatch follow-up transactions on the next
    // tick) still see the suppression.
    queueMicrotask(() => {
      if (suppressDocChanged > 0) suppressDocChanged--;
    });
  }
}

function postToHost(msg: Record<string, unknown>): void {
  try {
    window.webkit?.messageHandlers?.wysiwyg?.postMessage(msg);
  } catch {
    // running outside WKWebView (perf harness, dev page) — ignore
  }
}

function applyAppearance(appearance: "light" | "dark", fontSize: number): void {
  document.documentElement.dataset.appearance = appearance;
  document.documentElement.style.setProperty("--editor-font-size", `${fontSize}px`);
}

function fullMarkdown(e: Editor): string {
  const body = preservation ? preservation.getMarkdownBody(e) : e.getMarkdown();
  return joinFrontmatter(storedFrontmatter, body);
}

function openImageLightbox(img: HTMLImageElement): void {
  const overlay = document.createElement("div");
  overlay.className = "lightbox-overlay";
  const clone = img.cloneNode() as HTMLImageElement;
  clone.className = "lightbox-img";
  clone.removeAttribute("style");
  overlay.appendChild(clone);
  overlay.addEventListener("click", () => {
    overlay.style.opacity = "0";
    setTimeout(() => overlay.remove(), 200);
  });
  document.body.appendChild(overlay);
  requestAnimationFrame(() => {
    overlay.style.opacity = "1";
  });
}

function attachClickDelegate(root: HTMLElement): void {
  // Capture-phase listener so we run before ProseMirror's own handlers (which
  // swallow some clicks) and before the browser navigates anchor tags.
  root.addEventListener(
    "click",
    (event) => {
      const target = event.target as HTMLElement | null;
      if (!target) return;

      const tagEl = target.closest("[data-tag]") as HTMLElement | null;
      if (tagEl) {
        const name = tagEl.getAttribute("data-name") ?? "";
        if (name) {
          event.preventDefault();
          event.stopPropagation();
          postToHost({ type: "openLink", kind: "tag", target: name });
        }
        return;
      }

      const wikiEl = target.closest("[data-wikilink]") as HTMLElement | null;
      if (wikiEl) {
        const wikiTarget = wikiEl.getAttribute("data-target") ?? "";
        const heading = wikiEl.getAttribute("data-heading");
        const alias = wikiEl.getAttribute("data-alias");
        if (wikiTarget) {
          event.preventDefault();
          event.stopPropagation();
          const payload: Record<string, unknown> = {
            type: "openLink",
            kind: "wiki",
            target: wikiTarget,
          };
          if (heading) payload.heading = heading;
          if (alias) payload.alias = alias;
          postToHost(payload);
        }
        return;
      }

      const img = target.closest(".ProseMirror img") as HTMLImageElement | null;
      if (img) {
        event.preventDefault();
        event.stopPropagation();
        openImageLightbox(img);
        return;
      }

      const fnRefAnchor = target.closest("sup.footnote-ref a") as HTMLAnchorElement | null;
      if (fnRefAnchor) {
        event.preventDefault();
        event.stopPropagation();
        const href = fnRefAnchor.getAttribute("href") || "";
        if (href.startsWith("#")) {
          const el = document.getElementById(href.slice(1));
          if (el) el.scrollIntoView({ behavior: "smooth", block: "center" });
        }
        return;
      }

      const tocAnchor = target.closest("nav.toc a[data-toc-pos]") as HTMLAnchorElement | null;
      if (tocAnchor) {
        event.preventDefault();
        event.stopPropagation();
        const pos = parseInt(tocAnchor.getAttribute("data-toc-pos") || "0", 10);
        if (editor) {
          try {
            const coords = editor.view.coordsAtPos(pos + 1);
            const top = coords.top + window.scrollY - 80;
            window.scrollTo({ top: Math.max(0, top), behavior: "smooth" });
          } catch {
            editor
              .chain()
              .focus()
              .setTextSelection(pos + 1)
              .scrollIntoView()
              .run();
          }
        }
        return;
      }

      const anchor = target.closest("a[href]") as HTMLAnchorElement | null;
      if (anchor && anchor.getAttribute("href")) {
        event.preventDefault();
        event.stopPropagation();
        postToHost({ type: "openLink", kind: "url", target: anchor.href });
      }
    },
    true
  );
}

// `setContent("", { contentType: "markdown" })` is a silent no-op: the
// markdown extension parses "" to `{ type: "doc", content: [] }`, which
// violates ProseMirror's `block+` schema, and the resulting `replaceWith`
// leaves the editor unchanged. `clearContent()` uses `tr.delete()` instead,
// which auto-fills with an empty paragraph. Use it for the empty case so a
// new untitled document doesn't display the previous note's content (#313).
function replaceEditorBody(body: string): void {
  if (!editor) return;
  if (body.length === 0) {
    editor.commands.clearContent();
  } else {
    editor.commands.setContent(body, { contentType: "markdown" });
  }
}

// Tiptap 3 / ProseMirror have no command to clear undo history, so reset
// the plugin instance instead. `unregisterPlugin("history")` filters by key
// prefix `history$` (the key PM's `history()` plugin always uses); the
// fresh `history()` registers under the same key, keeping UndoRedo's
// `Mod-Z` shortcut wired without extra plumbing.
function resetUndoHistory(): void {
  if (!editor) return;
  editor.unregisterPlugin("history");
  editor.registerPlugin(history());
}

function ensureMounted(initialMarkdown: string, epoch: number, appearance: "light" | "dark", fontSize: number): void {
  const root = document.getElementById("editor");
  if (!root) throw new Error("missing #editor root");
  applyAppearance(appearance, fontSize);
  const split = splitFrontmatter(initialMarkdown);
  storedFrontmatter = split.frontmatter;
  if (editor) {
    withSuppressedUpdates(() => {
      preservation?.beginExternalReplace(split.body);
      replaceEditorBody(split.body);
      // Tiptap's setContent leaves the selection covering the whole inserted
      // range (Selection.atStart-of-replaced-range to atEnd). Collapse to the
      // start so switching INTO WYSIWYG mode doesn't show the whole doc as
      // a giant selection.
      editor!.commands.setTextSelection(0);
      if (preservation) preservation.attach(editor!);
    });
    resetUndoHistory();
    pendingEpoch = epoch;
    return;
  }
  withSuppressedUpdates(() => {
    editor = new Editor({
      element: root,
      extensions: clearlyExtensions,
      content: split.body,
      contentType: "markdown",
      onUpdate: ({ editor: e }) => {
        if (suppressDocChanged > 0) return;
        // Skip docChanged during IME composition. WebKit fires per-keystroke
        // updates while the user is mid-composition (e.g. typing Hiragana
        // before committing Kanji); posting each one to Swift floods the
        // bridge and the resulting markdown is in an intermediate state.
        // PM exposes `view.composing`; a final docChanged fires after
        // compositionend automatically.
        if (e.view.composing) return;
        postToHost({ type: "docChanged", markdown: fullMarkdown(e), epoch: pendingEpoch });
      },
    });
    editor.commands.setTextSelection(0);
    preservation = new SourcePreservation(split.body);
    preservation.attach(editor);
    attachClickDelegate(root);
    attachCompositionFlush(editor, root);
  });
  pendingEpoch = epoch;
  postToHost({ type: "ready" });
}

function attachCompositionFlush(editor: Editor, root: HTMLElement): void {
  // PM clears `view.composing` synchronously when compositionend fires, but
  // the final flush of composed text into the doc lands in a transaction
  // immediately after — that transaction's onUpdate sees composing=false
  // and posts docChanged correctly. Belt-and-braces: also fire a manual
  // docChanged after compositionend in case the order changes in WebKit.
  root.addEventListener(
    "compositionend",
    () => {
      // Wait one tick so PM has a chance to apply the composed text.
      queueMicrotask(() => {
        if (!editor) return;
        if (suppressDocChanged > 0) return;
        if (editor.view.composing) return;
        postToHost({ type: "docChanged", markdown: fullMarkdown(editor), epoch: pendingEpoch });
      });
    },
    true
  );
}

window.clearlyWYSIWYG = {
  mount({ appearance, fontSize, epoch }) {
    ensureMounted("", epoch, appearance, fontSize);
  },
  setDocument({ markdown, epoch }) {
    pendingEpoch = epoch;
    if (!editor) {
      const appearance = (document.documentElement.dataset.appearance as "light" | "dark") || "light";
      const fontSize = parseInt(getComputedStyle(document.documentElement).getPropertyValue("--editor-font-size")) || 16;
      ensureMounted(markdown, epoch, appearance, fontSize);
      return;
    }
    const split = splitFrontmatter(markdown);
    storedFrontmatter = split.frontmatter;
    withSuppressedUpdates(() => {
      preservation?.beginExternalReplace(split.body);
      replaceEditorBody(split.body);
      editor!.commands.setTextSelection(0);
      if (preservation) preservation.attach(editor!);
    });
    resetUndoHistory();
  },
  setTheme({ appearance, fontSize }) {
    applyAppearance(appearance, fontSize);
  },
  setWikiTargets({ targets }) {
    setWikiTargets(targets);
  },
  setTagTargets({ targets }) {
    setTagTargets(targets);
  },
  setFindQuery({ query, replacement, caseSensitive, wholeWord, regex }) {
    if (!editor) return;
    if (!query) {
      resetFind(editor.view);
      // Emit empty status so the host clears match counts.
      try {
        window.webkit?.messageHandlers?.wysiwyg?.postMessage({
          type: "findStatus",
          matchCount: 0,
          currentIndex: 0,
          regexError: null,
        });
      } catch {
        // ignore
      }
      return;
    }
    findSetQuery(editor.view, query, replacement ?? "", {
      caseSensitive: !!caseSensitive,
      useRegex: !!regex,
      wholeWord: !!wholeWord,
    });
  },
  applyCommand({ command }) {
    if (!editor) return;
    // Find / replace commands don't go through chain — they manipulate the
    // find plugin state directly.
    switch (command) {
      case "findNext":
        findNavigate(editor.view, "next");
        return;
      case "findPrevious":
        findNavigate(editor.view, "previous");
        return;
      case "replaceCurrent": {
        const count = findReplaceCurrent(editor.view);
        try {
          window.webkit?.messageHandlers?.wysiwyg?.postMessage({
            type: "replaceStatus",
            replaceCount: count,
          });
        } catch {
          // ignore
        }
        return;
      }
      case "replaceAll": {
        const count = findReplaceAll(editor.view);
        try {
          window.webkit?.messageHandlers?.wysiwyg?.postMessage({
            type: "replaceStatus",
            replaceCount: count,
          });
        } catch {
          // ignore
        }
        return;
      }
    }
    const chain = editor.chain().focus();
    switch (command) {
      case "bold":
        chain.toggleBold().run();
        break;
      case "italic":
        chain.toggleItalic().run();
        break;
      case "strikethrough":
      case "strike":
        chain.toggleStrike().run();
        break;
      case "inlineCode":
      case "code":
        chain.toggleCode().run();
        break;
      case "heading": {
        // Cycle: paragraph → H1 → H2 → H3 → paragraph.
        const isH1 = editor.isActive("heading", { level: 1 });
        const isH2 = editor.isActive("heading", { level: 2 });
        const isH3 = editor.isActive("heading", { level: 3 });
        if (isH3) {
          chain.setParagraph().run();
        } else if (isH2) {
          chain.setHeading({ level: 3 }).run();
        } else if (isH1) {
          chain.setHeading({ level: 2 }).run();
        } else {
          chain.setHeading({ level: 1 }).run();
        }
        break;
      }
      case "blockquote":
        chain.toggleBlockquote().run();
        break;
      case "bulletList":
        chain.toggleBulletList().run();
        break;
      case "numberedList":
      case "orderedList":
        chain.toggleOrderedList().run();
        break;
      case "todoList":
        chain.toggleTaskList().run();
        break;
      case "horizontalRule":
        chain.setHorizontalRule().run();
        break;
      case "pageBreak":
        chain.insertContent("\n\n---\n\n").run();
        break;
      case "codeBlock":
        chain.toggleCodeBlock().run();
        break;
      case "table":
        chain
          .insertContent({
            type: "table",
            content: [
              { type: "tableRow", content: [
                { type: "tableHeader", content: [{ type: "paragraph", content: [{ type: "text", text: "" }] }] },
                { type: "tableHeader", content: [{ type: "paragraph", content: [{ type: "text", text: "" }] }] },
              ]},
              { type: "tableRow", content: [
                { type: "tableCell", content: [{ type: "paragraph" }] },
                { type: "tableCell", content: [{ type: "paragraph" }] },
              ]},
            ],
          })
          .run();
        break;
      case "link": {
        const view = editor.view;
        const sel = view.state.selection;
        const selectedText = view.state.doc.textBetween(sel.from, sel.to, " ");
        const label = selectedText || "link text";
        const insert = `[${label}](url)`;
        const urlStart = sel.from + `[${label}](`.length;
        chain
          .insertContent(insert)
          .setTextSelection({ from: urlStart, to: urlStart + "url".length })
          .run();
        break;
      }
      case "image": {
        const view = editor.view;
        const sel = view.state.selection;
        const selectedText = view.state.doc.textBetween(sel.from, sel.to, " ");
        const label = selectedText || "alt text";
        const insert = `![${label}](url)`;
        const urlStart = sel.from + `![${label}](`.length;
        chain
          .insertContent(insert)
          .setTextSelection({ from: urlStart, to: urlStart + "url".length })
          .run();
        break;
      }
      case "inlineMath":
        chain.insertContent({ type: "inlineMath", attrs: { formula: "" } }).run();
        break;
      case "mathBlock":
        chain.insertContent({ type: "blockMath", attrs: { formula: "" } }).run();
        break;
      default:
        break;
    }
  },
  scrollToLine() {
    // Markdown line numbers don't map cleanly to PM positions after the
    // body has been parsed (frontmatter strip, atom nodes, source-range
    // preservation). Use scrollToHeading instead for outline navigation.
  },
  scrollToOffset() {
    // See scrollToLine — markdown byte offsets don't have a stable mapping
    // to PM positions in this editor. Use scrollToHeading.
  },
  scrollToHeading({ ordinal }) {
    if (!editor) return;
    // OutlineState only tracks top-level headings (its regex won't match
    // `> ##` inside blockquotes / callouts), so we count top-level children
    // here — using descendants() would over-count.
    let seen = 0;
    let targetPos: number | null = null;
    let runningPos = 0;
    editor.state.doc.forEach((node) => {
      if (targetPos != null) {
        runningPos += node.nodeSize;
        return;
      }
      if (node.type.name === "heading") {
        if (seen === ordinal) {
          targetPos = runningPos;
        }
        seen++;
      }
      runningPos += node.nodeSize;
    });
    if (targetPos == null) return;
    // After moving overflow to body, PM's chain.scrollIntoView (which
    // assumes the editor's content DOM is the scroller) doesn't reliably
    // scroll. Compute the target position's screen rect ourselves and
    // scroll the body window.
    try {
      editor.commands.setTextSelection(targetPos + 1);
      const coords = editor.view.coordsAtPos(targetPos + 1);
      const top = coords.top + window.scrollY - 80;
      window.scrollTo({ top: Math.max(0, top), behavior: "smooth" });
    } catch {
      editor.chain().focus("start").setTextSelection(targetPos + 1).scrollIntoView().run();
    }
  },
  insertText({ text }) {
    editor?.chain().focus().insertContent(text).run();
  },
  focus() {
    // Explicit "start" prevents Tiptap from auto-selecting the whole doc
    // when nothing has placed the cursor yet (e.g. after mount).
    editor?.commands.focus("start", { scrollIntoView: false });
  },
  getDocument() {
    return editor ? fullMarkdown(editor) : "";
  },
};

postToHost({ type: "ready" });
