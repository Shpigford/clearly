// "After edit" round-trip: insert a single space at end of doc, then serialize.
// Per Section 7.2 of docs/WYSIWYG.md, only the *edited* block should re-flow.
// Everything else should remain byte-identical to source.
//
// This test measures how many lines change vs the no-edit baseline. With the
// simplified global-dirty approach, every byte-level normalization fires and
// we expect significant churn. With per-block preservation, only the trailing
// block of each file should differ.

import { readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { execSync } from "node:child_process";
import puppeteer from "puppeteer-core";

const __dirname = dirname(fileURLToPath(import.meta.url));
const pkgRoot = dirname(__dirname);
const projectRoot = dirname(pkgRoot);

function walkMarkdown(dir, out = []) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) {
      if (entry === "node_modules" || entry.startsWith(".")) continue;
      walkMarkdown(full, out);
    } else if (entry.toLowerCase().endsWith(".md")) {
      out.push(full);
    }
  }
  return out;
}

const corpus = walkMarkdown(join(projectRoot, "Shared", "Resources")).sort();

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

let totalSrcLines = 0;
let totalChangedLines = 0;
for (const file of corpus) {
  const src = readFileSync(file, "utf8");
  const r = await page.evaluate((md) => window.__roundTripAfterEdit(md), src);
  const srcLines = src.split("\n");
  const outLines = r.output.split("\n");
  totalSrcLines += srcLines.length;
  let changed = 0;
  const max = Math.max(srcLines.length, outLines.length);
  for (let i = 0; i < max; i++) {
    if ((srcLines[i] ?? "") !== (outLines[i] ?? "")) changed++;
  }
  totalChangedLines += changed;
  const rel = relative(projectRoot, file);
  const pct = ((changed / srcLines.length) * 100).toFixed(1);
  console.log(`${rel}  ${changed}/${srcLines.length} lines changed (${pct}%)`);
}
console.log(`\nTotal: ${totalChangedLines}/${totalSrcLines} lines changed (${((totalChangedLines / totalSrcLines) * 100).toFixed(1)}%)`);

await browser.close();
