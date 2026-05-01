// Probe: do marked's top-level block tokens cleanly align with Tiptap's
// top-level PM doc children?

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { execSync } from "node:child_process";
import puppeteer from "puppeteer-core";

const __dirname = dirname(fileURLToPath(import.meta.url));
const pkgRoot = dirname(__dirname);
const projectRoot = dirname(pkgRoot);

execSync(
  "npx esbuild test/src/round-trip-bundle.ts --bundle --outfile=test/dist/bundle.js --format=iife --target=es2020",
  { cwd: pkgRoot, stdio: "inherit" }
);

const browser = await puppeteer.launch({
  executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  headless: "new",
  args: ["--no-sandbox"],
});
const page = await browser.newPage();
await page.goto("file://" + join(__dirname, "index.html"), { waitUntil: "load" });

const targets = process.argv.slice(2).length
  ? process.argv.slice(2)
  : ["Shared/Resources/demo.md", "Shared/Resources/getting-started.md", "Shared/Resources/recipes/capture.md", "Shared/Resources/wiki-template/AGENTS.md"];

for (const rel of targets) {
  const src = readFileSync(join(projectRoot, rel), "utf8");
  const r = await page.evaluate((md) => window.__probeAlignment(md), src);
  console.log(`\n=== ${rel} ===`);
  console.log(`body bytes: ${r.bodyByteCount}, tokens: ${r.tokens.length}, doc children: ${r.docChildren.length}`);

  const sumBytes = r.tokens.reduce((acc, t) => acc + t.rawBytes, 0);
  console.log(`token raw byte sum: ${sumBytes} (matches body? ${sumBytes === r.bodyByteCount})`);

  const max = Math.max(r.tokens.length, r.docChildren.length);
  for (let i = 0; i < max; i++) {
    const t = r.tokens[i];
    const c = r.docChildren[i];
    const tStr = t ? `${t.type.padEnd(14)} (${t.rawBytes}b) "${t.rawHead}"` : "(none)";
    const cStr = c ? c.type : "(none)";
    const aligned = t && c && (
      t.type === c.type ||
      (t.type === "list" && c.type === "bulletList") ||
      (t.type === "list" && c.type === "orderedList") ||
      (t.type === "code" && c.type === "codeBlock") ||
      (t.type === "hr" && c.type === "horizontalRule") ||
      (t.type === "space" && c.type === undefined) ||
      (t.type === "html" && c.type === undefined)
    );
    const marker = aligned ? "✓" : "✗";
    console.log(`  ${i.toString().padStart(3)} ${marker} ${tStr}  →  ${cStr}`);
  }
}

await browser.close();
