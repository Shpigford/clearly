// Source-range preservation. Per docs/WYSIWYG.md Section 7, edits to a single
// block should not normalize the rest of the document. We achieve this by:
//
//   1. Tokenizing the original markdown with marked. Each non-`space` token
//      is a "block" that maps 1:1 with a top-level PM doc child.
//   2. Stamping each PM child with a stable preserveId attribute matching
//      its block-token index.
//   3. Snapshotting the JSON of each child at mount time.
//   4. On serialize, walking the original token sequence in order. For each
//      block token, find the current PM child with matching preserveId; if
//      the child's JSON still equals the snapshot, emit the original raw
//      bytes verbatim. Otherwise render that child via @tiptap/markdown.
//      Non-block tokens (`space`) emit raw unconditionally.
//
// Misalignment fall-back. If the parsed PM tree's child count diverges from
// the block-token count (schema gap — table extension missing, etc.), we
// degrade to a global dirty bit: emit body verbatim until any edit, then
// fall back to the renderer for the whole document. Phase 4 follow-up: add
// the missing schema so misalignment goes away.
//
// Insertions / deletions. New top-level children (no preserveId) get
// rendered and appended after the last preserved block. Deleted children
// (a preserveId from the original set with no matching PM child) drop both
// their token and the preceding space token. This handles common edits
// without losing content; complex restructuring may shift positions but
// won't lose bytes.

import type { Editor } from "@tiptap/core";

interface MarkedToken {
  type: string;
  raw: string;
}

interface BlockSnapshot {
  raw: string;
  json: string; // canonicalized JSON of the PM child at mount time
}

export class SourcePreservation {
  private originalBody: string;
  private tokens: MarkedToken[] = [];
  // Index in `tokens` for each block-token, ordered by blockId.
  private blockTokenIndex: number[] = [];
  // Snapshot of each block at mount time, indexed by preserveId / blockId.
  private snapshots: BlockSnapshot[] = [];
  private aligned = false;
  // Used only when not aligned (global dirty bit).
  private globalDirty = false;
  private ignoreNextUpdate = false;

  constructor(body: string) {
    this.originalBody = body;
  }

  // Tokenize with the editor's marked instance, then stamp each top-level
  // PM child with a preserveId, then snapshot JSON. Must be called after
  // the editor finishes mounting.
  attach(editor: Editor): void {
    const manager = (editor as any).markdown;
    const marked = manager?.instance;
    if (manager && marked && typeof marked.lexer === "function") {
      const allTokens: MarkedToken[] = marked.lexer(this.originalBody);
      this.tokens = allTokens.map((t: any) => ({ type: t.type, raw: t.raw ?? "" }));
      this.blockTokenIndex = [];
      for (let i = 0; i < this.tokens.length; i++) {
        if (this.tokens[i].type !== "space") this.blockTokenIndex.push(i);
      }
    }

    const doc = editor.state.doc;
    this.aligned = doc.childCount === this.blockTokenIndex.length;

    // Up-front validation: every top-level child must accept the preserveId
    // attribute. Tiptap's markdown parser occasionally emits stray nodes at
    // top level (a bare `text` for certain inline shapes — see demo.md). PM
    // mounts the resulting tree without complaining, but ANY future
    // transaction triggers schema validation against `doc.content = block+`,
    // which fails. We can't stamp into that — fall back to global mode.
    let allBlockSafe = this.aligned;
    if (this.aligned) {
      doc.forEach((child) => {
        const attrs = child.type.spec.attrs as Record<string, unknown> | undefined;
        if (!attrs || !Object.prototype.hasOwnProperty.call(attrs, "preserveId")) {
          allBlockSafe = false;
        }
      });
    }
    this.aligned = allBlockSafe;

    if (this.aligned) {
      this.ignoreNextUpdate = true;
      const tr = editor.state.tr;
      tr.setMeta("addToHistory", false);
      tr.setMeta("preservation:internal", true);
      doc.forEach((_child, offset, idx) => {
        tr.setNodeAttribute(offset, "preserveId", idx);
      });
      editor.view.dispatch(tr);
      this.snapshots = [];
      editor.state.doc.forEach((child, _offset, idx) => {
        const blockTokIdx = this.blockTokenIndex[idx];
        const raw = blockTokIdx != null ? this.tokens[blockTokIdx].raw : "";
        this.snapshots.push({ raw, json: jsonFingerprint(child.toJSON()) });
      });
    }

    editor.on("update", ({ transaction }) => {
      if (this.ignoreNextUpdate) {
        this.ignoreNextUpdate = false;
        return;
      }
      if (transaction.getMeta("preservation:internal")) return;
      this.globalDirty = true;
    });
  }

