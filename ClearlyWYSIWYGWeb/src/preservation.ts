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

// Forensic-only ping to the host when block-level alignment fails or
// degrades. Lets `DiagnosticLog` show which markdown constructs trigger
// fallback (issue #340 follow-up) without surfacing anything to the user.
function postFallback(reason: string, info: Record<string, unknown> = {}): void {
  try {
    (window as unknown as { webkit?: { messageHandlers?: { wysiwyg?: { postMessage: (m: Record<string, unknown>) => void } } } })
      .webkit?.messageHandlers?.wysiwyg?.postMessage({
        type: "preservationFallback",
        reason,
        ...info,
      });
  } catch {
    // dev harness — ignore
  }
}

interface BlockSnapshot {
  raw: string;
  json: string; // canonicalized JSON of the PM child at mount time
}

type UpdateHandler = (event: { transaction: any }) => void;

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
  // Held so we can detach on re-attach. `editor.on("update", fn)` registers
  // a fresh listener each call without removing prior ones — without this,
  // every doc switch would leak a listener that fires on every keystroke.
  private updateHandler: UpdateHandler | null = null;

  constructor(body: string) {
    this.originalBody = body;
  }

  // Tokenize with the editor's marked instance, then stamp each top-level
  // PM child with a preserveId, then snapshot JSON. Must be called after
  // the editor finishes mounting.
  attach(editor: Editor): void {
    if (this.updateHandler) {
      editor.off("update", this.updateHandler);
      this.updateHandler = null;
    }
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
    const documentChildCount = doc.childCount;
    const blockTokenCount = this.blockTokenIndex.length;
    this.aligned = documentChildCount === blockTokenCount;
    if (!this.aligned) {
      postFallback("child-count-mismatch", { documentChildCount, blockTokenCount });
    }

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
    if (this.aligned && !allBlockSafe) {
      postFallback("non-block-safe-node", { documentChildCount, blockTokenCount });
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

    this.updateHandler = ({ transaction }) => {
      if (this.ignoreNextUpdate) {
        this.ignoreNextUpdate = false;
        return;
      }
      if (transaction.getMeta("preservation:internal")) return;
      if (!this.aligned && !this.globalDirty) {
        // Aligned-mode never reached on this document, and the user just
        // made the first edit — switching from "emit body verbatim" to
        // "render whole doc through @tiptap/markdown" is the formatting-
        // drift moment. Log so we can see which docs trigger it.
        postFallback("global-dirty");
      }
      this.globalDirty = true;
    };
    editor.on("update", this.updateHandler);
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

    // Aligned mode: walk the PM doc in tree order so that blocks the user
    // inserted via WYSIWYG land at their actual position, not appended at the
    // end. For each preserved child, emit its original raw bytes when its
    // JSON still matches the snapshot, otherwise re-render via @tiptap/markdown.
    // For new children (no preserveId), emit rendered output at this position.
    // Between two preserved children that are adjacent in original order, we
    // re-emit the original space token to preserve whitespace fidelity;
    // everywhere else falls back to a "\n\n" separator.
    const manager = (editor as any).markdown;
    const out: string[] = [];
    let prevPreservedId: number | null = null;
    let prevWasNew = false;

    editor.state.doc.forEach((child) => {
      const id = child.attrs?.preserveId;
      const isPreserved = typeof id === "number";
      const isEmptyParagraph =
        child.type.name === "paragraph" &&
        child.content.size === 0;
      // Skip PM-auto-added empty trailing paragraphs (the user didn't author
      // them — PM needs a trailing editable paragraph after atom blocks like
      // htmlBlock or image).
      if (!isPreserved && isEmptyParagraph) return;

      if (out.length > 0) {
        const adjacent =
          isPreserved &&
          prevPreservedId !== null &&
          !prevWasNew &&
          id === prevPreservedId + 1;
        if (adjacent) {
          // The two preserved blocks sit next to each other in the original
          // token list. Either (a) directly adjacent with no space token
          // between them — emit nothing extra, the prev block's raw already
          // ended where it needed; or (b) a space token sits between them —
          // re-emit it verbatim to preserve original whitespace.
          const prevBlockTokIdx = this.blockTokenIndex[prevPreservedId];
          const thisBlockTokIdx = this.blockTokenIndex[id as number];
          if (prevBlockTokIdx + 1 === thisBlockTokIdx) {
            // Directly adjacent — no separator.
          } else if (this.tokens[prevBlockTokIdx + 1]?.type === "space") {
            out.push(this.tokens[prevBlockTokIdx + 1].raw);
          } else {
            ensureBlockSeparator(out);
          }
        } else {
          ensureBlockSeparator(out);
        }
      }

      if (isPreserved) {
        const blockTokIdx = this.blockTokenIndex[id as number];
        const tok = blockTokIdx != null ? this.tokens[blockTokIdx] : null;
        const currentJson = jsonFingerprint(child.toJSON());
        const snap = this.snapshots[id as number]?.json;
        if (tok && currentJson === snap) {
          out.push(tok.raw);
        } else {
          // Tiptap's serializer doesn't always emit trailing newlines that
          // match the original token's raw bytes. The space tokens we emit
          // between blocks assume each block ends exactly the way its raw
          // ended; if the rendered output is missing a trailing \n, the
          // following space token collapses the boundary and we fuse two
          // blocks into one (e.g. `- [x] task### Heading`). Normalize the
          // rendered tail to match the original.
          const rendered = renderChild(manager, child);
          out.push(matchTrailingNewlines(rendered, tok?.raw ?? ""));
        }
        prevPreservedId = id as number;
        prevWasNew = false;
      } else {
        // New child — render and ensure a trailing newline so the next
        // separator behaves consistently.
        const rendered = renderChild(manager, child);
        out.push(rendered.endsWith("\n") ? rendered : rendered + "\n");
        prevWasNew = true;
        // Keep prevPreservedId so the next preserved child can still test
        // adjacency (which will fail because prevWasNew=true) and fall back
        // to the default separator.
      }
    });

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

function ensureBlockSeparator(out: string[]): void {
  if (out.length === 0) return;
  const last = out[out.length - 1];
  if (last.endsWith("\n\n")) return;
  if (last.endsWith("\n")) out.push("\n");
  else out.push("\n\n");
}

// Pad or trim trailing "\n" on `rendered` so its trailing-newline count
// matches the original `raw`. Lets the surrounding space tokens reproduce
// the source's whitespace structure even when a block is re-rendered.
function matchTrailingNewlines(rendered: string, raw: string): string {
  const renderedTrail = countTrailingNewlines(rendered);
  const rawTrail = countTrailingNewlines(raw);
  if (renderedTrail === rawTrail) return rendered;
  if (renderedTrail < rawTrail) {
    return rendered + "\n".repeat(rawTrail - renderedTrail);
  }
  return rendered.slice(0, rendered.length - (renderedTrail - rawTrail));
}

function countTrailingNewlines(s: string): number {
  let n = 0;
  for (let i = s.length - 1; i >= 0 && s[i] === "\n"; i--) n++;
  return n;
}

function renderChild(manager: any, child: any): string {
  if (!manager || typeof manager.serialize !== "function") return "";
  // serialize accepts a JSONContent doc-or-fragment. Wrapping the child
  // node's JSON in a synthetic doc keeps the serializer happy and emits
  // just this block's content.
  const doc = { type: "doc", content: [child.toJSON()] };
  return manager.serialize(doc);
}
