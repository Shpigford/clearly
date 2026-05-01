// Slash menu — type "/" inside the editor to open a Notion-style command
// palette. Driven by @tiptap/suggestion, which handles range tracking,
// keyboard navigation, and dismissal. The DOM popup is a plain absolutely-
// positioned div managed by this extension; styling lives in
// Shared/Resources/wysiwyg/index.html.
//
// Each command runs as `editor.chain().focus().deleteRange(suggestion.range)`
// followed by the actual insertion, so the literal `/query` text never
// survives into the doc.

import { Extension } from "@tiptap/core";
import { PluginKey } from "@tiptap/pm/state";
import Suggestion from "@tiptap/suggestion";

const SLASH_MENU_KEY = new PluginKey("clearlySlashMenu");

interface SlashItem {
  title: string;
  description: string;
  keywords: string[];
  command: (props: { editor: any; range: { from: number; to: number } }) => void;
}

const ITEMS: SlashItem[] = [
  {
    title: "Heading 1",
    description: "Big section title",
    keywords: ["heading", "h1", "title"],
    command: ({ editor, range }) => {
      editor.chain().focus().deleteRange(range).setNode("heading", { level: 1 }).run();
    },
  },
  {
    title: "Heading 2",
    description: "Medium section title",
    keywords: ["heading", "h2"],
    command: ({ editor, range }) => {
      editor.chain().focus().deleteRange(range).setNode("heading", { level: 2 }).run();
    },
  },
  {
    title: "Heading 3",
    description: "Small section title",
    keywords: ["heading", "h3"],
    command: ({ editor, range }) => {
      editor.chain().focus().deleteRange(range).setNode("heading", { level: 3 }).run();
    },
  },
  {
    title: "Bullet List",
    description: "Unordered list",
    keywords: ["bullet", "ul", "list", "unordered"],
    command: ({ editor, range }) => {
      editor.chain().focus().deleteRange(range).toggleBulletList().run();
    },
  },
  {
    title: "Numbered List",
    description: "Ordered list",
    keywords: ["numbered", "ol", "ordered", "list"],
    command: ({ editor, range }) => {
      editor.chain().focus().deleteRange(range).toggleOrderedList().run();
    },
  },
  {
    title: "Task List",
    description: "Checkbox list",
    keywords: ["task", "todo", "checklist", "checkbox"],
    command: ({ editor, range }) => {
      editor.chain().focus().deleteRange(range).toggleTaskList().run();
    },
  },
  {
    title: "Code Block",
    description: "Multi-line monospace code",
    keywords: ["code", "fence", "pre"],
    command: ({ editor, range }) => {
      editor.chain().focus().deleteRange(range).toggleCodeBlock().run();
    },
  },
  {
    title: "Blockquote",
    description: "Quoted paragraph",
    keywords: ["quote", "blockquote", "cite"],
    command: ({ editor, range }) => {
      editor.chain().focus().deleteRange(range).toggleBlockquote().run();
    },
  },
  {
    title: "Horizontal Rule",
    description: "Section divider",
    keywords: ["hr", "rule", "divider", "separator", "line"],
    command: ({ editor, range }) => {
      editor.chain().focus().deleteRange(range).setHorizontalRule().run();
    },
  },
  {
    title: "Table",
    description: "2-column table",
    keywords: ["table", "grid"],
    command: ({ editor, range }) => {
      editor
        .chain()
        .focus()
        .deleteRange(range)
        .insertContent({
          type: "table",
          content: [
            {
              type: "tableRow",
              content: [
                { type: "tableHeader", content: [{ type: "paragraph" }] },
                { type: "tableHeader", content: [{ type: "paragraph" }] },
              ],
            },
            {
              type: "tableRow",
              content: [
                { type: "tableCell", content: [{ type: "paragraph" }] },
                { type: "tableCell", content: [{ type: "paragraph" }] },
              ],
            },
          ],
        })
        .run();
    },
  },
  {
    title: "Math (block)",
    description: "$$…$$ display equation",
    keywords: ["math", "equation", "latex", "katex"],
    command: ({ editor, range }) => {
      editor
        .chain()
        .focus()
        .deleteRange(range)
        .insertContent({ type: "blockMath", attrs: { formula: "" } })
        .run();
    },
  },
  {
    title: "Math (inline)",
    description: "$…$ inline equation",
    keywords: ["math", "inline", "equation", "latex"],
    command: ({ editor, range }) => {
      editor
        .chain()
        .focus()
        .deleteRange(range)
        .insertContent({ type: "inlineMath", attrs: { formula: "" } })
        .run();
    },
  },
  {
    title: "Mermaid",
    description: "Diagram fenced block",
    keywords: ["mermaid", "diagram", "flowchart", "sequence"],
    command: ({ editor, range }) => {
      editor
        .chain()
        .focus()
        .deleteRange(range)
        .insertContent({ type: "mermaid", attrs: { code: "graph TD\n  A --> B" } })
        .run();
    },
  },
  {
    title: "Callout / Tip",
    description: "> [!TIP] block",
    keywords: ["callout", "tip", "note", "warn", "admonition"],
    command: ({ editor, range }) => {
      editor
        .chain()
        .focus()
        .deleteRange(range)
        .insertContent({
          type: "callout",
          attrs: { kind: "TIP", foldable: false, open: true, summary: null },
          content: [{ type: "paragraph" }],
        })
        .run();
    },
  },
];

