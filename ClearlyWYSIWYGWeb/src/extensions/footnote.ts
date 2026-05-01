// Footnotes — markdown-it-footnote shape, ported to marked. Two pieces:
//
//   FootnoteRef: inline `[^id]` (atom inline node).
//   FootnoteDef: block `[^id]: body` (atom block node with the raw body
//                bytes preserved on a `body` attr).
//
// NodeViews compute an id→ordinal map by walking the document for refs in
// order, mirroring how the preview renders footnotes (first ref of `[^id]`
// gets the next ordinal; subsequent refs reuse it). Refs show the ordinal
// as a superscript chip with a hover popover; defs render the body
// markdown inline next to the ordinal.
//
// The body of a footnote def can span multiple lines if continuation lines
// are indented by 4 spaces (CommonMark indent for "lazy continuation"). For
// Phase 1 simplicity we capture only single-line defs — the demo corpus
// doesn't use multi-line defs and source preservation handles unrecognized
// shapes gracefully via the global fallback.

import { Node } from "@tiptap/core";
import { marked } from "marked";

const FOOTNOTE_REF_RE = /^\[\^([^\]\n]+)]/;
const FOOTNOTE_DEF_RE = /^\[\^([^\]\n]+)]:[ \t]*([^\n]*)(\r?\n|$)/;

interface FootnoteMaps {
  ordinals: Map<string, number>;
  bodies: Map<string, string>;
}

function buildFootnoteMaps(doc: any): FootnoteMaps {
  const ordinals = new Map<string, number>();
  const bodies = new Map<string, string>();
  let next = 1;
  doc.descendants((node: any) => {
    if (node.type.name === "footnoteRef") {
      const id = node.attrs.id as string;
      if (id && !ordinals.has(id)) {
        ordinals.set(id, next++);
      }
    }
    if (node.type.name === "footnoteDef") {
      const id = node.attrs.id as string;
      if (id) {
        bodies.set(id, node.attrs.body as string);
        if (!ordinals.has(id)) {
          ordinals.set(id, next++);
        }
      }
    }
  });
  return { ordinals, bodies };
}

function renderInlineMarkdown(text: string): string {
  try {
    return marked.parseInline(text, { async: false }) as string;
  } catch {
    return text.replace(/[<>&]/g, (c) =>
      c === "<" ? "&lt;" : c === ">" ? "&gt;" : "&amp;"
    );
  }
}

export const FootnoteRef = Node.create({
  name: "footnoteRef",
  group: "inline",
  inline: true,
  atom: true,
  selectable: true,

  addAttributes() {
    return {
      id: { default: "" },
    };
  },

  parseHTML() {
    return [{ tag: "sup[data-footnote-ref]" }];
  },

  renderHTML({ node }) {
    const id = (node.attrs.id ?? "") as string;
    return [
      "sup",
      { "data-footnote-ref": "", "data-id": id, class: "footnote-ref" },
      `[^${id}]`,
    ];
  },

  addNodeView() {
    return ({ node, editor }) => {
      const id = (node.attrs.id ?? "") as string;
      const dom = document.createElement("sup");
      dom.setAttribute("data-footnote-ref", "");
      dom.setAttribute("data-id", id);
      dom.className = "footnote-ref";
      dom.contentEditable = "false";

      const link = document.createElement("a");
      link.href = `#fn-${encodeURIComponent(id)}`;
      dom.appendChild(link);

      const render = () => {
        const { ordinals } = buildFootnoteMaps(editor.state.doc);
        const ordinal = ordinals.get(id);
        link.textContent = ordinal != null ? String(ordinal) : id;
      };
      render();

      const onTransaction = ({ transaction }: { transaction: { docChanged: boolean } }) => {
        if (transaction.docChanged) render();
      };
      editor.on("transaction", onTransaction);

      let popover: HTMLDivElement | null = null;
      dom.addEventListener("mouseenter", () => {
        const { bodies } = buildFootnoteMaps(editor.state.doc);
        const body = bodies.get(id);
        if (!body) return;
        popover = document.createElement("div");
        popover.className = "footnote-popover";
        popover.innerHTML = renderInlineMarkdown(body);
        document.body.appendChild(popover);
        const rect = dom.getBoundingClientRect();
        popover.style.top = `${rect.bottom + window.scrollY + 6}px`;
        popover.style.left = `${Math.max(8, Math.min(rect.left, window.innerWidth - 420))}px`;
      });
      dom.addEventListener("mouseleave", () => {
        popover?.remove();
        popover = null;
      });
      link.addEventListener("click", (e) => {
        e.preventDefault();
        const target = document.getElementById(`fn-${id}`);
        if (target) {
          target.scrollIntoView({ behavior: "smooth", block: "center" });
        }
      });

      return {
        dom,
        ignoreMutation: () => true,
        stopEvent: () => false,
        destroy() {
          editor.off("transaction", onTransaction);
          popover?.remove();
        },
      };
    };
  },

  markdownTokenName: "footnoteRef",

  markdownTokenizer: {
    name: "footnoteRef",
    level: "inline" as const,
    start(src: string) {
      const i = src.indexOf("[^");
      return i < 0 ? -1 : i;
    },
    tokenize(src: string) {
      // Skip if this is actually a definition (starts at line start with ":").
      // The block tokenizer below will catch defs first when we're at a line
      // boundary; this guards against the ref tokenizer incorrectly claiming
      // an inline-position def fragment.
      const m = FOOTNOTE_REF_RE.exec(src);
      if (!m) return undefined;
      const after = src.slice(m[0].length);
      if (after.startsWith(":")) return undefined;
      return {
        type: "footnoteRef",
        raw: m[0],
        id: m[1],
      };
    },
  },

  parseMarkdown(token: any, h: any) {
    return h.createNode("footnoteRef", { id: token.id }, []);
  },

  renderMarkdown(node: any) {
    return `[^${node.attrs.id}]`;
  },
});

