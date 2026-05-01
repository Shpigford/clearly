import puppeteer from "puppeteer-core";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { execSync } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));

execSync(
  "npx esbuild src/main.ts --bundle --outfile=dist/bundle.js --format=iife --target=es2020",
  { cwd: __dirname, stdio: "inherit" }
);

const browser = await puppeteer.launch({
  executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  headless: "new",
  args: ["--no-sandbox"],
});
const page = await browser.newPage();
await page.goto("file://" + resolve(__dirname, "index.html"), { waitUntil: "load" });

const md = `---
title: Sanity
---

# Heading 1

A **paragraph** with *italic* and \`inline code\` and [a link](https://x).

- bullet a
- bullet b
- bullet c

\`\`\`ts
function hello() { return 42; }
\`\`\`

| A | B |
|---|---|
| 1 | 2 |
`;

await page.evaluate((c) => {
  window.__initialContent = c;
  window.__initialContentIsMarkdown = true;
}, md);
await page.evaluate(() => window.__mountEditor());
const summary = await page.evaluate(() => {
  const e = window.__editor;
  if (!e) return { error: "no editor" };
  const json = e.getJSON();
  const types = new Map();
  function walk(node) {
    types.set(node.type, (types.get(node.type) || 0) + 1);
    if (node.content) for (const c of node.content) walk(c);
  }
  walk(json);
  const md = e.getMarkdown ? e.getMarkdown() : null;
  return {
    types: Array.from(types.entries()).sort((a, b) => b[1] - a[1]),
    docSize: e.state.doc.content.size,
    childCount: json.content?.length ?? 0,
    markdownPreview: md ? md.slice(0, 300) : null,
  };
});
console.log("Doc tree types:", summary.types);
console.log("Top-level children:", summary.childCount);
console.log("Doc size (PM units):", summary.docSize);
console.log("Round-trip preview:\n" + summary.markdownPreview);
await browser.close();
