// `[TOC]` placeholder — block atom node that renders a live, clickable
// table of contents built from the document's headings. Click a TOC entry
// to smooth-scroll to that heading. Re-renders on every doc-changing
// transaction so the outline tracks edits.
//
// Behaves like a paragraph in markdown round-trip: tokenizes `[TOC]` on its
// own block, emits `[TOC]` back when serializing.

import { Node } from "@tiptap/core";

const TOC_RE = /^\[TOC\][ \t]*(?:\n|$)/;

interface HeadingEntry {
  level: number;
  text: string;
  pos: number;
}

function escapeHTML(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function buildList(headings: HeadingEntry[]): string {
  if (headings.length === 0) {
    return '<em class="toc-empty">No headings yet</em>';
  }
  const minLevel = headings.reduce((m, h) => Math.min(m, h.level), 6);
  let html = "<ul>";
  let prev = minLevel;
  headings.forEach((h, i) => {
    const level = h.level;
    if (level > prev) {
      for (let k = 0; k < level - prev; k++) html += "<ul>";
    } else if (level < prev) {
      for (let k = 0; k < prev - level; k++) html += "</li></ul>";
      html += "</li>";
    } else if (i > 0) {
      html += "</li>";
    }
    html += `<li><a href="#" data-toc-pos="${h.pos}">${escapeHTML(h.text)}</a>`;
    prev = level;
  });
  for (let k = 0; k < prev - minLevel; k++) html += "</li></ul>";
  html += "</li></ul>";
  return html;
}

export const TOC = Node.create({
  name: "toc",
  group: "block",
  atom: true,
  selectable: true,

  parseHTML() {
    return [{ tag: "nav[data-toc]" }, { tag: "span[data-toc]" }];
  },

  renderHTML() {
    return ["nav", { "data-toc": "", class: "toc" }, "[TOC]"];
  },

  addNodeView() {
    return ({ editor }) => {
      const dom = document.createElement("nav");
      dom.className = "toc";
      dom.setAttribute("data-toc", "");
      dom.contentEditable = "false";

      let lastSig = "";

      const collect = (): HeadingEntry[] => {
        const out: HeadingEntry[] = [];
        editor.state.doc.descendants((node, pos) => {
          if (node.type.name === "heading") {
            out.push({
              level: (node.attrs.level as number) || 1,
              text: node.textContent,
              pos,
            });
          }
        });
        return out;
      };

      const render = () => {
        const headings = collect();
        const sig = headings.map((h) => `${h.level}|${h.text}|${h.pos}`).join("\n");
        if (sig === lastSig) return;
        lastSig = sig;
        dom.innerHTML = buildList(headings);
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
        destroy() {
          editor.off("transaction", onTransaction);
        },
      };
    };
  },

  markdownTokenName: "toc",

  markdownTokenizer: {
    name: "toc",
    level: "block" as const,
    start(src: string) {
      // Only signal at a line-start `[TOC]`. Returning mid-paragraph
      // positions makes marked split paragraphs around the candidate
      // index, causing spurious tokenization of the surrounding text.
      const m = /(?:^|\n)\[TOC\]/.exec(src);
      return m ? m.index + (src[m.index] === "\n" ? 1 : 0) : -1;
    },
    tokenize(src: string) {
      const m = TOC_RE.exec(src);
      if (!m) return undefined;
      return { type: "toc", raw: m[0] };
    },
  },

  parseMarkdown(_token: any, h: any) {
    return h.createNode("toc", {}, []);
  },

  renderMarkdown() {
    return "[TOC]\n";
  },
});
