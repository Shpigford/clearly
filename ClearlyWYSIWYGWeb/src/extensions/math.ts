// Math: inline `$x^2$` and block `$$\n...\n$$`. Both are atom nodes — the
// formula is opaque to the editor; click to open a popover for editing
// (Phase 4 polish). NodeViews render via KaTeX when window.katex is loaded
// (the WKWebView's index.html includes ../katex.min.js); else fall back to
// a styled monospace placeholder so the perf harness / tests still work.
//
// Disambiguation rules for inline:
// - Single `$` doesn't open math when followed by whitespace (avoids `$ X`).
// - The expression can't span newlines.
// - `$price` and `cost: $5.00` don't open math because the closing `$` would
//   need a non-whitespace character right before it.

import { Node } from "@tiptap/core";

interface KatexLike {
  render(formula: string, target: HTMLElement, options?: Record<string, unknown>): void;
}

function katex(): KatexLike | null {
  const w = window as unknown as { katex?: KatexLike };
  return w.katex && typeof w.katex.render === "function" ? w.katex : null;
}

function renderMath(target: HTMLElement, formula: string, displayMode: boolean): void {
  const k = katex();
  target.textContent = "";
  if (k) {
    try {
      k.render(formula, target, { throwOnError: false, displayMode });
      return;
    } catch {
      // Fall through to plain-text fallback.
    }
  }
  target.textContent = displayMode ? `$$${formula}$$` : `$${formula}$`;
}

const INLINE_MATH_RE = /^\$([^$\n][^$\n]*?[^\s$])\$(?!\d)|^\$([^$\s\n])\$(?!\d)/;
const BLOCK_MATH_RE = /^\$\$\s*\n([\s\S]*?)\n\$\$(?:\n|$)/;

export const InlineMath = Node.create({
  name: "inlineMath",
  group: "inline",
  inline: true,
  atom: true,
  selectable: true,

  addAttributes() {
    return {
      formula: { default: "" },
    };
  },

  parseHTML() {
    return [{ tag: "span[data-inline-math]" }];
  },

  renderHTML({ node }) {
    const formula = (node.attrs.formula ?? "") as string;
    return [
      "span",
      { "data-inline-math": "", "data-formula": formula, class: "math math-inline" },
      `$${formula}$`,
    ];
  },

  addNodeView() {
    return ({ node, getPos, editor }) => {
      const dom = document.createElement("span");
      dom.className = "math math-inline";
      dom.setAttribute("data-inline-math", "");
      let editing = false;
      let currentFormula = (node.attrs.formula ?? "") as string;
      dom.setAttribute("data-formula", currentFormula);

      const showRendered = () => {
        editing = false;
        dom.classList.remove("is-editing");
        renderMath(dom, currentFormula, false);
      };

      const showEditor = () => {
        editing = true;
        dom.classList.add("is-editing");
        dom.textContent = "";
        const input = document.createElement("input");
        input.type = "text";
        input.className = "math-edit-input";
        input.value = currentFormula;
        input.size = Math.max(8, currentFormula.length + 2);
        const commit = () => {
          const pos = typeof getPos === "function" ? getPos() : null;
          if (pos == null) return;
          const newValue = input.value;
          if (newValue === currentFormula) {
            showRendered();
            return;
          }
          const tr = editor.view.state.tr.setNodeAttribute(pos, "formula", newValue);
          editor.view.dispatch(tr);
        };
        input.addEventListener("blur", () => commit());
        input.addEventListener("keydown", (e) => {
          if (e.key === "Enter") {
            e.preventDefault();
            commit();
          } else if (e.key === "Escape") {
            e.preventDefault();
            showRendered();
          }
        });
        dom.appendChild(input);
        input.focus();
        input.select();
      };

      dom.addEventListener("click", (event) => {
        if (editing) return;
        event.preventDefault();
        event.stopPropagation();
        showEditor();
      });

      showRendered();

      return {
        dom,
        update(updated) {
          if (updated.type.name !== "inlineMath") return false;
          const f = (updated.attrs.formula ?? "") as string;
          if (f !== currentFormula) {
            currentFormula = f;
            dom.setAttribute("data-formula", f);
          }
          if (!editing) showRendered();
          return true;
        },
        stopEvent: () => editing,
      };
    };
  },

  markdownTokenName: "inlineMath",

  markdownTokenizer: {
    name: "inlineMath",
    level: "inline" as const,
    start(src: string) {
      const i = src.indexOf("$");
      return i < 0 ? -1 : i;
    },
    tokenize(src: string) {
      const m = INLINE_MATH_RE.exec(src);
      if (!m) return undefined;
      const formula = m[1] ?? m[2];
      return {
        type: "inlineMath",
        raw: m[0],
        formula,
      };
    },
  },

  parseMarkdown(token: any, h: any) {
    return h.createNode("inlineMath", { formula: token.formula }, []);
  },

  renderMarkdown(node: any) {
    return `$${node.attrs.formula}$`;
  },
});

