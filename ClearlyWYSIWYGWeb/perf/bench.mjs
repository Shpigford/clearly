import { performance } from "node:perf_hooks";
import puppeteer from "puppeteer-core";
import { fileURLToPath } from "node:url";
import { dirname, resolve, join } from "node:path";
import { execSync } from "node:child_process";
import { existsSync } from "node:fs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const KEYSTROKE_COUNT = 50;
const SIZES_DEFAULT = [50_000, 100_000, 200_000];
const sizesArg = process.argv.find((a) => a.startsWith("--sizes="));
const SIZES = sizesArg
  ? sizesArg.replace("--sizes=", "").split(",").map((s) => parseInt(s, 10)).filter((n) => Number.isFinite(n))
  : SIZES_DEFAULT;

function generateMarkdown(targetWords) {
  const out = [];
  let wordCount = 0;
  out.push("---", "title: Synthetic perf doc", "tags: bench, perf", "---", "");
  const sample = "The quick brown fox jumps over the lazy dog. ".repeat(2);
  const linkLine = "Here is [a link](https://example.com) and **bold** text with `inline code`. ";
  const codeFence = ["```ts", "function example() {", "  return 42;", "}", "```"];
  const tableBlock = ["| Col A | Col B | Col C |", "|---|---|---|", "| 1 | 2 | 3 |", "| 4 | 5 | 6 |"];
  let line = 5;
  while (wordCount < targetWords) {
    if (line % 150 === 0 && line > 5) {
      tableBlock.forEach((t) => { out.push(t); wordCount += t.split(/\s+/).length; });
      line += tableBlock.length;
      out.push(""); line += 1;
      continue;
    }
    if (line % 80 === 0 && line > 5) {
      codeFence.forEach((c) => { out.push(c); wordCount += c.split(/\s+/).length; });
      line += codeFence.length;
      out.push(""); line += 1;
      continue;
    }
    if (line % 30 === 0) {
      out.push(`# Heading ${Math.floor(line / 30)}`);
      wordCount += 3; line += 1;
      continue;
    }
    const useLink = line % 4 === 0;
    const text = useLink ? linkLine + sample : sample;
    out.push(text);
    wordCount += text.split(/\s+/).length;
    line += 1;
  }
  return { md: out.join("\n"), lines: out.length, wordCount };
}

console.log("Building perf bundle...");
execSync(
  "npx esbuild src/main.ts --bundle --outfile=dist/bundle.js --format=iife --target=es2020",
  { cwd: __dirname, stdio: "inherit" }
);

const chromePath = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
if (!existsSync(chromePath)) {
  console.error(`Chrome not found at ${chromePath}. Install Google Chrome or update the path.`);
  process.exit(2);
}
const browser = await puppeteer.launch({
  executablePath: chromePath,
  headless: "new",
  args: ["--no-sandbox"],
});

function summarize(t) {
  const s = [...t].sort((a, b) => a - b);
  const sum = s.reduce((a, b) => a + b, 0);
  return {
    mean: sum / s.length,
    p50: s[Math.floor(s.length * 0.5)],
    p95: s[Math.floor(s.length * 0.95)],
    p99: s[Math.floor(s.length * 0.99)],
    max: s[s.length - 1],
  };
}
const fmt = (n) => `${n.toFixed(1).padStart(7)}ms`;
const results = [];

for (const targetWords of SIZES) {
  const { md, lines, wordCount } = generateMarkdown(targetWords);
  console.log(`\n=== ${wordCount.toLocaleString()} words / ${lines.toLocaleString()} lines ===`);
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 900 });
  await page.goto("file://" + resolve(__dirname, "index.html"), { waitUntil: "load" });
  await page.evaluate((c) => {
    window.__initialContent = c;
    window.__initialContentIsMarkdown = true;
    window.__useFullStack = true;
  }, md);
  const t0 = performance.now();
  await page.evaluate(() => window.__mountEditor());
  const mountWall = performance.now() - t0;
  const mountInternal = await page.evaluate(() => window.__mountTimeMs);
  console.log(`  Mount: ${fmt(mountInternal)} (wall ${fmt(mountWall)})`);
  for (const position of ["end", "middle", "start"]) {
    for (const flavor of ["raw", "serialize"]) {
      const serializeEachStroke = flavor === "serialize";
      const timings = await page.evaluate(
        (c, p, opts) => window.__runKeystrokes(c, p, opts),
        KEYSTROKE_COUNT,
        position,
        { serializeEachStroke }
      );
      const s = summarize(timings);
      console.log(`  Keystroke @${position.padEnd(6)} [${flavor.padEnd(9)}]: p50 ${fmt(s.p50)} p95 ${fmt(s.p95)} p99 ${fmt(s.p99)} max ${fmt(s.max)}`);
      results.push({ words: wordCount, position, flavor, mount: mountInternal, ...s });
    }
  }
  await page.close();
}
await browser.close();

console.log("\n=== Verdict matrix (50 ms p95 target) ===");
for (const r of results) {
  const status = r.p95 < 50 ? "PASS" : r.p95 < 100 ? "MARGINAL" : "FAIL";
  console.log(
    `${r.words.toLocaleString().padStart(10)} ${r.position.padEnd(7)} ${r.flavor.padEnd(9)} p95 ${fmt(r.p95)}  ${status}`
  );
}
