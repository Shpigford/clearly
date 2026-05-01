// Mermaid diagrams: ```mermaid fenced blocks. Custom block node with the
// raw diagram source on a `code` attr.
//
// NodeView calls mermaid.render() to produce SVG when window.mermaid is
// available (the WKWebView's index.html loads ../mermaid.min.js, which is
// the same bundle the existing Preview uses). When mermaid isn't loaded
// (perf harness, jsdom tests), falls back to a monospace pre block so
// content is still inspectable.
//
// The tokenizer claims mermaid fences exclusively at higher priority than
// StarterKit's fenced-code matcher, so the rest of the code-block pipeline
// never sees them.

import { Node } from "@tiptap/core";

interface MermaidLike {
  initialize?(opts: Record<string, unknown>): void;
  render(id: string, code: string): Promise<{ svg: string }>;
}

function mermaidLib(): MermaidLike | null {
  const w = window as unknown as { mermaid?: MermaidLike };
  return w.mermaid && typeof w.mermaid.render === "function" ? w.mermaid : null;
}

let mermaidInitialized = false;
let mermaidRenderCounter = 0;

function ensureMermaidInitialized(lib: MermaidLike): void {
  if (mermaidInitialized) return;
  mermaidInitialized = true;
  try {
    lib.initialize?.({
      startOnLoad: false,
      securityLevel: "loose",
      theme: document.documentElement.dataset.appearance === "dark" ? "dark" : "default",
    });
  } catch {
    // Initialization is best-effort; render() can still succeed.
  }
}

async function renderMermaid(target: HTMLElement, code: string): Promise<void> {
  const lib = mermaidLib();
  if (!lib) {
    target.innerHTML = "";
    const pre = document.createElement("pre");
    pre.textContent = code;
    target.appendChild(pre);
    return;
  }
  ensureMermaidInitialized(lib);
  const id = `mermaid-${++mermaidRenderCounter}`;
  try {
    const { svg } = await lib.render(id, code);
    target.innerHTML = svg;
  } catch (err) {
    target.innerHTML = "";
    const pre = document.createElement("pre");
    pre.className = "mermaid-error";
    pre.textContent = `Mermaid render error:\n${(err as Error)?.message ?? "unknown"}\n\n${code}`;
    target.appendChild(pre);
  }
}

const MERMAID_FENCE_RE = /^```mermaid[ \t]*\n([\s\S]*?)\n```[ \t]*(?:\n|$)/;

export const Mermaid = Node.create({
  name: "mermaid",
  group: "block",
  atom: true,
  selectable: true,
  defining: true,

  addAttributes() {
    return {
      code: { default: "" },
    };
  },

  parseHTML() {
    return [{ tag: "div[data-mermaid]" }];
  },

  renderHTML({ node }) {
    const code = (node.attrs.code ?? "") as string;
    return [
      "div",
      { "data-mermaid": "", class: "mermaid-block" },
      ["pre", {}, code],
    ];
  },

  addNodeView() {
    return ({ node, getPos, editor }) => {
      const dom = document.createElement("div");
      dom.className = "mermaid-block";
      dom.setAttribute("data-mermaid", "");
      let editing = false;
      let currentCode = (node.attrs.code ?? "") as string;

      const showRendered = () => {
        editing = false;
        dom.classList.remove("is-editing");
        void renderMermaid(dom, currentCode);
      };

      const showEditor = () => {
        editing = true;
        dom.classList.add("is-editing");
        dom.textContent = "";
        const ta = document.createElement("textarea");
        ta.className = "mermaid-edit-textarea";
        ta.value = currentCode;
        ta.rows = Math.max(4, currentCode.split("\n").length + 1);
        const commit = () => {
          const pos = typeof getPos === "function" ? getPos() : null;
          if (pos == null) return;
          const newValue = ta.value;
          if (newValue === currentCode) {
            showRendered();
            return;
          }
          const tr = editor.view.state.tr.setNodeAttribute(pos, "code", newValue);
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
          if (updated.type.name !== "mermaid") return false;
          const code = (updated.attrs.code ?? "") as string;
          if (code !== currentCode) {
            currentCode = code;
          }
          if (!editing) showRendered();
          return true;
        },
        stopEvent: () => editing,
      };
    };
  },

  markdownTokenName: "mermaid",

  markdownTokenizer: {
    name: "mermaid",
    level: "block" as const,
    start(src: string) {
      const i = src.indexOf("```mermaid");
      return i < 0 ? -1 : i;
    },
    tokenize(src: string) {
      const m = MERMAID_FENCE_RE.exec(src);
      if (!m) return undefined;
      return {
        type: "mermaid",
        raw: m[0],
        code: m[1],
      };
    },
  },

  parseMarkdown(token: any, h: any) {
    return h.createNode("mermaid", { code: token.code }, []);
  },

  renderMarkdown(node: any) {
    const code = (node.attrs.code ?? "") as string;
    return "```mermaid\n" + code + "\n```\n";
  },
});
