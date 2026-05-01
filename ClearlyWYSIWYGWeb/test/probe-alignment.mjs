// Probe block-token / PM-child alignment for the entire corpus. Per-block
// preservation depends on this being 1:1 (after filtering `space` tokens).

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

let aligned = 0;
let total = 0;
for (const file of corpus) {
  total++;
  const src = readFileSync(file, "utf8");
  const r = await page.evaluate((md) => window.__probeBlockAlignment(md), src);
  const rel = relative(projectRoot, file);
  const tokenCoverage = r.tokenSumBytes === r.bodyByteCount ? "✓" : "✗";
  if (r.aligned) {
    aligned++;
    console.log(`${rel}  ✓  blocks=${r.blockTokens.length} children=${r.docChildren.length} bytes=${tokenCoverage}`);
  } else {
    console.log(`${rel}  ✗  blocks=${r.blockTokens.length} children=${r.docChildren.length} mismatch@${r.mismatchAt} bytes=${tokenCoverage}`);
    if (r.mismatchAt !== null) {
      const t = r.blockTokens[r.mismatchAt];
      const c = r.docChildren[r.mismatchAt];
      const tStr = t ? `${t.type} "${t.raw.slice(0, 60).replace(/\n/g, "\\n")}"` : "(none)";
      const cStr = c ? c.type : "(none)";
      console.log(`     token  : ${tStr}`);
      console.log(`     pm node: ${cStr}`);
    }
  }
}
console.log(`\n${aligned}/${total} aligned`);

await browser.close();
