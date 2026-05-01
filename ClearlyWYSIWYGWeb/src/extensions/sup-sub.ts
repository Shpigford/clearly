// Superscript `^x^` and subscript `~x~`. Inline marks.
//
// Subscript matters most: marked's GFM strikethrough tokenizer accepts single
// `~` and emits a strikethrough token, which @tiptap/markdown then rerenders
// as `~~text~~` — a destructive normalization (`H~2~O` → `H~~2~~O`). The Sub
// tokenizer here is registered with higher priority and matches single `~text~`,
// preempting strikethrough. True GFM `~~text~~` is unaffected.

import { Mark } from "@tiptap/core";

// Greedy-but-bounded; subscript text shouldn't span newlines or contain
// caret/tilde literals.
const SUP_RE = /^\^([^\^\n\s][^\^\n]*?)\^/;
const SUB_RE = /^~([^~\n\s][^~\n]*?)~/;

export const Superscript = Mark.create({
  name: "superscript",

  parseHTML() {
    return [{ tag: "sup" }];
  },

  renderHTML() {
    return ["sup", 0];
  },

  markdownTokenName: "superscript",

  markdownTokenizer: {
    name: "superscript",
    level: "inline" as const,
    start(src: string) {
      const i = src.indexOf("^");
      return i < 0 ? -1 : i;
    },
    tokenize(src: string, _tokens: any, helper: any) {
      const m = SUP_RE.exec(src);
      if (!m) return undefined;
      return {
        type: "superscript",
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
    return h.applyMark("superscript", inner);
  },

  renderMarkdown(node: any, h: any) {
    return `^${h.renderChildren(node.content ?? [])}^`;
  },
});

export const Subscript = Mark.create({
  name: "subscript",

  parseHTML() {
    return [{ tag: "sub" }];
  },

  renderHTML() {
    return ["sub", 0];
  },

  markdownTokenName: "subscript",

  markdownTokenizer: {
    name: "subscript",
    level: "inline" as const,
    start(src: string) {
      // Don't trigger on a `~~` (true GFM strike) — let the strikethrough
      // tokenizer handle that case.
      let i = src.indexOf("~");
      while (i >= 0 && src[i + 1] === "~") {
        i = src.indexOf("~", i + 2);
      }
      return i < 0 ? -1 : i;
    },
    tokenize(src: string, _tokens: any, helper: any) {
      // Reject double-tilde — let strikethrough win.
      if (src.startsWith("~~")) return undefined;
      const m = SUB_RE.exec(src);
      if (!m) return undefined;
      return {
        type: "subscript",
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
    return h.applyMark("subscript", inner);
  },

  renderMarkdown(node: any, h: any) {
    return `~${h.renderChildren(node.content ?? [])}~`;
  },
});
