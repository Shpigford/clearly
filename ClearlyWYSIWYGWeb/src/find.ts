// Find / replace plugin for the WYSIWYG editor. Scans the doc's plain text
// content, builds a list of match ranges, and renders inline Decorations that
// the host CSS styles. Supports plain-text and JS regex modes, case-sensitive
// toggle. Navigation (nextMatch/prevMatch) wraps; current match gets an extra
// `match-current` class for distinct styling.
//
// Replacement: for atom inline nodes (wikiLink, tag, emoji, math…) the match
// range can land on text adjacent to atoms — we replace the contiguous text
// span only, never the atom itself. PM's tr.replaceWith handles that safely
// because we identified the range from text, so the start/end positions sit
// at text boundaries.

import { Plugin, PluginKey, EditorState, Transaction } from "@tiptap/pm/state";
import { Decoration, DecorationSet, EditorView } from "@tiptap/pm/view";

export interface FindOptions {
  caseSensitive: boolean;
  useRegex: boolean;
  wholeWord: boolean;
}

export interface FindStatus {
  matchCount: number;
  currentIndex: number;
  regexError: string | null;
}

interface MatchRange {
  from: number;
  to: number;
}

interface PluginState {
  query: string;
  replacement: string;
  options: FindOptions;
  matches: MatchRange[];
  currentIndex: number;
  decorations: DecorationSet;
  regexError: string | null;
}

export const findPluginKey = new PluginKey<PluginState>("clearlyFind");

const META_SET_QUERY = "find:setQuery";
const META_NAVIGATE = "find:navigate";
const META_RESET = "find:reset";

interface SetQueryMeta {
  query: string;
  replacement: string;
  options: FindOptions;
}

interface NavigateMeta {
  direction: "next" | "previous";
}

function emptyState(): PluginState {
  return {
    query: "",
    replacement: "",
    options: { caseSensitive: false, useRegex: false, wholeWord: false },
    matches: [],
    currentIndex: -1,
    decorations: DecorationSet.empty,
    regexError: null,
  };
}

function buildDocText(doc: any): { text: string; positions: number[] } {
  // Collect every text leaf with its absolute position. We concat into a flat
  // text buffer plus a parallel position array indicating the PM doc offset
  // for each character. Matches are then translated back via positions[i].
  let text = "";
  const positions: number[] = [];
  doc.descendants((node: any, pos: number) => {
    if (node.isText && node.text) {
      const s = node.text as string;
      for (let i = 0; i < s.length; i++) {
        text += s[i];
        positions.push(pos + i);
      }
    }
    return true;
  });
  return { text, positions };
}

function findMatches(
  doc: any,
  query: string,
  options: FindOptions
): { matches: MatchRange[]; regexError: string | null } {
  if (!query) return { matches: [], regexError: null };
  const { text, positions } = buildDocText(doc);
  if (text.length === 0) return { matches: [], regexError: null };

  let regex: RegExp;
  try {
    if (options.useRegex) {
      const flags = options.caseSensitive ? "g" : "gi";
      regex = new RegExp(query, flags);
    } else {
      // Escape regex metacharacters for plain-text search.
      const escaped = query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      const pattern = options.wholeWord ? `\\b${escaped}\\b` : escaped;
      const flags = options.caseSensitive ? "g" : "gi";
      regex = new RegExp(pattern, flags);
    }
  } catch (err) {
    return { matches: [], regexError: (err as Error).message };
  }

  const matches: MatchRange[] = [];
  let m: RegExpExecArray | null;
  while ((m = regex.exec(text)) !== null) {
    if (m[0].length === 0) {
      regex.lastIndex++;
      continue;
    }
    const startIdx = m.index;
    const endIdx = m.index + m[0].length - 1;
    const fromPos = positions[startIdx];
    const toPos = positions[endIdx] + 1;
    matches.push({ from: fromPos, to: toPos });
  }
  return { matches, regexError: null };
}

function buildDecorations(doc: any, matches: MatchRange[], currentIndex: number): DecorationSet {
  if (matches.length === 0) return DecorationSet.empty;
  const decos = matches.map((m, i) =>
    Decoration.inline(m.from, m.to, {
      class: i === currentIndex ? "find-match find-match-current" : "find-match",
    })
  );
  return DecorationSet.create(doc, decos);
}

function emitStatus(view: EditorView, state: PluginState): void {
  const status: FindStatus = {
    matchCount: state.matches.length,
    currentIndex: state.matches.length === 0 ? 0 : state.currentIndex + 1,
    regexError: state.regexError,
  };
  const w = window as any;
  try {
    w.webkit?.messageHandlers?.wysiwyg?.postMessage({
      type: "findStatus",
      ...status,
    });
  } catch {
    // Outside WKWebView; ignore.
  }
  view.dom.dispatchEvent(
    new CustomEvent("clearly-find-status", { detail: status })
  );
}

