// HTML block node. Captures raw HTML tokens marked emits at block level
// (HTML comments, raw <div>, etc.) so they round-trip byte-perfect rather
// than getting reinterpreted as paragraphs whose content is lost on edit.
//
// Treated as an atom — the contents aren't editable as text in WYSIWYG
// mode. Click → switch to Edit mode for raw HTML editing (Phase 4 polish).

import { Node } from "@tiptap/core";

export const HtmlBlock = Node.create({
  name: "htmlBlock",
  group: "block",
  atom: true,
  selectable: true,
  defining: true,
  isolating: true,

  addAttributes() {
    return {
      raw: { default: "" },
    };
  },

  parseHTML() {
    return [{ tag: "div[data-html-block]" }];
  },

  renderHTML({ node }) {
    const raw = (node.attrs.raw ?? "") as string;
    // Render the raw HTML inside a wrapper div so PM has something to mount
    // against. Use innerHTML at NodeView time — the simple renderHTML below
    // shows the raw bytes as text for now (Phase 4 will swap to a NodeView
    // that injects the actual HTML).
    return [
      "div",
      {
        "data-html-block": "",
        class: "html-block",
        style: "white-space: pre-wrap; font-family: ui-monospace, monospace; opacity: 0.6;",
      },
      raw,
    ];
  },

  markdownTokenName: "html",

  parseMarkdown(token: any, h: any) {
    return h.createNode("htmlBlock", { raw: token.raw ?? "" }, []);
  },

  renderMarkdown(node: any) {
    return (node.attrs?.raw ?? "") as string;
  },
});
