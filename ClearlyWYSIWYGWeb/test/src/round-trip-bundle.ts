import { Editor } from "@tiptap/core";
import { joinFrontmatter, splitFrontmatter } from "../../src/frontmatter";
import { SourcePreservation } from "../../src/preservation";
import { clearlyExtensions } from "../../src/extensions";

declare global {
  interface Window {
    __roundTrip: (markdown: string) => { output: string };
    __roundTripAfterEdit: (markdown: string) => { output: string };
    __rawParseAndRender: (markdown: string) => { typesSeen: string[]; output: string };
    __createEditor: (markdown: string) => Editor;
    __simulateIMECompose: (
      composed: string,
      pasteAtEnd?: boolean
    ) => Promise<{ markdown: string; updatesPosted: number }>;
    __editor: Editor | null;
    __probeBlockAlignment: (markdown: string) => {
      blockTokens: Array<{ type: string; raw: string }>;
      sepTokens: Array<{ index: number; type: string; raw: string }>;
      docChildren: Array<{ type: string }>;
      aligned: boolean;
      mismatchAt: number | null;
      bodyByteCount: number;
      tokenSumBytes: number;
    };
  }
}

function makeEditor(body: string): Editor {
  const root = document.getElementById("editor")!;
  root.innerHTML = "";
  return new Editor({
    element: root,
    extensions: clearlyExtensions,
    content: body,
    contentType: "markdown",
  } as any);
}

window.__roundTrip = (markdown: string) => {
  const split = splitFrontmatter(markdown);
  const editor = makeEditor(split.body);
  const preserve = new SourcePreservation(split.body);
  preserve.attach(editor);
  // No edits performed — preservation should return the original body.
  const body = preserve.getMarkdownBody(editor);
  const output = joinFrontmatter(split.frontmatter, body);
  editor.destroy();
  return { output };
};

window.__probeBlockAlignment = (markdown: string) => {
  const split = splitFrontmatter(markdown);
  const editor = makeEditor(split.body);
  const manager: any = (editor as any).markdown;
  const marked: any = manager?.instance;
  const blockTokens: Array<{ type: string; raw: string }> = [];
  const sepTokens: Array<{ index: number; type: string; raw: string }> = [];
  let tokenSumBytes = 0;
  if (marked && typeof marked.lexer === "function") {
    const tokens: any[] = marked.lexer(split.body);
    let blockI = 0;
    for (const t of tokens) {
      tokenSumBytes += (t.raw ?? "").length;
      if (t.type === "space") {
        sepTokens.push({ index: blockI, type: t.type, raw: t.raw ?? "" });
      } else {
        blockTokens.push({ type: t.type, raw: t.raw ?? "" });
        blockI++;
      }
    }
  }
  const json: any = editor.getJSON();
  const children = (json.content ?? []) as Array<{ type: string }>;
  let aligned = blockTokens.length === children.length;
  let mismatchAt: number | null = null;
  if (aligned) {
    for (let i = 0; i < children.length; i++) {
      const t = blockTokens[i].type;
      const c = children[i].type;
      const ok =
        t === c ||
        (t === "list" && (c === "bulletList" || c === "orderedList")) ||
        (t === "code" && c === "codeBlock") ||
        (t === "hr" && c === "horizontalRule");
      if (!ok) {
        aligned = false;
        mismatchAt = i;
        break;
      }
    }
  } else {
    mismatchAt = Math.min(blockTokens.length, children.length);
  }
  editor.destroy();
  return {
    blockTokens,
    sepTokens,
    docChildren: children.map((c) => ({ type: c.type })),
    aligned,
    mismatchAt,
    bodyByteCount: split.body.length,
    tokenSumBytes,
  };
};

window.__dumpTokens = (markdown: string) => {
  const split = splitFrontmatter(markdown);
  const editor = makeEditor(split.body);
  const manager: any = (editor as any).markdown;
  const marked: any = manager?.instance;
  const tokens: any[] = marked.lexer(split.body);
  const out = tokens.map((t: any) => ({
    type: t.type,
    raw: (t.raw ?? "").slice(0, 80).replace(/\n/g, "\\n"),
    rawLen: (t.raw ?? "").length,
  }));
  editor.destroy();
  return { bodyLen: split.body.length, tokens: out };
};

