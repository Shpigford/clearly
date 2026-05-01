// Obsidian-style callouts:
//   > [!TIP]              plain
//   > [!NOTE]-            foldable, default closed
//   > [!WARNING]+         foldable, default open
//   > [!INFO] Title       optional inline title
//   > body line 1
//   > body line 2
//
// Parsed as a custom block node with attrs { type, foldable, open, summary }
// and content composed of regular block children. Edits to the body re-render
// through the renderer below; otherwise source preservation emits raw bytes.

import { Node } from "@tiptap/core";

const HEADER_RE = /^\[!([A-Z][A-Z0-9_-]*)\]([\-+])?(?:\s+(.*))?$/i;

type CalloutHeader = {
  type: string;
  foldable: boolean;
  open: boolean;
  summary: string | null;
};

function parseHeader(line: string): CalloutHeader | null {
  const m = HEADER_RE.exec(line.trim());
  if (!m) return null;
  const sigil = m[2];
  return {
    type: m[1].toUpperCase(),
    foldable: sigil === "-" || sigil === "+",
    open: sigil !== "-",
    summary: m[3] ? m[3].trim() : null,
  };
}

function indentLines(text: string): string {
  return text
    .split("\n")
    .map((ln) => (ln.length === 0 ? ">" : `> ${ln}`))
    .join("\n");
}

export const Callout = Node.create({
  name: "callout",
  group: "block",
  content: "block+",
  defining: true,

  addAttributes() {
    return {
      kind: { default: "NOTE" },
      foldable: { default: false },
      open: { default: true },
      summary: { default: null },
    };
  },

  parseHTML() {
    return [{ tag: "div[data-callout]" }];
  },

  renderHTML({ node }) {
    return [
      "div",
      {
        "data-callout": "",
        "data-kind": (node.attrs.kind ?? "NOTE") as string,
        "data-foldable": node.attrs.foldable ? "1" : "0",
        "data-open": node.attrs.open ? "1" : "0",
        class: `callout callout-${(node.attrs.kind ?? "NOTE").toLowerCase()}`,
      },
      0,
    ];
  },

  // Marked emits blockquotes as type 'blockquote'. We register an alternate
  // tokenizer that fires before blockquote when the first line of a `>`
  // block looks like a callout header.
  markdownTokenName: "callout",

  markdownTokenizer: {
    name: "callout",
    level: "block" as const,
    start(src: string) {
      // Only signal at a line-start `>`. Returning mid-line positions
      // (e.g. the `>` inside `<details>` mentioned in inline code) makes
      // marked break the paragraph there and route the tail through its
      // built-in blockquote tokenizer, producing spurious blockquotes.
      const m = /(?:^|\n)>/.exec(src);
      return m ? m.index + (src[m.index] === "\n" ? 1 : 0) : -1;
    },
    tokenize(src: string, _tokens: any, helper: any) {
      // Must be a blockquote: lines that start with `> ` (or `>` at SOL).
      const lines: string[] = [];
      let consumed = 0;
      const srcLines = src.split("\n");
      for (let i = 0; i < srcLines.length; i++) {
        const ln = srcLines[i];
        if (!/^>\s?/.test(ln)) {
          if (i === 0) return undefined;
          break;
        }
        lines.push(ln.replace(/^>\s?/, ""));
        consumed += ln.length + (i < srcLines.length - 1 ? 1 : 0);
      }
      if (lines.length === 0) return undefined;
      const header = parseHeader(lines[0]);
      if (!header) return undefined;
      const bodyText = lines.slice(1).join("\n");
      const trailingNewline = src.length > consumed && src[consumed] === "\n" ? "\n" : "";
      const raw = src.slice(0, consumed) + trailingNewline;
      const innerTokens = helper?.blockTokens ? helper.blockTokens(bodyText + "\n") : [];
      return {
        type: "callout",
        raw,
        kind: header.type,
        foldable: header.foldable,
        open: header.open,
        summary: header.summary,
        tokens: innerTokens,
      };
    },
  },

  parseMarkdown(token: any, h: any) {
    const children = token.tokens && token.tokens.length > 0
      ? h.parseBlockChildren(token.tokens)
      : [{ type: "paragraph" }];
    return h.createNode(
      "callout",
      {
        kind: token.kind,
        foldable: !!token.foldable,
        open: token.open !== false,
        summary: token.summary ?? null,
      },
      children
    );
  },

  renderMarkdown(node: any, h: any) {
    const sigil = node.attrs.foldable ? (node.attrs.open ? "+" : "-") : "";
    const summary = node.attrs.summary ? ` ${node.attrs.summary}` : "";
    const header = `[!${node.attrs.kind}]${sigil}${summary}`;
    const body = h.renderChildren(node.content ?? []);
    const combined = body ? `${header}\n${body}` : header;
    return indentLines(combined.replace(/\n+$/, "")) + "\n";
  },
});
