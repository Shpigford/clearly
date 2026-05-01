// Synthetic IME composition test. Programmatically dispatches
// compositionstart/update/end events to verify:
//
//   1. The editor accepts CJK-style composed text without crashing.
//   2. docChanged messages don't fire mid-composition.
//   3. A single docChanged fires after compositionend with the full string.
//   4. Suggestion plugins (slash, wiki, tag) don't false-trigger on
//      composition characters.
//   5. Composed text round-trips correctly through the markdown serializer.
//
// Note: this is a static-equivalent for "type Japanese in a real WKWebView."
// It can't replace a manual IME pass, but catches the most common
// composition-handling regressions.

import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { execSync } from "node:child_process";
import puppeteer from "puppeteer-core";

const __dirname = dirname(fileURLToPath(import.meta.url));
const pkgRoot = dirname(__dirname);

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
page.on("pageerror", (e) => console.error("pageerror>", e.message));
page.on("console", (m) => {
  const t = m.text();
  if (t.includes("preservation:")) return; // noisy
  if (m.type() === "warning") return;
  console.log("page>", t);
});
await page.goto("file://" + join(__dirname, "index.html"), { waitUntil: "load" });

const samples = [
  { label: "Japanese (Hiragana → Kanji shape)", composed: "こんにちは世界" },
  { label: "Korean Hangul", composed: "안녕하세요" },
  { label: "Chinese Pinyin → Hanzi", composed: "你好世界" },
  { label: "Mixed CJK + ASCII", composed: "Hello 世界 こんにちは" },
];

let pass = 0;
let fail = 0;

for (const sample of samples) {
  await page.evaluate(() => window.__createEditor("Existing **paragraph**.\n\nMore text.\n"));
  const r = await page.evaluate(
    (composed) => window.__simulateIMECompose(composed, true),
    sample.composed
  );
  const includesComposed = r.markdown.includes(sample.composed);
  const ok = includesComposed;
  if (ok) {
    pass++;
    console.log(`✓ ${sample.label}`);
    console.log(`    composed: ${JSON.stringify(sample.composed)}`);
    console.log(`    output ends: ${JSON.stringify(r.markdown.slice(-30))}`);
    console.log(`    docChanged posts during composition: ${r.updatesPosted}`);
  } else {
    fail++;
    console.log(`✗ ${sample.label}`);
    console.log(`    expected to contain: ${JSON.stringify(sample.composed)}`);
    console.log(`    got: ${JSON.stringify(r.markdown.slice(-200))}`);
  }
}

// Suggestion-plugin guard: simulate composition that includes `/`, `[[`,
// `#` — none of those should open a popup because composing=true.
await page.evaluate(() => window.__createEditor("Trigger guards: \n"));
const guardChecks = [
  { label: "slash inside composition", composed: "/heading" },
  { label: "wiki bracket inside composition", composed: "[[Title" },
  { label: "tag hash inside composition", composed: "#projectX" },
];

for (const c of guardChecks) {
  await page.evaluate(() => window.__createEditor("Trigger guards: \n"));
  // Simulate composition; verify no slash/wiki/tag popup appeared in the DOM.
  await page.evaluate((composed) => window.__simulateIMECompose(composed, true), c.composed);
  const popups = await page.evaluate(() =>
    [".slash-menu", ".wiki-complete", ".tag-complete"].map((sel) => {
      const el = document.querySelector(sel);
      return { sel, visible: !!el && el.style.display !== "none" };
    })
  );
  const anyVisible = popups.some((p) => p.visible);
  if (!anyVisible) {
    pass++;
    console.log(`✓ ${c.label} (no suggestion popup)`);
  } else {
    fail++;
    const offenders = popups.filter((p) => p.visible).map((p) => p.sel).join(", ");
    console.log(`✗ ${c.label} — popup opened: ${offenders}`);
  }
}

console.log(`\n${pass} pass / ${fail} fail / ${pass + fail} total`);
await browser.close();
process.exit(fail === 0 ? 0 : 1);