export const BlockMath = Node.create({
  name: "blockMath",
  group: "block",
  atom: true,
  selectable: true,
  defining: true,

  addAttributes() {
    return {
      formula: { default: "" },
    };
  },

  parseHTML() {
    return [{ tag: "div[data-block-math]" }];
  },

  renderHTML({ node }) {
    const formula = (node.attrs.formula ?? "") as string;
    return [
      "div",
      { "data-block-math": "", class: "math math-block" },
      `$$\n${formula}\n$$`,
    ];
  },

  addNodeView() {
    return ({ node, getPos, editor }) => {
      const dom = document.createElement("div");
      dom.className = "math math-block";
      dom.setAttribute("data-block-math", "");
      let editing = false;
      let currentFormula = (node.attrs.formula ?? "") as string;

      const showRendered = () => {
        editing = false;
        dom.classList.remove("is-editing");
        renderMath(dom, currentFormula, true);
      };

      const showEditor = () => {
        editing = true;
        dom.classList.add("is-editing");
        dom.textContent = "";
        const ta = document.createElement("textarea");
        ta.className = "math-edit-textarea";
        ta.value = currentFormula;
        ta.rows = Math.max(2, currentFormula.split("\n").length + 1);
        const commit = () => {
          const pos = typeof getPos === "function" ? getPos() : null;
          if (pos == null) return;
          const newValue = ta.value;
          if (newValue === currentFormula) {
            showRendered();
            return;
          }
          const tr = editor.view.state.tr.setNodeAttribute(pos, "formula", newValue);
          editor.view.dispatch(tr);
        };
        ta.addEventListener("blur", () => commit());
        ta.addEventListener("keydown", (e) => {
          if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
            e.preventDefault();
            commit();
          } else if (e.key === "Escape") {
            e.preventDefault();
            showRendered();
          }
        });
        dom.appendChild(ta);
        ta.focus();
      };

      dom.addEventListener("click", (event) => {
        if (editing) return;
        event.preventDefault();
        event.stopPropagation();
        showEditor();
      });

      showRendered();

      return {
        dom,
        update(updated) {
          if (updated.type.name !== "blockMath") return false;
          const f = (updated.attrs.formula ?? "") as string;
          if (f !== currentFormula) {
            currentFormula = f;
          }
          if (!editing) showRendered();
          return true;
        },
        stopEvent: () => editing,
      };
    };
  },

  markdownTokenName: "blockMath",

  markdownTokenizer: {
    name: "blockMath",
    level: "block" as const,
    start(src: string) {
      const i = src.indexOf("$$");
      return i < 0 ? -1 : i;
    },
    tokenize(src: string) {
      const m = BLOCK_MATH_RE.exec(src);
      if (!m) return undefined;
      return {
        type: "blockMath",
        raw: m[0],
        formula: m[1],
      };
    },
  },

  parseMarkdown(token: any, h: any) {
    return h.createNode("blockMath", { formula: token.formula }, []);
  },

  renderMarkdown(node: any) {
    return `$$\n${node.attrs.formula}\n$$\n`;
  },
});
