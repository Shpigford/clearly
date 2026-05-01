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

const target = process.argv[2] ?? "Shared/Resources/wiki-template/log.md";
const src = readFileSync(join(projectRoot, target), "utf8");
const r = await page.evaluate((md) => window.__dumpTokens(md), src);
console.log(`bodyLen=${r.bodyLen}`);
let sum = 0;
for (let i = 0; i < r.tokens.length; i++) {
  const t = r.tokens[i];
  sum += t.rawLen;
  console.log(`  [${i.toString().padStart(2)}] ${t.type.padEnd(10)} (${t.rawLen}b cum=${sum}) "${t.raw}"`);
}
console.log(`token sum=${sum}`);

const rt = await page.evaluate((md) => window.__roundTrip(md), src);
console.log(`\nround-trip output len: ${rt.output.length} (source: ${src.length})`);
const lastChars = rt.output.slice(-15);
console.log(`output last 15 chars: ${JSON.stringify(lastChars)}`);
const srcLastChars = src.slice(-15);
console.log(`source last 15 chars: ${JSON.stringify(srcLastChars)}`);
await browser.close();
