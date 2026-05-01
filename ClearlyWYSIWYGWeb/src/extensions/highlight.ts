// Highlight `==text==` — markdown-it-mark behavior, ported to marked.
// Inline mark.

import { Mark } from "@tiptap/core";

const HIGHLIGHT_RE = /^==([^\n=][^\n]*?)==/;

export const Highlight = Mark.create({
  name: "highlight",

  parseHTML() {
    return [{ tag: "mark" }];
  },

  renderHTML() {
    return ["mark", 0];
  },

  markdownTokenName: "highlight",

  markdownTokenizer: {
    name: "highlight",
    level: "inline" as const,
    start(src: string) {
      const i = src.indexOf("==");
      return i < 0 ? -1 : i;
    },
    tokenize(src: string, _tokens: any, helper: any) {
      const m = HIGHLIGHT_RE.exec(src);
      if (!m) return undefined;
      return {
        type: "highlight",
        raw: m[0],
        text: m[1],
        tokens: helper?.inlineTokens
          ? helper.inlineTokens(m[1])
          : [{ type: "text", raw: m[1], text: m[1] }],
      };
    },
  },

  parseMarkdown(token: any, h: any) {
    const inner = h.parseInline ? h.parseInline(token.tokens ?? []) : [{ type: "text", text: token.text }];
    return h.applyMark("highlight", inner);
  },

  renderMarkdown(node: any, h: any) {
    return `==${h.renderChildren(node.content ?? [])}==`;
  },
});
