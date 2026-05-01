// Tag autocomplete — type `#` mid-paragraph to open a popup of known vault
// tags (filtered by what comes after the `#`). Allows committing an unknown
// query as a fresh tag too. Mirrors the wiki-completion shape; the tag list
// is pushed in from Swift via window.clearlyWYSIWYG.setTagTargets.
//
// Trigger constraints: only fires when the `#` follows whitespace or sits at
// the start of a node — avoids false positives on `[[X#H]]`, URL fragments,
// `H1#anchor`, etc. Ranges through unicode word chars + `-`, `_`, `/`.

import { Extension } from "@tiptap/core";
import { PluginKey } from "@tiptap/pm/state";
import Suggestion from "@tiptap/suggestion";

const TAG_COMPLETION_KEY = new PluginKey("clearlyTagCompletion");

export interface TagTarget {
  name: string;
  count?: number;
}

let tagTargets: TagTarget[] = [];

export function setTagTargets(targets: TagTarget[]): void {
  tagTargets = Array.isArray(targets) ? targets : [];
}

function filterTargets(query: string, limit = 12): TagTarget[] {
  const q = query.toLowerCase().trim();
  if (!q) return tagTargets.slice(0, limit);
  const exact: TagTarget[] = [];
  const prefix: TagTarget[] = [];
  const contains: TagTarget[] = [];
  for (const t of tagTargets) {
    const name = t.name.toLowerCase();
    if (name === q) exact.push(t);
    else if (name.startsWith(q)) prefix.push(t);
    else if (name.includes(q)) contains.push(t);
    if (exact.length + prefix.length + contains.length >= limit * 3) break;
  }
  return [...exact, ...prefix, ...contains].slice(0, limit);
}

class TagCompletionRenderer {
  private element: HTMLElement;
  private items: TagTarget[] = [];
  private query = "";
  private selectedIndex = 0;
  private clientRect: (() => DOMRect | null) | null = null;
  private command: ((item: TagTarget | null) => void) | null = null;

  constructor() {
    this.element = document.createElement("div");
    this.element.className = "tag-complete";
    this.element.style.position = "absolute";
    this.element.style.zIndex = "9999";
    this.element.style.display = "none";
    document.body.appendChild(this.element);
  }

  show(props: any): void {
    this.items = props.items;
    this.query = props.query ?? "";
    this.selectedIndex = 0;
    this.clientRect = props.clientRect;
    this.command = props.command;
    this.render();
    this.position();
    this.element.style.display = "block";
  }

  update(props: any): void {
    this.items = props.items;
    this.query = props.query ?? "";
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
    const total = this.items.length === 0 ? 1 : this.items.length;
    if (event.key === "ArrowDown") {
      this.selectedIndex = (this.selectedIndex + 1) % total;
      this.render();
      return true;
    }
    if (event.key === "ArrowUp") {
      this.selectedIndex = (this.selectedIndex - 1 + total) % total;
      this.render();
      return true;
    }
    if (event.key === "Enter" || event.key === "Tab") {
      if (!this.command) return true;
      if (this.items.length > 0) {
        this.command(this.items[this.selectedIndex]);
      } else {
        this.command(null);
      }
      return true;
    }
    if (event.key === " ") {
      // Space terminates a tag — commit current query.
      if (!this.command) return false;
      if (this.items.length > 0) {
        this.command(this.items[this.selectedIndex]);
      } else if (this.query) {
        this.command(null);
      } else {
        return false;
      }
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
      empty.className = "tag-complete-empty";
      empty.textContent = this.query
        ? `No match — Enter to create #${this.query}`
        : "Type to search tags";
      this.element.appendChild(empty);
      return;
    }
    this.items.forEach((item, i) => {
      const row = document.createElement("button");
      row.type = "button";
      row.className =
        "tag-complete-item" + (i === this.selectedIndex ? " is-selected" : "");
      const name = document.createElement("span");
      name.className = "tag-complete-name";
      name.textContent = `#${item.name}`;
      row.appendChild(name);
      if (item.count !== undefined && item.count > 0) {
        const count = document.createElement("span");
        count.className = "tag-complete-count";
        count.textContent = String(item.count);
        row.appendChild(count);
      }
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

export const TagCompletion = Extension.create({
  name: "tagCompletion",

  addProseMirrorPlugins() {
    const renderer = new TagCompletionRenderer();
    return [
      Suggestion({
        pluginKey: TAG_COMPLETION_KEY,
        editor: this.editor,
        char: "#",
        startOfLine: false,
        allowSpaces: false,
        // Only fire after whitespace, start-of-node, or punctuation that
        // isn't part of an identifier — so `[[X#h]]` and `H1#anchor` don't
        // trigger.
        allowedPrefixes: [" ", "\t", "\n", "(", "[", ",", ";", ":", null],
        // Suppress during IME composition. `#` appears in some kana→kanji
        // candidate windows and we don't want it to false-trigger.
        allow: ({ editor }) => !editor.view.composing,
        items: ({ query }) => filterTargets(query),
        render: () => ({
          onStart: (props) => {
            renderer.show({
              items: props.items,
              query: props.query,
              clientRect: props.clientRect,
              command: (item: TagTarget | null) => {
                const name = item ? item.name : props.query;
                if (!name) return;
                props.editor
                  .chain()
                  .focus()
                  .deleteRange(props.range)
                  .insertContent({ type: "tag", attrs: { name } })
                  .insertContent(" ")
                  .run();
                renderer.hide();
              },
            });
          },
          onUpdate: (props) => {
            renderer.update({
              items: props.items,
              query: props.query,
              clientRect: props.clientRect,
              command: (item: TagTarget | null) => {
                const name = item ? item.name : props.query;
                if (!name) return;
                props.editor
                  .chain()
                  .focus()
                  .deleteRange(props.range)
                  .insertContent({ type: "tag", attrs: { name } })
                  .insertContent(" ")
                  .run();
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
