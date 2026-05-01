// Wiki links: `[[target]]`, `[[target|alias]]`, `[[target#heading]]`,
// `[[target#heading|alias]]`. Inline atom node — the contents aren't editable
// as text; clicking opens a popover (Phase 4 polish). For Phase 1 the goal is
// just byte-perfect round-trip preservation.

import { Node } from "@tiptap/core";

// Greedy bracket matcher with a guard against starting `[[` inside a code span
// — that's the markdown-it-wikilinks contract; we'll inherit @tiptap/markdown's
// code-region protection (it doesn't run inline tokenizers inside code marks).
const WIKI_LINK_RE = /^\[\[([^\[\]|#\n]+)(?:#([^\[\]|\n]+))?(?:\|([^\[\]\n]+))?]]/;

export const WikiLink = Node.create({
  name: "wikiLink",
  group: "inline",
  inline: true,
  atom: true,
  selectable: true,
  draggable: false,

  addAttributes() {
    return {
      target: { default: "" },
      heading: { default: null },
      alias: { default: null },
    };
  },

  parseHTML() {
    return [{ tag: "span[data-wikilink]" }];
  },

  renderHTML({ node }) {
    const { target, heading, alias } = node.attrs as {
      target: string;
      heading: string | null;
      alias: string | null;
    };
    const display = alias ?? (heading ? `${target} › ${heading}` : target);
    return [
      "span",
      {
        "data-wikilink": "",
        "data-target": target ?? "",
        ...(heading ? { "data-heading": heading } : {}),
        ...(alias ? { "data-alias": alias } : {}),
        class: "wikilink",
      },
      display,
    ];
  },

  markdownTokenName: "wikiLink",

  markdownTokenizer: {
    name: "wikiLink",
    level: "inline" as const,
    start(src: string) {
      const i = src.indexOf("[[");
      return i < 0 ? -1 : i;
    },
    tokenize(src: string) {
      const m = WIKI_LINK_RE.exec(src);
      if (!m) return undefined;
      return {
        type: "wikiLink",
        raw: m[0],
        target: m[1],
        heading: m[2] ?? null,
        alias: m[3] ?? null,
      };
    },
  },

  parseMarkdown(token: any, h: any) {
    return h.createNode(
      "wikiLink",
      {
        target: token.target,
        heading: token.heading ?? null,
        alias: token.alias ?? null,
      },
      []
    );
  },

  renderMarkdown(node: any) {
    const { target, heading, alias } = node.attrs;
    let out = `[[${target}`;
    if (heading) out += `#${heading}`;
    if (alias) out += `|${alias}`;
    out += `]]`;
    return out;
  },
});
