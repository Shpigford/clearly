// `<details>...</details>` HTML blocks. Captures the entire block (including
// any blank-line-containing markdown body) as one node, then renders a real
// native <details> element so the browser handles open/close. The summary
// and body markdown are rendered via marked at NodeView time.
//
// Registered before HtmlBlock so this tokenizer claims <details> blocks
// before they get split into separate raw-HTML pieces by marked's default
// HTML block tokenizer.

import { Node } from "@tiptap/core";
import { marked } from "marked";

const DETAILS_RE = /^<details(?:\s[^>]*)?>([\s\S]*?)<\/details>[ \t]*(?:\n|$)/i;
const SUMMARY_RE = /<summary[^>]*>([\s\S]*?)<\/summary>/i;

export const Details = Node.create({
  name: "details",
  group: "block",
  atom: true,
  selectable: true,
  defining: true,

  addAttributes() {
    return {
      summary: { default: "Details" },
      body: { default: "" },
    };
  },

  parseHTML() {
    return [{ tag: "details[data-clearly-details]" }];
  },

  renderHTML({ node }) {
    return [
      "details",
      { "data-clearly-details": "" },
      ["summary", {}, node.attrs.summary as string],
    ];
  },

  addNodeView() {
    return ({ node }) => {
      const dom = document.createElement("details");
      dom.setAttribute("data-clearly-details", "");
      dom.contentEditable = "false";

      const summary = document.createElement("summary");
      try {
        summary.innerHTML = marked.parseInline(node.attrs.summary as string, { async: false }) as string;
      } catch {
        summary.textContent = node.attrs.summary as string;
      }
      dom.appendChild(summary);

      const body = document.createElement("div");
      body.className = "details-body";
      try {
        body.innerHTML = marked.parse(node.attrs.body as string, { async: false }) as string;
      } catch {
        body.textContent = node.attrs.body as string;
      }
      dom.appendChild(body);

      return {
        dom,
        ignoreMutation: () => true,
        stopEvent: () => false,
      };
    };
  },

  markdownTokenName: "details_block",

  markdownTokenizer: {
    name: "details_block",
    level: "block" as const,
    start(src: string) {
      // Only signal at a line-start <details>. Returning mid-paragraph
      // positions (e.g. an inline `<details>` mention inside backticks)
      // makes marked break the paragraph and route the leftover text
      // through its raw-HTML-block tokenizer.
      const m = /(?:^|\n)<details(?:\s|>)/i.exec(src);
      return m ? m.index + (src[m.index] === "\n" ? 1 : 0) : -1;
    },
    tokenize(src: string) {
      const m = DETAILS_RE.exec(src);
      if (!m) return undefined;
      const inner = m[1] || "";
      const sm = SUMMARY_RE.exec(inner);
      const summary = sm ? sm[1].trim() : "Details";
      const body = sm ? inner.replace(sm[0], "").trim() : inner.trim();
      return {
        type: "details_block",
        raw: m[0],
        summary,
        body,
      };
    },
  },

  parseMarkdown(token: any, h: any) {
    return h.createNode(
      "details",
      { summary: token.summary ?? "Details", body: token.body ?? "" },
      []
    );
  },

  renderMarkdown(node: any) {
    const summary = (node.attrs?.summary ?? "") as string;
    const body = (node.attrs?.body ?? "") as string;
    return `<details>\n<summary>${summary}</summary>\n\n${body}\n\n</details>\n`;
  },
});
