import { readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { execSync } from "node:child_process";
import puppeteer from "puppeteer-core";

const __dirname = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(__dirname, "..", "..");

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

const corpusRoot = join(projectRoot, "Shared", "Resources");
const files = walkMarkdown(corpusRoot).sort();

console.log(`Found ${files.length} markdown files under ${relative(projectRoot, corpusRoot)}`);

console.log("Building round-trip bundle...");
execSync(
  "npx esbuild test/src/round-trip-bundle.ts --bundle --outfile=test/dist/bundle.js --format=iife --target=es2020",
  { cwd: resolve(__dirname, ".."), stdio: "inherit" }
);

const browser = await puppeteer.launch({
  executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  headless: "new",
  args: ["--no-sandbox"],
});
const page = await browser.newPage();
page.on("pageerror", (err) => process.stderr.write(`pageerror> ${err.message}\n`));
await page.goto("file://" + join(__dirname, "index.html"), { waitUntil: "load" });

let pass = 0;
let fail = 0;
const failures = [];

for (const file of files) {
  const src = readFileSync(file, "utf8");
  const result = await page.evaluate((md) => window.__roundTrip(md), src);
  const out = result.output;
  if (out === src) {
    pass++;
    process.stdout.write(".");
  } else {
    fail++;
    process.stdout.write("F");
    failures.push({ file: relative(projectRoot, file), src, out });
  }
}
process.stdout.write("\n");

console.log(`\n${pass} pass / ${fail} fail / ${files.length} total\n`);

const verbose = process.argv.includes("--verbose");

for (const f of failures) {
  console.log(`\n=== ${f.file} ===`);
  if (verbose) {
    console.log("--- expected (source) ---");
    console.log(f.src);
    console.log("--- actual (round-trip) ---");
    console.log(f.out);
  } else {
    const srcLines = f.src.split("\n");
    const outLines = f.out.split("\n");
    const max = Math.max(srcLines.length, outLines.length);
    let shownDiffs = 0;
    for (let i = 0; i < max; i++) {
      const a = srcLines[i] ?? "<EOF>";
      const b = outLines[i] ?? "<EOF>";
      if (a !== b) {
        shownDiffs++;
        if (shownDiffs > 5) {
          console.log(`  ... (${max - i} more lines, run with --verbose for full diff)`);
          break;
        }
        console.log(`  ${(i + 1).toString().padStart(4)}- ${JSON.stringify(a)}`);
        console.log(`  ${(i + 1).toString().padStart(4)}+ ${JSON.stringify(b)}`);
      }
    }
  }
}

await browser.close();
process.exit(fail === 0 ? 0 : 1);