  // Re-initialize state for a new source body. Must be followed by attach().
  beginExternalReplace(body: string): void {
    this.originalBody = body;
    this.tokens = [];
    this.blockTokenIndex = [];
    this.snapshots = [];
    this.aligned = false;
    this.globalDirty = false;
    this.ignoreNextUpdate = true;
  }

  getMarkdownBody(editor: Editor): string {
    if (!this.aligned) {
      // Global mode: dirty → renderer; clean → original verbatim.
      if (!this.globalDirty) return this.originalBody;
      return editor.getMarkdown();
    }

    // Aligned mode: walk tokens; emit raw for clean blocks, rendered for
    // dirty ones, raw for space tokens. Insertions appended at end;
    // deletions skip both block and the immediately-preceding space token.
    const manager = (editor as any).markdown;
    const pmById = new Map<number, any>();
    const newChildren: any[] = [];
    const seenIds = new Set<number>();
    editor.state.doc.forEach((child) => {
      const id = child.attrs?.preserveId;
      if (typeof id === "number" && !seenIds.has(id)) {
        pmById.set(id, child);
        seenIds.add(id);
      } else {
        // Skip empty placeholder paragraphs PM may auto-append (happens when
        // the last source block is an atom like htmlBlock or image — PM needs
        // a trailing editable paragraph for cursor placement). The user
        // didn't author this, so don't emit it.
        const isEmptyParagraph =
          child.type.name === "paragraph" &&
          child.content.size === 0;
        if (!isEmptyParagraph) {
          newChildren.push(child);
        }
      }
    });

    const out: string[] = [];
    let blockId = 0;
    for (let i = 0; i < this.tokens.length; i++) {
      const tok = this.tokens[i];
      if (tok.type === "space") {
        const nextBlockExists = pmById.has(blockId);
        if (nextBlockExists) out.push(tok.raw);
        continue;
      }
      const child = pmById.get(blockId);
      if (child) {
        const currentJson = jsonFingerprint(child.toJSON());
        const snap = this.snapshots[blockId]?.json;
        if (currentJson === snap) {
          out.push(tok.raw);
        } else {
          out.push(renderChild(manager, child));
        }
      }
      blockId++;
    }

    // Append new children at end with a default \n\n separator if needed.
    for (const child of newChildren) {
      if (out.length > 0 && !out[out.length - 1].endsWith("\n\n")) {
        const last = out[out.length - 1];
        if (last.endsWith("\n")) out.push("\n");
        else out.push("\n\n");
      }
      out.push(renderChild(manager, child));
    }

    return out.join("");
  }
}

function jsonFingerprint(json: any): string {
  // Strip preserveId before hashing — we're checking content equality, and
  // the id attribute is bookkeeping, not semantic state.
  return JSON.stringify(json, (key, value) => {
    if (key === "preserveId") return undefined;
    return value;
  });
}

function renderChild(manager: any, child: any): string {
  if (!manager || typeof manager.serialize !== "function") return "";
  // serialize accepts a JSONContent doc-or-fragment. Wrapping the child
  // node's JSON in a synthetic doc keeps the serializer happy and emits
  // just this block's content.
  const doc = { type: "doc", content: [child.toJSON()] };
  return manager.serialize(doc);
}