function filterItems(query: string): SlashItem[] {
  const q = query.toLowerCase().trim();
  if (!q) return ITEMS;
  return ITEMS.filter((item) => {
    if (item.title.toLowerCase().includes(q)) return true;
    if (item.description.toLowerCase().includes(q)) return true;
    return item.keywords.some((k) => k.toLowerCase().includes(q));
  });
}

class SlashMenuRenderer {
  private element: HTMLElement;
  private items: SlashItem[] = [];
  private selectedIndex = 0;
  private clientRect: (() => DOMRect | null) | null = null;
  private command: ((item: SlashItem) => void) | null = null;

  constructor() {
    this.element = document.createElement("div");
    this.element.className = "slash-menu";
    this.element.style.position = "absolute";
    this.element.style.zIndex = "9999";
    this.element.style.display = "none";
    document.body.appendChild(this.element);
  }

  show(props: any): void {
    this.items = props.items;
    this.selectedIndex = 0;
    this.clientRect = props.clientRect;
    this.command = props.command;
    this.render();
    this.position();
    this.element.style.display = "block";
  }

  update(props: any): void {
    this.items = props.items;
    this.selectedIndex = 0;
    this.clientRect = props.clientRect;
    this.command = props.command;
    this.render();
    this.position();
  }

  hide(): void {
    this.element.style.display = "none";
  }

  destroy(): void {
    this.element.remove();
  }

  onKeyDown(props: { event: KeyboardEvent }): boolean {
    const { event } = props;
    if (event.key === "ArrowDown") {
      this.selectedIndex = (this.selectedIndex + 1) % Math.max(this.items.length, 1);
      this.render();
      return true;
    }
    if (event.key === "ArrowUp") {
      this.selectedIndex =
        (this.selectedIndex - 1 + Math.max(this.items.length, 1)) % Math.max(this.items.length, 1);
      this.render();
      return true;
    }
    if (event.key === "Enter" || event.key === "Tab") {
      const item = this.items[this.selectedIndex];
      if (item && this.command) this.command(item);
      return true;
    }
    if (event.key === "Escape") {
      this.hide();
      return true;
    }
    return false;
  }

  private render(): void {
    this.element.innerHTML = "";
    if (this.items.length === 0) {
      const empty = document.createElement("div");
      empty.className = "slash-menu-empty";
      empty.textContent = "No matches";
      this.element.appendChild(empty);
      return;
    }
    this.items.forEach((item, i) => {
      const row = document.createElement("button");
      row.type = "button";
      row.className = "slash-menu-item" + (i === this.selectedIndex ? " is-selected" : "");
      const title = document.createElement("span");
      title.className = "slash-menu-title";
      title.textContent = item.title;
      const desc = document.createElement("span");
      desc.className = "slash-menu-desc";
      desc.textContent = item.description;
      row.appendChild(title);
      row.appendChild(desc);
      row.addEventListener("mousedown", (e) => {
        e.preventDefault();
        if (this.command) this.command(item);
      });
      this.element.appendChild(row);
    });
  }

  private position(): void {
    const rect = this.clientRect?.();
    if (!rect) return;
    const top = rect.bottom + window.scrollY + 4;
    const left = rect.left + window.scrollX;
    this.element.style.top = `${top}px`;
    this.element.style.left = `${left}px`;
  }
}

export const SlashMenu = Extension.create({
  name: "slashMenu",

  addProseMirrorPlugins() {
    const renderer = new SlashMenuRenderer();
    return [
      Suggestion({
        pluginKey: SLASH_MENU_KEY,
        editor: this.editor,
        char: "/",
        startOfLine: false,
        allowSpaces: false,
        // Don't open the slash menu mid-IME-composition. Some IMEs use `/`
        // internally as a separator before commit, and showing the popup
        // there steals key focus and breaks the composition.
        allow: ({ editor }) => !editor.view.composing,
        items: ({ query }) => filterItems(query),
        render: () => ({
          onStart: (props) => {
            renderer.show({
              items: props.items,
              clientRect: props.clientRect,
              command: (item: SlashItem) => {
                item.command({ editor: props.editor, range: props.range });
                renderer.hide();
              },
            });
          },
          onUpdate: (props) => {
            renderer.update({
              items: props.items,
              clientRect: props.clientRect,
              command: (item: SlashItem) => {
                item.command({ editor: props.editor, range: props.range });
                renderer.hide();
              },
            });
          },
          onKeyDown: (props) => renderer.onKeyDown(props),
          onExit: () => {
            renderer.hide();
          },
        }),
      }),
    ];
  },
});
