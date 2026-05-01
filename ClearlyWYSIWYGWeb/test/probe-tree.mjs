// Probe how Tiptap parses a small markdown sample. Useful for verifying that
// custom inline extensions actually fire (vs falling through to plain text).

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
page.on("pageerror", (e) => process.stderr.write(`pageerror> ${e.message}\n`));
await page.goto("file://" + join(__dirname, "index.html"), { waitUntil: "load" });

const samples = process.argv.slice(2).length
  ? process.argv.slice(2)
  : [
      "Plain paragraph with [[Wiki Link]] and [[Other|alias]] and [[X#H|al]] and [[Pure]] inline.",
      "Tags: #foo #nested/bar #with-hyphen #unicode-café",
      "Math: inline $x^2$ then $$ block $$ and a $price.",
      "Sub/sup: H~2~O and x^2^ are formulas.",
      "Highlight ==important== text.",
      "> [!TIP]\n> Here is a tip.\n> Multiline.",
      ":rocket: emoji and :100: shortcodes.",
    ];

for (const s of samples) {
  const r = await page.evaluate((md) => window.__rawParseAndRender(md), s);
  console.log("\nin: ", JSON.stringify(s));
  console.log("out:", JSON.stringify(r.output));
  console.log("types:", r.typesSeen.join(", "));
  console.log("eq: ", r.output === s ? "✓" : "✗ (raw renderer)");
}

await browser.close();
