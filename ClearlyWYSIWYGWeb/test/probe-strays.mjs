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

const target = process.argv[2] ?? "Shared/Resources/demo.md";
const src = readFileSync(join(projectRoot, target), "utf8");
const r = await page.evaluate((md) => window.__findStrayTopLevel(md), src);

console.log(`=== ${target} ===`);
console.log(`Strays: ${r.findings.length}`);
for (const f of r.findings) {
  console.log(`  idx=${f.idx} type=${f.type} sample="${f.sample}"`);
  // Show neighbors
  const neighbors = r.context.slice(Math.max(0, f.idx - 2), f.idx + 3);
  for (const n of neighbors) {
    const marker = n.idx === f.idx ? " >>" : "   ";
    console.log(`${marker} ${n.idx.toString().padStart(3)} ${n.type.padEnd(15)} ${JSON.stringify(n.head)}`);
  }
}

await browser.close();