function scrollMatchIntoView(view: EditorView, range: MatchRange): void {
  const dom = view.domAtPos(range.from);
  const node = dom.node as Node;
  const el = node.nodeType === Node.ELEMENT_NODE
    ? (node as HTMLElement)
    : (node.parentElement as HTMLElement | null);
  if (!el) return;
  el.scrollIntoView({ block: "center", behavior: "smooth" });
}

export function findPlugin() {
  return new Plugin<PluginState>({
    key: findPluginKey,
    state: {
      init: emptyState,
      apply(tr: Transaction, value: PluginState, _oldState: EditorState, newState: EditorState) {
        const setQuery = tr.getMeta(META_SET_QUERY) as SetQueryMeta | undefined;
        const navigate = tr.getMeta(META_NAVIGATE) as NavigateMeta | undefined;
        const reset = tr.getMeta(META_RESET) as boolean | undefined;

        if (reset) {
          return emptyState();
        }

        if (setQuery) {
          const { matches, regexError } = findMatches(
            newState.doc,
            setQuery.query,
            setQuery.options
          );
          const currentIndex = matches.length === 0 ? -1 : 0;
          return {
            query: setQuery.query,
            replacement: setQuery.replacement,
            options: setQuery.options,
            matches,
            currentIndex,
            decorations: buildDecorations(newState.doc, matches, currentIndex),
            regexError,
          };
        }

        if (navigate && value.matches.length > 0) {
          const next =
            navigate.direction === "next"
              ? (value.currentIndex + 1) % value.matches.length
              : (value.currentIndex - 1 + value.matches.length) % value.matches.length;
          return {
            ...value,
            currentIndex: next,
            decorations: buildDecorations(newState.doc, value.matches, next),
          };
        }

        // If the doc changed, re-scan against the current query so highlights
        // stay accurate. Cheap because we only do this when docChanged.
        if (tr.docChanged && value.query) {
          const { matches, regexError } = findMatches(
            newState.doc,
            value.query,
            value.options
          );
          const currentIndex =
            matches.length === 0
              ? -1
              : Math.min(Math.max(0, value.currentIndex), matches.length - 1);
          return {
            ...value,
            matches,
            currentIndex,
            decorations: buildDecorations(newState.doc, matches, currentIndex),
            regexError,
          };
        }

        // Map decorations through doc changes if we didn't rebuild above.
        if (tr.docChanged) {
          return {
            ...value,
            decorations: value.decorations.map(tr.mapping, tr.doc),
          };
        }

        return value;
      },
    },
    props: {
      decorations(state) {
        return findPluginKey.getState(state)?.decorations;
      },
    },
  });
}

export function setFindQuery(
  view: EditorView,
  query: string,
  replacement: string,
  options: FindOptions
): void {
  const tr = view.state.tr.setMeta(META_SET_QUERY, {
    query,
    replacement,
    options,
  } as SetQueryMeta);
  view.dispatch(tr);
  const state = findPluginKey.getState(view.state);
  if (state && state.matches.length > 0 && state.currentIndex >= 0) {
    scrollMatchIntoView(view, state.matches[state.currentIndex]);
  }
  if (state) emitStatus(view, state);
}

export function navigateMatch(view: EditorView, direction: "next" | "previous"): void {
  const tr = view.state.tr.setMeta(META_NAVIGATE, { direction } as NavigateMeta);
  view.dispatch(tr);
  const state = findPluginKey.getState(view.state);
  if (state && state.matches.length > 0 && state.currentIndex >= 0) {
    scrollMatchIntoView(view, state.matches[state.currentIndex]);
  }
  if (state) emitStatus(view, state);
}

export function replaceCurrent(view: EditorView): number {
  const state = findPluginKey.getState(view.state);
  if (!state || state.matches.length === 0 || state.currentIndex < 0) return 0;
  const match = state.matches[state.currentIndex];
  const tr = view.state.tr.replaceRangeWith(
    match.from,
    match.to,
    view.state.schema.text(state.replacement)
  );
  view.dispatch(tr);
  // Re-emit status (doc change re-scans automatically).
  const newState = findPluginKey.getState(view.state);
  if (newState) emitStatus(view, newState);
  return 1;
}

export function replaceAll(view: EditorView): number {
  const state = findPluginKey.getState(view.state);
  if (!state || state.matches.length === 0) return 0;
  // Replace from the back so earlier match offsets stay valid.
  const tr = view.state.tr;
  const sortedMatches = [...state.matches].sort((a, b) => b.from - a.from);
  for (const m of sortedMatches) {
    tr.replaceRangeWith(m.from, m.to, view.state.schema.text(state.replacement));
  }
  view.dispatch(tr);
  const replaceCount = state.matches.length;
  const newState = findPluginKey.getState(view.state);
  if (newState) emitStatus(view, newState);
  return replaceCount;
}

export function resetFind(view: EditorView): void {
  const tr = view.state.tr.setMeta(META_RESET, true);
  view.dispatch(tr);
}