window.__findStrayTopLevel = (markdown: string) => {
  const split = splitFrontmatter(markdown);
  const editor = makeEditor(split.body);
  const findings: Array<{ idx: number; type: string; sample: string }> = [];
  editor.state.doc.forEach((child, _offset, idx) => {
    if (child.type.name === "text" || !child.isBlock) {
      findings.push({
        idx,
        type: child.type.name,
        sample: (child.textContent ?? "").slice(0, 120),
      });
    }
  });
  // Show contextual neighbors for each stray.
  const context: Array<{ idx: number; type: string; head: string }> = [];
  editor.state.doc.forEach((child, _offset, idx) => {
    context.push({
      idx,
      type: child.type.name,
      head: (child.textContent ?? "").slice(0, 60).replace(/\n/g, "\\n"),
    });
  });
  editor.destroy();
  return { findings, context };
};

window.__createEditor = (markdown: string) => {
  const split = splitFrontmatter(markdown);
  const editor = makeEditor(split.body);
  (window as any).__editor = editor;
  return editor;
};

window.__simulateIMECompose = async (
  composed: string,
  pasteAtEnd = false
): Promise<{ markdown: string; updatesPosted: number }> => {
  // Simulate a Hiragana → Kanji conversion: composition fires update events
  // for each intermediate character then an end event with the final
  // composed string. We track how many docChanged messages would have been
  // posted to the host (the bridge stub on window collects them).
  const editor = (window as any).__editor as Editor | null;
  if (!editor) throw new Error("no editor");

  // Reset the message capture.
  const posted: any[] = [];
  (window as any).webkit = {
    messageHandlers: {
      wysiwyg: {
        postMessage: (m: any) => posted.push(m),
      },
    },
  };

  // Move cursor to end so the composition lands at end of doc.
  if (pasteAtEnd) {
    editor.commands.focus("end");
  }

  const dom = editor.view.dom as HTMLElement;
  const compositionStart = new CompositionEvent("compositionstart", {
    data: "",
    bubbles: true,
    cancelable: true,
  });
  dom.dispatchEvent(compositionStart);

  // Fire one update per character — mimics IME committing partial states.
  for (let i = 0; i < composed.length; i++) {
    const partial = composed.slice(0, i + 1);
    const ev = new CompositionEvent("compositionupdate", {
      data: partial,
      bubbles: true,
      cancelable: true,
    });
    dom.dispatchEvent(ev);
    await new Promise((r) => setTimeout(r, 5));
  }

  // Final compositionend insert: fire the input event + end event so PM
  // commits the composed text into the doc.
  const endEv = new CompositionEvent("compositionend", {
    data: composed,
    bubbles: true,
    cancelable: true,
  });
  dom.dispatchEvent(endEv);

  // PM listens for the textInput event with .data = composed; ensure PM
  // sees the final string by inserting it through the standard channel.
  editor.commands.insertContent(composed);

  // Yield so any queued microtasks fire.
  await new Promise((r) => setTimeout(r, 20));

  const md = editor.getMarkdown ? (editor as any).getMarkdown() : "";
  return { markdown: md, updatesPosted: posted.filter((m) => m.type === "docChanged").length };
};

window.__rawParseAndRender = (markdown: string) => {
  const split = splitFrontmatter(markdown);
  const editor = makeEditor(split.body);
  const json = editor.getJSON();
  const types = new Set<string>();
  function walk(n: any) {
    types.add(n.type);
    if (Array.isArray(n.marks)) {
      for (const m of n.marks) types.add(`mark:${m.type}`);
    }
    if (n.content) for (const c of n.content) walk(c);
  }
  walk(json);
  const rendered = editor.getMarkdown();
  editor.destroy();
  return { typesSeen: Array.from(types), output: rendered };
};

window.__roundTripAfterEdit = (markdown: string) => {
  // Same flow, but trigger an edit so we exercise the rendered fall-back path.
  const split = splitFrontmatter(markdown);
  const editor = makeEditor(split.body);
  const preserve = new SourcePreservation(split.body);
  preserve.attach(editor);
  editor.chain().focus("end").insertContent(" ").run();
  // Body is now dirty — preserve falls back to renderer.
  const body = preserve.getMarkdownBody(editor);
  const output = joinFrontmatter(split.frontmatter, body);
  editor.destroy();
  return { output };
};
