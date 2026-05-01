// Tags: `#tag`, `#nested/tag`, `#café`, `#日本語`. Inline atom node — the leading
// `#` and the name are visible together; the user deletes the whole tag rather
// than splitting it.
//
// Disambiguation:
// - The character right after `#` must be a letter, digit, or underscore.
// - Continues through letters, digits, `-`, `_`, `/`, and unicode word chars.
// - We do NOT try to suppress URL-fragment matches like `https://x#h` here —
//   marked's inline tokenizers run after link resolution, so the `#h` inside
//   a parsed link doesn't reach our tokenizer.

import { Node } from "@tiptap/core";

const TAG_RE = /^#([\p{L}\p{N}_][\p{L}\p{N}_/\-]*)/u;

export const Tag = Node.create({
  name: "tag",
  group: "inline",
  inline: true,
  atom: true,
  selectable: true,

  addAttributes() {
    return {
      name: { default: "" },
    };
  },

  parseHTML() {
    return [{ tag: "span[data-tag]" }];
  },

  renderHTML({ node }) {
    const name = (node.attrs.name ?? "") as string;
    return [
      "span",
      { "data-tag": "", "data-name": name, class: "tag" },
      `#${name}`,
    ];
  },

  markdownTokenName: "tag",

  markdownTokenizer: {
    name: "tag",
    level: "inline" as const,
    start(src: string) {
      const i = src.indexOf("#");
      return i < 0 ? -1 : i;
    },
    tokenize(src: string) {
      const m = TAG_RE.exec(src);
      if (!m) return undefined;
      return {
        type: "tag",
        raw: m[0],
        name: m[1],
      };
    },
  },

  parseMarkdown(token: any, h: any) {
    return h.createNode("tag", { name: token.name }, []);
  },

  renderMarkdown(node: any) {
    return `#${node.attrs.name}`;
  },
});
