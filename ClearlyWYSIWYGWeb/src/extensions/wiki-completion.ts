// Wiki link autocomplete — type `[[` inside the editor to open a popup of
// matching vault files. The vault file list is pushed in from Swift via
// window.clearlyWYSIWYG.setWikiTargets and stored in a module-level cache;
// filtering and rendering happen entirely on the JS side so typing is
// instant. On commit, the `[[query` range is replaced with a wikiLink atom
// node carrying the selected target.

import { Extension } from "@tiptap/core";
import { PluginKey } from "@tiptap/pm/state";
import Suggestion from "@tiptap/suggestion";

const WIKI_COMPLETION_KEY = new PluginKey("clearlyWikiCompletion");

export interface WikiTarget {
  title: string;
  path: string;
  isWiki?: boolean;
}

let wikiTargets: WikiTarget[] = [];

export function setWikiTargets(targets: WikiTarget[]): void {
  wikiTargets = Array.isArray(targets) ? targets : [];
}

export function getWikiTargets(): WikiTarget[] {
  return wikiTargets;
}

function filterTargets(query: string, limit = 12): WikiTarget[] {
  const q = query.toLowerCase().trim();
  if (!q) return wikiTargets.slice(0, limit);
  const exact: WikiTarget[] = [];
  const prefix: WikiTarget[] = [];
  const contains: WikiTarget[] = [];
  for (const t of wikiTargets) {
    const title = t.title.toLowerCase();
    if (title === q) exact.push(t);
    else if (title.startsWith(q)) prefix.push(t);
    else if (title.includes(q) || t.path.toLowerCase().includes(q)) contains.push(t);
    if (exact.length + prefix.length + contains.length >= limit * 3) break;
  }
  return [...exact, ...prefix, ...contains].slice(0, limit);
}

class WikiCompletionRenderer {
  private element: HTMLElement;
  private items: WikiTarget[] = [];
  private query = "";
  private selectedIndex = 0;
  private clientRect: (() => DOMRect | null) | null = null;
  private command: ((item: WikiTarget | null) => void) | null = null;

  constructor() {
    this.element = document.createElement("div");
    this.element.className = "wiki-complete";
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
        // No match — commit a fresh wiki link with the typed query as target.
        this.command(null);
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
      empty.className = "wiki-complete-empty";
      empty.textContent = this.query
        ? `No match — Enter to create [[${this.query}]]`
        : "Type to search vault";
      this.element.appendChild(empty);
      return;
    }
    this.items.forEach((item, i) => {
      const row = document.createElement("button");
      row.type = "button";
      row.className =
        "wiki-complete-item" + (i === this.selectedIndex ? " is-selected" : "");
      const title = document.createElement("span");
      title.className = "wiki-complete-title";
      title.textContent = item.title;
      const path = document.createElement("span");
      path.className = "wiki-complete-path";
      path.textContent = item.path;
      row.appendChild(title);
      row.appendChild(path);
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

export const WikiCompletion = Extension.create({
  name: "wikiCompletion",

  addProseMirrorPlugins() {
    const renderer = new WikiCompletionRenderer();
    return [
      Suggestion({
        pluginKey: WIKI_COMPLETION_KEY,
        editor: this.editor,
        // Match `[[` as the trigger; suggestion drops the leading char from
        // the query, but for two-char triggers we use a custom pattern below.
        char: "[[",
        startOfLine: false,
        allowSpaces: true,
        // Suppress during IME composition — the `[` characters are common
        // in CJK punctuation overrides and we don't want to trigger the
        // wiki popup mid-compose.
        allow: ({ editor }) => !editor.view.composing,
        items: ({ query }) => filterTargets(query),
        render: () => ({
          onStart: (props) => {
            renderer.show({
              items: props.items,
              query: props.query,
              clientRect: props.clientRect,
              command: (item: WikiTarget | null) => {
                const target = item ? item.title : props.query;
                if (!target) return;
                props.editor
                  .chain()
                  .focus()
                  .deleteRange(props.range)
                  .insertContent({
                    type: "wikiLink",
                    attrs: { target, heading: null, alias: null },
                  })
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
              command: (item: WikiTarget | null) => {
                const target = item ? item.title : props.query;
                if (!target) return;
                props.editor
                  .chain()
                  .focus()
                  .deleteRange(props.range)
                  .insertContent({
                    type: "wikiLink",
                    attrs: { target, heading: null, alias: null },
                  })
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