export const FootnoteDef = Node.create({
  name: "footnoteDef",
  group: "block",
  atom: true,
  selectable: true,
  defining: true,

  addAttributes() {
    return {
      id: { default: "" },
      body: { default: "" },
    };
  },

  parseHTML() {
    return [{ tag: "div[data-footnote-def]" }];
  },

  renderHTML({ node }) {
    const id = (node.attrs.id ?? "") as string;
    const body = (node.attrs.body ?? "") as string;
    return [
      "div",
      { "data-footnote-def": "", "data-id": id, class: "footnote-def" },
      [
        "span",
        { class: "footnote-def-marker" },
        `[^${id}]:`,
      ],
      ` ${body}`,
    ];
  },

  addNodeView() {
    return ({ node, editor }) => {
      const id = (node.attrs.id ?? "") as string;
      const dom = document.createElement("div");
      dom.setAttribute("data-footnote-def", "");
      dom.setAttribute("data-id", id);
      dom.className = "footnote-def";
      dom.id = `fn-${id}`;
      dom.contentEditable = "false";

      const marker = document.createElement("sup");
      marker.className = "footnote-def-marker";
      dom.appendChild(marker);

      const bodyEl = document.createElement("span");
      bodyEl.className = "footnote-def-body";
      dom.appendChild(bodyEl);

      const render = () => {
        const { ordinals } = buildFootnoteMaps(editor.state.doc);
        const ordinal = ordinals.get(id);
        marker.textContent = ordinal != null ? String(ordinal) : id;
        bodyEl.innerHTML = renderInlineMarkdown((node.attrs.body ?? "") as string);
      };
      render();

      const onTransaction = ({ transaction }: { transaction: { docChanged: boolean } }) => {
        if (transaction.docChanged) render();
      };
      editor.on("transaction", onTransaction);

      return {
        dom,
        ignoreMutation: () => true,
        stopEvent: () => false,
        update(updated) {
          if (updated.type.name !== "footnoteDef") return false;
          (node as any) = updated;
          render();
          return true;
        },
        destroy() {
          editor.off("transaction", onTransaction);
        },
      };
    };
  },

  markdownTokenName: "footnoteDef",

  markdownTokenizer: {
    name: "footnoteDef",
    level: "block" as const,
    start(src: string) {
      // Only return positions where `[^` sits at a block boundary (start of
      // doc or right after a newline). Otherwise marked treats the index as
      // a place to split the surrounding paragraph.
      let i = 0;
      while (i < src.length) {
        const next = src.indexOf("[^", i);
        if (next < 0) return -1;
        if (next === 0 || src[next - 1] === "\n") return next;
        i = next + 1;
      }
      return -1;
    },
    tokenize(src: string) {
      const m = FOOTNOTE_DEF_RE.exec(src);
      if (!m) return undefined;
      return {
        type: "footnoteDef",
        raw: m[0],
        id: m[1],
        body: m[2],
      };
    },
  },

  parseMarkdown(token: any, h: any) {
    return h.createNode(
      "footnoteDef",
      { id: token.id, body: token.body },
      []
    );
  },

  renderMarkdown(node: any) {
    return `[^${node.attrs.id}]: ${node.attrs.body}\n`;
  },
});
