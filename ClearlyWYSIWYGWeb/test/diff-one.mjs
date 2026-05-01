import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { execSync } from "node:child_process";
import puppeteer from "puppeteer-core";

const __dirname = dirname(fileURLToPath(import.meta.url));
const pkgRoot = dirname(__dirname);
const projectRoot = dirname(pkgRoot);

const target = process.argv[2] ?? "Shared/Resources/wiki-template/index.md";
const mode = process.argv[3] ?? "after-edit"; // "noop" or "after-edit"

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

const src = readFileSync(join(projectRoot, target), "utf8");
const fn = mode === "noop" ? "__roundTrip" : "__roundTripAfterEdit";
const r = await page.evaluate((md, fnName) => window[fnName](md), src, fn);
const out = r.output;

console.log(`=== ${target} (${mode}) ===`);
const a = src.split("\n");
const b = out.split("\n");
const max = Math.max(a.length, b.length);
for (let i = 0; i < max; i++) {
  const sa = a[i] ?? "<EOF>";
  const sb = b[i] ?? "<EOF>";
  if (sa === sb) console.log(`  ${(i + 1).toString().padStart(4)}  ${JSON.stringify(sa)}`);
  else {
    console.log(`  ${(i + 1).toString().padStart(4)}- ${JSON.stringify(sa)}`);
    console.log(`  ${(i + 1).toString().padStart(4)}+ ${JSON.stringify(sb)}`);
  }
}

await browser.close();
