// Floating selection-aware toolbar. Appears above any non-empty text
// selection with the standard inline-format buttons (bold, italic, strike,
// inline-code, link). Hides when the selection is empty, on a code block,
// or on an atom node like an image or wiki link.

import { Extension } from "@tiptap/core";
import { BubbleMenuPlugin } from "@tiptap/extension-bubble-menu";
import type { Editor } from "@tiptap/core";

interface ButtonSpec {
  label: string;
  title: string;
  isActive: (editor: Editor) => boolean;
  command: (editor: Editor) => void;
}

const BUTTONS: ButtonSpec[] = [
  {
    label: "B",
    title: "Bold (⌘B)",
    isActive: (e) => e.isActive("bold"),
    command: (e) => {
      e.chain().focus().toggleBold().run();
    },
  },
  {
    label: "I",
    title: "Italic (⌘I)",
    isActive: (e) => e.isActive("italic"),
    command: (e) => {
      e.chain().focus().toggleItalic().run();
    },
  },
  {
    label: "S",
    title: "Strikethrough",
    isActive: (e) => e.isActive("strike"),
    command: (e) => {
      e.chain().focus().toggleStrike().run();
    },
  },
  {
    label: "</>",
    title: "Inline code",
    isActive: (e) => e.isActive("code"),
    command: (e) => {
      e.chain().focus().toggleCode().run();
    },
  },
  {
    label: "==",
    title: "Highlight",
    isActive: (e) => e.isActive("highlight"),
    command: (e) => {
      e.chain().focus().toggleMark("highlight").run();
    },
  },
  {
    label: "🔗",
    title: "Link (⌘K)",
    isActive: () => false,
    command: (e) => {
      const sel = e.state.selection;
      const selectedText = e.state.doc.textBetween(sel.from, sel.to, " ");
      const label = selectedText || "link text";
      const insert = `[${label}](url)`;
      const urlStart = sel.from + `[${label}](`.length;
      e.chain()
        .focus()
        .insertContent(insert)
        .setTextSelection({ from: urlStart, to: urlStart + "url".length })
        .run();
    },
  },
];

function buildElement(editor: Editor): HTMLElement {
  const container = document.createElement("div");
  container.className = "bubble-menu";
  const buttons: { spec: ButtonSpec; el: HTMLButtonElement }[] = [];
  for (const spec of BUTTONS) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "bubble-menu-button";
    btn.title = spec.title;
    btn.textContent = spec.label;
    btn.addEventListener("mousedown", (e) => {
      e.preventDefault();
      spec.command(editor);
    });
    container.appendChild(btn);
    buttons.push({ spec, el: btn });
  }
  // Refresh active states whenever the selection moves.
  const refresh = () => {
    for (const { spec, el } of buttons) {
      el.classList.toggle("is-active", spec.isActive(editor));
    }
  };
  editor.on("selectionUpdate", refresh);
  editor.on("transaction", refresh);
  return container;
}

export const BubbleMenu = Extension.create({
  name: "clearlyBubbleMenu",

  addProseMirrorPlugins() {
    const editor = this.editor;
    const element = buildElement(editor);
    document.body.appendChild(element);
    return [
      BubbleMenuPlugin({
        editor,
        element,
        pluginKey: "clearlyBubbleMenu",
        shouldShow: ({ editor: ed, state }) => {
          const { selection } = state;
          if (selection.empty) return false;
          // Hide inside code blocks (formatting doesn't apply there).
          if (ed.isActive("codeBlock")) return false;
          // Hide for atom-only selections (image, wiki link, math, etc.).
          const slice = state.doc.cut(selection.from, selection.to);
          let onlyAtoms = true;
          slice.descendants((node) => {
            if (!node.isAtom && node.isText) onlyAtoms = false;
            return true;
          });
          if (onlyAtoms) return false;
          return true;
        },
      }),
    ];
  },
});
