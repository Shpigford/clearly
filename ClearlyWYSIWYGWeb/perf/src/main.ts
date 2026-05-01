import { Editor } from "@tiptap/core";
import StarterKit from "@tiptap/starter-kit";
import { Markdown } from "@tiptap/markdown";
import { clearlyExtensions } from "../../src/extensions";

declare global {
  interface Window {
    __editor: Editor | null;
    __mountTimeMs: number | null;
    __initialContent: string;
    __initialContentIsMarkdown: boolean;
    __useFullStack: boolean;
    __mountEditor: () => void;
    __runKeystrokes: (
      count: number,
      position: "start" | "middle" | "end",
      opts?: { serializeEachStroke?: boolean }
    ) => Promise<number[]>;
  }
}

window.__editor = null;
window.__mountTimeMs = null;

window.__mountEditor = () => {
  const root = document.getElementById("editor")!;
  const t0 = performance.now();
  let exts: any[];
  if (window.__useFullStack) {
    exts = clearlyExtensions;
  } else {
    exts = [StarterKit];
    if (window.__initialContentIsMarkdown) exts.push(Markdown.configure({}));
  }
  window.__editor = new Editor({
    element: root,
    extensions: exts,
    content: window.__initialContent,
    contentType: window.__initialContentIsMarkdown ? "markdown" : undefined,
  } as any);
  void root.getBoundingClientRect();
  window.__mountTimeMs = performance.now() - t0;
};

window.__runKeystrokes = async (count, position, opts) => {
  const editor = window.__editor!;
  const timings: number[] = [];
  const docSize = editor.state.doc.content.size;
  const basePos =
    position === "start" ? 1 : position === "middle" ? Math.floor(docSize / 2) : docSize - 1;
  const serializeEachStroke = !!opts?.serializeEachStroke;
  let lastMarkdownLength = 0;
  for (let i = 0; i < count; i++) {
    const pos = basePos + (position === "end" ? i : 0);
    const t0 = performance.now();
    editor.chain().setTextSelection(pos).insertContent("x").run();
    if (serializeEachStroke) {
      lastMarkdownLength = (editor as any).getMarkdown().length;
    }
    void editor.view.dom.getBoundingClientRect();
    timings.push(performance.now() - t0);
    await new Promise((r) => setTimeout(r, 0));
  }
  void lastMarkdownLength;
  return timings;
};
